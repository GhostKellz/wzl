const std = @import("std");
const testing = std.testing;
const wzl = @import("wzl");
const protocol = wzl.protocol;

test "Memory: message allocation and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
            @panic("Memory leak in message allocation test");
        }
    }
    const allocator = gpa.allocator();

    // Create and immediately release message
    {
        const message = try protocol.Message.init(
            allocator,
            1,
            0,
            &[_]protocol.Argument{
                .{ .uint = 42 },
            },
        );
        _ = message;
    }
}

test "Memory: string argument allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in string allocation!\n", .{});
            @panic("Memory leak");
        }
    }
    const allocator = gpa.allocator();

    const test_string = try allocator.dupe(u8, "test string");
    defer allocator.free(test_string);

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .string = test_string },
        },
    );
    _ = message;
}

test "Memory: array argument allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in array allocation!\n", .{});
            @panic("Memory leak");
        }
    }
    const allocator = gpa.allocator();

    const test_array = try allocator.alloc(u8, 100);
    defer allocator.free(test_array);

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .array = test_array },
        },
    );
    _ = message;
}

test "Memory: multiple messages lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in multiple messages test");
        }
    }
    const allocator = gpa.allocator();

    // Create 100 messages
    for (0..100) |i| {
        const message = try protocol.Message.init(
            allocator,
            @intCast(i + 1),
            0,
            &[_]protocol.Argument{
                .{ .uint = @intCast(i) },
            },
        );
        _ = message;
    }
}

test "Memory: large allocation and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in large allocation test");
        }
    }
    const allocator = gpa.allocator();

    // Allocate large buffer
    const large_buffer = try allocator.alloc(u8, 1024 * 1024); // 1MB
    defer allocator.free(large_buffer);

    @memset(large_buffer, 0xFF);

    // Verify allocation worked
    try testing.expectEqual(@as(u8, 0xFF), large_buffer[0]);
    try testing.expectEqual(@as(u8, 0xFF), large_buffer[large_buffer.len - 1]);
}

test "Memory: HashMap lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in HashMap test");
        }
    }
    const allocator = gpa.allocator();

    var map = std.AutoHashMap(u32, u32).init(allocator);
    defer map.deinit();

    // Insert many entries
    for (0..1000) |i| {
        try map.put(@intCast(i), @intCast(i * 2));
    }

    // Remove all entries
    var it = map.keyIterator();
    while (it.next()) |key| {
        _ = map.remove(key.*);
    }
}

test "Memory: ArrayList lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in ArrayList test");
        }
    }
    const allocator = gpa.allocator();

    var list = std.ArrayList(u32).init(allocator);
    defer list.deinit();

    // Add many items
    for (0..1000) |i| {
        try list.append(@intCast(i));
    }

    // Clear list
    list.clearRetainingCapacity();
}

test "Memory: repeated allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in repeated allocations test");
        }
    }
    const allocator = gpa.allocator();

    // Repeatedly allocate and free
    for (0..100) |_| {
        const buffer = try allocator.alloc(u8, 256);
        allocator.free(buffer);
    }
}

test "Memory: nested structures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in nested structures test");
        }
    }
    const allocator = gpa.allocator();

    const Inner = struct {
        data: []u8,
    };

    const Outer = struct {
        inner: Inner,
        name: []const u8,
    };

    const inner_data = try allocator.alloc(u8, 50);
    defer allocator.free(inner_data);

    const name = try allocator.dupe(u8, "test");
    defer allocator.free(name);

    const outer = Outer{
        .inner = Inner{ .data = inner_data },
        .name = name,
    };

    try testing.expectEqual(@as(usize, 50), outer.inner.data.len);
    try testing.expectEqualStrings("test", outer.name);
}

test "Memory: arena allocator cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in arena test");
        }
    }
    const backing_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Make many small allocations (arena will clean them all up)
    for (0..1000) |_| {
        const small_alloc = try allocator.alloc(u8, 16);
        _ = small_alloc;
    }

    // Arena deinit will clean everything
}

test "Memory: string duplication" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in string duplication test");
        }
    }
    const allocator = gpa.allocator();

    const original = "original string";

    const copy1 = try allocator.dupe(u8, original);
    defer allocator.free(copy1);

    const copy2 = try allocator.dupe(u8, original);
    defer allocator.free(copy2);

    try testing.expectEqualStrings(original, copy1);
    try testing.expectEqualStrings(original, copy2);
}

test "Memory: allocation failure handling" {
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const allocator = failing_allocator.allocator();

    // First allocation should fail
    const result = allocator.alloc(u8, 100);
    try testing.expectError(error.OutOfMemory, result);
}

test "Memory: buffer serialization no leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in buffer serialization test");
        }
    }
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;

    for (0..100) |i| {
        const message = try protocol.Message.init(
            allocator,
            @intCast(i + 1),
            0,
            &[_]protocol.Argument{
                .{ .uint = @intCast(i) },
                .{ .int = @intCast(-(i + 1)) },
            },
        );

        _ = try message.serialize(&buffer);
    }
}

test "Memory: complex message lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in complex message test");
        }
    }
    const allocator = gpa.allocator();

    const test_string = try allocator.dupe(u8, "complex test");
    defer allocator.free(test_string);

    const test_array = try allocator.alloc(u8, 20);
    defer allocator.free(test_array);
    @memset(test_array, 42);

    const message = try protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .uint = 100 },
            .{ .string = test_string },
            .{ .array = test_array },
            .{ .int = -50 },
        },
    );
    _ = message;
}

test "Memory: zero-size allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in zero-size allocation test");
        }
    }
    const allocator = gpa.allocator();

    // Zero-size allocations should be handled gracefully
    const empty = try allocator.alloc(u8, 0);
    defer allocator.free(empty);

    try testing.expectEqual(@as(usize, 0), empty.len);
}

test "Memory: alignment requirements" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in alignment test");
        }
    }
    const allocator = gpa.allocator();

    // Test aligned allocations
    const aligned_buffer = try allocator.alignedAlloc(u8, 16, 256);
    defer allocator.free(aligned_buffer);

    // Verify alignment
    const addr = @intFromPtr(aligned_buffer.ptr);
    try testing.expectEqual(@as(usize, 0), addr % 16);
}

test "Memory: reallocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in reallocation test");
        }
    }
    const allocator = gpa.allocator();

    var buffer = try allocator.alloc(u8, 10);
    @memset(buffer, 1);

    // Grow buffer
    buffer = try allocator.realloc(buffer, 20);
    defer allocator.free(buffer);

    // Original data should be preserved
    try testing.expectEqual(@as(u8, 1), buffer[0]);
    try testing.expectEqual(@as(usize, 20), buffer.len);
}
