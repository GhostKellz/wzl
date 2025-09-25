const std = @import("std");

/// Thread-safe object registry
pub fn Registry(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        objects: std.AutoHashMap(u32, *T),
        mutex: std.Thread.RwLock,
        next_id: std.atomic.Value(u32),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .objects = std.AutoHashMap(u32, *T).init(allocator),
                .mutex = std.Thread.RwLock{},
                .next_id = std.atomic.Value(u32).init(1),
            };
        }

        pub fn deinit(self: *Self) void {
            self.objects.deinit();
        }

        pub fn add(self: *Self, object: *T) !u32 {
            const id = self.next_id.fetchAdd(1, .seq_cst);

            self.mutex.lock();
            defer self.mutex.unlock();

            try self.objects.put(id, object);
            return id;
        }

        pub fn remove(self: *Self, id: u32) ?*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.objects.fetchRemove(id)) |entry| {
                return entry.value;
            }
            return null;
        }

        pub fn get(self: *Self, id: u32) ?*T {
            self.mutex.lockShared();
            defer self.mutex.unlockShared();

            return self.objects.get(id);
        }

        pub fn contains(self: *Self, id: u32) bool {
            self.mutex.lockShared();
            defer self.mutex.unlockShared();

            return self.objects.contains(id);
        }

        pub fn count(self: *Self) usize {
            self.mutex.lockShared();
            defer self.mutex.unlockShared();

            return self.objects.count();
        }
    };
}

/// Thread-safe message queue
pub fn MessageQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        messages: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,
        closed: std.atomic.Value(bool),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .messages = std.ArrayList(T).init(allocator),
                .mutex = std.Thread.Mutex{},
                .condition = std.Thread.Condition{},
                .closed = std.atomic.Value(bool).init(false),
            };
        }

        pub fn deinit(self: *Self) void {
            self.messages.deinit();
        }

        pub fn push(self: *Self, message: T) !void {
            if (self.closed.load(.seq_cst)) return error.QueueClosed;

            self.mutex.lock();
            defer self.mutex.unlock();

            try self.messages.append(message);
            self.condition.signal();
        }

        pub fn pushBatch(self: *Self, messages: []const T) !void {
            if (self.closed.load(.seq_cst)) return error.QueueClosed;

            self.mutex.lock();
            defer self.mutex.unlock();

            try self.messages.appendSlice(messages);
            self.condition.broadcast();
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.messages.items.len == 0) return null;
            return self.messages.orderedRemove(0);
        }

        pub fn popWait(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.messages.items.len == 0) {
                if (self.closed.load(.seq_cst)) return error.QueueClosed;
                self.condition.wait(&self.mutex);
            }

            return self.messages.orderedRemove(0);
        }

        pub fn popTimeout(self: *Self, timeout_ns: u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.messages.items.len == 0) {
                if (self.closed.load(.seq_cst)) return error.QueueClosed;
                self.condition.timedWait(&self.mutex, timeout_ns) catch {
                    if (self.messages.items.len == 0) return error.Timeout;
                };
            }

            if (self.messages.items.len == 0) return error.Timeout;
            return self.messages.orderedRemove(0);
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.messages.items.len;
        }

        pub fn close(self: *Self) void {
            self.closed.store(true, .seq_cst);
            self.condition.broadcast();
        }

        pub fn isClosed(self: *Self) bool {
            return self.closed.load(.seq_cst);
        }
    };
}

/// Thread-safe event dispatcher
pub const EventDispatcher = struct {
    const HandlerFn = *const fn (event: anytype) void;
    const HandlerEntry = struct {
        handler: HandlerFn,
        type_id: usize,
    };

    allocator: std.mem.Allocator,
    handlers: std.ArrayList(HandlerEntry),
    mutex: std.Thread.RwLock,

    pub fn init(allocator: std.mem.Allocator) EventDispatcher {
        return .{
            .allocator = allocator,
            .handlers = std.ArrayList(HandlerEntry).init(allocator),
            .mutex = std.Thread.RwLock{},
        };
    }

    pub fn deinit(self: *EventDispatcher) void {
        self.handlers.deinit();
    }

    pub fn subscribe(self: *EventDispatcher, comptime T: type, handler: *const fn (T) void) !void {
        const type_id = @intFromPtr(&T);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.handlers.append(.{
            .handler = @ptrCast(handler),
            .type_id = type_id,
        });
    }

    pub fn dispatch(self: *EventDispatcher, event: anytype) void {
        const T = @TypeOf(event);
        const type_id = @intFromPtr(&T);

        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        for (self.handlers.items) |entry| {
            if (entry.type_id == type_id) {
                const typed_handler: *const fn (T) void = @ptrCast(entry.handler);
                typed_handler(event);
            }
        }
    }
};

/// Lock-free ring buffer for single producer, single consumer
pub fn SPSCRingBuffer(comptime T: type, comptime size: usize) type {
    const size_power_of_two = std.math.ceilPowerOfTwo(usize, size) catch unreachable;
    const mask = size_power_of_two - 1;

    return struct {
        const Self = @This();

        buffer: [size_power_of_two]T,
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),

        pub fn init() Self {
            return .{
                .buffer = undefined,
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
            };
        }

        pub fn push(self: *Self, item: T) bool {
            const current_head = self.head.load(.acquire);
            const next_head = (current_head + 1) & mask;

            if (next_head == self.tail.load(.acquire)) {
                return false; // Buffer full
            }

            self.buffer[current_head] = item;
            self.head.store(next_head, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            const current_tail = self.tail.load(.acquire);

            if (current_tail == self.head.load(.acquire)) {
                return null; // Buffer empty
            }

            const item = self.buffer[current_tail];
            self.tail.store((current_tail + 1) & mask, .release);
            return item;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.head.load(.acquire) == self.tail.load(.acquire);
        }

        pub fn isFull(self: *Self) bool {
            const current_head = self.head.load(.acquire);
            const next_head = (current_head + 1) & mask;
            return next_head == self.tail.load(.acquire);
        }

        pub fn len(self: *Self) usize {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            return (head + size_power_of_two - tail) & mask;
        }
    };
}

