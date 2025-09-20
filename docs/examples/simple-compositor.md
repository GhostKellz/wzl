# wzl Performance Guide

This guide covers performance optimization techniques and best practices for applications using the wzl library.

## 📊 Performance Characteristics

wzl is designed for high performance with several key optimizations:

### Memory Performance
- **Arena Allocators**: Request-scoped memory management
- **Buffer Pooling**: Reuse of network and rendering buffers
- **Zero-Copy Operations**: Direct buffer access where possible
- **SIMD Acceleration**: Vectorized message processing

### CPU Performance
- **Async I/O**: Non-blocking operations reduce context switches
- **Cooperative Multitasking**: Efficient coroutine scheduling
- **Cache-Friendly Data Structures**: Optimized memory layouts
- **Platform-Specific Optimizations**: Arch Linux and hardware-specific tuning

### Network Performance
- **Message Batching**: Multiple messages in single syscall
- **QUIC Streaming**: High-performance transport protocol
- **Compression**: Optional data compression for remote sessions
- **Connection Pooling**: Efficient connection reuse

## 🏃‍♂️ Optimization Techniques

### 1. Buffer Management

#### Reuse Buffers
```zig
// Bad: Creating new buffers frequently
for (frames) |_| {
    const buffer = try createBuffer(width, height);
    // ... use buffer ...
    buffer.destroy();
}

// Good: Reuse existing buffers
var buffers = try createBufferPool(allocator, 3, width, height);
for (frames) |_| {
    const buffer = try buffers.get();
    // ... use buffer ...
    buffers.put(buffer);
}
```

#### Choose Optimal Formats
```zig
// For GPU rendering, prefer these formats
const preferred_formats = [_]buffer.ShmFormat{
    .argb8888,  // Most compatible
    .xrgb8888,  // No alpha channel
    .rgb565,    // 16-bit for performance
};

// For CPU rendering, use native formats
const cpu_formats = [_]buffer.ShmFormat{
    .argb8888,
    .xrgb8888,
};
```

### 2. Event Handling

#### Batch Updates
```zig
// Bad: Individual commits
try surface.attach(buffer1, 0, 0);
try surface.commit();

try surface.damage(0, 0, 100, 100);
try surface.commit();

// Good: Batch operations
try surface.attach(buffer1, 0, 0);
try surface.damage(0, 0, 100, 100);
try surface.commit(); // Single commit
```

#### Use Frame Callbacks
```zig
// Synchronous frame waiting (blocks)
const callback_id = try surface.frame();
const callback = try client.waitForCallback(callback_id);

// Async frame handling (non-blocking)
surface.setFrameHandler(struct {
    pub fn handleFrame(self: *anyopaque, callback: wzl.FrameCallback) void {
        // Process frame immediately
        updateApplication();
        renderFrame();
    }
}.handleFrame);
```

### 3. Memory Management

#### Use Arena Allocators
```zig
// Request-scoped allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const request_allocator = arena.allocator();

// All allocations in this scope are freed together
const surface = try compositor.createSurface(request_allocator);
const buffer = try shm.createBuffer(request_allocator);
// ... use objects ...

// Everything freed automatically
```

#### Pool Common Objects
```zig
const ObjectPool = struct {
    objects: std.ArrayList(*Object),
    allocator: std.mem.Allocator,

    pub fn get(self: *ObjectPool) !*Object {
        if (self.objects.popOrNull()) |obj| {
            return obj;
        }
        return try self.createNew();
    }

    pub fn put(self: *ObjectPool, obj: *Object) void {
        // Reset object state
        obj.reset();
        self.objects.append(obj) catch {
            // Pool full, destroy object
            obj.destroy();
        };
    }
};
```

### 4. Rendering Optimization

#### Double Buffering
```zig
const DoubleBuffer = struct {
    front: *Buffer,
    back: *Buffer,

    pub fn swap(self: *DoubleBuffer) void {
        const temp = self.front;
        self.front = self.back;
        self.back = temp;
    }

    pub fn render(self: *DoubleBuffer) !void {
        // Render to back buffer
        try self.renderToBuffer(self.back);

        // Swap buffers
        self.swap();

        // Present front buffer
        try surface.attach(self.front, 0, 0);
        try surface.commit();
    }
};
```

#### Damage Tracking
```zig
// Only update changed regions
var damage_regions = std.ArrayList(wzl.Rect).init(allocator);
defer damage_regions.deinit();

// Track damaged areas
try damage_regions.append(.{ .x = 100, .y = 100, .width = 50, .height = 50 });

// Submit damage in single call
for (damage_regions.items) |rect| {
    try surface.damage(rect.x, rect.y, rect.width, rect.height);
}
try surface.commit();
```

## 🔧 Platform-Specific Optimizations

### Arch Linux Optimizations

#### CPU Affinity
```zig
// Pin to specific CPU core for consistent performance
const core_id = 0; // Pin to first CPU core
try std.os.sched_setaffinity(0, &std.os.cpu_set_t{ .mask = 1 << core_id });
```

#### Memory Allocation
```zig
// Use huge pages for large allocations
const huge_page_size = 2 * 1024 * 1024; // 2MB
const flags = std.os.MAP.HUGETLB | std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE;
const buffer = try std.os.mmap(null, size, std.os.PROT.READ | std.os.PROT.WRITE, flags, -1, 0);
```

#### I/O Optimizations
```zig
// Use io_uring for async I/O (Linux 5.1+)
const ring = try std.os.linux.io_uring_init(256, 0);
defer std.os.linux.io_uring_deinit(&ring);

// Queue async operations
// ... io_uring operations ...
```

### Hardware Acceleration

