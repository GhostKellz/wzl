const std = @import("std");
const testing = std.testing;
const wzl = @import("wzl");
const protocol = wzl.protocol;

test "Thread: mutex basic locking" {
    var mutex = std.Thread.Mutex{};

    mutex.lock();
    defer mutex.unlock();

    // Critical section
    var value: u32 = 0;
    value = 42;

    try testing.expectEqual(@as(u32, 42), value);
}

test "Thread: concurrent counter with mutex" {
    const Counter = struct {
        mutex: std.Thread.Mutex,
        value: u32,

        fn init() @This() {
            return .{
                .mutex = .{},
                .value = 0,
            };
        }

        fn increment(self: *@This()) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.value += 1;
        }

        fn get(self: *@This()) u32 {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.value;
        }
    };

    var counter = Counter.init();

    // Single-threaded test
    for (0..1000) |_| {
        counter.increment();
    }

    try testing.expectEqual(@as(u32, 1000), counter.get());
}

test "Thread: RwLock read-write separation" {
    const Data = struct {
        lock: std.Thread.RwLock,
        value: u32,

        fn init() @This() {
            return .{
                .lock = .{},
                .value = 0,
            };
        }

        fn read(self: *@This()) u32 {
            self.lock.lockShared();
            defer self.lock.unlockShared();
            return self.value;
        }

        fn write(self: *@This(), val: u32) void {
            self.lock.lock();
            defer self.lock.unlock();
            self.value = val;
        }
    };

    var data = Data.init();

    // Write
    data.write(123);

    // Read
    try testing.expectEqual(@as(u32, 123), data.read());
}

test "Thread: atomic operations" {
    var atomic_value = std.atomic.Value(u32).init(0);

    // Atomic increment
    for (0..1000) |_| {
        _ = atomic_value.fetchAdd(1, .monotonic);
    }

    try testing.expectEqual(@as(u32, 1000), atomic_value.load(.monotonic));
}

test "Thread: atomic compare-and-swap" {
    var atomic_value = std.atomic.Value(u32).init(0);

    // Try to CAS from 0 to 1
    const old = atomic_value.cmpxchgStrong(0, 1, .seq_cst, .seq_cst);
    try testing.expectEqual(@as(?u32, null), old); // Success returns null

    // Try to CAS from 0 to 2 (should fail, value is now 1)
    const old2 = atomic_value.cmpxchgStrong(0, 2, .seq_cst, .seq_cst);
    try testing.expectEqual(@as(u32, 1), old2.?); // Failure returns old value
}

test "Thread: shared object registry" {
    const Registry = struct {
        mutex: std.Thread.Mutex,
        objects: std.AutoHashMap(u32, ObjectInfo),

        const ObjectInfo = struct {
            id: u32,
            interface: []const u8,
        };

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .mutex = .{},
                .objects = std.AutoHashMap(u32, ObjectInfo).init(allocator),
            };
        }

        fn deinit(self: *@This()) void {
            self.objects.deinit();
        }

        fn insert(self: *@This(), id: u32, interface: []const u8) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.objects.put(id, .{
                .id = id,
                .interface = interface,
            });
        }

        fn remove(self: *@This(), id: u32) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.objects.remove(id);
        }

        fn count(self: *@This()) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.objects.count();
        }
    };

    var registry = Registry.init(testing.allocator);
    defer registry.deinit();

    try registry.insert(1, "wl_surface");
    try registry.insert(2, "wl_buffer");

    try testing.expectEqual(@as(usize, 2), registry.count());

    try testing.expect(registry.remove(1));
    try testing.expectEqual(@as(usize, 1), registry.count());
}

