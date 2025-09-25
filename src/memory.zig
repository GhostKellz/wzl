const std = @import("std");

/// Memory tracking allocator for leak detection
pub const TrackingAllocator = struct {
    backing_allocator: std.mem.Allocator,
    allocations: std.AutoHashMap(usize, AllocationInfo),
    mutex: std.Thread.Mutex,
    total_allocated: usize,
    total_freed: usize,
    peak_allocated: usize,
    allocation_count: usize,
    free_count: usize,
    enable_tracking: bool,

    const AllocationInfo = struct {
        size: usize,
        alignment: u8,
        stack_trace: ?[]usize,
        timestamp: i64,
        tag: ?[]const u8,
    };

    pub fn init(backing_allocator: std.mem.Allocator) !TrackingAllocator {
        return TrackingAllocator{
            .backing_allocator = backing_allocator,
            .allocations = std.AutoHashMap(usize, AllocationInfo).init(backing_allocator),
            .mutex = std.Thread.Mutex{},
            .total_allocated = 0,
            .total_freed = 0,
            .peak_allocated = 0,
            .allocation_count = 0,
            .free_count = 0,
            .enable_tracking = true,
        };
    }

    pub fn deinit(self: *TrackingAllocator) void {
        self.allocations.deinit();
    }

    pub fn allocator(self: *TrackingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));

        const result = self.backing_allocator.rawAlloc(len, log2_ptr_align, ret_addr);

        if (result) |ptr| {
            if (self.enable_tracking) {
                self.mutex.lock();
                defer self.mutex.unlock();

                const addr = @intFromPtr(ptr);
                const info = AllocationInfo{
                    .size = len,
                    .alignment = log2_ptr_align,
                    .stack_trace = null,
                    .timestamp = std.time.milliTimestamp(),
                    .tag = null,
                };

                self.allocations.put(addr, info) catch {
                    self.backing_allocator.rawFree(ptr[0..len], log2_ptr_align, ret_addr);
                    return null;
                };

                self.total_allocated += len;
                self.allocation_count += 1;

                const current_usage = self.total_allocated - self.total_freed;
                if (current_usage > self.peak_allocated) {
                    self.peak_allocated = current_usage;
                }
            }
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_ptr_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));

        const old_size = buf.len;
        const result = self.backing_allocator.rawResize(buf, log2_ptr_align, new_len, ret_addr);

        if (result and self.enable_tracking) {
            self.mutex.lock();
            defer self.mutex.unlock();

            const addr = @intFromPtr(buf.ptr);
            if (self.allocations.get(addr)) |*info| {
                const size_diff = if (new_len > old_size) new_len - old_size else old_size - new_len;

                if (new_len > old_size) {
                    self.total_allocated += size_diff;
                } else {
                    self.total_freed += size_diff;
                }

                info.size = new_len;

                const current_usage = self.total_allocated - self.total_freed;
                if (current_usage > self.peak_allocated) {
                    self.peak_allocated = current_usage;
                }
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_ptr_align: u8, ret_addr: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));

        if (self.enable_tracking) {
            self.mutex.lock();
            defer self.mutex.unlock();

            const addr = @intFromPtr(buf.ptr);
            if (self.allocations.fetchRemove(addr)) |entry| {
                self.total_freed += entry.value.size;
                self.free_count += 1;
            }
        }

        self.backing_allocator.rawFree(buf, log2_ptr_align, ret_addr);
    }

    pub fn getStats(self: *TrackingAllocator) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return Stats{
            .total_allocated = self.total_allocated,
            .total_freed = self.total_freed,
            .current_usage = self.total_allocated - self.total_freed,
            .peak_usage = self.peak_allocated,
            .allocation_count = self.allocation_count,
            .free_count = self.free_count,
            .leak_count = self.allocation_count - self.free_count,
        };
    }

    pub fn detectLeaks(self: *TrackingAllocator, leak_alloc: std.mem.Allocator) ![]LeakInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        var leaks = std.ArrayList(LeakInfo).init(leak_alloc);
        errdefer leaks.deinit();

        var iter = self.allocations.iterator();
        while (iter.next()) |entry| {
            try leaks.append(LeakInfo{
                .address = entry.key_ptr.*,
                .size = entry.value_ptr.size,
                .alignment = entry.value_ptr.alignment,
                .timestamp = entry.value_ptr.timestamp,
                .tag = entry.value_ptr.tag,
            });
        }

        return leaks.toOwnedSlice();
    }

    pub fn reset(self: *TrackingAllocator) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.allocations.clearRetainingCapacity();
        self.total_allocated = 0;
        self.total_freed = 0;
        self.peak_allocated = 0;
        self.allocation_count = 0;
        self.free_count = 0;
    }

    pub fn setTracking(self: *TrackingAllocator, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enable_tracking = enabled;
    }

    pub const Stats = struct {
        total_allocated: usize,
        total_freed: usize,
        current_usage: usize,
        peak_usage: usize,
        allocation_count: usize,
        free_count: usize,
        leak_count: usize,

        pub fn format(
            self: Stats,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            try writer.print(
                \\Memory Statistics:
                \\  Total Allocated: {} bytes
                \\  Total Freed: {} bytes
                \\  Current Usage: {} bytes
                \\  Peak Usage: {} bytes
                \\  Allocations: {}
                \\  Frees: {}
                \\  Potential Leaks: {}
            , .{
                self.total_allocated,
                self.total_freed,
                self.current_usage,
                self.peak_usage,
                self.allocation_count,
                self.free_count,
                self.leak_count,
            });
        }
    };

    pub const LeakInfo = struct {
        address: usize,
        size: usize,
        alignment: u8,
        timestamp: i64,
        tag: ?[]const u8,

        pub fn format(
            self: LeakInfo,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            try writer.print("Leak at 0x{x}: {} bytes", .{ self.address, self.size });
            if (self.tag) |tag| {
                try writer.print(" [{}]", .{tag});
            }
        }
    };
};