#### GPU Buffer Sharing
```zig
// Use dmabuf for zero-copy GPU operations
const dmabuf = try wzl.DmabufBuffer.init(allocator, width, height, .argb8888, modifier);

// Import into GPU context
const gpu_texture = try gpu.importDmabuf(dmabuf);

// Render directly to GPU texture
// ... GPU rendering ...

// Present without copying
try surface.attachDmabuf(dmabuf, 0, 0);
```

#### SIMD Operations
```zig
// Use SIMD for bulk operations
const pixel_count = width * height;
const pixels = @as([*]u32, @ptrCast(buffer.data));

// Process 4 pixels at once (SIMD)
var i: usize = 0;
while (i + 4 <= pixel_count) : (i += 4) {
    const pixel_block = std.simd.load(u32, pixels + i, 4);
    const processed = processPixels(pixel_block);
    std.simd.store(u32, pixels + i, processed, 4);
}
```

## 📈 Benchmarking

### Performance Metrics

#### Frame Rate Monitoring
```zig
const FrameTimer = struct {
    start_time: i64,
    frame_count: u64,
    last_report: i64,

    pub fn start(self: *FrameTimer) void {
        self.start_time = std.time.nanoTimestamp();
        self.last_report = self.start_time;
    }

    pub fn frame(self: *FrameTimer) void {
        self.frame_count += 1;

        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_report;

        if (elapsed >= std.time.ns_per_s) { // Report every second
            const fps = @as(f64, @floatFromInt(self.frame_count)) /
                       (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);

            std.debug.print("FPS: {d:.1}\n", .{fps});

            self.frame_count = 0;
            self.last_report = now;
        }
    }
};
```

#### Memory Usage Tracking
```zig
const MemoryTracker = struct {
    allocator: std.mem.Allocator,
    allocated: usize = 0,
    allocations: usize = 0,

    pub fn init(allocator: std.mem.Allocator) MemoryTracker {
        return .{
            .allocator = allocator,
        };
    }

    pub fn alloc(self: *MemoryTracker, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
        const result = try self.allocator.allocFn(self.allocator.ptr, len, ptr_align, len_align, ret_addr);
        self.allocated += result.len;
        self.allocations += 1;
        return result;
    }

    pub fn report(self: *MemoryTracker) void {
        std.debug.print("Memory: {} bytes in {} allocations\n",
            .{self.allocated, self.allocations});
    }
};
```

### Profiling Tools

#### CPU Profiling
```zig
// Use Zig's built-in profiler
var profiler = try std.time.Profiler.start();
defer profiler.deinit();

// Profile specific code sections
{
    profiler.begin("render");
    defer profiler.end("render");

    // Rendering code here
    try renderFrame();
}

// Print profiling results
profiler.print();
```

#### Memory Profiling
```zig
// Track allocations
const tracking_allocator = std.heap.trackingAllocator(allocator);
const tracked = &tracking_allocator.tracker;

{
    // Code to profile
    const data = try tracking_allocator.allocator.alloc(u8, 1024);
    defer tracking_allocator.allocator.free(data);
}

// Report allocations
tracked.printAllocations();
```

## 🚀 Advanced Optimizations

### Connection Pooling
```zig
const ConnectionPool = struct {
    connections: std.ArrayList(*wzl.Connection),
    max_connections: usize,

    pub fn get(self: *ConnectionPool) !*wzl.Connection {
        if (self.connections.popOrNull()) |conn| {
            return conn;
        }
        return try wzl.Connection.connect();
    }

    pub fn put(self: *ConnectionPool, conn: *wzl.Connection) void {
        if (self.connections.items.len < self.max_connections) {
            self.connections.append(conn) catch {
                conn.close();
            };
        } else {
            conn.close();
        }
    }
};
```

### Message Batching
```zig
const MessageBatch = struct {
    messages: std.ArrayList(wzl.Message),
    max_batch_size: usize,

    pub fn add(self: *MessageBatch, message: wzl.Message) !void {
        try self.messages.append(message);

        if (self.messages.items.len >= self.max_batch_size) {
            try self.flush();
        }
    }

    pub fn flush(self: *MessageBatch) !void {
        if (self.messages.items.len == 0) return;

        // Send all messages in single operation
        try connection.sendBatch(&self.messages);

        // Clear batch
        self.messages.clearRetainingCapacity();
    }
};
```

### Cache-Friendly Data Structures
```zig
// Structure of arrays instead of array of structures
const ParticleSystem = struct {
    x: []f32,
    y: []f32,
    vx: []f32,
    vy: []f32,

    pub fn update(self: *ParticleSystem) void {
        // Process all X coordinates together (cache-friendly)
        for (self.x, 0..) |*x_pos, i| {
            x_pos.* += self.vx[i];
        }

        // Process all Y coordinates together
        for (self.y, 0..) |*y_pos, i| {
            y_pos.* += self.vy[i];
        }
    }
};
```

## 📋 Performance Checklist

- [ ] Use buffer pooling for frequently allocated buffers
- [ ] Implement double buffering for smooth rendering
- [ ] Use frame callbacks instead of polling
- [ ] Batch surface updates and commits
- [ ] Use arena allocators for request-scoped memory
- [ ] Choose appropriate buffer formats for your use case
- [ ] Implement damage tracking to reduce rendering work
- [ ] Use SIMD operations for bulk data processing
- [ ] Profile memory usage and fix leaks
- [ ] Monitor frame rates and optimize bottlenecks
- [ ] Use connection pooling for multiple requests
- [ ] Implement message batching for network efficiency
- [ ] Optimize data structures for cache performance

Following these optimization techniques will help you achieve the best possible performance with wzl applications.</content>
<parameter name="filePath">/data/projects/wzl/docs/performance.md