test "Thread: message queue with mutex" {
    const MessageQueue = struct {
        mutex: std.Thread.Mutex,
        queue: std.ArrayList(u32),

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .mutex = .{},
                .queue = std.ArrayList(u32).init(allocator),
            };
        }

        fn deinit(self: *@This()) void {
            self.queue.deinit();
        }

        fn push(self: *@This(), value: u32) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.queue.append(value);
        }

        fn pop(self: *@This()) ?u32 {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.queue.items.len == 0) return null;
            return self.queue.orderedRemove(0);
        }

        fn len(self: *@This()) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.queue.items.len;
        }
    };

    var queue = MessageQueue.init(testing.allocator);
    defer queue.deinit();

    // Push messages
    try queue.push(1);
    try queue.push(2);
    try queue.push(3);

    try testing.expectEqual(@as(usize, 3), queue.len());

    // Pop messages
    try testing.expectEqual(@as(u32, 1), queue.pop().?);
    try testing.expectEqual(@as(u32, 2), queue.pop().?);
    try testing.expectEqual(@as(u32, 3), queue.pop().?);
    try testing.expectEqual(@as(?u32, null), queue.pop());
}

test "Thread: atomic state machine" {
    const State = enum(u32) {
        idle = 0,
        connecting = 1,
        connected = 2,
        disconnecting = 3,
        disconnected = 4,
    };

    var state = std.atomic.Value(u32).init(@intFromEnum(State.idle));

    // Transition idle -> connecting
    try testing.expectEqual(@as(u32, @intFromEnum(State.idle)), state.load(.acquire));

    state.store(@intFromEnum(State.connecting), .release);
    try testing.expectEqual(@as(u32, @intFromEnum(State.connecting)), state.load(.acquire));

    // Transition connecting -> connected
    state.store(@intFromEnum(State.connected), .release);
    try testing.expectEqual(@as(u32, @intFromEnum(State.connected)), state.load(.acquire));
}

test "Thread: lock ordering documentation" {
    // Document lock ordering to prevent deadlocks
    // Order: client_mutex -> registry_mutex -> object_mutex

    const Context = struct {
        client_mutex: std.Thread.Mutex,
        registry_mutex: std.Thread.Mutex,
        object_mutex: std.Thread.Mutex,

        fn init() @This() {
            return .{
                .client_mutex = .{},
                .registry_mutex = .{},
                .object_mutex = .{},
            };
        }

        fn correctOrder(self: *@This()) void {
            // Correct: lock in order
            self.client_mutex.lock();
            defer self.client_mutex.unlock();

            self.registry_mutex.lock();
            defer self.registry_mutex.unlock();

            self.object_mutex.lock();
            defer self.object_mutex.unlock();

            // Critical section
        }
    };

    var ctx = Context.init();
    ctx.correctOrder();
}

test "Thread: reference counting" {
    const RefCounted = struct {
        mutex: std.Thread.Mutex,
        ref_count: u32,
        data: u32,

        fn init(value: u32) @This() {
            return .{
                .mutex = .{},
                .ref_count = 1,
                .data = value,
            };
        }

        fn acquire(self: *@This()) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.ref_count += 1;
        }

        fn release(self: *@This()) u32 {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.ref_count -= 1;
            return self.ref_count;
        }
    };

    var obj = RefCounted.init(42);

    obj.acquire();
    try testing.expectEqual(@as(u32, 2), obj.ref_count);

    try testing.expectEqual(@as(u32, 1), obj.release());
    try testing.expectEqual(@as(u32, 0), obj.release());
}

test "Thread: wait-free data structure (SPSC queue concept)" {
    // Single Producer Single Consumer queue using atomics
    const SPSCQueue = struct {
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),
        buffer: [16]u32,

        fn init() @This() {
            return .{
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
                .buffer = [_]u32{0} ** 16,
            };
        }

        fn push(self: *@This(), value: u32) bool {
            const head = self.head.load(.acquire);
            const next_head = (head + 1) % self.buffer.len;

            if (next_head == self.tail.load(.acquire)) {
                return false; // Queue full
            }

            self.buffer[head] = value;
            self.head.store(next_head, .release);
            return true;
        }

        fn pop(self: *@This()) ?u32 {
            const tail = self.tail.load(.acquire);

            if (tail == self.head.load(.acquire)) {
                return null; // Queue empty
            }

            const value = self.buffer[tail];
            const next_tail = (tail + 1) % self.buffer.len;
            self.tail.store(next_tail, .release);
            return value;
        }
    };

    var queue = SPSCQueue.init();

    // Push some values
    try testing.expect(queue.push(10));
    try testing.expect(queue.push(20));
    try testing.expect(queue.push(30));

    // Pop values
    try testing.expectEqual(@as(u32, 10), queue.pop().?);
    try testing.expectEqual(@as(u32, 20), queue.pop().?);
    try testing.expectEqual(@as(u32, 30), queue.pop().?);
    try testing.expectEqual(@as(?u32, null), queue.pop());
}

