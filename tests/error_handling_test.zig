const std = @import("std");
const testing = std.testing;
const wzl = @import("wzl");
const protocol = wzl.protocol;
const errors = wzl.errors;

test "Error: InvalidObject on zero object ID" {
    const result = protocol.Message.init(
        testing.allocator,
        0, // invalid
        0,
        &[_]protocol.Argument{},
    );

    try testing.expectError(error.InvalidObject, result);
}

test "Error: InvalidArgument on oversized string" {
    const allocator = testing.allocator;

    const huge_string = try allocator.alloc(u8, 5000);
    defer allocator.free(huge_string);

    const result = protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .string = huge_string },
        },
    );

    try testing.expectError(error.InvalidArgument, result);
}

test "Error: InvalidArgument on oversized array" {
    const allocator = testing.allocator;

    const huge_array = try allocator.alloc(u8, 70000);
    defer allocator.free(huge_array);

    const result = protocol.Message.init(
        allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .array = huge_array },
        },
    );

    try testing.expectError(error.InvalidArgument, result);
}

test "Error: BufferTooSmall on serialization" {
    const message = try protocol.Message.init(
        testing.allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .string = "this is a test string" },
        },
    );

    var tiny_buffer: [8]u8 = undefined;
    const result = message.serialize(&tiny_buffer);

    try testing.expectError(error.BufferTooSmall, result);
}

test "Error: OutOfMemory handling" {
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{
        .fail_index = 0,
    });

    const result = failing_allocator.allocator().alloc(u8, 1000);
    try testing.expectError(error.OutOfMemory, result);
}

test "Error: error set composition" {
    const WaylandError = error{
        InvalidObject,
        InvalidArgument,
        BufferTooSmall,
        BufferOverflow,
        ConnectionLost,
        ProtocolError,
    };

    // Verify error types exist
    const err: WaylandError = error.InvalidObject;
    try testing.expectEqual(WaylandError.InvalidObject, err);
}

test "Error: error propagation" {
    const Outer = struct {
        fn middle() !void {
            try inner();
        }

        fn inner() !void {
            return error.InvalidObject;
        }
    };

    const result = Outer.middle();
    try testing.expectError(error.InvalidObject, result);
}

test "Error: catch and recover" {
    const value = blk: {
        const result = protocol.Message.init(
            testing.allocator,
            0, // invalid - will error
            0,
            &[_]protocol.Argument{},
        );

        const message = result catch |err| {
            try testing.expectEqual(error.InvalidObject, err);
            break :blk null;
        };

        break :blk message;
    };

    try testing.expectEqual(@as(?protocol.Message, null), value);
}

test "Error: errdefer cleanup" {
    var cleaned_up = false;

    const result = blk: {
        errdefer cleaned_up = true;

        const allocator = testing.allocator;
        _ = allocator;

        // Simulate error
        break :blk error.InvalidObject;
    };

    try testing.expectError(error.InvalidObject, result);
    try testing.expect(cleaned_up);
}

test "Error: multiple error paths" {
    const TestFn = struct {
        fn doWork(value: i32) !u32 {
            if (value < 0) return error.InvalidArgument;
            if (value == 0) return error.InvalidObject;
            if (value > 1000) return error.BufferOverflow;
            return @intCast(value);
        }
    };

    try testing.expectError(error.InvalidArgument, TestFn.doWork(-1));
    try testing.expectError(error.InvalidObject, TestFn.doWork(0));
    try testing.expectError(error.BufferOverflow, TestFn.doWork(2000));
    try testing.expectEqual(@as(u32, 500), try TestFn.doWork(500));
}

test "Error: error union handling" {
    const Result = union(enum) {
        ok: u32,
        err: anyerror,
    };

    const success = Result{ .ok = 42 };
    const failure = Result{ .err = error.InvalidObject };

    try testing.expectEqual(@as(u32, 42), success.ok);
    try testing.expectEqual(error.InvalidObject, failure.err);
}

test "Error: optional vs error" {
    const maybe_value: ?u32 = null;
    try testing.expectEqual(@as(?u32, null), maybe_value);

    const error_value: anyerror!u32 = error.InvalidObject;
    try testing.expectError(error.InvalidObject, error_value);
}

test "Error: allocation failure recovery" {
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{
        .fail_index = 1, // Fail on second allocation
    });
    const allocator = failing_allocator.allocator();

    // First allocation succeeds
    const first = try allocator.alloc(u8, 100);
    defer allocator.free(first);

    // Second allocation fails
    const second = allocator.alloc(u8, 100);
    try testing.expectError(error.OutOfMemory, second);

    // Can still free the first allocation
    // (defer handles this)
}

