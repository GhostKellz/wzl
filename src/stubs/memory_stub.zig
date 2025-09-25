// Memory tracking stub - provides no-op implementations when memory tracking is disabled

pub const TrackingAllocator = struct {
    backing_allocator: @import("std").mem.Allocator,

    pub fn init(backing_allocator: @import("std").mem.Allocator) !TrackingAllocator {
        return .{ .backing_allocator = backing_allocator };
    }

    pub fn deinit(self: *TrackingAllocator) void {
        _ = self;
    }

    pub fn allocator(self: *TrackingAllocator) @import("std").mem.Allocator {
        return self.backing_allocator;
    }

    pub const Stats = struct {
        total_allocated: usize = 0,
        total_freed: usize = 0,
        current_usage: usize = 0,
        peak_usage: usize = 0,
        allocation_count: usize = 0,
        free_count: usize = 0,
        leak_count: usize = 0,
    };

    pub fn getStats(self: *TrackingAllocator) Stats {
        _ = self;
        return .{};
    }

    pub fn detectLeaks(self: *TrackingAllocator, alloc: @import("std").mem.Allocator) ![]@import("std").mem.Allocator.Error {
        _ = self;
        _ = alloc;
        return &.{};
    }
};

pub fn PoolAllocator(comptime T: type) type {
    return struct {
        pub fn init(allocator: @import("std").mem.Allocator, size: usize) !@This() {
            _ = allocator;
            _ = size;
            return .{};
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }

        pub fn alloc(self: *@This()) !*T {
            _ = self;
            return @import("std").mem.Allocator.Error.OutOfMemory;
        }

        pub fn free(self: *@This(), ptr: *T) void {
            _ = self;
            _ = ptr;
        }
    };
}

pub const RingAllocator = struct {
    pub fn init(allocator: @import("std").mem.Allocator, size: usize) !RingAllocator {
        _ = allocator;
        _ = size;
        return .{};
    }

    pub fn deinit(self: *RingAllocator, allocator: @import("std").mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn alloc(self: *RingAllocator, size: usize, alignment: u8) ?[]u8 {
        _ = self;
        _ = size;
        _ = alignment;
        return null;
    }
};