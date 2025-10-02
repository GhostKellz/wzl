const std = @import("std");
const protocol = @import("protocol.zig");

pub const xdg_wm_base_interface = protocol.Interface{
    .name = "xdg_wm_base",
    .version = 6,
    .method_count = 4,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "create_positioner", .signature = "n", .types = &[_]?*const protocol.Interface{&xdg_positioner_interface} },
        .{ .name = "get_xdg_surface", .signature = "no", .types = &[_]?*const protocol.Interface{&xdg_surface_interface, &protocol.wl_surface_interface} },
        .{ .name = "pong", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
    .event_count = 1,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "ping", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
};

pub const xdg_positioner_interface = protocol.Interface{
    .name = "xdg_positioner",
    .version = 6,
    .method_count = 11,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_size", .signature = "ii", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "set_anchor_rect", .signature = "iiii", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "set_anchor", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "set_gravity", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "set_constraint_adjustment", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "set_offset", .signature = "ii", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "set_reactive", .signature = "3", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_parent_size", .signature = "3ii", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "set_parent_configure", .signature = "3u", .types = &[_]?*const protocol.Interface{null} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

pub const xdg_surface_interface = protocol.Interface{
    .name = "xdg_surface",
    .version = 6,
    .method_count = 5,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "get_toplevel", .signature = "n", .types = &[_]?*const protocol.Interface{&xdg_toplevel_interface} },
        .{ .name = "get_popup", .signature = "n?o", .types = &[_]?*const protocol.Interface{&xdg_popup_interface, &xdg_surface_interface, &xdg_positioner_interface} },
        .{ .name = "set_window_geometry", .signature = "iiii", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "ack_configure", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
    .event_count = 1,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "configure", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
};

pub const xdg_toplevel_interface = protocol.Interface{
    .name = "xdg_toplevel",
    .version = 6,
    .method_count = 14,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_parent", .signature = "?o", .types = &[_]?*const protocol.Interface{&xdg_toplevel_interface} },
        .{ .name = "set_title", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "set_app_id", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "show_window_menu", .signature = "ouu", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "move", .signature = "ou", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "resize", .signature = "ouu", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "set_max_size", .signature = "ii", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "set_min_size", .signature = "ii", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "set_maximized", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "unset_maximized", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_fullscreen", .signature = "?o", .types = &[_]?*const protocol.Interface{&protocol.wl_output_interface} },
        .{ .name = "unset_fullscreen", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_minimized", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 2,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "configure", .signature = "iia", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "close", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
};

pub const xdg_popup_interface = protocol.Interface{
    .name = "xdg_popup",
    .version = 6,
    .method_count = 3,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "grab", .signature = "ou", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "reposition", .signature = "3ou", .types = &[_]?*const protocol.Interface{&xdg_positioner_interface, null} },
    },
    .event_count = 3,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "configure", .signature = "iiii", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "popup_done", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "repositioned", .signature = "3u", .types = &[_]?*const protocol.Interface{null} },
    },
};

// Enums for XDG shell
pub const XdgToplevelState = enum(u32) {
    maximized = 1,
    fullscreen = 2,
    resizing = 3,
    activated = 4,
    tiled_left = 5,
    tiled_right = 6,
    tiled_top = 7,
    tiled_bottom = 8,
    suspended = 9,
};

pub const XdgToplevelResizeEdge = enum(u32) {
    none = 0,
    top = 1,
    bottom = 2,
    left = 4,
    top_left = 5,
    bottom_left = 6,
    right = 8,
    top_right = 9,
    bottom_right = 10,
};

pub const XdgPositionerAnchor = enum(u32) {
    none = 0,
    top = 1,
    bottom = 2,
    left = 3,
    right = 4,
    top_left = 5,
    bottom_left = 6,
    top_right = 7,
    bottom_right = 8,
};

pub const XdgPositionerGravity = enum(u32) {
    none = 0,
    top = 1,
    bottom = 2,
    left = 3,
    right = 4,
    top_left = 5,
    bottom_left = 6,
    top_right = 7,
    bottom_right = 8,
};

pub const XdgPositionerConstraintAdjustment = packed struct {
    slide_x: bool = false,
    slide_y: bool = false,
    flip_x: bool = false,
    flip_y: bool = false,
    resize_x: bool = false,
    resize_y: bool = false,
    _padding: u26 = 0,
    
    pub fn toU32(self: XdgPositionerConstraintAdjustment) u32 {
        return @bitCast(self);
    }
    
    pub fn fromU32(value: u32) XdgPositionerConstraintAdjustment {
        return @bitCast(value);
    }
};

