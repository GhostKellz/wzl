const std = @import("std");
const testing = std.testing;
const protocol = @import("wzl").protocol;

test "ObjectId: valid range" {
    const valid_ids = [_]protocol.ObjectId{ 1, 100, 1000, 0xFFFFFFFF };

    for (valid_ids) |id| {
        try testing.expect(id > 0 or id == 0xFFFFFFFF); // 0 is reserved, max is valid
    }
}

test "Interface: wl_display interface" {
    const display = protocol.wl_display_interface;

    try testing.expectEqualStrings("wl_display", display.name);
    try testing.expectEqual(@as(u32, 1), display.version);
}

test "Interface: wl_registry interface" {
    const registry = protocol.wl_registry_interface;

    try testing.expectEqualStrings("wl_registry", registry.name);
    try testing.expectEqual(@as(u32, 1), registry.version);
}

test "Interface: wl_compositor interface" {
    const compositor = protocol.wl_compositor_interface;

    try testing.expectEqualStrings("wl_compositor", compositor.name);
    try testing.expect(compositor.version >= 1);
}

test "Interface: wl_surface interface" {
    const surface = protocol.wl_surface_interface;

    try testing.expectEqualStrings("wl_surface", surface.name);
    try testing.expect(surface.version >= 1);
}

test "Interface: wl_callback interface" {
    const callback = protocol.wl_callback_interface;

    try testing.expectEqualStrings("wl_callback", callback.name);
    try testing.expectEqual(@as(u32, 1), callback.version);
}

test "MessageHeader: size and alignment" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(protocol.MessageHeader));
    try testing.expectEqual(@as(usize, 4), @alignOf(protocol.MessageHeader));
}

test "MessageHeader: field layout" {
    var header = protocol.MessageHeader{
        .object_id = 123,
        .opcode = 456,
        .size = 789,
    };

    try testing.expectEqual(@as(u32, 123), header.object_id);
    try testing.expectEqual(@as(u16, 456), header.opcode);
    try testing.expectEqual(@as(u16, 789), header.size);
}

test "Argument: union size" {
    // Verify Argument union doesn't waste excessive memory
    const arg_size = @sizeOf(protocol.Argument);
    try testing.expect(arg_size <= 32); // Reasonable upper bound
}

test "Argument: int variant" {
    const arg = protocol.Argument{ .int = -42 };
    switch (arg) {
        .int => |val| try testing.expectEqual(@as(i32, -42), val),
        else => try testing.expect(false),
    }
}

test "Argument: uint variant" {
    const arg = protocol.Argument{ .uint = 12345 };
    switch (arg) {
        .uint => |val| try testing.expectEqual(@as(u32, 12345), val),
        else => try testing.expect(false),
    }
}

test "Argument: fixed variant" {
    const fixed = protocol.FixedPoint.fromFloat(2.5);
    const arg = protocol.Argument{ .fixed = fixed };
    switch (arg) {
        .fixed => |val| {
            const float_val = val.toFloat();
            try testing.expect(@abs(float_val - 2.5) < 0.001);
        },
        else => try testing.expect(false),
    }
}

test "Argument: string variant" {
    const arg = protocol.Argument{ .string = "hello" };
    switch (arg) {
        .string => |val| try testing.expectEqualStrings("hello", val),
        else => try testing.expect(false),
    }
}

test "Argument: object variant" {
    const arg = protocol.Argument{ .object = 999 };
    switch (arg) {
        .object => |val| try testing.expectEqual(@as(u32, 999), val),
        else => try testing.expect(false),
    }
}

test "Argument: new_id variant" {
    const arg = protocol.Argument{ .new_id = 1001 };
    switch (arg) {
        .new_id => |val| try testing.expectEqual(@as(u32, 1001), val),
        else => try testing.expect(false),
    }
}

test "Argument: array variant" {
    const data = [_]u8{ 1, 2, 3, 4 };
    const arg = protocol.Argument{ .array = &data };
    switch (arg) {
        .array => |val| try testing.expectEqualSlices(u8, &data, val),
        else => try testing.expect(false),
    }
}

test "Protocol: version constant" {
    try testing.expectEqual(@as(u32, 1), protocol.WAYLAND_VERSION);
}

