const std = @import("std");
const errors = @import("errors.zig");

pub const WAYLAND_VERSION = 1;

pub const ObjectId = u32;
pub const MessageHeader = packed struct {
    object_id: ObjectId,
    opcode: u16,
    size: u16,
};

pub const FixedPoint = packed struct {
    raw: i32,

    pub fn fromFloat(value: f32) FixedPoint {
        return .{ .raw = @intFromFloat(value * 256.0) };
    }

    pub fn toFloat(self: FixedPoint) f32 {
        return @as(f32, @floatFromInt(self.raw)) / 256.0;
    }
};

pub const Argument = union(enum) {
    int: i32,
    uint: u32,
    fixed: FixedPoint,
    string: []const u8,
    object: ObjectId,
    new_id: ObjectId,
    array: []const u8,
    fd: std.fs.File.Handle,
};

pub const Message = struct {
    header: MessageHeader,
    arguments: []const Argument,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, object_id: ObjectId, opcode: u16, arguments: []const Argument) !Message {
        if (object_id == 0) return error.InvalidObject;

        var size: u16 = @sizeOf(MessageHeader);

        for (arguments) |arg| {
            const arg_size = switch (arg) {
                .int, .uint, .fixed => 4,
                .object, .new_id => 4,
                .string => |s| blk: {
                    if (s.len > 4096) return error.InvalidArgument;
                    break :blk @as(u16, @intCast(4 + std.mem.alignForward(usize, s.len + 1, 4)));
                },
                .array => |a| blk: {
                    if (a.len > 65536) return error.InvalidArgument;
                    break :blk @as(u16, @intCast(4 + std.mem.alignForward(usize, a.len, 4)));
                },
                .fd => 0,
            };

            if (size > std.math.maxInt(u16) - arg_size) return error.BufferOverflow;
            size += arg_size;
        }

        return Message{
            .header = MessageHeader{
                .object_id = object_id,
                .opcode = opcode,
                .size = size,
            },
            .arguments = arguments,
            .allocator = allocator,
        };
    }

    pub fn serialize(self: Message, buffer: []u8) !usize {
        if (buffer.len < self.header.size) return error.BufferTooSmall;

        // Performance optimization: Use packed writes for header
        std.mem.writeInt(u32, @ptrCast(buffer[0..4]), self.header.object_id, .little);
        std.mem.writeInt(u16, @ptrCast(buffer[4..6]), self.header.opcode, .little);
        std.mem.writeInt(u16, @ptrCast(buffer[6..8]), self.header.size, .little);

        var offset: usize = 8;

        // Optimize for common argument types
        for (self.arguments) |arg| {
            switch (arg) {
                .int => |val| {
                    std.mem.writeInt(i32, @ptrCast(buffer[offset..][0..4]), val, .little);
                    offset += 4;
                },
                .uint => |val| {
                    std.mem.writeInt(u32, @ptrCast(buffer[offset..][0..4]), val, .little);
                    offset += 4;
                },
                .fixed => |val| {
                    std.mem.writeInt(i32, @ptrCast(buffer[offset..][0..4]), val.raw, .little);
                    offset += 4;
                },
                .object, .new_id => |val| {
                    std.mem.writeInt(u32, @ptrCast(buffer[offset..][0..4]), val, .little);
                    offset += 4;
                },
                .string => |str| {
                    const len: u32 = @intCast(str.len + 1);
                    std.mem.writeInt(u32, @ptrCast(buffer[offset..][0..4]), len, .little);
                    offset += 4;
                    @memcpy(buffer[offset .. offset + str.len], str);
                    buffer[offset + str.len] = 0;
                    offset += std.mem.alignForward(usize, str.len + 1, 4);
                },
                .array => |arr| {
                    const len: u32 = @intCast(arr.len);
                    std.mem.writeInt(u32, @ptrCast(buffer[offset..][0..4]), len, .little);
                    offset += 4;
                    @memcpy(buffer[offset .. offset + arr.len], arr);
                    offset += std.mem.alignForward(usize, arr.len, 4);
                },
                .fd => {
                    // File descriptors are sent separately
                    // Performance: Avoid copying large data through socket
                },
            }
        }

        return self.header.size;
    }


    pub fn deserialize(allocator: std.mem.Allocator, buffer: []const u8, signature: ?[]const u8) !Message {
        if (buffer.len < @sizeOf(MessageHeader)) return error.MalformedMessage;

        const header = MessageHeader{
            .object_id = std.mem.readInt(u32, @ptrCast(buffer[0..4]), .little),
            .opcode = std.mem.readInt(u16, @ptrCast(buffer[4..6]), .little),
            .size = std.mem.readInt(u16, @ptrCast(buffer[6..8]), .little),
        };

        if (header.object_id == 0) return error.InvalidObject;
        if (buffer.len < header.size) return error.MalformedMessage;
        if (header.size < @sizeOf(MessageHeader)) return error.MalformedMessage;

        var arguments = std.ArrayList(Argument){};
        errdefer arguments.deinit(allocator);

        if (signature) |sig| {
            var offset: usize = @sizeOf(MessageHeader);

            for (sig) |sig_char| {
                if (offset >= buffer.len) return error.MalformedMessage;

                const arg = switch (sig_char) {
                    'i' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const val = std.mem.readInt(i32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;
                        break :blk Argument{ .int = val };
                    },
                    'u' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const val = std.mem.readInt(u32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;
                        break :blk Argument{ .uint = val };
                    },
                    'f' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const raw = std.mem.readInt(i32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;
                        break :blk Argument{ .fixed = FixedPoint{ .raw = raw } };
                    },
                    's' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const len = std.mem.readInt(u32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;

                        if (len == 0 or len > 4096) return error.InvalidArgument;
                        if (offset + len > buffer.len) return error.MalformedMessage;

                        const str = try allocator.alloc(u8, len - 1);
                        @memcpy(str, buffer[offset..offset + len - 1]);
                        offset += std.mem.alignForward(usize, len, 4);
                        break :blk Argument{ .string = str };
                    },
                    'o' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const val = std.mem.readInt(u32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;
                        break :blk Argument{ .object = val };
                    },
                    'n' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const val = std.mem.readInt(u32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;
                        break :blk Argument{ .new_id = val };
                    },
                    'a' => blk: {
                        if (offset + 4 > buffer.len) return error.MalformedMessage;
                        const len = std.mem.readInt(u32, @ptrCast(buffer[offset..][0..4]), .little);
                        offset += 4;

                        if (len > 65536) return error.InvalidArgument;
                        if (offset + len > buffer.len) return error.MalformedMessage;

                        const arr = try allocator.alloc(u8, len);
                        @memcpy(arr, buffer[offset..offset + len]);
                        offset += std.mem.alignForward(usize, len, 4);
                        break :blk Argument{ .array = arr };
                    },
                    'h' => Argument{ .fd = -1 },
                    else => return error.InvalidArgument,
                };

                try arguments.append(allocator, arg);
            }
        }

        return Message{
            .header = header,
            .arguments = try arguments.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Message) void {
        for (self.arguments) |arg| {
            switch (arg) {
                .string => |s| self.allocator.free(s),
                .array => |a| self.allocator.free(a),
                else => {},
            }
        }
        if (self.arguments.len > 0) {
            self.allocator.free(self.arguments);
        }
    }
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    method_count: u32,
    methods: []const MethodSignature,
    event_count: u32,
    events: []const MethodSignature,
};

