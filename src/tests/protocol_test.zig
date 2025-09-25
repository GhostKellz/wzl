const std = @import("std");
const protocol = @import("../protocol.zig");
const errors = @import("../errors.zig");
const memory = @import("../memory.zig");

test "Message creation with valid arguments" {
    const allocator = std.testing.allocator;

    const args = [_]protocol.Argument{
        .{ .uint = 42 },
        .{ .int = -10 },
        .{ .string = "hello" },
    };

    var message = try protocol.Message.init(allocator, 1, 0, &args);
    defer message.deinit();

    try std.testing.expectEqual(@as(protocol.ObjectId, 1), message.header.object_id);
    try std.testing.expectEqual(@as(u16, 0), message.header.opcode);
    try std.testing.expectEqual(@as(usize, 3), message.arguments.len);
}

test "Message creation with invalid object ID" {
    const allocator = std.testing.allocator;

    const args = [_]protocol.Argument{
        .{ .uint = 42 },
    };

    const result = protocol.Message.init(allocator, 0, 0, &args);
    try std.testing.expectError(error.InvalidObject, result);
}

test "Message serialization and deserialization" {
    const allocator = std.testing.allocator;

    const args = [_]protocol.Argument{
        .{ .uint = 0xDEADBEEF },
        .{ .int = -42 },
        .{ .fixed = protocol.FixedPoint.fromFloat(3.14159) },
    };

    var message = try protocol.Message.init(allocator, 100, 5, &args);
    defer message.deinit();

    var buffer: [1024]u8 = undefined;
    const written = try message.serialize(&buffer);

    try std.testing.expect(written > 0);
    try std.testing.expect(written <= buffer.len);

    // Deserialize with signature
    var deserialized = try protocol.Message.deserialize(allocator, buffer[0..written], "uif");
    defer deserialized.deinit();

    try std.testing.expectEqual(message.header, deserialized.header);
    try std.testing.expectEqual(@as(usize, 3), deserialized.arguments.len);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), deserialized.arguments[0].uint);
    try std.testing.expectEqual(@as(i32, -42), deserialized.arguments[1].int);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14159), deserialized.arguments[2].fixed.toFloat(), 0.01);
}

test "Message with string arguments" {
    const allocator = std.testing.allocator;

    const test_string = "Hello, Wayland!";
    const args = [_]protocol.Argument{
        .{ .string = test_string },
        .{ .uint = 123 },
    };

    var message = try protocol.Message.init(allocator, 50, 2, &args);
    defer message.deinit();

    var buffer: [1024]u8 = undefined;
    const written = try message.serialize(&buffer);

    var deserialized = try protocol.Message.deserialize(allocator, buffer[0..written], "su");
    defer deserialized.deinit();

    try std.testing.expectEqualStrings(test_string, deserialized.arguments[0].string);
    try std.testing.expectEqual(@as(u32, 123), deserialized.arguments[1].uint);
}

test "Message with array arguments" {
    const allocator = std.testing.allocator;

    const test_array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const args = [_]protocol.Argument{
        .{ .array = &test_array },
    };

    var message = try protocol.Message.init(allocator, 75, 3, &args);
    defer message.deinit();

    var buffer: [1024]u8 = undefined;
    const written = try message.serialize(&buffer);

    var deserialized = try protocol.Message.deserialize(allocator, buffer[0..written], "a");
    defer deserialized.deinit();

    try std.testing.expectEqualSlices(u8, &test_array, deserialized.arguments[0].array);
}

test "Buffer overflow protection" {
    const allocator = std.testing.allocator;

    // Create a very long string
    const long_string = "x" ** 5000;
    const args = [_]protocol.Argument{
        .{ .string = long_string },
    };

    const result = protocol.Message.init(allocator, 1, 0, &args);
    try std.testing.expectError(error.InvalidArgument, result);
}