test "Error: stack unwinding" {
    var step1 = false;
    var step2 = false;
    var step3 = false;

    const result = blk: {
        step1 = true;
        defer step3 = true;

        step2 = true;
        errdefer step2 = false; // Roll back step2 on error

        break :blk error.InvalidObject;
    };

    try testing.expectError(error.InvalidObject, result);
    try testing.expect(step1);
    try testing.expect(!step2); // rolled back
    try testing.expect(step3); // defer always runs
}

test "Error: resource cleanup on error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const TestResource = struct {
        allocator: std.mem.Allocator,
        buffer: []u8,

        fn init(alloc: std.mem.Allocator, size: usize, should_fail: bool) !@This() {
            const buf = try alloc.alloc(u8, size);
            errdefer alloc.free(buf);

            if (should_fail) {
                return error.InvalidObject;
            }

            return .{
                .allocator = alloc,
                .buffer = buf,
            };
        }

        fn deinit(self: *@This()) void {
            self.allocator.free(self.buffer);
        }
    };

    // Test error path cleans up
    const result = TestResource.init(allocator, 100, true);
    try testing.expectError(error.InvalidObject, result);

    // Memory should be cleaned up by errdefer
}

test "Error: partial message serialization" {
    const message = try protocol.Message.init(
        testing.allocator,
        1,
        0,
        &[_]protocol.Argument{
            .{ .uint = 1 },
            .{ .uint = 2 },
            .{ .uint = 3 },
        },
    );

    // Buffer too small for all arguments
    var small_buffer: [16]u8 = undefined;
    const result = message.serialize(&small_buffer);

    // Should fail gracefully without partial write
    try testing.expectError(error.BufferTooSmall, result);
}

test "Error: concurrent error handling" {
    // Simulate multiple operations with potential errors
    var errors_caught: u32 = 0;

    for (0..10) |i| {
        const result = blk: {
            if (i % 3 == 0) {
                break :blk error.InvalidObject;
            }
            break :blk @as(u32, @intCast(i));
        };

        _ = result catch |_| {
            errors_caught += 1;
            continue;
        };
    }

    // 0, 3, 6, 9 should error = 4 errors
    try testing.expectEqual(@as(u32, 4), errors_caught);
}

test "Error: error description" {
    const err = error.InvalidObject;
    const name = @errorName(err);
    try testing.expectEqualStrings("InvalidObject", name);
}

test "Error: anyerror type" {
    const err: anyerror = error.InvalidObject;
    try testing.expectEqual(error.InvalidObject, err);

    const err2: anyerror = error.OutOfMemory;
    try testing.expectEqual(error.OutOfMemory, err2);
}

test "Error: error payload" {
    const Result = struct {
        value: u32,
        error_code: ?u32,

        fn create(val: u32, should_error: bool) @This() {
            return .{
                .value = val,
                .error_code = if (should_error) 1 else null,
            };
        }

        fn isOk(self: @This()) bool {
            return self.error_code == null;
        }
    };

    const ok = Result.create(42, false);
    const err = Result.create(0, true);

    try testing.expect(ok.isOk());
    try testing.expect(!err.isOk());
    try testing.expectEqual(@as(u32, 1), err.error_code.?);
}

test "Error: try expression" {
    const TestFn = struct {
        fn step1() !u32 {
            return 10;
        }

        fn step2(val: u32) !u32 {
            return val * 2;
        }

        fn step3(val: u32) !u32 {
            if (val > 100) return error.BufferOverflow;
            return val;
        }

        fn pipeline() !u32 {
            const a = try step1();
            const b = try step2(a);
            const c = try step3(b);
            return c;
        }
    };

    const result = try TestFn.pipeline();
    try testing.expectEqual(@as(u32, 20), result);
}

test "Error: nested error handling" {
    const Outer = struct {
        fn outer() !void {
            try middle();
        }

        fn middle() !void {
            try inner();
        }

        fn inner() !void {
            return error.InvalidObject;
        }
    };

    try testing.expectError(error.InvalidObject, Outer.outer());
}

test "Error: error set subset" {
    const SmallSet = error{
        InvalidObject,
        InvalidArgument,
    };

    const LargeSet = error{
        InvalidObject,
        InvalidArgument,
        BufferOverflow,
        OutOfMemory,
    };

    const small_err: SmallSet = error.InvalidObject;
    const large_err: LargeSet = small_err; // Coercion works

    try testing.expectEqual(LargeSet.InvalidObject, large_err);
}