pub const MethodSignature = struct {
    name: []const u8,
    signature: []const u8,
    types: []const ?*const Interface,
};

pub const wl_display_interface = Interface{
    .name = "wl_display",
    .version = 1,
    .method_count = 2,
    .methods = &[_]MethodSignature{
        .{ .name = "sync", .signature = "n", .types = &[_]?*const Interface{&wl_callback_interface} },
        .{ .name = "get_registry", .signature = "n", .types = &[_]?*const Interface{&wl_registry_interface} },
    },
    .event_count = 2,
    .events = &[_]MethodSignature{
        .{ .name = "error", .signature = "ous", .types = &[_]?*const Interface{ null, null, null } },
        .{ .name = "delete_id", .signature = "u", .types = &[_]?*const Interface{null} },
    },
};

pub const wl_registry_interface = Interface{
    .name = "wl_registry",
    .version = 1,
    .method_count = 1,
    .methods = &[_]MethodSignature{
        .{ .name = "bind", .signature = "usun", .types = &[_]?*const Interface{ null, null, null, null } },
    },
    .event_count = 2,
    .events = &[_]MethodSignature{
        .{ .name = "global", .signature = "usu", .types = &[_]?*const Interface{ null, null, null } },
        .{ .name = "global_remove", .signature = "u", .types = &[_]?*const Interface{null} },
    },
};