/// Atomic reference counting
pub fn AtomicRefCounted(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        ref_count: std.atomic.Value(u32),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, data: T) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .data = data,
                .ref_count = std.atomic.Value(u32).init(1),
                .allocator = allocator,
            };
            return self;
        }

        pub fn retain(self: *Self) void {
            _ = self.ref_count.fetchAdd(1, .seq_cst);
        }

        pub fn release(self: *Self) void {
            if (self.ref_count.fetchSub(1, .seq_cst) == 1) {
                if (@hasDecl(T, "deinit")) {
                    self.data.deinit();
                }
                self.allocator.destroy(self);
            }
        }

        pub fn getRefCount(self: *const Self) u32 {
            return self.ref_count.load(.seq_cst);
        }
    };
}

/// Thread-safe object pool
pub fn ThreadSafePool(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        free_list: std.ArrayList(*T),
        mutex: std.Thread.Mutex,
        factory: ?*const fn (std.mem.Allocator) anyerror!*T,
        reset_fn: ?*const fn (*T) void,
        max_size: usize,

        pub fn init(allocator: std.mem.Allocator, max_size: usize) Self {
            return .{
                .allocator = allocator,
                .free_list = std.ArrayList(*T).init(allocator),
                .mutex = std.Thread.Mutex{},
                .factory = null,
                .reset_fn = null,
                .max_size = max_size,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.free_list.items) |item| {
                if (@hasDecl(T, "deinit")) {
                    item.deinit();
                }
                self.allocator.destroy(item);
            }
            self.free_list.deinit();
        }

        pub fn setFactory(self: *Self, factory: *const fn (std.mem.Allocator) anyerror!*T) void {
            self.factory = factory;
        }

        pub fn setResetFn(self: *Self, reset_fn: *const fn (*T) void) void {
            self.reset_fn = reset_fn;
        }

        pub fn acquire(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.free_list.items.len > 0) {
                const item = self.free_list.pop();
                if (self.reset_fn) |reset| {
                    reset(item);
                }
                return item;
            }

            if (self.factory) |factory| {
                return try factory(self.allocator);
            }

            const item = try self.allocator.create(T);
            item.* = undefined;
            return item;
        }

        pub fn release(self: *Self, item: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.free_list.items.len >= self.max_size) {
                if (@hasDecl(T, "deinit")) {
                    item.deinit();
                }
                self.allocator.destroy(item);
                return;
            }

            self.free_list.append(item) catch {
                if (@hasDecl(T, "deinit")) {
                    item.deinit();
                }
                self.allocator.destroy(item);
            };
        }
    };
}

test "Registry thread safety" {
    const TestObject = struct {
        value: u32,
    };

    var registry = Registry(TestObject).init(std.testing.allocator);
    defer registry.deinit();

    var obj1 = TestObject{ .value = 42 };
    var obj2 = TestObject{ .value = 100 };

    const id1 = try registry.add(&obj1);
    const id2 = try registry.add(&obj2);

    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(&obj1, registry.get(id1).?);
    try std.testing.expectEqual(&obj2, registry.get(id2).?);

    _ = registry.remove(id1);
    try std.testing.expect(registry.get(id1) == null);
}

test "MessageQueue operations" {
    var queue = MessageQueue(u32).init(std.testing.allocator);
    defer queue.deinit();

    try queue.push(1);
    try queue.push(2);
    try queue.push(3);

    try std.testing.expectEqual(@as(usize, 3), queue.len());

    try std.testing.expectEqual(@as(u32, 1), queue.pop().?);
    try std.testing.expectEqual(@as(u32, 2), queue.pop().?);
    try std.testing.expectEqual(@as(u32, 3), queue.pop().?);
    try std.testing.expect(queue.pop() == null);
}

test "SPSCRingBuffer" {
    var ring = SPSCRingBuffer(u32, 4).init();

    try std.testing.expect(ring.push(1));
    try std.testing.expect(ring.push(2));
    try std.testing.expect(ring.push(3));
    try std.testing.expect(!ring.push(4)); // Buffer full

    try std.testing.expectEqual(@as(u32, 1), ring.pop().?);
    try std.testing.expectEqual(@as(u32, 2), ring.pop().?);

    try std.testing.expect(ring.push(4));
    try std.testing.expect(ring.push(5));

    try std.testing.expectEqual(@as(u32, 3), ring.pop().?);
    try std.testing.expectEqual(@as(u32, 4), ring.pop().?);
    try std.testing.expectEqual(@as(u32, 5), ring.pop().?);
    try std.testing.expect(ring.pop() == null);
}

test "AtomicRefCounted" {
    const TestData = struct {
        value: u32,
    };

    const ref = try AtomicRefCounted(TestData).init(
        std.testing.allocator,
        TestData{ .value = 42 },
    );

    try std.testing.expectEqual(@as(u32, 1), ref.getRefCount());

    ref.retain();
    try std.testing.expectEqual(@as(u32, 2), ref.getRefCount());

    ref.release();
    try std.testing.expectEqual(@as(u32, 1), ref.getRefCount());

    ref.release(); // This will deallocate
}