test "Thread: memory ordering semantics" {
    // Test different memory orderings
    var value = std.atomic.Value(u32).init(0);

    // Relaxed ordering (no synchronization)
    value.store(1, .unordered);
    try testing.expectEqual(@as(u32, 1), value.load(.unordered));

    // Acquire-Release ordering (synchronizes with release)
    value.store(2, .release);
    try testing.expectEqual(@as(u32, 2), value.load(.acquire));

    // Sequentially consistent (strongest ordering)
    value.store(3, .seq_cst);
    try testing.expectEqual(@as(u32, 3), value.load(.seq_cst));
}

test "Thread: double-checked locking pattern" {
    const Singleton = struct {
        instance: ?*Data = null,
        mutex: std.Thread.Mutex = .{},
        initialized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        const Data = struct {
            value: u32,
        };

        fn getInstance(self: *@This(), allocator: std.mem.Allocator) !*Data {
            // First check (no lock)
            if (self.initialized.load(.acquire)) {
                return self.instance.?;
            }

            // Lock for initialization
            self.mutex.lock();
            defer self.mutex.unlock();

            // Second check (with lock)
            if (self.initialized.load(.acquire)) {
                return self.instance.?;
            }

            // Initialize
            const data = try allocator.create(Data);
            data.* = .{ .value = 42 };

            self.instance = data;
            self.initialized.store(true, .release);

            return data;
        }

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.instance) |data| {
                allocator.destroy(data);
            }
        }
    };

    var singleton = Singleton{};
    defer singleton.deinit(testing.allocator);

    const instance1 = try singleton.getInstance(testing.allocator);
    const instance2 = try singleton.getInstance(testing.allocator);

    // Should return same instance
    try testing.expectEqual(instance1, instance2);
    try testing.expectEqual(@as(u32, 42), instance1.value);
}

test "Thread: barrier concept" {
    // Barrier ensures all threads reach a point before continuing
    const BarrierState = struct {
        mutex: std.Thread.Mutex,
        count: u32,
        required: u32,

        fn init(required_threads: u32) @This() {
            return .{
                .mutex = .{},
                .count = 0,
                .required = required_threads,
            };
        }

        fn arrive(self: *@This()) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.count += 1;
            return self.count >= self.required;
        }
    };

    var barrier = BarrierState.init(3);

    try testing.expect(!barrier.arrive()); // 1st thread
    try testing.expect(!barrier.arrive()); // 2nd thread
    try testing.expect(barrier.arrive()); // 3rd thread - all arrived
}

test "Thread: lock-free stack (Treiber stack concept)" {
    // Simplified lock-free stack using atomic CAS
    const Node = struct {
        value: u32,
        next: ?*Node,
    };

    var top: std.atomic.Value(?*Node) = std.atomic.Value(?*Node).init(null);

    // For testing, we'll use stack allocation (in real code, use dynamic allocation)
    var node1 = Node{ .value = 1, .next = null };
    var node2 = Node{ .value = 2, .next = null };

    // Push node1
    while (true) {
        const current_top = top.load(.acquire);
        node1.next = current_top;
        const result = top.cmpxchgStrong(current_top, &node1, .release, .acquire);
        if (result == null) break; // Success
    }

    // Push node2
    while (true) {
        const current_top = top.load(.acquire);
        node2.next = current_top;
        const result = top.cmpxchgStrong(current_top, &node2, .release, .acquire);
        if (result == null) break; // Success
    }

    // Verify stack order (LIFO)
    const top_node = top.load(.acquire);
    try testing.expectEqual(@as(u32, 2), top_node.?.value);
    try testing.expectEqual(@as(u32, 1), top_node.?.next.?.value);
}