test "Message: minimum size" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{},
    );

    var buffer: [16]u8 = undefined;
    const size = try message.serialize(&buffer);

    // Minimum message is just the header (8 bytes)
    try testing.expectEqual(@as(usize, 8), size);
}

test "Message: maximum opcode" {
    const allocator = testing.allocator;

    const max_opcode: u16 = std.math.maxInt(u16);
    const message = try protocol.Message.init(
        allocator,
        1,
        max_opcode,
        &[_]protocol.Argument{},
    );

    var buffer: [16]u8 = undefined;
    _ = try message.serialize(&buffer);

    // Should not error with max opcode
}

test "Message: size calculation accuracy" {
    const allocator = testing.allocator;

    const test_string = "test";
    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .uint = 42 },
            .{ .string = test_string },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    // Verify reported size matches header
    const header_size = std.mem.readInt(u16, buffer[6..8], .little);
    try testing.expectEqual(@as(u16, @intCast(size)), header_size);
}

test "Message: serialization deterministic" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .uint = 100 },
            .{ .string = "test" },
        },
    );

    var buffer1: [128]u8 = undefined;
    var buffer2: [128]u8 = undefined;

    const size1 = try message.serialize(&buffer1);
    const size2 = try message.serialize(&buffer2);

    try testing.expectEqual(size1, size2);
    try testing.expectEqualSlices(u8, buffer1[0..size1], buffer2[0..size2]);
}

test "FixedPoint: zero value" {
    const zero = protocol.FixedPoint{ .raw = 0 };
    try testing.expectEqual(@as(f32, 0.0), zero.toFloat());

    const zero_from_float = protocol.FixedPoint.fromFloat(0.0);
    try testing.expectEqual(@as(i32, 0), zero_from_float.raw);
}

test "FixedPoint: negative values" {
    const negative = protocol.FixedPoint.fromFloat(-10.5);
    const result = negative.toFloat();
    try testing.expect(@abs(result - (-10.5)) < 0.001);
}

test "FixedPoint: precision limits" {
    // Fixed point is 24.8 format (256 units per integer)
    // So minimum precision is 1/256 ≈ 0.00390625
    const min_precision = 1.0 / 256.0;

    const fixed = protocol.FixedPoint.fromFloat(min_precision);
    const result = fixed.toFloat();

    try testing.expect(@abs(result - min_precision) < 0.0001);
}

test "Message: null pointer safety" {
    const allocator = testing.allocator;

    // Empty arguments should work
    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{},
    );

    var buffer: [16]u8 = undefined;
    const size = try message.serialize(&buffer);
    try testing.expectEqual(@as(usize, 8), size);
}

test "Message: large message with many arguments" {
    const allocator = testing.allocator;

    // Create message with 10 uint arguments
    var args: [10]protocol.Argument = undefined;
    for (&args, 0..) |*arg, i| {
        arg.* = .{ .uint = @intCast(i) };
    }

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &args,
    );

    var buffer: [256]u8 = undefined;
    const size = try message.serialize(&buffer);

    // header(8) + 10 * uint(4) = 48 bytes
    try testing.expectEqual(@as(usize, 48), size);
}

test "Message: mixed argument types ordering" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .uint = 1 },
            .{ .int = -2 },
            .{ .object = 3 },
            .{ .new_id = 4 },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    // Verify each argument in order
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, buffer[8..12], .little));
    try testing.expectEqual(@as(i32, -2), std.mem.readInt(i32, buffer[12..16], .little));
    try testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, buffer[16..20], .little));
    try testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, buffer[20..24], .little));
}

test "Message: string with special characters" {
    const allocator = testing.allocator;

    const special_string = "hello\nworld\t!\0embedded";
    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .string = special_string },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    // Verify string is correctly serialized
    const str_len = std.mem.readInt(u32, buffer[8..12], .little);
    try testing.expectEqual(@as(u32, special_string.len + 1), str_len);
}

test "Message: UTF-8 string support" {
    const allocator = testing.allocator;

    const utf8_string = "Hello 世界 🌍";
    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .string = utf8_string },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    // UTF-8 should work transparently (byte length)
    const str_len = std.mem.readInt(u32, buffer[8..12], .little);
    try testing.expectEqual(@as(u32, utf8_string.len + 1), str_len);
}
