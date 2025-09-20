# wzl Client API

The client API provides a high-level interface for creating Wayland client applications, such as terminal emulators, GUI applications, and other desktop software.

## 🏗️ Client Structure

```zig
pub const Client = struct {
    connection: connection.Connection,
    allocator: std.mem.Allocator,
    display_id: protocol.ObjectId,
    next_object_id: protocol.ObjectId,
    objects: std.HashMap(protocol.ObjectId, ObjectType),
    runtime: ?*zsync.Runtime,
};
```

## 🚀 Initialization

### Basic Client Creation

```zig
const std = @import("std");
const wzl = @import("wzl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Create client with default configuration
    var client = try wzl.Client.init(allocator, .{});
    defer client.deinit();

    // Connect to Wayland display
    try client.connect();

    std.debug.print("Connected to Wayland display!\n", .{});
}
```

### Advanced Configuration

```zig
// Client with custom runtime and configuration
var client = try wzl.Client.init(allocator, .{
    .runtime = my_zsync_runtime, // Custom async runtime
});
```

## 🔗 Connection Management

### Connecting to Display

```zig
// Automatic connection using WAYLAND_DISPLAY environment variable
try client.connect();

// Manual connection to specific socket
try client.connectToSocket("/run/user/1000/wayland-0");
```

### Connection Status

```zig
if (client.isConnected()) {
    std.debug.print("Client is connected\n", .{});
}

// Get connection information
const display_name = client.getDisplayName();
const connection_info = client.getConnectionInfo();
```

## 📋 Registry and Globals

### Accessing the Registry

```zig
// Get the global registry
const registry = try client.getRegistry();

// List all available globals
var globals = try registry.getGlobals(allocator);
defer globals.deinit();

for (globals.items) |global| {
    std.debug.print("Global: {s} (id: {}, version: {})\n",
        .{global.interface, global.name, global.version});
}
```

### Binding to Globals

```zig
// Bind to wl_compositor
const compositor_id = try registry.bind("wl_compositor", 6);
const compositor = client.getObject(compositor_id).compositor;

// Bind to wl_shm for shared memory
const shm_id = try registry.bind("wl_shm", 1);
const shm = client.getObject(shm_id).shm;
```

## 🎨 Surface Management

### Creating Surfaces

```zig
// Get compositor from registry
const compositor = try client.getCompositor();

// Create a new surface
const surface = try compositor.createSurface();

// Set up surface for rendering
try surface.attach(buffer, 0, 0);
try surface.damage(0, 0, width, height);
try surface.commit();
```

### Surface Configuration

```zig
// Set surface geometry
try surface.setGeometry(100, 100, 800, 600);

// Set opaque region for optimization
const region = try compositor.createRegion();
try region.add(0, 0, 800, 600);
try surface.setOpaqueRegion(region);

// Set input region
try surface.setInputRegion(region);
```

## 🖼️ Buffer Management

### Shared Memory Buffers

```zig
// Get SHM from registry
const shm = try client.getShm();

// Create a shared memory pool
const pool = try shm.createPool(fd, size);

// Create a buffer from the pool
const buffer = try pool.createBuffer(0, width, height, stride, format);

// Map buffer for CPU access
const data = try buffer.map();
defer buffer.unmap();

// Draw to the buffer
// ... drawing code ...

// Attach buffer to surface
try surface.attach(buffer, 0, 0);
```

### dmabuf Buffers (GPU)

```zig
// Create dmabuf buffer for GPU rendering
const dmabuf = try wzl.DmabufBuffer.init(allocator, width, height, .argb8888, modifier);

// Get file descriptors for each plane
for (dmabuf.planes, 0..) |plane, i| {
    // Use plane.fd for GPU operations
}

// Import into GPU context
// ... GPU import code ...
```

## ⌨️ Input Handling

### Keyboard Input

```zig
// Get seat from registry
const seat = try client.getSeat();

// Get keyboard
const keyboard = try seat.getKeyboard();

// Set up keyboard event handlers
keyboard.setKeyHandler(struct {
    pub fn handleKey(self: *anyopaque, keycode: u32, state: enum { pressed, released }) void {
        _ = self;
        if (state == .pressed) {
            std.debug.print("Key pressed: {}\n", .{keycode});
        }
    }
}.handleKey);
```

### Pointer Input

```zig
// Get pointer from seat
const pointer = try seat.getPointer();

// Set up pointer event handlers
pointer.setMotionHandler(struct {
    pub fn handleMotion(self: *anyopaque, x: f64, y: f64) void {
        _ = self;
        std.debug.print("Pointer at: ({}, {})\n", .{x, y});
    }
}.handleMotion);

pointer.setButtonHandler(struct {
    pub fn handleButton(self: *anyopaque, button: u32, state: enum { pressed, released }) void {
        _ = self;
        std.debug.print("Button {} {}\n", .{button, state});
    }
}.handleButton);
```

## 🖱️ Frame Callbacks

### Synchronous Frame Updates

