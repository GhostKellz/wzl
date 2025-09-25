const std = @import("std");
const protocol = @import("protocol.zig");
const thread_safety = @import("thread_safety.zig");

/// Tablet tool types
pub const TabletToolType = enum(u32) {
    pen = 0x140,
    eraser = 0x141,
    brush = 0x142,
    pencil = 0x143,
    airbrush = 0x144,
    finger = 0x145,
    mouse = 0x146,
    lens = 0x147,
};

/// Tablet tool capabilities
pub const TabletToolCapability = packed struct {
    tilt: bool = false,
    pressure: bool = false,
    distance: bool = false,
    rotation: bool = false,
    slider: bool = false,
    wheel: bool = false,
    _padding: u26 = 0,
};

/// Tablet button states
pub const TabletButtonState = enum(u32) {
    released = 0,
    pressed = 1,
};

/// Tablet interfaces following Wayland tablet protocol
pub const zwp_tablet_manager_v2_interface = protocol.Interface{
    .name = "zwp_tablet_manager_v2",
    .version = 1,
    .method_count = 2,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "get_tablet_seat", .signature = "no", .types = &[_]?*const protocol.Interface{&zwp_tablet_seat_v2_interface, null} },
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

pub const zwp_tablet_seat_v2_interface = protocol.Interface{
    .name = "zwp_tablet_seat_v2",
    .version = 1,
    .method_count = 1,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 2,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "tablet_added", .signature = "n", .types = &[_]?*const protocol.Interface{&zwp_tablet_v2_interface} },
        .{ .name = "tool_added", .signature = "n", .types = &[_]?*const protocol.Interface{&zwp_tablet_tool_v2_interface} },
    },
};

pub const zwp_tablet_v2_interface = protocol.Interface{
    .name = "zwp_tablet_v2",
    .version = 1,
    .method_count = 1,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 5,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "name", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "id", .signature = "uu", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "path", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "done", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "removed", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
};

pub const zwp_tablet_tool_v2_interface = protocol.Interface{
    .name = "zwp_tablet_tool_v2",
    .version = 1,
    .method_count = 2,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "set_cursor", .signature = "u?oii", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface, null, null} },
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 19,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "type", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "hardware_serial", .signature = "uu", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "hardware_id_wacom", .signature = "uu", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "capability", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "done", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "removed", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "proximity_in", .signature = "uo", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface} },
        .{ .name = "proximity_out", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "down", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "up", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "motion", .signature = "ff", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "pressure", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "distance", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "tilt", .signature = "ff", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "rotation", .signature = "f", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "slider", .signature = "i", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "wheel", .signature = "fi", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "button", .signature = "uuu", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "frame", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
};

/// Tablet tool state
pub const TabletToolState = struct {
    object_id: protocol.ObjectId,
    tool_type: TabletToolType,
    hardware_serial: u64,
    hardware_id: u64,
    capabilities: TabletToolCapability,

    // Current state
    surface: ?protocol.ObjectId = null,
    x: f32 = 0,
    y: f32 = 0,
    pressure: f32 = 0,
    distance: f32 = 0,
    tilt_x: f32 = 0,
    tilt_y: f32 = 0,
    rotation: f32 = 0,
    slider: f32 = 0,
    wheel_degrees: f32 = 0,
    wheel_clicks: i32 = 0,

    // Button state
    buttons_pressed: std.ArrayList(u32),

    // Tool state
    is_down: bool = false,
    in_proximity: bool = false,
    timestamp: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, object_id: protocol.ObjectId) TabletToolState {
        return .{
            .object_id = object_id,
            .tool_type = .pen,
            .hardware_serial = 0,
            .hardware_id = 0,
            .capabilities = .{},
            .buttons_pressed = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *TabletToolState) void {
        self.buttons_pressed.deinit();
    }
};

/// Tablet device state
pub const TabletState = struct {
    object_id: protocol.ObjectId,
    name: []const u8,
    vendor_id: u32,
    product_id: u32,
    path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, object_id: protocol.ObjectId) TabletState {
        return .{
            .object_id = object_id,
            .name = "",
            .vendor_id = 0,
            .product_id = 0,
            .path = "",
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TabletState) void {
        if (self.name.len > 0) self.allocator.free(self.name);
        if (self.path.len > 0) self.allocator.free(self.path);
    }
};

