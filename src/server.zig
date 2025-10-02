const std = @import("std");
const protocol = @import("protocol.zig");
const connection = @import("connection.zig");
const zsync = @import("zsync");

pub const ClientConnection = struct {
    connection: connection.Connection,
    id: u32,
    objects: std.HashMap(protocol.ObjectId, *ServerObject, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage),
    server: *Server,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, server: *Server, client_socket: std.net.Stream, client_id: u32) Self {
        return Self{
            .connection = connection.Connection.init(allocator, client_socket),
            .id = client_id,
            .objects = std.HashMap(protocol.ObjectId, *ServerObject, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage).init(allocator),
            .server = server,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.objects.deinit();
        self.connection.deinit();
    }
    
    pub fn handleMessage(self: *Self, message: protocol.Message) !void {
        if (self.objects.get(message.header.object_id)) |object| {
            try object.handleRequest(message);
        }
    }
    
    pub fn sendEvent(self: *Self, object_id: protocol.ObjectId, opcode: u16, arguments: []const protocol.Argument) !void {
        const message = try protocol.Message.init(
            self.connection.allocator,
            object_id,
            opcode,
            arguments,
        );
        try self.connection.sendMessage(message);
    }
};

pub const ServerObject = struct {
    id: protocol.ObjectId,
    interface: *const protocol.Interface,
    version: u32,
    client: *ClientConnection,
    
    const Self = @This();
    
    pub fn handleRequest(self: *Self, message: protocol.Message) !void {
        // Default implementation - subclasses should override
        std.debug.print("Unhandled request for object {} interface {s} opcode {}\n", .{ self.id, self.interface.name, message.header.opcode });
    }
    
    pub fn sendEvent(self: *Self, opcode: u16, arguments: []const protocol.Argument) !void {
        try self.client.sendEvent(self.id, opcode, arguments);
    }
};

pub const Display = struct {
    object: ServerObject,
    
    const Self = @This();
    
    pub fn init(client: *ClientConnection) Self {
        return Self{
            .object = ServerObject{
                .id = 1,
                .interface = &protocol.wl_display_interface,
                .version = 1,
                .client = client,
            },
        };
    }
    
    pub fn handleRequest(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleSync(message),
            1 => try self.handleGetRegistry(message),
            else => {},
        }
    }
    
    fn handleSync(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 1) {
            const callback_id = switch (message.arguments[0]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            // Send callback done event immediately
            try self.object.client.sendEvent(callback_id, 0, &[_]protocol.Argument{
                .{ .uint = 0 }, // serial
            });
        }
    }
    
    fn handleGetRegistry(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 1) {
            const registry_id = switch (message.arguments[0]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            const registry = try self.object.client.connection.allocator.create(Registry);
            registry.* = Registry.init(self.object.client, registry_id);
            
            try self.object.client.objects.put(registry_id, &registry.object);
            
            // Send global events for all registered globals
            try registry.sendGlobals();
        }
    }
};

pub const Registry = struct {
    object: ServerObject,
    
    const Self = @This();
    
    pub fn init(client: *ClientConnection, id: protocol.ObjectId) Self {
        return Self{
            .object = ServerObject{
                .id = id,
                .interface = &protocol.wl_registry_interface,
                .version = 1,
                .client = client,
            },
        };
    }
    
    pub fn handleRequest(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleBind(message),
            else => {},
        }
    }
    
    fn handleBind(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 4) {
            const name = switch (message.arguments[0]) {
                .uint => |v| v,
                else => return error.InvalidArgument,
            };
            const interface_name = switch (message.arguments[1]) {
                .string => |s| s,
                else => return error.InvalidArgument,
            };
            const version = switch (message.arguments[2]) {
                .uint => |v| v,
                else => return error.InvalidArgument,
            };
            const new_id = switch (message.arguments[3]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            try self.object.client.server.bindGlobal(self.object.client, name, interface_name, version, new_id);
        }
    }
    
    pub fn sendGlobals(self: *Self) !void {
        // Send compositor global
        try self.object.sendEvent(0, &[_]protocol.Argument{
            .{ .uint = 1 }, // name
            .{ .string = "wl_compositor" },
            .{ .uint = 6 }, // version
        });
        
        // Send shm global
        try self.object.sendEvent(0, &[_]protocol.Argument{
            .{ .uint = 2 }, // name
            .{ .string = "wl_shm" },
            .{ .uint = 2 }, // version
        });
    }
};

pub const CompositorObject = struct {
    object: ServerObject,
    
    const Self = @This();
    
    pub fn init(client: *ClientConnection, id: protocol.ObjectId) Self {
        return Self{
            .object = ServerObject{
                .id = id,
                .interface = &protocol.wl_compositor_interface,
                .version = 6,
                .client = client,
            },
        };
    }
    
    pub fn handleRequest(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleCreateSurface(message),
            1 => try self.handleCreateRegion(message),
            else => {},
        }
    }
    
    fn handleCreateSurface(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 1) {
            const surface_id = switch (message.arguments[0]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            const surface = try self.object.client.connection.allocator.create(SurfaceObject);
            surface.* = SurfaceObject.init(self.object.client, surface_id);
            
            try self.object.client.objects.put(surface_id, &surface.object);
            
            // Notify server about new surface
            try self.object.client.server.onSurfaceCreated(surface);
        }
    }
    
    fn handleCreateRegion(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 1) {
            const region_id = switch (message.arguments[0]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            const region = try self.object.client.connection.allocator.create(RegionObject);
            region.* = RegionObject.init(self.object.client, region_id);
            
            try self.object.client.objects.put(region_id, &region.object);
        }
    }
};