pub const wl_callback_interface = Interface{
    .name = "wl_callback",
    .version = 1,
    .method_count = 0,
    .methods = &[_]MethodSignature{},
    .event_count = 1,
    .events = &[_]MethodSignature{
        .{ .name = "done", .signature = "u", .types = &[_]?*const Interface{null} },
    },
};

pub const wl_compositor_interface = Interface{
    .name = "wl_compositor",
    .version = 6,
    .method_count = 2,
    .methods = &[_]MethodSignature{
        .{ .name = "create_surface", .signature = "n", .types = &[_]?*const Interface{&wl_surface_interface} },
        .{ .name = "create_region", .signature = "n", .types = &[_]?*const Interface{&wl_region_interface} },
    },
    .event_count = 0,
    .events = &[_]MethodSignature{},
};

pub const wl_surface_interface = Interface{
    .name = "wl_surface",
    .version = 6,
    .method_count = 10,
    .methods = &[_]MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const Interface{} },
        .{ .name = "attach", .signature = "oii", .types = &[_]?*const Interface{ &wl_buffer_interface, null, null } },
        .{ .name = "damage", .signature = "iiii", .types = &[_]?*const Interface{ null, null, null, null } },
        .{ .name = "frame", .signature = "n", .types = &[_]?*const Interface{&wl_callback_interface} },
        .{ .name = "set_opaque_region", .signature = "o", .types = &[_]?*const Interface{&wl_region_interface} },
        .{ .name = "set_input_region", .signature = "o", .types = &[_]?*const Interface{&wl_region_interface} },
        .{ .name = "commit", .signature = "", .types = &[_]?*const Interface{} },
        .{ .name = "set_buffer_transform", .signature = "i", .types = &[_]?*const Interface{null} },
        .{ .name = "set_buffer_scale", .signature = "i", .types = &[_]?*const Interface{null} },
        .{ .name = "damage_buffer", .signature = "iiii", .types = &[_]?*const Interface{ null, null, null, null } },
    },
    .event_count = 2,
    .events = &[_]MethodSignature{
        .{ .name = "enter", .signature = "o", .types = &[_]?*const Interface{&wl_output_interface} },
        .{ .name = "leave", .signature = "o", .types = &[_]?*const Interface{&wl_output_interface} },
    },
};

pub const wl_region_interface = Interface{
    .name = "wl_region",
    .version = 1,
    .method_count = 3,
    .methods = &[_]MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const Interface{} },
        .{ .name = "add", .signature = "iiii", .types = &[_]?*const Interface{ null, null, null, null } },
        .{ .name = "subtract", .signature = "iiii", .types = &[_]?*const Interface{ null, null, null, null } },
    },
    .event_count = 0,
    .events = &[_]MethodSignature{},
};

