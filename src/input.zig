const std = @import("std");
const protocol = @import("protocol.zig");

// Wayland seat interface (the main input device manager)
pub const wl_seat_interface = protocol.Interface{
    .name = "wl_seat",
    .version = 9,
    .method_count = 3,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "get_pointer", .signature = "n", .types = &[_]?*const protocol.Interface{&wl_pointer_interface} },
        .{ .name = "get_keyboard", .signature = "n", .types = &[_]?*const protocol.Interface{&wl_keyboard_interface} },
        .{ .name = "get_touch", .signature = "n", .types = &[_]?*const protocol.Interface{&wl_touch_interface} },
        .{ .name = "release", .signature = "5", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 2,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "capabilities", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "name", .signature = "2s", .types = &[_]?*const protocol.Interface{null} },
    },
};

// Pointer (mouse) interface
pub const wl_pointer_interface = protocol.Interface{
    .name = "wl_pointer",
    .version = 9,
    .method_count = 2,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "set_cursor", .signature = "u?oii", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface, null, null} },
        .{ .name = "release", .signature = "3", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 9,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "enter", .signature = "uoff", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface, null, null} },
        .{ .name = "leave", .signature = "uo", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface} },
        .{ .name = "motion", .signature = "uff", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "button", .signature = "uuuu", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "axis", .signature = "uuf", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "frame", .signature = "5", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "axis_source", .signature = "5u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "axis_stop", .signature = "5uu", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "axis_discrete", .signature = "5ui", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "axis_value120", .signature = "9ui", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "axis_relative_direction", .signature = "9uu", .types = &[_]?*const protocol.Interface{null, null} },
    },
};

// Keyboard interface
pub const wl_keyboard_interface = protocol.Interface{
    .name = "wl_keyboard",
    .version = 9,
    .method_count = 1,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "release", .signature = "3", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 6,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "keymap", .signature = "uhu", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "enter", .signature = "uoa", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface, null} },
        .{ .name = "leave", .signature = "uo", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface} },
        .{ .name = "key", .signature = "uuuu", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "modifiers", .signature = "uuuuu", .types = &[_]?*const protocol.Interface{null, null, null, null, null} },
        .{ .name = "repeat_info", .signature = "4ii", .types = &[_]?*const protocol.Interface{null, null} },
    },
};

// Touch interface
pub const wl_touch_interface = protocol.Interface{
    .name = "wl_touch",
    .version = 9,
    .method_count = 1,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "release", .signature = "3", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 7,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "down", .signature = "uuoiff", .types = &[_]?*const protocol.Interface{null, null, &protocol.wl_surface_interface, null, null, null} },
        .{ .name = "up", .signature = "uui", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "motion", .signature = "uiff", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "frame", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "cancel", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "shape", .signature = "6iff", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "orientation", .signature = "6if", .types = &[_]?*const protocol.Interface{null, null, null} },
    },
};

// Enums for input events
pub const SeatCapability = packed struct {
    pointer: bool = false,
    keyboard: bool = false,
    touch: bool = false,
    _padding: u29 = 0,
    
    pub fn toU32(self: SeatCapability) u32 {
        return @bitCast(self);
    }
    
    pub fn fromU32(value: u32) SeatCapability {
        return @bitCast(value);
    }
};

pub const KeyState = enum(u32) {
    released = 0,
    pressed = 1,
};

pub const ButtonState = enum(u32) {
    released = 0,
    pressed = 1,
};

pub const PointerAxis = enum(u32) {
    vertical_scroll = 0,
    horizontal_scroll = 1,
};

pub const PointerAxisSource = enum(u32) {
    wheel = 0,
    finger = 1,
    continuous = 2,
    wheel_tilt = 3,
};

pub const KeymapFormat = enum(u32) {
    no_keymap = 0,
    xkb_v1 = 1,
};

// Client-side input device implementations
pub const Seat = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    capabilities: SeatCapability,
    name: ?[]const u8,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
            .capabilities = SeatCapability{},
            .name = null,
        };
    }
    
    pub fn getPointer(self: *Self) !protocol.ObjectId {
        if (!self.capabilities.pointer) return error.CapabilityNotAvailable;
        
        const pointer_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // get_pointer opcode
            &[_]protocol.Argument{
                .{ .new_id = pointer_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return pointer_id;
    }
    
    pub fn getKeyboard(self: *Self) !protocol.ObjectId {
        if (!self.capabilities.keyboard) return error.CapabilityNotAvailable;
        
        const keyboard_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // get_keyboard opcode
            &[_]protocol.Argument{
                .{ .new_id = keyboard_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return keyboard_id;
    }
    
    pub fn getTouch(self: *Self) !protocol.ObjectId {
        if (!self.capabilities.touch) return error.CapabilityNotAvailable;
        
        const touch_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            2, // get_touch opcode
            &[_]protocol.Argument{
                .{ .new_id = touch_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return touch_id;
    }
    
    pub fn release(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            3, // release opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => { // capabilities
                if (message.arguments.len >= 1) {
                    const caps = switch (message.arguments[0]) {
                        .uint => |v| SeatCapability.fromU32(v),
                        else => return error.InvalidArgument,
                    };
                    self.capabilities = caps;
                }
            },
            1 => { // name
                if (message.arguments.len >= 1) {
                    const name = switch (message.arguments[0]) {
                        .string => |s| try self.client.allocator.dupe(u8, s),
                        else => return error.InvalidArgument,
                    };
                    
                    if (self.name) |old_name| {
                        self.client.allocator.free(old_name);
                    }
                    self.name = name;
                }
            },
            else => {},
        }
    }
    
    pub fn deinit(self: *Self) void {
        if (self.name) |name| {
            self.client.allocator.free(name);
        }
    }
};

pub const Pointer = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
        };
    }
    
    pub fn setCursor(self: *Self, serial: u32, surface_id: ?protocol.ObjectId, hotspot_x: i32, hotspot_y: i32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // set_cursor opcode
            &[_]protocol.Argument{
                .{ .uint = serial },
                .{ .object = surface_id orelse 0 },
                .{ .int = hotspot_x },
                .{ .int = hotspot_y },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn release(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // release opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
};

pub const Keyboard = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
        };
    }
    
    pub fn release(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // release opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
};

pub const Touch = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
        };
    }
    
    pub fn release(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // release opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
};