pub const SurfaceObject = struct {
    object: ServerObject,
    committed: bool,
    
    const Self = @This();
    
    pub fn init(client: *ClientConnection, id: protocol.ObjectId) Self {
        return Self{
            .object = ServerObject{
                .id = id,
                .interface = &protocol.wl_surface_interface,
                .version = 6,
                .client = client,
            },
            .committed = false,
        };
    }
    
    pub fn handleRequest(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleDestroy(message),
            1 => try self.handleAttach(message),
            2 => try self.handleDamage(message),
            3 => try self.handleFrame(message),
            6 => try self.handleCommit(message),
            else => {},
        }
    }
    
    fn handleDestroy(self: *Self, message: protocol.Message) !void {
        _ = message;
        // Remove from client objects
        _ = self.object.client.objects.remove(self.object.id);
        
        // Notify server
        try self.object.client.server.onSurfaceDestroyed(self);
    }
    
    fn handleAttach(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        // Handle buffer attachment
    }
    
    fn handleDamage(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        // Handle surface damage
    }
    
    fn handleFrame(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 1) {
            const callback_id = switch (message.arguments[0]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            // Schedule frame callback
            try self.object.client.server.scheduleFrameCallback(self.object.client, callback_id);
        }
    }
    
    fn handleCommit(self: *Self, message: protocol.Message) !void {
        _ = message;
        self.committed = true;
        
        // Notify server about surface commit
        try self.object.client.server.onSurfaceCommit(self);
    }
};

pub const RegionObject = struct {
    object: ServerObject,
    
    const Self = @This();
    
    pub fn init(client: *ClientConnection, id: protocol.ObjectId) Self {
        return Self{
            .object = ServerObject{
                .id = id,
                .interface = &protocol.wl_region_interface,
                .version = 1,
                .client = client,
            },
        };
    }
    
    pub fn handleRequest(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleDestroy(message),
            1 => try self.handleAdd(message),
            2 => try self.handleSubtract(message),
            else => {},
        }
    }
    
    fn handleDestroy(self: *Self, message: protocol.Message) !void {
        _ = message;
        _ = self.object.client.objects.remove(self.object.id);
    }
    
    fn handleAdd(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        // Handle region add
    }
    
    fn handleSubtract(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        // Handle region subtract
    }
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket: std.net.Server,
    clients: std.ArrayList(*ClientConnection),
    next_client_id: u32,
    runtime: ?*zsync.Runtime,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: struct {}) !Self {
        _ = config;
        const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-1";
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
        
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const socket_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ xdg_runtime_dir, wayland_display });
        
        // Remove existing socket if it exists
        std.fs.deleteFileAbsolute(socket_path) catch {};
        
        const socket_addr = try std.net.Address.initUnix(socket_path);
        const socket = try socket_addr.listen(.{});
        
        return Self{
            .allocator = allocator,
            .socket = socket,
            .clients = std.ArrayList(*ClientConnection){},
            .next_client_id = 1,
            .runtime = null,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        self.clients.deinit(self.allocator);
        self.socket.deinit();
    }
    
    pub fn run(self: *Self) !void {
        while (true) {
            const client_socket = try self.socket.accept();
            try self.addClient(client_socket.stream);
        }
    }
    
    fn addClient(self: *Self, client_socket: std.net.Stream) !void {
        const client = try self.allocator.create(ClientConnection);
        client.* = ClientConnection.init(self.allocator, self, client_socket, self.next_client_id);
        self.next_client_id += 1;
        
        // Add display object
        const display = try self.allocator.create(Display);
        display.* = Display.init(client);
        try client.objects.put(1, &display.object);
        
        try self.clients.append(self.allocator, client);
    }
    
    pub fn bindGlobal(self: *Self, client: *ClientConnection, name: u32, interface_name: []const u8, version: u32, new_id: protocol.ObjectId) !void {
        _ = version;
        
        if (std.mem.eql(u8, interface_name, "wl_compositor")) {
            if (name == 1) {
                const compositor = try self.allocator.create(CompositorObject);
                compositor.* = CompositorObject.init(client, new_id);
                try client.objects.put(new_id, &compositor.object);
            }
        } else if (std.mem.eql(u8, interface_name, "wl_shm")) {
            // Handle shm binding
        }
    }
    
    pub fn onSurfaceCreated(self: *Self, surface: *SurfaceObject) !void {
        _ = self;
        std.debug.print("Surface created: {}\n", .{surface.object.id});
    }
    
    pub fn onSurfaceDestroyed(self: *Self, surface: *SurfaceObject) !void {
        _ = self;
        std.debug.print("Surface destroyed: {}\n", .{surface.object.id});
    }
    
    pub fn onSurfaceCommit(self: *Self, surface: *SurfaceObject) !void {
        _ = self;
        std.debug.print("Surface committed: {}\n", .{surface.object.id});
    }
    
    pub fn scheduleFrameCallback(self: *Self, client: *ClientConnection, callback_id: protocol.ObjectId) !void {
        _ = self;
        // For now, send the callback immediately
        try client.sendEvent(callback_id, 0, &[_]protocol.Argument{
            .{ .uint = 0 }, // timestamp
        });
    }
};