/// Tablet input handler
pub const TabletHandler = struct {
    allocator: std.mem.Allocator,
    tablets: thread_safety.Registry(TabletState),
    tools: thread_safety.Registry(TabletToolState),
    event_queue: thread_safety.MessageQueue(TabletEvent),

    // Pressure curves for different tools
    pressure_curves: std.AutoHashMap(TabletToolType, PressureCurve),

    const TabletEvent = struct {
        tool_id: protocol.ObjectId,
        event_type: EventType,
        data: EventData,

        const EventType = enum {
            proximity_in,
            proximity_out,
            down,
            up,
            motion,
            pressure,
            tilt,
            rotation,
            button,
            frame,
        };

        const EventData = union {
            proximity: struct {
                surface: protocol.ObjectId,
                x: f32,
                y: f32,
            },
            motion: struct {
                x: f32,
                y: f32,
            },
            pressure: f32,
            tilt: struct {
                x: f32,
                y: f32,
            },
            rotation: f32,
            button: struct {
                button: u32,
                state: TabletButtonState,
            },
            frame: u32,
        };
    };

    const PressureCurve = struct {
        points: []const Point,

        const Point = struct {
            input: f32,
            output: f32,
        };

        pub fn map(self: PressureCurve, pressure: f32) f32 {
            if (self.points.len < 2) return pressure;

            // Find the two points to interpolate between
            for (self.points[1..], 0..) |point, i| {
                if (pressure <= point.input) {
                    const prev = self.points[i];
                    const t = (pressure - prev.input) / (point.input - prev.input);
                    return prev.output + t * (point.output - prev.output);
                }
            }

            return self.points[self.points.len - 1].output;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !TabletHandler {
        var handler = TabletHandler{
            .allocator = allocator,
            .tablets = thread_safety.Registry(TabletState).init(allocator),
            .tools = thread_safety.Registry(TabletToolState).init(allocator),
            .event_queue = thread_safety.MessageQueue(TabletEvent).init(allocator),
            .pressure_curves = std.AutoHashMap(TabletToolType, PressureCurve).init(allocator),
        };

        // Set default pressure curves
        const linear_curve = PressureCurve{
            .points = &[_]PressureCurve.Point{
                .{ .input = 0.0, .output = 0.0 },
                .{ .input = 1.0, .output = 1.0 },
            },
        };

        const soft_curve = PressureCurve{
            .points = &[_]PressureCurve.Point{
                .{ .input = 0.0, .output = 0.0 },
                .{ .input = 0.5, .output = 0.7 },
                .{ .input = 1.0, .output = 1.0 },
            },
        };

        try handler.pressure_curves.put(.pen, linear_curve);
        try handler.pressure_curves.put(.brush, soft_curve);
        try handler.pressure_curves.put(.pencil, linear_curve);
        try handler.pressure_curves.put(.airbrush, soft_curve);

        return handler;
    }

    pub fn deinit(self: *TabletHandler) void {
        self.tablets.deinit();
        self.tools.deinit();
        self.event_queue.deinit();
        self.pressure_curves.deinit();
    }

    pub fn handleTabletAdded(self: *TabletHandler, message: protocol.Message) !void {
        if (message.arguments.len < 1) return error.InvalidArgument;

        const tablet_id = message.arguments[0].new_id;
        var tablet = TabletState.init(self.allocator, tablet_id);
        _ = try self.tablets.add(&tablet);
    }

    pub fn handleToolAdded(self: *TabletHandler, message: protocol.Message) !void {
        if (message.arguments.len < 1) return error.InvalidArgument;

        const tool_id = message.arguments[0].new_id;
        var tool = TabletToolState.init(self.allocator, tool_id);
        _ = try self.tools.add(&tool);
    }

    pub fn handleToolMessage(self: *TabletHandler, tool_id: protocol.ObjectId, message: protocol.Message) !void {
        const tool = self.tools.get(@intCast(tool_id)) orelse return error.ToolNotFound;

        switch (message.header.opcode) {
            0 => { // type
                if (message.arguments.len >= 1) {
                    tool.tool_type = @enumFromInt(message.arguments[0].uint);
                }
            },
            1 => { // hardware_serial
                if (message.arguments.len >= 2) {
                    const high = @as(u64, message.arguments[0].uint);
                    const low = @as(u64, message.arguments[1].uint);
                    tool.hardware_serial = (high << 32) | low;
                }
            },
            3 => { // capability
                if (message.arguments.len >= 1) {
                    const cap = message.arguments[0].uint;
                    tool.capabilities.tilt = (cap & 1) != 0;
                    tool.capabilities.pressure = (cap & 2) != 0;
                    tool.capabilities.distance = (cap & 4) != 0;
                    tool.capabilities.rotation = (cap & 8) != 0;
                    tool.capabilities.slider = (cap & 16) != 0;
                    tool.capabilities.wheel = (cap & 32) != 0;
                }
            },
            6 => { // proximity_in
                if (message.arguments.len >= 2) {
                    const serial = message.arguments[0].uint;
                    const surface = message.arguments[1].object;

                    tool.surface = surface;
                    tool.in_proximity = true;
                    tool.timestamp = serial;

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .proximity_in,
                        .data = .{
                            .proximity = .{
                                .surface = surface,
                                .x = tool.x,
                                .y = tool.y,
                            },
                        },
                    });
                }
            },
            7 => { // proximity_out
                tool.in_proximity = false;
                tool.surface = null;

                try self.event_queue.push(.{
                    .tool_id = tool_id,
                    .event_type = .proximity_out,
                    .data = .{ .frame = tool.timestamp },
                });
            },
            8 => { // down
                if (message.arguments.len >= 1) {
                    tool.is_down = true;
                    tool.timestamp = message.arguments[0].uint;

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .down,
                        .data = .{ .frame = tool.timestamp },
                    });
                }
            },
            9 => { // up
                tool.is_down = false;

                try self.event_queue.push(.{
                    .tool_id = tool_id,
                    .event_type = .up,
                    .data = .{ .frame = tool.timestamp },
                });
            },
            10 => { // motion
                if (message.arguments.len >= 2) {
                    tool.x = message.arguments[0].fixed.toFloat();
                    tool.y = message.arguments[1].fixed.toFloat();

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .motion,
                        .data = .{
                            .motion = .{
                                .x = tool.x,
                                .y = tool.y,
                            },
                        },
                    });
                }
            },
            11 => { // pressure
                if (message.arguments.len >= 1) {
                    const raw_pressure = @as(f32, @floatFromInt(message.arguments[0].uint)) / 65535.0;

                    // Apply pressure curve
                    tool.pressure = if (self.pressure_curves.get(tool.tool_type)) |curve|
                        curve.map(raw_pressure)
                    else
                        raw_pressure;

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .pressure,
                        .data = .{ .pressure = tool.pressure },
                    });
                }
            },
            12 => { // distance
                if (message.arguments.len >= 1) {
                    tool.distance = @as(f32, @floatFromInt(message.arguments[0].uint)) / 65535.0;
                }
            },
            13 => { // tilt
                if (message.arguments.len >= 2) {
                    tool.tilt_x = message.arguments[0].fixed.toFloat();
                    tool.tilt_y = message.arguments[1].fixed.toFloat();

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .tilt,
                        .data = .{
                            .tilt = .{
                                .x = tool.tilt_x,
                                .y = tool.tilt_y,
                            },
                        },
                    });
                }
            },
            14 => { // rotation
                if (message.arguments.len >= 1) {
                    tool.rotation = message.arguments[0].fixed.toFloat();

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .rotation,
                        .data = .{ .rotation = tool.rotation },
                    });
                }
            },
            15 => { // slider
                if (message.arguments.len >= 1) {
                    tool.slider = @as(f32, @floatFromInt(message.arguments[0].int)) / 65535.0;
                }
            },
            16 => { // wheel
                if (message.arguments.len >= 2) {
                    tool.wheel_degrees = message.arguments[0].fixed.toFloat();
                    tool.wheel_clicks = message.arguments[1].int;
                }
            },
            17 => { // button
                if (message.arguments.len >= 3) {
                    const serial = message.arguments[0].uint;
                    const button = message.arguments[1].uint;
                    const state = @as(TabletButtonState, @enumFromInt(message.arguments[2].uint));

                    if (state == .pressed) {
                        try tool.buttons_pressed.append(button);
                    } else {
                        for (tool.buttons_pressed.items, 0..) |b, i| {
                            if (b == button) {
                                _ = tool.buttons_pressed.swapRemove(i);
                                break;
                            }
                        }
                    }

                    tool.timestamp = serial;

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .button,
                        .data = .{
                            .button = .{
                                .button = button,
                                .state = state,
                            },
                        },
                    });
                }
            },
            18 => { // frame
                if (message.arguments.len >= 1) {
                    tool.timestamp = message.arguments[0].uint;

                    try self.event_queue.push(.{
                        .tool_id = tool_id,
                        .event_type = .frame,
                        .data = .{ .frame = tool.timestamp },
                    });
                }
            },
            else => {},
        }
    }

    pub fn setPressureCurve(self: *TabletHandler, tool_type: TabletToolType, curve: PressureCurve) !void {
        try self.pressure_curves.put(tool_type, curve);
    }

    pub fn getToolState(self: *TabletHandler, tool_id: protocol.ObjectId) ?*TabletToolState {
        return self.tools.get(@intCast(tool_id));
    }

    pub fn processEvents(self: *TabletHandler) !void {
        while (self.event_queue.pop()) |event| {
            // Process event callbacks here
            _ = event;
        }
    }
};

test "PressureCurve mapping" {
    const curve = TabletHandler.PressureCurve{
        .points = &[_]TabletHandler.PressureCurve.Point{
            .{ .input = 0.0, .output = 0.0 },
            .{ .input = 0.5, .output = 0.7 },
            .{ .input = 1.0, .output = 1.0 },
        },
    };

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), curve.map(0.0), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), curve.map(0.5), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), curve.map(1.0), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), curve.map(0.25), 0.01);
}

test "TabletToolState button management" {
    var tool = TabletToolState.init(std.testing.allocator, 1);
    defer tool.deinit();

    try tool.buttons_pressed.append(1);
    try tool.buttons_pressed.append(2);

    try std.testing.expectEqual(@as(usize, 2), tool.buttons_pressed.items.len);

    // Remove button 1
    for (tool.buttons_pressed.items, 0..) |b, i| {
        if (b == 1) {
            _ = tool.buttons_pressed.swapRemove(i);
            break;
        }
    }

    try std.testing.expectEqual(@as(usize, 1), tool.buttons_pressed.items.len);
    try std.testing.expectEqual(@as(u32, 2), tool.buttons_pressed.items[0]);
}