/// Pool allocator for efficient fixed-size allocations
pub fn PoolAllocator(comptime T: type) type {
    return struct {
        const Self = @This();

        backing_allocator: std.mem.Allocator,
        free_list: ?*Node,
        allocated_blocks: std.ArrayList([*]T),
        block_size: usize,
        mutex: std.Thread.Mutex,

        const Node = struct {
            next: ?*Node,
        };

        pub fn init(allocator: std.mem.Allocator, block_size: usize) !Self {
            return Self{
                .backing_allocator = allocator,
                .free_list = null,
                .allocated_blocks = std.ArrayList([*]T).init(allocator),
                .block_size = block_size,
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.allocated_blocks.items) |block| {
                self.backing_allocator.free(block[0..self.block_size]);
            }
            self.allocated_blocks.deinit();
        }

        pub fn alloc(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.free_list) |node| {
                self.free_list = node.next;
                const ptr: *T = @ptrCast(@alignCast(node));
                ptr.* = undefined;
                return ptr;
            }

            // Allocate new block
            const block = try self.backing_allocator.alloc(T, self.block_size);
            try self.allocated_blocks.append(block.ptr);

            // Add all but first to free list
            for (block[1..]) |*item| {
                const node: *Node = @ptrCast(@alignCast(item));
                node.next = self.free_list;
                self.free_list = node;
            }

            return &block[0];
        }

        pub fn free(self: *Self, ptr: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const node: *Node = @ptrCast(@alignCast(ptr));
            node.next = self.free_list;
            self.free_list = node;
        }

        pub fn reset(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.free_list = null;
            for (self.allocated_blocks.items) |block| {
                for (block[0..self.block_size]) |*item| {
                    const node: *Node = @ptrCast(@alignCast(item));
                    node.next = self.free_list;
                    self.free_list = node;
                }
            }
        }
    };
}

/// Ring buffer allocator for temporary allocations
pub const RingAllocator = struct {
    buffer: []u8,
    head: usize,
    tail: usize,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, size: usize) !RingAllocator {
        return RingAllocator{
            .buffer = try allocator.alloc(u8, size),
            .head = 0,
            .tail = 0,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *RingAllocator, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
    }

    pub fn alloc(self: *RingAllocator, size: usize, alignment: u8) ?[]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const align_mask = (@as(usize, 1) << @intCast(alignment)) - 1;
        const aligned_head = (self.head + align_mask) & ~align_mask;

        if (aligned_head + size > self.buffer.len) {
            // Wrap around if needed
            if (size > self.tail) return null;
            self.head = 0;
            return self.buffer[0..size];
        }

        if (aligned_head + size > self.tail and self.tail > self.head) {
            return null;
        }

        const result = self.buffer[aligned_head..aligned_head + size];
        self.head = aligned_head + size;
        return result;
    }

    pub fn reset(self: *RingAllocator) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.head = 0;
        self.tail = 0;
    }

    pub fn advance(self: *RingAllocator, new_tail: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.tail = new_tail;
    }
};

test "TrackingAllocator leak detection" {
    var tracking = try TrackingAllocator.init(std.testing.allocator);
    defer tracking.deinit();

    const alloc = tracking.allocator();

    // Allocate some memory
    const ptr1 = try alloc.alloc(u8, 100);
    const ptr2 = try alloc.alloc(u8, 200);

    // Free only one
    alloc.free(ptr1);

    // Check stats
    const stats = tracking.getStats();
    try std.testing.expectEqual(@as(usize, 300), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 100), stats.total_freed);
    try std.testing.expectEqual(@as(usize, 200), stats.current_usage);
    try std.testing.expectEqual(@as(usize, 1), stats.leak_count);

    // Detect leaks
    const leaks = try tracking.detectLeaks(std.testing.allocator);
    defer std.testing.allocator.free(leaks);

    try std.testing.expectEqual(@as(usize, 1), leaks.len);
    try std.testing.expectEqual(@as(usize, 200), leaks[0].size);

    // Clean up
    alloc.free(ptr2);
}

test "PoolAllocator" {
    const TestStruct = struct {
        value: u32,
        data: [64]u8,
    };

    var pool = try PoolAllocator(TestStruct).init(std.testing.allocator, 10);
    defer pool.deinit();

    var ptrs = std.ArrayList(*TestStruct).init(std.testing.allocator);
    defer ptrs.deinit();

    // Allocate items
    for (0..5) |i| {
        const item = try pool.alloc();
        item.value = @intCast(i);
        try ptrs.append(item);
    }

    // Free some items
    pool.free(ptrs.items[0]);
    pool.free(ptrs.items[2]);

    // Allocate again (should reuse)
    const item1 = try pool.alloc();
    const item2 = try pool.alloc();

    item1.value = 100;
    item2.value = 200;
}

test "RingAllocator" {
    var ring = try RingAllocator.init(std.testing.allocator, 1024);
    defer ring.deinit(std.testing.allocator);

    const ptr1 = ring.alloc(100, 3).?;
    const ptr2 = ring.alloc(200, 3).?;

    @memset(ptr1, 0xAA);
    @memset(ptr2, 0xBB);

    ring.advance(100);

    const ptr3 = ring.alloc(50, 3).?;
    @memset(ptr3, 0xCC);
}