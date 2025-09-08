const std = @import("std");
const protocol = @import("protocol.zig");
const connection = @import("connection.zig");
const zsync = @import("zsync");

pub const Object = struct {
    id: protocol.ObjectId,
    interface: *const protocol.Interface,
    version: u32,
    client: *Client,
    
    const Self = @This();
    
    pub fn destroy(self: *Self) !void {
        if (std.mem.eql(u8, self.interface.name, "wl_surface")) {
            const message = try protocol.Message.init(
                self.client.allocator,
                self.id,
                0, // destroy opcode
                &.{},
            );
            try self.client.connection.sendMessage(message);
        }
        
        self.client.objects.remove(self.id);
    }
};

pub const Registry = struct {
    object: Object,
    client: *Client,
    globals: std.HashMap(u32, Global, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    
    const Self = @This();
    
    pub const Global = struct {
        name: u32,
        interface: []const u8,
        version: u32,
    };
    
    pub fn init(client: *Client, id: protocol.ObjectId) Self {
        return Self{
            .object = Object{
                .id = id,
                .interface = &protocol.wl_registry_interface,
                .version = 1,
                .client = client,
            },
            .client = client,
            .globals = std.HashMap(u32, Global, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(client.allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.globals.iterator();
        while (iterator.next()) |entry| {
            self.client.allocator.free(entry.value_ptr.interface);
        }
        self.globals.deinit();
    }
    
    pub fn bind(self: *Self, name: u32, interface_name: []const u8, version: u32) !protocol.ObjectId {
        const new_id = self.client.nextId();
        
        const interface_str = try self.client.allocator.dupe(u8, interface_name);
        defer self.client.allocator.free(interface_str);
        
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object.id,
            0, // bind opcode
            &[_]protocol.Argument{
                .{ .uint = name },
                .{ .string = interface_str },
                .{ .uint = version },
                .{ .new_id = new_id },
            },
        );
        
        try self.client.connection.sendMessage(message);
        return new_id;
    }
    
    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => { // global
                if (message.arguments.len >= 3) {
                    const name = switch (message.arguments[0]) {
                        .uint => |v| v,
                        else => return error.InvalidArgument,
                    };
                    const interface_name = switch (message.arguments[1]) {
                        .string => |s| try self.client.allocator.dupe(u8, s),
                        else => return error.InvalidArgument,
                    };
                    const version = switch (message.arguments[2]) {
                        .uint => |v| v,
                        else => return error.InvalidArgument,
                    };
                    
                    try self.globals.put(name, Global{
                        .name = name,
                        .interface = interface_name,
                        .version = version,
                    });
                }
            },
            1 => { // global_remove
                if (message.arguments.len >= 1) {
                    const name = switch (message.arguments[0]) {
                        .uint => |v| v,
                        else => return error.InvalidArgument,
                    };
                    
                    if (self.globals.fetchRemove(name)) |entry| {
                        self.client.allocator.free(entry.value.interface);
                    }
                }
            },
            else => {},
        }
    }
};

pub const Surface = struct {
    object: Object,
    
    const Self = @This();
    
    pub fn init(client: *Client, id: protocol.ObjectId) Self {
        return Self{
            .object = Object{
                .id = id,
                .interface = &protocol.wl_surface_interface,
                .version = 6,
                .client = client,
            },
        };
    }
    
    pub fn attach(self: *Self, buffer_id: ?protocol.ObjectId, x: i32, y: i32) !void {
        const message = try protocol.Message.init(
            self.object.client.allocator,
            self.object.id,
            1, // attach opcode
            &[_]protocol.Argument{
                .{ .object = buffer_id orelse 0 },
                .{ .int = x },
                .{ .int = y },
            },
        );
        try self.object.client.connection.sendMessage(message);
    }
    
    pub fn damage(self: *Self, x: i32, y: i32, width: i32, height: i32) !void {
        const message = try protocol.Message.init(
            self.object.client.allocator,
            self.object.id,
            2, // damage opcode
            &[_]protocol.Argument{
                .{ .int = x },
                .{ .int = y },
                .{ .int = width },
                .{ .int = height },
            },
        );
        try self.object.client.connection.sendMessage(message);
    }
    
    pub fn commit(self: *Self) !void {
        const message = try protocol.Message.init(
            self.object.client.allocator,
            self.object.id,
            6, // commit opcode
            &.{},
        );
        try self.object.client.connection.sendMessage(message);
    }
    
    pub fn frame(self: *Self) !protocol.ObjectId {
        const callback_id = self.object.client.nextId();
        const message = try protocol.Message.init(
            self.object.client.allocator,
            self.object.id,
            3, // frame opcode
            &[_]protocol.Argument{
                .{ .new_id = callback_id },
            },
        );
        try self.object.client.connection.sendMessage(message);
        return callback_id;
    }
};

pub const Compositor = struct {
    object: Object,
    
    const Self = @This();
    
    pub fn init(client: *Client, id: protocol.ObjectId) Self {
        return Self{
            .object = Object{
                .id = id,
                .interface = &protocol.wl_compositor_interface,
                .version = 6,
                .client = client,
            },
        };
    }
    
    pub fn createSurface(self: *Self) !Surface {
        const surface_id = self.object.client.nextId();
        const message = try protocol.Message.init(
            self.object.client.allocator,
            self.object.id,
            0, // create_surface opcode
            &[_]protocol.Argument{
                .{ .new_id = surface_id },
            },
        );
        try self.object.client.connection.sendMessage(message);
        
        const surface = Surface.init(self.object.client, surface_id);
        try self.object.client.objects.put(surface_id, .{ .surface = surface });
        return surface;
    }
};

pub const ObjectType = union(enum) {
    registry: Registry,
    compositor: Compositor,
    surface: Surface,
    generic: Object,
};

pub const Client = struct {
    connection: connection.Connection,
    allocator: std.mem.Allocator,
    display_id: protocol.ObjectId,
    next_object_id: protocol.ObjectId,
    objects: std.HashMap(protocol.ObjectId, ObjectType, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage),
    runtime: ?*zsync.Runtime,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: struct {}) !Self {
        _ = config;
        const conn = try connection.Connection.connectToWaylandSocket(allocator);
        
        return Self{
            .connection = conn,
            .allocator = allocator,
            .display_id = 1,
            .next_object_id = 2,
            .objects = std.HashMap(protocol.ObjectId, ObjectType, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage).init(allocator),
            .runtime = null,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.objects.iterator();
        while (iterator.next()) |entry| {
            switch (entry.value_ptr.*) {
                .registry => |*registry| registry.deinit(),
                else => {},
            }
        }
        self.objects.deinit();
        self.connection.deinit();
    }
    
    pub fn connect(self: *Self) !void {
        _ = self;
        // Connection is established in init, so nothing to do here
    }
    
    pub fn nextId(self: *Self) protocol.ObjectId {
        const id = self.next_object_id;
        self.next_object_id += 1;
        return id;
    }
    
    pub fn getRegistry(self: *Self) !Registry {
        const registry_id = self.nextId();
        
        const message = try protocol.Message.init(
            self.allocator,
            self.display_id,
            1, // get_registry opcode
            &[_]protocol.Argument{
                .{ .new_id = registry_id },
            },
        );
        
        try self.connection.sendMessage(message);
        
        const registry = Registry.init(self, registry_id);
        try self.objects.put(registry_id, .{ .registry = registry });
        
        return registry;
    }
    
    pub fn sync(self: *Self) !protocol.ObjectId {
        const callback_id = self.nextId();
        
        const message = try protocol.Message.init(
            self.allocator,
            self.display_id,
            0, // sync opcode
            &[_]protocol.Argument{
                .{ .new_id = callback_id },
            },
        );
        
        try self.connection.sendMessage(message);
        return callback_id;
    }
    
    pub fn roundtrip(self: *Self) !void {
        const callback_id = try self.sync();
        
        while (true) {
            const message = try self.connection.receiveMessage();
            try self.handleMessage(message);
            
            if (message.header.object_id == callback_id and message.header.opcode == 0) {
                // Callback done event received
                break;
            }
        }
    }
    
    pub fn handleMessage(self: *Self, message: protocol.Message) !void {
        if (self.objects.getPtr(message.header.object_id)) |object_wrapper| {
            switch (object_wrapper.*) {
                .registry => |*registry| try registry.handleEvent(message),
                .compositor => {},
                .surface => {},
                .generic => {},
            }
        }
    }
    
    pub fn dispatch(self: *Self) !void {
        const message = try self.connection.receiveMessage();
        try self.handleMessage(message);
    }
    
    pub fn run(self: *Self) !void {
        while (true) {
            try self.dispatch();
        }
    }
};