// XDG Shell client-side implementations
pub const XdgWmBase = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
        };
    }
    
    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn createPositioner(self: *Self) !protocol.ObjectId {
        const positioner_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // create_positioner opcode
            &[_]protocol.Argument{
                .{ .new_id = positioner_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return positioner_id;
    }
    
    pub fn getXdgSurface(self: *Self, surface_id: protocol.ObjectId) !protocol.ObjectId {
        const xdg_surface_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            2, // get_xdg_surface opcode
            &[_]protocol.Argument{
                .{ .new_id = xdg_surface_id },
                .{ .object = surface_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return xdg_surface_id;
    }
    
    pub fn pong(self: *Self, serial: u32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            3, // pong opcode
            &[_]protocol.Argument{
                .{ .uint = serial },
            },
        );
        try self.client.connection.sendMessage(message);
    }
};

pub const XdgSurface = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
        };
    }
    
    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn getToplevel(self: *Self) !protocol.ObjectId {
        const toplevel_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // get_toplevel opcode
            &[_]protocol.Argument{
                .{ .new_id = toplevel_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return toplevel_id;
    }
    
    pub fn getPopup(self: *Self, parent_id: ?protocol.ObjectId, positioner_id: protocol.ObjectId) !protocol.ObjectId {
        const popup_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            2, // get_popup opcode
            &[_]protocol.Argument{
                .{ .new_id = popup_id },
                .{ .object = parent_id orelse 0 },
                .{ .object = positioner_id },
            },
        );
        try self.client.connection.sendMessage(message);
        return popup_id;
    }
    
    pub fn setWindowGeometry(self: *Self, x: i32, y: i32, width: i32, height: i32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            3, // set_window_geometry opcode
            &[_]protocol.Argument{
                .{ .int = x },
                .{ .int = y },
                .{ .int = width },
                .{ .int = height },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn ackConfigure(self: *Self, serial: u32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            4, // ack_configure opcode
            &[_]protocol.Argument{
                .{ .uint = serial },
            },
        );
        try self.client.connection.sendMessage(message);
    }
};

pub const XdgToplevel = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
        };
    }
    
    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setParent(self: *Self, parent_id: ?protocol.ObjectId) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // set_parent opcode
            &[_]protocol.Argument{
                .{ .object = parent_id orelse 0 },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setTitle(self: *Self, title: []const u8) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            2, // set_title opcode
            &[_]protocol.Argument{
                .{ .string = title },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setAppId(self: *Self, app_id: []const u8) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            3, // set_app_id opcode
            &[_]protocol.Argument{
                .{ .string = app_id },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setMaximized(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            9, // set_maximized opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn unsetMaximized(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            10, // unset_maximized opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setFullscreen(self: *Self, output_id: ?protocol.ObjectId) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            11, // set_fullscreen opcode
            &[_]protocol.Argument{
                .{ .object = output_id orelse 0 },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn unsetFullscreen(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            12, // unset_fullscreen opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setMinimized(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            13, // set_minimized opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
};

// XDG Activation support (for focus/attention requests)
pub const xdg_activation_v1_interface = protocol.Interface{
    .name = "xdg_activation_v1",
    .version = 1,
    .method_count = 2,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "get_activation_token", .signature = "n", .types = &[_]?*const protocol.Interface{&xdg_activation_token_v1_interface} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

pub const xdg_activation_token_v1_interface = protocol.Interface{
    .name = "xdg_activation_token_v1",
    .version = 1,
    .method_count = 5,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_serial", .signature = "uo", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "set_app_id", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "set_surface", .signature = "o", .types = &[_]?*const protocol.Interface{&protocol.wl_surface_interface} },
        .{ .name = "commit", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 1,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "done", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
    },
};

pub const ActivationToken = struct {
    allocator: std.mem.Allocator,
    client: *@import("client.zig").Client,
    object_id: protocol.ObjectId,
    listener: ?Listener = null,
    
    const Self = @This();
    const Client = @import("client.zig").Client;

    pub const Listener = struct {
        context: ?*anyopaque,
        done_fn: ?*const fn (context: ?*anyopaque, token: *ActivationToken, token_string: []const u8) void,
    };

    pub fn init(allocator: std.mem.Allocator, client: *Client, object_id: protocol.ObjectId) Self {
        return Self{
            .allocator = allocator,
            .client = client,
            .object_id = object_id,
            .listener = null,
        };
    }

    /// Set a listener for activation token events (backward compatibility API)
    pub fn setListener(
        self: *Self,
        comptime T: type,
        listener: struct {
            done: ?*const fn (data: ?*T, token: *ActivationToken, token_string: []const u8) void = null,
        },
        data: ?*T,
    ) void {
        const Wrapper = struct {
            fn doneWrapper(context: ?*anyopaque, token: *ActivationToken, token_string: []const u8) void {
                const typed_data = @as(?*T, @ptrCast(@alignCast(context)));
                if (listener.done) |cb| {
                    cb(typed_data, token, token_string);
                }
            }
        };

        self.listener = Listener{
            .context = @as(?*anyopaque, @ptrCast(data)),
            .done_fn = if (listener.done != null) &Wrapper.doneWrapper else null,
        };
    }

    pub fn setSerial(self: *Self, serial: u32, seat_id: protocol.ObjectId) !void {
        const message = try protocol.Message.init(
            self.allocator,
            self.object_id,
            1, // set_serial opcode
            &[_]protocol.Argument{
                .{ .uint = serial },
                .{ .object = seat_id },
            },
        );
        try self.client.connection.sendMessage(message);
    }

    pub fn setAppId(self: *Self, app_id: []const u8) !void {
        const message = try protocol.Message.init(
            self.allocator,
            self.object_id,
            2, // set_app_id opcode
            &[_]protocol.Argument{
                .{ .string = app_id },
            },
        );
        try self.client.connection.sendMessage(message);
    }

    pub fn setSurface(self: *Self, surface_id: protocol.ObjectId) !void {
        const message = try protocol.Message.init(
            self.allocator,
            self.object_id,
            3, // set_surface opcode
            &[_]protocol.Argument{
                .{ .object = surface_id },
            },
        );
        try self.client.connection.sendMessage(message);
    }

    pub fn commit(self: *Self) !void {
        const message = try protocol.Message.init(
            self.allocator,
            self.object_id,
            4, // commit opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }

    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => { // done event
                if (message.arguments.len >= 1) {
                    const token_string = switch (message.arguments[0]) {
                        .string => |s| s,
                        else => return error.InvalidArgument,
                    };

                    // Call listener callback if registered
                    if (self.listener) |listener| {
                        if (listener.done_fn) |callback| {
                            callback(listener.context, self, token_string);
                        }
                    }
                }
            },
            else => {},
        }
    }

    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.allocator,
            self.object_id,
            0, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
};