test "Malformed message detection" {
    const allocator = std.testing.allocator;

    // Empty buffer
    const result1 = protocol.Message.deserialize(allocator, &[_]u8{}, null);
    try std.testing.expectError(error.MalformedMessage, result1);

    // Buffer too small for header
    const small_buffer = [_]u8{ 1, 2, 3 };
    const result2 = protocol.Message.deserialize(allocator, &small_buffer, null);
    try std.testing.expectError(error.MalformedMessage, result2);

    // Invalid size in header
    var bad_header: [8]u8 = undefined;
    std.mem.writeInt(u32, @ptrCast(bad_header[0..4]), 1, .little); // object_id
    std.mem.writeInt(u16, @ptrCast(bad_header[4..6]), 0, .little); // opcode
    std.mem.writeInt(u16, @ptrCast(bad_header[6..8]), 2, .little); // size too small

    const result3 = protocol.Message.deserialize(allocator, &bad_header, null);
    try std.testing.expectError(error.MalformedMessage, result3);
}

test "FixedPoint conversion" {
    const test_values = [_]f32{ 0.0, 1.0, -1.0, 3.14159, -2.71828, 1234.5678, -9876.5432 };

    for (test_values) |value| {
        const fixed = protocol.FixedPoint.fromFloat(value);
        const converted = fixed.toFloat();
        try std.testing.expectApproxEqAbs(value, converted, 0.01);
    }
}

test "Interface definitions" {
    // Test core interfaces are properly defined
    try std.testing.expectEqualStrings("wl_display", protocol.wl_display_interface.name);
    try std.testing.expectEqual(@as(u32, 1), protocol.wl_display_interface.version);
    try std.testing.expect(protocol.wl_display_interface.method_count > 0);
    try std.testing.expect(protocol.wl_display_interface.event_count > 0);

    try std.testing.expectEqualStrings("wl_registry", protocol.wl_registry_interface.name);
    try std.testing.expectEqualStrings("wl_callback", protocol.wl_callback_interface.name);
    try std.testing.expectEqualStrings("wl_compositor", protocol.wl_compositor_interface.name);
    try std.testing.expectEqualStrings("wl_surface", protocol.wl_surface_interface.name);
}

test "Memory leak detection in Message" {
    var tracking = try memory.TrackingAllocator.init(std.testing.allocator);
    defer tracking.deinit();

    const alloc = tracking.allocator();

    {
        const args = [_]protocol.Argument{
            .{ .string = "test string" },
            .{ .array = "test array" },
        };

        var message = try protocol.Message.init(alloc, 1, 0, &args);

        var buffer: [1024]u8 = undefined;
        _ = try message.serialize(&buffer);

        var deserialized = try protocol.Message.deserialize(alloc, buffer[0..message.header.size], "sa");
        deserialized.deinit();
        message.deinit();
    }

    const stats = tracking.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.leak_count);
}

test "Concurrent message creation" {
    const ThreadContext = struct {
        fn worker(allocator: std.mem.Allocator, id: u32) !void {
            for (0..100) |i| {
                const args = [_]protocol.Argument{
                    .{ .uint = id },
                    .{ .int = @intCast(i) },
                };

                var message = try protocol.Message.init(allocator, id, @intCast(i), &args);
                defer message.deinit();

                var buffer: [1024]u8 = undefined;
                _ = try message.serialize(&buffer);
            }
        }
    };

    var threads: [4]std.Thread = undefined;

    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ std.testing.allocator, @intCast(i + 1) });
    }

    for (threads) |thread| {
        thread.join();
    }
}

test "Error context formatting" {
    const ctx = errors.ErrorContext.init(error.InvalidObject, "Test error message", .err)
        .withObject(42, "wl_surface")
        .withMethod("commit");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ctx.format("", .{}, stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "InvalidObject") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Test error message") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wl_surface") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "commit") != null);
}

test "ErrorHandler recovery strategies" {
    var handler = try errors.ErrorHandler.init(std.testing.allocator);
    defer handler.deinit();

    // Test default recovery strategies
    const ctx1 = errors.ErrorContext.init(error.WouldBlock, "Resource busy", .warning);
    const result1 = handler.handle(ctx1);
    try std.testing.expectError(error.ShouldRetry, result1);

    const ctx2 = errors.ErrorContext.init(error.BrokenPipe, "Connection lost", .err);
    const result2 = handler.handle(ctx2);
    try std.testing.expectError(error.ShouldReconnect, result2);

    // Test custom strategy
    try handler.setStrategy(error.InvalidObject, .fatal);
    const ctx3 = errors.ErrorContext.init(error.InvalidObject, "Bad object", .err);
    const result3 = handler.handle(ctx3);
    try std.testing.expectError(error.InvalidObject, result3);
}