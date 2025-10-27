const std = @import("std");
const testing = std.testing;
const protocol = @import("wzl").protocol;

test "Message: serialize and deserialize int argument" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        1, // object_id
        0, // opcode
        &[_]protocol.Argument{
            .{ .int = -42 },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expect(size == 12); // header(8) + int(4)
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, buffer[0..4], .little));
    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, buffer[4..6], .little));
    try testing.expectEqual(@as(u16, 12), std.mem.readInt(u16, buffer[6..8], .little));
    try testing.expectEqual(@as(i32, -42), std.mem.readInt(i32, buffer[8..12], .little));
}

test "Message: serialize and deserialize uint argument" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        2, // object_id
        1, // opcode
        &[_]protocol.Argument{
            .{ .uint = 0xDEADBEEF },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expect(size == 12); // header(8) + uint(4)
    try testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, buffer[0..4], .little));
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, buffer[4..6], .little));
    try testing.expectEqual(@as(u32, 0xDEADBEEF), std.mem.readInt(u32, buffer[8..12], .little));
}

test "Message: serialize and deserialize fixed point argument" {
    const allocator = testing.allocator;

    const fixed = protocol.FixedPoint.fromFloat(3.14159);
    const message = try protocol.Message.init(
        allocator,
        3,
        2,
        &[_]protocol.Argument{
            .{ .fixed = fixed },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expect(size == 12);
    const deserialized_fixed = protocol.FixedPoint{
        .raw = std.mem.readInt(i32, buffer[8..12], .little),
    };
    const float_val = deserialized_fixed.toFloat();
    try testing.expect(@abs(float_val - 3.14159) < 0.001);
}

test "Message: serialize and deserialize string argument" {
    const allocator = testing.allocator;

    const test_string = "hello wayland";
    const message = try protocol.Message.init(
        allocator,
        4,
        3,
        &[_]protocol.Argument{
            .{ .string = test_string },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    // header(8) + string_len(4) + string_data(aligned to 4 bytes)
    const expected_size = 8 + 4 + std.mem.alignForward(usize, test_string.len + 1, 4);
    try testing.expectEqual(expected_size, size);

    // Verify string length field
    const str_len = std.mem.readInt(u32, buffer[8..12], .little);
    try testing.expectEqual(@as(u32, test_string.len + 1), str_len); // includes null terminator

    // Verify string data
    try testing.expectEqualStrings(test_string, buffer[12 .. 12 + test_string.len]);
    try testing.expectEqual(@as(u8, 0), buffer[12 + test_string.len]); // null terminator
}

test "Message: serialize and deserialize array argument" {
    const allocator = testing.allocator;

    const test_array = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    const message = try protocol.Message.init(
        allocator,
        5,
        4,
        &[_]protocol.Argument{
            .{ .array = &test_array },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    // header(8) + array_len(4) + array_data(aligned to 4 bytes)
    const expected_size = 8 + 4 + std.mem.alignForward(usize, test_array.len, 4);
    try testing.expectEqual(expected_size, size);

    // Verify array length field
    const arr_len = std.mem.readInt(u32, buffer[8..12], .little);
    try testing.expectEqual(@as(u32, test_array.len), arr_len);

    // Verify array data
    try testing.expectEqualSlices(u8, &test_array, buffer[12 .. 12 + test_array.len]);
}

test "Message: serialize multiple arguments" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        6,
        5,
        &[_]protocol.Argument{
            .{ .uint = 100 },
            .{ .int = -200 },
            .{ .string = "test" },
        },
    );

    var buffer: [128]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expect(size > 8);

    // Verify uint
    try testing.expectEqual(@as(u32, 100), std.mem.readInt(u32, buffer[8..12], .little));

    // Verify int
    try testing.expectEqual(@as(i32, -200), std.mem.readInt(i32, buffer[12..16], .little));

    // Verify string length
    const str_len = std.mem.readInt(u32, buffer[16..20], .little);
    try testing.expectEqual(@as(u32, 5), str_len); // "test" + null
}

test "Message: edge case - empty string" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        7,
        6,
        &[_]protocol.Argument{
            .{ .string = "" },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    // header(8) + string_len(4) + null terminator aligned to 4 bytes
    try testing.expectEqual(@as(usize, 16), size);

    const str_len = std.mem.readInt(u32, buffer[8..12], .little);
    try testing.expectEqual(@as(u32, 1), str_len); // just null terminator
}

test "Message: edge case - empty array" {
    const allocator = testing.allocator;

    const empty_array = [_]u8{};
    const message = try protocol.Message.init(
        allocator,
        8,
        7,
        &[_]protocol.Argument{
            .{ .array = &empty_array },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    // header(8) + array_len(4)
    try testing.expectEqual(@as(usize, 12), size);

    const arr_len = std.mem.readInt(u32, buffer[8..12], .little);
    try testing.expectEqual(@as(u32, 0), arr_len);
}

test "Message: edge case - maximum string size" {
    const allocator = testing.allocator;

    // Create a 4096-byte string (max allowed)
    const max_string = try allocator.alloc(u8, 4096);
    defer allocator.free(max_string);
    @memset(max_string, 'A');

    const message = try protocol.Message.init(
        allocator,
        9,
        8,
        &[_]protocol.Argument{
            .{ .string = max_string },
        },
    );

    var buffer: [8192]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expect(size > 4096);
}

test "Message: error - string too large" {
    const allocator = testing.allocator;

    // Create a string larger than 4096 bytes
    const huge_string = try allocator.alloc(u8, 4097);
    defer allocator.free(huge_string);
    @memset(huge_string, 'B');

    const result = protocol.Message.init(
        allocator,
        10,
        9,
        &[_]protocol.Argument{
            .{ .string = huge_string },
        },
    );

    try testing.expectError(error.InvalidArgument, result);
}

test "Message: error - array too large" {
    const allocator = testing.allocator;

    // Create an array larger than 65536 bytes
    const huge_array = try allocator.alloc(u8, 65537);
    defer allocator.free(huge_array);

    const result = protocol.Message.init(
        allocator,
        11,
        10,
        &[_]protocol.Argument{
            .{ .array = huge_array },
        },
    );

    try testing.expectError(error.InvalidArgument, result);
}

test "Message: error - invalid object id (zero)" {
    const allocator = testing.allocator;

    const result = protocol.Message.init(
        allocator,
        0, // invalid object_id
        0,
        &[_]protocol.Argument{
            .{ .uint = 42 },
        },
    );

    try testing.expectError(error.InvalidObject, result);
}

test "Message: error - buffer too small" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        12,
        11,
        &[_]protocol.Argument{
            .{ .string = "this is a long string" },
        },
    );

    var small_buffer: [16]u8 = undefined;
    const result = message.serialize(&small_buffer);

    try testing.expectError(error.BufferTooSmall, result);
}

test "Message: alignment - string padding" {
    const allocator = testing.allocator;

    // Test various string lengths to verify 4-byte alignment
    const test_cases = [_][]const u8{ "a", "ab", "abc", "abcd", "abcde" };

    for (test_cases) |test_str| {
        const message = try protocol.Message.init(
            allocator,
            13,
            12,
            &[_]protocol.Argument{
                .{ .string = test_str },
            },
        );

        var buffer: [128]u8 = undefined;
        const size = try message.serialize(&buffer);

        // Verify size is aligned to 4 bytes
        try testing.expectEqual(@as(usize, 0), size % 4);
    }
}

test "Message: object id argument" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        14,
        13,
        &[_]protocol.Argument{
            .{ .object = 999 },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expectEqual(@as(usize, 12), size);
    try testing.expectEqual(@as(u32, 999), std.mem.readInt(u32, buffer[8..12], .little));
}

test "Message: new_id argument" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        15,
        14,
        &[_]protocol.Argument{
            .{ .new_id = 1001 },
        },
    );

    var buffer: [64]u8 = undefined;
    const size = try message.serialize(&buffer);

    try testing.expectEqual(@as(usize, 12), size);
    try testing.expectEqual(@as(u32, 1001), std.mem.readInt(u32, buffer[8..12], .little));
}

test "FixedPoint: float conversion accuracy" {
    const test_values = [_]f32{ 0.0, 1.0, -1.0, 3.14159, -2.71828, 100.5, -100.5 };

    for (test_values) |val| {
        const fixed = protocol.FixedPoint.fromFloat(val);
        const result = fixed.toFloat();
        try testing.expect(@abs(result - val) < 0.001);
    }
}

test "FixedPoint: edge cases" {
    // Test very small values
    const small = protocol.FixedPoint.fromFloat(0.001);
    try testing.expect(@abs(small.toFloat() - 0.001) < 0.0001);

    // Test large values
    const large = protocol.FixedPoint.fromFloat(8388607.0); // near max for fixed24.8
    try testing.expect(@abs(large.toFloat() - 8388607.0) < 1.0);
}

test "Message: complex message with all argument types" {
    const allocator = testing.allocator;

    const message = try protocol.Message.init(
        allocator,
        16,
        15,
        &[_]protocol.Argument{
            .{ .int = -123 },
            .{ .uint = 456 },
            .{ .fixed = protocol.FixedPoint.fromFloat(7.89) },
            .{ .string = "complex" },
            .{ .object = 111 },
            .{ .new_id = 222 },
            .{ .array = &[_]u8{ 1, 2, 3 } },
        },
    );

    var buffer: [256]u8 = undefined;
    const size = try message.serialize(&buffer);

    // Verify header
    try testing.expectEqual(@as(u32, 16), std.mem.readInt(u32, buffer[0..4], .little));
    try testing.expectEqual(@as(u16, 15), std.mem.readInt(u16, buffer[4..6], .little));
    try testing.expectEqual(@as(u16, @intCast(size)), std.mem.readInt(u16, buffer[6..8], .little));

    // Verify size is reasonable
    try testing.expect(size > 8);
    try testing.expect(size < 256);
    try testing.expectEqual(@as(usize, 0), size % 4); // 4-byte aligned
}
