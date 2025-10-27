const std = @import("std");
const testing = std.testing;
const wzl = @import("wzl");
const protocol = wzl.protocol;

test "Stress: 10K message creation and serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in 10K message stress test");
        }
    }
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    const start_time = std.time.milliTimestamp();

    // Create and serialize 10,000 messages
    for (0..10_000) |i| {
        const message = try protocol.Message.init(
            allocator,
            @intCast((i % 65535) + 1),
            @intCast(i % 256),
            &[_]protocol.Argument{
                .{ .uint = @intCast(i) },
            },
        );

        _ = try message.serialize(&buffer);
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("10K messages processed in {}ms\n", .{elapsed_ms});
}

test "Stress: 100K small allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in 100K allocations stress test");
        }
    }
    const allocator = gpa.allocator();

    const start_time = std.time.milliTimestamp();

    // Allocate and immediately free 100K small buffers
    for (0..100_000) |_| {
        const small_buf = try allocator.alloc(u8, 64);
        allocator.free(small_buf);
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("100K allocations in {}ms\n", .{elapsed_ms});
}

test "Stress: 1000 concurrent objects" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in concurrent objects stress test");
        }
    }
    const allocator = gpa.allocator();

    // Simulate object management
    var objects = std.AutoHashMap(u32, ObjectData).init(allocator);
    defer objects.deinit();

    const start_time = std.time.milliTimestamp();

    // Create 1000 objects
    for (0..1000) |i| {
        const id: u32 = @intCast(i + 1);
        try objects.put(id, .{
            .id = id,
            .interface_name = "wl_surface",
            .version = 4,
        });
    }

    try testing.expectEqual(@as(usize, 1000), objects.count());

    // Destroy half of them
    for (0..500) |i| {
        const id: u32 = @intCast(i + 1);
        _ = objects.remove(id);
    }

    try testing.expectEqual(@as(usize, 500), objects.count());

    // Create more objects
    for (1000..2000) |i| {
        const id: u32 = @intCast(i + 1);
        try objects.put(id, .{
            .id = id,
            .interface_name = "wl_buffer",
            .version = 1,
        });
    }

    try testing.expectEqual(@as(usize, 1500), objects.count());

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("Object lifecycle stress test: {}ms\n", .{elapsed_ms});
}

test "Stress: large message serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in large message stress test");
        }
    }
    const allocator = gpa.allocator();

    // Create large string for message
    const large_string = try allocator.alloc(u8, 4000);
    defer allocator.free(large_string);
    @memset(large_string, 'X');

    var large_buffer: [8192]u8 = undefined;

    const start_time = std.time.milliTimestamp();

    // Serialize 1000 large messages
    for (0..1000) |i| {
        const message = try protocol.Message.init(
            allocator,
            @intCast(i + 1),
            0,
            &[_]protocol.Argument{
                .{ .string = large_string },
            },
        );

        _ = try message.serialize(&large_buffer);
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("1000 large messages in {}ms\n", .{elapsed_ms});
}

test "Stress: HashMap operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in HashMap stress test");
        }
    }
    const allocator = gpa.allocator();

    var map = std.AutoHashMap(u32, u32).init(allocator);
    defer map.deinit();

    const start_time = std.time.milliTimestamp();

    // Insert 10K entries
    for (0..10_000) |i| {
        try map.put(@intCast(i), @intCast(i * 2));
    }

    // Lookup all entries
    for (0..10_000) |i| {
        const value = map.get(@intCast(i));
        try testing.expectEqual(@as(u32, @intCast(i * 2)), value.?);
    }

    // Remove every other entry
    for (0..10_000) |i| {
        if (i % 2 == 0) {
            _ = map.remove(@intCast(i));
        }
    }

    try testing.expectEqual(@as(usize, 5000), map.count());

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("HashMap stress test: {}ms\n", .{elapsed_ms});
}

test "Stress: ArrayList growth" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in ArrayList stress test");
        }
    }
    const allocator = gpa.allocator();

    var list = std.ArrayList(MessageData).init(allocator);
    defer list.deinit();

    const start_time = std.time.milliTimestamp();

    // Add 50K items (tests reallocation)
    for (0..50_000) |i| {
        try list.append(.{
            .object_id = @intCast(i),
            .opcode = @intCast(i % 256),
            .size = @intCast(i % 1024),
        });
    }

    try testing.expectEqual(@as(usize, 50_000), list.items.len);

    // Remove from end
    while (list.items.len > 25_000) {
        _ = list.pop();
    }

    try testing.expectEqual(@as(usize, 25_000), list.items.len);

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("ArrayList stress test: {}ms\n", .{elapsed_ms});
}

