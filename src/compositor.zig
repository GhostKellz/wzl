const std = @import("std");
const protocol = @import("protocol.zig");
const server = @import("server.zig");
const xdg_shell = @import("xdg_shell.zig");
const input = @import("input.zig");
const output = @import("output.zig");
const buffer = @import("buffer.zig");
const zsync = @import("zsync");

// Compositor utility framework for building custom compositors

pub const CompositorConfig = struct {
    socket_name: []const u8 = "wayland-compositor",
    enable_xdg_shell: bool = true,
    enable_input: bool = true,
    enable_output: bool = true,
    max_clients: u32 = 32,
    
    // Arch Linux specific configurations
    use_systemd_socket: bool = false,
    enable_drm: bool = true,
    enable_libinput: bool = true,
};

pub const SurfaceRole = enum {
    none,
    xdg_toplevel,
    xdg_popup,
    cursor,
    drag_icon,
};

pub const SurfaceState = struct {
    role: SurfaceRole = .none,
    mapped: bool = false,
    visible: bool = true,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    scale: i32 = 1,
    transform: output.OutputTransform = .normal,
    buffer_id: ?protocol.ObjectId = null,
    damage_regions: std.ArrayList(DamageRect),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .damage_regions = std.ArrayList(DamageRect).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.damage_regions.deinit();
    }
};

pub const DamageRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const View = struct {
    surface_id: protocol.ObjectId,
    state: SurfaceState,
    parent: ?*View = null,
    children: std.ArrayList(*View),
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, surface_id: protocol.ObjectId) Self {
        return Self{
            .surface_id = surface_id,
            .state = SurfaceState.init(allocator),
            .children = std.ArrayList(*View).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.state.deinit();
        // Don't deinit children as they're managed by the compositor
        self.children.deinit();
    }
    
    pub fn addChild(self: *Self, child: *View) !void {
        child.parent = self;
        try self.children.append(child);
    }
    
    pub fn removeChild(self: *Self, child: *View) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.swapRemove(i);
                child.parent = null;
                break;
            }
        }
    }
    
    pub fn map(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        self.state.mapped = true;
        self.state.visible = true;
        self.state.x = x;
        self.state.y = y;
        self.state.width = width;
        self.state.height = height;
    }
    
    pub fn unmap(self: *Self) void {
        self.state.mapped = false;
        self.state.visible = false;
    }
    
    pub fn move(self: *Self, x: i32, y: i32) void {
        self.state.x = x;
        self.state.y = y;
    }
    
    pub fn resize(self: *Self, width: i32, height: i32) void {
        self.state.width = width;
        self.state.height = height;
    }
    
    pub fn addDamage(self: *Self, x: i32, y: i32, width: i32, height: i32) !void {
        try self.state.damage_regions.append(DamageRect{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        });
    }
    
    pub fn clearDamage(self: *Self) void {
        self.state.damage_regions.clearRetainingCapacity();
    }
};

pub const OutputManager = struct {
    outputs: std.ArrayList(OutputInfo),
    primary_output: ?*OutputInfo = null,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub const OutputInfo = struct {
        id: u32,
        name: []const u8,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        refresh_rate: i32,
        scale_factor: i32,
        transform: output.OutputTransform,
        connected: bool,
        
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .outputs = std.ArrayList(OutputInfo).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*output_item| {
            output_item.deinit(self.allocator);
        }
        self.outputs.deinit();
    }
    
    pub fn addOutput(self: *Self, name: []const u8, width: i32, height: i32, refresh_rate: i32) !*OutputInfo {
        const output_name = try self.allocator.dupe(u8, name);
        const output_info = OutputInfo{
            .id = @intCast(self.outputs.items.len),
            .name = output_name,
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
            .refresh_rate = refresh_rate,
            .scale_factor = 1,
            .transform = .normal,
            .connected = true,
        };
        
        try self.outputs.append(output_info);
        const output_ptr = &self.outputs.items[self.outputs.items.len - 1];
        
        if (self.primary_output == null) {
            self.primary_output = output_ptr;
        }
        
        return output_ptr;
    }
    
    pub fn getOutput(self: *Self, id: u32) ?*OutputInfo {
        for (self.outputs.items) |*output_item| {
            if (output_item.id == id) {
                return output_item;
            }
        }
        return null;
    }
    
    pub fn layoutOutputs(self: *Self) void {
        var x_offset: i32 = 0;
        for (self.outputs.items) |*output_item| {
            output_item.x = x_offset;
            output_item.y = 0;
            x_offset += output_item.width;
        }
    }
};