```zig
// Request frame callback
const callback_id = try surface.frame();

// Wait for frame callback
const callback = client.waitForCallback(callback_id);
std.debug.print("Frame time: {}\n", .{callback.timestamp});
```

### Async Frame Handling

```zig
// Set up frame callback handler
surface.setFrameHandler(struct {
    pub fn handleFrame(self: *anyopaque, callback_data: wzl.FrameCallback) void {
        _ = self;

        // Update application state
        // Render next frame
        // Submit new frame

        std.debug.print("New frame at time: {}\n", .{callback_data.timestamp});
    }
}.handleFrame);
```

## 🎭 Window Management (XDG Shell)

### Creating Toplevel Windows

```zig
// Get XDG WM Base
const xdg_wm_base = try client.getXdgWmBase();

// Create XDG surface
const xdg_surface = try xdg_wm_base.getXdgSurface(surface);

// Create toplevel window
const toplevel = try xdg_surface.getToplevel();

// Configure window
try toplevel.setTitle("My Application");
try toplevel.setAppId("com.example.myapp");

// Set window geometry
try xdg_surface.setWindowGeometry(0, 0, width, height);
```

### Window Events

```zig
// Handle window configuration
xdg_surface.setConfigureHandler(struct {
    pub fn handleConfigure(self: *anyopaque, config: wzl.XdgSurfaceConfigure) void {
        _ = self;

        // Resize buffers if needed
        if (config.width != current_width or config.height != current_height) {
            // Recreate buffers with new size
            // Update surface geometry
        }

        // Acknowledge configuration
        try xdg_surface.ackConfigure(config.serial);
    }
}.handleConfigure);
```

## 📋 Clipboard Integration

### Setting Clipboard Content

```zig
// Get data device manager
const data_device_manager = try client.getDataDeviceManager();

// Create data source
const data_source = try data_device_manager.createDataSource();

// Offer MIME types
try data_source.offer("text/plain");
try data_source.offer("text/html");

// Set clipboard content
try data_source.setData("text/plain", "Hello, World!");
try data_source.setData("text/html", "<p>Hello, World!</p>");

// Set as clipboard content
const device = try data_device_manager.getDataDevice(seat);
try device.setSelection(data_source, 0);
```

### Reading Clipboard Content

```zig
// Get current clipboard content
const offer = try device.getSelection();

if (offer) |clipboard_offer| {
    // Check available MIME types
    const mime_types = try clipboard_offer.getMimeTypes(allocator);
    defer mime_types.deinit();

    // Request data in preferred format
    try clipboard_offer.receive("text/plain", fd);

    // Read data from file descriptor
    var buffer: [1024]u8 = undefined;
    const bytes_read = try std.fs.File{ .handle = fd }.read(&buffer);
    const text = buffer[0..bytes_read];
}
```

## 🔄 Event Loop Integration

### Basic Event Loop

```zig
// Simple event loop
while (true) {
    // Process Wayland events
    try client.dispatch();

    // Process application events
    // Update application state
    // Render frames

    // Small delay to prevent busy-waiting
    std.time.sleep(1_000_000); // 1ms
}
```

### Async Event Loop with zsync

```zig
// Create async runtime
var runtime = try zsync.Runtime.init(allocator);
defer runtime.deinit();

// Create client with runtime
var client = try wzl.Client.init(allocator, .{ .runtime = &runtime });
defer client.deinit();

// Async event processing
while (true) {
    // Process events asynchronously
    try await client.dispatchAsync();

    // Yield control to other coroutines
    suspend;
}
```

## 🧹 Resource Management

### Proper Cleanup

```zig
// Always clean up in reverse order of creation
defer {
    // Clean up surfaces
    surface.destroy();

    // Clean up buffers
    buffer.destroy();

    // Clean up globals
    compositor.destroy();
    shm.destroy();

    // Disconnect client
    client.disconnect();

    // Clean up client
    client.deinit();
}
```

### Error Handling

```zig
client.connect() catch |err| {
    switch (err) {
        error.ConnectionRefused => {
            std.debug.print("Wayland compositor not running\n", .{});
            return error.NoCompositor;
        },
        error.PermissionDenied => {
            std.debug.print("Permission denied accessing Wayland socket\n", .{});
            return error.AccessDenied;
        },
        else => {
            std.debug.print("Connection failed: {}\n", .{err});
            return err;
        }
    }
};
```

## 📊 Performance Considerations

### Buffer Management
- Reuse buffers when possible
- Use appropriate buffer formats for your use case
- Consider dmabuf for GPU-accelerated applications

### Event Handling
- Process events efficiently to avoid input lag
- Use frame callbacks for smooth animation
- Batch updates when possible

### Memory Management
- Use arena allocators for request-scoped allocations
- Clean up resources promptly
- Monitor memory usage in long-running applications

This API provides a comprehensive, type-safe interface for building Wayland client applications with excellent performance and memory safety guarantees.</content>
<parameter name="filePath">/data/projects/wzl/docs/api/client.md