test "Stress: string operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in string operations stress test");
        }
    }
    const allocator = gpa.allocator();

    const start_time = std.time.milliTimestamp();

    // Allocate and duplicate 5000 strings
    for (0..5000) |i| {
        var buf: [128]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "interface_{}", .{i});
        const dup = try allocator.dupe(u8, str);
        defer allocator.free(dup);

        try testing.expect(dup.len > 0);
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("String operations stress test: {}ms\n", .{elapsed_ms});
}

test "Stress: nested data structures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in nested structures stress test");
        }
    }
    const allocator = gpa.allocator();

    var outer_map = std.AutoHashMap(u32, std.ArrayList(u32)).init(allocator);
    defer {
        var it = outer_map.valueIterator();
        while (it.next()) |list| {
            list.deinit();
        }
        outer_map.deinit();
    }

    const start_time = std.time.milliTimestamp();

    // Create nested structure: map of lists
    for (0..100) |i| {
        var list = std.ArrayList(u32).init(allocator);
        for (0..100) |j| {
            try list.append(@intCast(j));
        }
        try outer_map.put(@intCast(i), list);
    }

    try testing.expectEqual(@as(usize, 100), outer_map.count());

    // Verify nested data
    for (0..100) |i| {
        const list = outer_map.get(@intCast(i)).?;
        try testing.expectEqual(@as(usize, 100), list.items.len);
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("Nested structures stress test: {}ms\n", .{elapsed_ms});
}

test "Stress: memory pressure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in memory pressure stress test");
        }
    }
    const allocator = gpa.allocator();

    const start_time = std.time.milliTimestamp();

    // Simulate memory pressure with large allocations
    var large_allocs = std.ArrayList([]u8).init(allocator);
    defer {
        for (large_allocs.items) |alloc| {
            allocator.free(alloc);
        }
        large_allocs.deinit();
    }

    // Allocate 100 * 1MB buffers = 100MB
    for (0..100) |_| {
        const large = try allocator.alloc(u8, 1024 * 1024);
        @memset(large, 0xAA);
        try large_allocs.append(large);
    }

    try testing.expectEqual(@as(usize, 100), large_allocs.items.len);

    // Verify data integrity
    for (large_allocs.items) |alloc| {
        try testing.expectEqual(@as(u8, 0xAA), alloc[0]);
        try testing.expectEqual(@as(u8, 0xAA), alloc[alloc.len - 1]);
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("Memory pressure test: {}ms\n", .{elapsed_ms});
}

test "Stress: rapid object creation and destruction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in rapid object lifecycle stress test");
        }
    }
    const allocator = gpa.allocator();

    const start_time = std.time.milliTimestamp();

    // Rapid create/destroy cycles
    for (0..1000) |_| {
        var temp_objects = std.AutoHashMap(u32, ObjectData).init(allocator);
        defer temp_objects.deinit();

        // Create 100 objects
        for (0..100) |i| {
            try temp_objects.put(@intCast(i), .{
                .id = @intCast(i),
                .interface_name = "wl_surface",
                .version = 4,
            });
        }

        // All destroyed when temp_objects goes out of scope
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("Rapid lifecycle test: {}ms\n", .{elapsed_ms});
}

test "Stress: fragmentation test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in fragmentation stress test");
        }
    }
    const allocator = gpa.allocator();

    const start_time = std.time.milliTimestamp();

    // Allocate varying sizes to test fragmentation
    var allocs = std.ArrayList([]u8).init(allocator);
    defer {
        for (allocs.items) |alloc| {
            allocator.free(alloc);
        }
        allocs.deinit();
    }

    const sizes = [_]usize{ 16, 64, 256, 1024, 4096, 16384 };

    // Allocate in mixed sizes
    for (0..1000) |i| {
        const size = sizes[i % sizes.len];
        const buf = try allocator.alloc(u8, size);
        try allocs.append(buf);
    }

    // Free every other allocation
    var i: usize = allocs.items.len;
    while (i > 0) {
        i -= 1;
        if (i % 2 == 0) {
            allocator.free(allocs.items[i]);
            _ = allocs.orderedRemove(i);
        }
    }

    try testing.expect(allocs.items.len > 0);

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    std.debug.print("Fragmentation test: {}ms\n", .{elapsed_ms});
}

// Helper structures
const ObjectData = struct {
    id: u32,
    interface_name: []const u8,
    version: u32,
};

const MessageData = struct {
    object_id: u32,
    opcode: u16,
    size: u16,
};