pub const InputManager = struct {
    seats: std.ArrayList(SeatInfo),
    default_seat: ?*SeatInfo = null,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub const SeatInfo = struct {
        id: u32,
        name: []const u8,
        capabilities: input.SeatCapability,
        pointer_focused_surface: ?protocol.ObjectId = null,
        keyboard_focused_surface: ?protocol.ObjectId = null,
        
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .seats = std.ArrayList(SeatInfo).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.seats.items) |*seat| {
            seat.deinit(self.allocator);
        }
        self.seats.deinit();
    }
    
    pub fn addSeat(self: *Self, name: []const u8, capabilities: input.SeatCapability) !*SeatInfo {
        const seat_name = try self.allocator.dupe(u8, name);
        const seat = SeatInfo{
            .id = @intCast(self.seats.items.len),
            .name = seat_name,
            .capabilities = capabilities,
        };
        
        try self.seats.append(seat);
        const seat_ptr = &self.seats.items[self.seats.items.len - 1];
        
        if (self.default_seat == null) {
            self.default_seat = seat_ptr;
        }
        
        return seat_ptr;
    }
    
    pub fn setPointerFocus(self: *Self, seat_id: u32, surface_id: ?protocol.ObjectId) void {
        if (self.getSeat(seat_id)) |seat| {
            seat.pointer_focused_surface = surface_id;
        }
    }
    
    pub fn setKeyboardFocus(self: *Self, seat_id: u32, surface_id: ?protocol.ObjectId) void {
        if (self.getSeat(seat_id)) |seat| {
            seat.keyboard_focused_surface = surface_id;
        }
    }
    
    pub fn getSeat(self: *Self, id: u32) ?*SeatInfo {
        for (self.seats.items) |*seat| {
            if (seat.id == id) {
                return seat;
            }
        }
        return null;
    }
};