pub const wl_buffer_interface = Interface{
    .name = "wl_buffer",
    .version = 1,
    .method_count = 1,
    .methods = &[_]MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const Interface{} },
    },
    .event_count = 1,
    .events = &[_]MethodSignature{
        .{ .name = "release", .signature = "", .types = &[_]?*const Interface{} },
    },
};

pub const wl_output_interface = Interface{
    .name = "wl_output",
    .version = 4,
    .method_count = 1,
    .methods = &[_]MethodSignature{
        .{ .name = "release", .signature = "", .types = &[_]?*const Interface{} },
    },
    .event_count = 4,
    .events = &[_]MethodSignature{
        .{ .name = "geometry", .signature = "iiiiissi", .types = &[_]?*const Interface{ null, null, null, null, null, null, null, null } },
        .{ .name = "mode", .signature = "uiii", .types = &[_]?*const Interface{ null, null, null, null } },
        .{ .name = "done", .signature = "", .types = &[_]?*const Interface{} },
        .{ .name = "scale", .signature = "i", .types = &[_]?*const Interface{null} },
    },
};

pub const wl_shm_interface = Interface{
    .name = "wl_shm",
    .version = 2,
    .method_count = 1,
    .methods = &[_]MethodSignature{
        .{ .name = "create_pool", .signature = "nhi", .types = &[_]?*const Interface{ &wl_shm_pool_interface, null, null } },
    },
    .event_count = 1,
    .events = &[_]MethodSignature{
        .{ .name = "format", .signature = "u", .types = &[_]?*const Interface{null} },
    },
};

pub const wl_shm_pool_interface = Interface{
    .name = "wl_shm_pool",
    .version = 2,
    .method_count = 3,
    .methods = &[_]MethodSignature{
        .{ .name = "create_buffer", .signature = "niiiiu", .types = &[_]?*const Interface{ &wl_buffer_interface, null, null, null, null, null } },
        .{ .name = "destroy", .signature = "", .types = &[_]?*const Interface{} },
        .{ .name = "resize", .signature = "i", .types = &[_]?*const Interface{null} },
    },
    .event_count = 0,
    .events = &[_]MethodSignature{},
};

test "Message serialization and deserialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test FixedPoint
    const fp = FixedPoint.fromFloat(1.5);
    try std.testing.expectEqual(@as(f32, 1.5), fp.toFloat());

    // Test Message creation and serialization
    const args = [_]Argument{
        .{ .uint = 42 },
        .{ .int = -10 },
    };

    var message = try Message.init(allocator, 1, 0, &args);
    defer message.deinit();

    try std.testing.expectEqual(@as(ObjectId, 1), message.header.object_id);
    try std.testing.expectEqual(@as(u16, 0), message.header.opcode);
    try std.testing.expect(message.arguments.len == 2);

    // Test serialization
    var buffer: [1024]u8 = undefined;
    const written = try message.serialize(&buffer);
    try std.testing.expect(written > 0);

    // Test deserialization with signature
    var deserialized = try Message.deserialize(allocator, buffer[0..written], "ui");
    defer deserialized.deinit();

    try std.testing.expectEqual(message.header, deserialized.header);
    try std.testing.expectEqual(@as(usize, 2), deserialized.arguments.len);
    try std.testing.expectEqual(@as(u32, 42), deserialized.arguments[0].uint);
    try std.testing.expectEqual(@as(i32, -10), deserialized.arguments[1].int);

    // Test error cases
    try std.testing.expectError(error.InvalidObject, Message.init(allocator, 0, 0, &args));
    try std.testing.expectError(error.MalformedMessage, Message.deserialize(allocator, &[_]u8{}, null));
}

test "Interface definitions" {
    // Test that interfaces are properly defined
    try std.testing.expectEqualStrings("wl_display", wl_display_interface.name);
    try std.testing.expectEqual(@as(u32, 1), wl_display_interface.version);
    try std.testing.expect(wl_display_interface.method_count > 0);
}