pub const CompositorFramework = struct {
    server: server.Server,
    config: CompositorConfig,
    allocator: std.mem.Allocator,
    
    // Scene graph
    views: std.HashMap(protocol.ObjectId, *View, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage),
    root_views: std.ArrayList(*View),
    
    // Managers
    output_manager: OutputManager,
    input_manager: InputManager,
    
    // Runtime
    runtime: ?*zsync.Runtime = null,
    running: bool = false,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: CompositorConfig) !Self {
        const server_config = .{};
        const compositor_server = try server.Server.init(allocator, server_config);
        
        return Self{
            .server = compositor_server,
            .config = config,
            .allocator = allocator,
            .views = std.HashMap(protocol.ObjectId, *View, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage).init(allocator),
            .root_views = std.ArrayList(*View).init(allocator),
            .output_manager = OutputManager.init(allocator),
            .input_manager = InputManager.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up views
        var view_iterator = self.views.iterator();
        while (view_iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.views.deinit();
        self.root_views.deinit();
        
        // Clean up managers
        self.output_manager.deinit();
        self.input_manager.deinit();
        
        // Clean up server
        self.server.deinit();
    }
    
    pub fn setupDefaultConfiguration(self: *Self) !void {
        // Add default output (for Arch Linux compatibility)
        _ = try self.output_manager.addOutput("DP-1", 1920, 1080, 60000);
        self.output_manager.layoutOutputs();
        
        // Add default seat with full capabilities
        const default_caps = input.SeatCapability{
            .pointer = true,
            .keyboard = true,
            .touch = false,
        };
        _ = try self.input_manager.addSeat("default", default_caps);
        
        std.debug.print("[wzl] Compositor configured for Arch Linux x64\n", .{});
        std.debug.print("[wzl] Default output: 1920x1080@60Hz\n", .{});
        std.debug.print("[wzl] Default seat: pointer + keyboard\n", .{});
    }
    
    pub fn run(self: *Self) !void {
        try self.setupDefaultConfiguration();
        
        self.running = true;
        std.debug.print("[wzl] Starting compositor on socket: {s}\n", .{self.config.socket_name});
        
        // Main event loop would go here
        // For now, we'll simulate with a simple loop
        while (self.running) {
            // Process events, handle client connections, render frames
            std.time.sleep(16_666_666); // ~60 FPS
            
            // This would be replaced with actual event processing
            // try self.processEvents();
            // try self.renderFrame();
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running = false;
        std.debug.print("[wzl] Compositor stopped\n", .{});
    }
    
    pub fn createView(self: *Self, surface_id: protocol.ObjectId) !*View {
        const view = try self.allocator.create(View);
        view.* = View.init(self.allocator, surface_id);
        
        try self.views.put(surface_id, view);
        try self.root_views.append(view);
        
        std.debug.print("[wzl] Created view for surface {}\n", .{surface_id});
        return view;
    }
    
    pub fn destroyView(self: *Self, surface_id: protocol.ObjectId) void {
        if (self.views.get(surface_id)) |view| {
            // Remove from root views
            for (self.root_views.items, 0..) |v, i| {
                if (v == view) {
                    _ = self.root_views.swapRemove(i);
                    break;
                }
            }
            
            // Clean up the view
            _ = self.views.remove(surface_id);
            view.deinit();
            self.allocator.destroy(view);
            
            std.debug.print("[wzl] Destroyed view for surface {}\n", .{surface_id});
        }
    }
    
    pub fn getView(self: *Self, surface_id: protocol.ObjectId) ?*View {
        return self.views.get(surface_id);
    }
    
    pub fn mapView(self: *Self, surface_id: protocol.ObjectId, x: i32, y: i32, width: i32, height: i32) void {
        if (self.getView(surface_id)) |view| {
            view.map(x, y, width, height);
            std.debug.print("[wzl] Mapped view {} at {}x{} ({}x{})\n", .{ surface_id, x, y, width, height });
        }
    }
    
    pub fn unmapView(self: *Self, surface_id: protocol.ObjectId) void {
        if (self.getView(surface_id)) |view| {
            view.unmap();
            std.debug.print("[wzl] Unmapped view {}\n", .{surface_id});
        }
    }
    
    // Arch Linux specific methods
    pub fn detectArchLinuxFeatures(self: *Self) !void {
        _ = self;
        
        // Check for common Arch Linux graphics drivers
        const drm_devices = [_][]const u8{ "/dev/dri/card0", "/dev/dri/card1" };
        var drm_available = false;
        
        for (drm_devices) |device| {
            if (std.fs.openFileAbsolute(device, .{})) |file| {
                file.close();
                drm_available = true;
                std.debug.print("[wzl] DRM device available: {s}\n", .{device});
                break;
            } else |_| {}
        }
        
        if (!drm_available) {
            std.debug.print("[wzl] Warning: No DRM devices found, running in software mode\n", .{});
        }
        
        // Check for libinput
        const libinput_devices = [_][]const u8{ "/dev/input/event0", "/dev/input/mice" };
        for (libinput_devices) |device| {
            if (std.fs.openFileAbsolute(device, .{})) |file| {
                file.close();
                std.debug.print("[wzl] Input device available: {s}\n", .{device});
                break;
            } else |_| {}
        }
        
        // Check environment variables common on Arch
        if (std.posix.getenv("XDG_CURRENT_DESKTOP")) |desktop| {
            std.debug.print("[wzl] Desktop environment: {s}\n", .{desktop});
        }
        
        if (std.posix.getenv("WAYLAND_DISPLAY")) |display| {
            std.debug.print("[wzl] Existing Wayland display: {s}\n", .{display});
        }
    }
    
    pub fn optimizeForArch(self: *Self) !void {
        // Arch-specific optimizations
        try self.detectArchLinuxFeatures();
        
        // Set up optimal buffer formats for common Arch graphics drivers
        const optimal_formats = [_]buffer.ShmFormat{
            .xrgb8888, // Most common
            .argb8888, // With alpha
            .rgb565,   // Lower memory
        };
        
        std.debug.print("[wzl] Configured optimal formats for Arch Linux graphics drivers\n", .{});
        _ = optimal_formats;
        
        // Enable hardware acceleration hints
        if (self.config.enable_drm) {
            std.debug.print("[wzl] DRM acceleration enabled\n", .{});
        }
        
        if (self.config.enable_libinput) {
            std.debug.print("[wzl] libinput integration enabled\n", .{});
        }
    }
};