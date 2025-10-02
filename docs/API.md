# WZL API Documentation

## Getting Started

### Basic Client Usage

```zig
const std = @import("std");
const wzl = @import("wzl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Connect to Wayland display
    var client = try wzl.Client.init(allocator);
    defer client.deinit();

    try client.connect(null); // Use default display

    // Get registry and enumerate globals
    const registry = try client.getRegistry();
    try client.roundtrip(); // Wait for globals

    // Bind to compositor
    if (registry.getGlobal("wl_compositor")) |compositor_global| {
        const compositor = try registry.bind(wzl.Compositor, compositor_global.name, 6);

        // Create surface
        const surface = try compositor.createSurface();

        // Your application logic here...
    }
}
```

### Basic Compositor Usage

```zig
const std = @import("std");
const wzl = @import("wzl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create compositor
    const config = wzl.CompositorConfig{
        .socket_name = "my-compositor",
        .enable_xdg_shell = true,
        .enable_input = true,
        .max_clients = 32,
    };

    var compositor = try wzl.CompositorFramework.init(allocator, config);
    defer compositor.deinit();

    // Set up event handlers
    compositor.setViewCreatedCallback(onViewCreated);
    compositor.setViewDestroyedCallback(onViewDestroyed);

    // Start main loop
    try compositor.run();
}

fn onViewCreated(view: *wzl.View) void {
    std.debug.print("New view created: {}\n", .{view.surface_id});
}
```

## Core API

### Protocol Types

#### Message

```zig
pub const Message = struct {
    header: MessageHeader,
    arguments: []const Argument,

    pub fn init(allocator: Allocator, object_id: ObjectId, opcode: u16,
                arguments: []const Argument) !Message;
    pub fn deinit(self: *Message) void;
    pub fn serialize(self: *const Message, buffer: []u8) !usize;
    pub fn deserialize(allocator: Allocator, data: []const u8) !Message;
};
```

#### Argument Types

```zig
pub const Argument = union(enum) {
    int: i32,
    uint: u32,
    fixed: FixedPoint,
    string: []const u8,
    object: ObjectId,
    new_id: ObjectId,
    array: []const u8,
    fd: std.posix.fd_t,
};
```

### Connection Management

```zig
pub const Connection = struct {
    pub fn init(allocator: Allocator, socket: std.net.Stream) Connection;
    pub fn deinit(self: *Connection) void;
    pub fn sendMessage(self: *Connection, message: Message) !void;
    pub fn receiveMessage(self: *Connection, allocator: Allocator) !Message;
    pub fn flush(self: *Connection) !void;
};
```

### Client API

```zig
pub const Client = struct {
    pub fn init(allocator: Allocator) !Client;
    pub fn deinit(self: *Client) void;
    pub fn connect(self: *Client, display_name: ?[]const u8) !void;
    pub fn disconnect(self: *Client) void;
    pub fn getRegistry(self: *Client) !Registry;
    pub fn roundtrip(self: *Client) !void;
    pub fn flush(self: *Client) !void;
    pub fn dispatchEvents(self: *Client) !void;
};

pub const Registry = struct {
    pub fn bind(self: *Registry, comptime T: type, name: u32, version: u32) !T;
    pub fn getGlobal(self: *Registry, interface_name: []const u8) ?GlobalInfo;
    pub fn listGlobals(self: *Registry) []const GlobalInfo;
};
```

## Compositor Framework API

### Core Framework

```zig
pub const CompositorFramework = struct {
    pub fn init(allocator: Allocator, config: CompositorConfig) !CompositorFramework;
    pub fn deinit(self: *CompositorFramework) void;
    pub fn run(self: *CompositorFramework) !void;
    pub fn stop(self: *CompositorFramework) void;

    // View management
    pub fn createView(self: *CompositorFramework, surface_id: ObjectId) !*View;
    pub fn destroyView(self: *CompositorFramework, surface_id: ObjectId) void;
    pub fn mapView(self: *CompositorFramework, surface_id: ObjectId,
                   x: i32, y: i32, width: u32, height: u32) void;
    pub fn unmapView(self: *CompositorFramework, surface_id: ObjectId) void;

    // Event callbacks
    pub fn setViewCreatedCallback(self: *CompositorFramework, callback: ViewCallback) void;
    pub fn setViewDestroyedCallback(self: *CompositorFramework, callback: ViewCallback) void;
    pub fn setViewMappedCallback(self: *CompositorFramework, callback: ViewCallback) void;
};

pub const ViewCallback = *const fn(view: *View) void;
```

### Configuration

```zig
pub const CompositorConfig = struct {
    socket_name: []const u8 = "wayland-0",
    enable_xdg_shell: bool = true,
    enable_input: bool = true,
    enable_output: bool = true,
    max_clients: u32 = 16,
    use_hardware_cursor: bool = true,
    enable_vsync: bool = true,
};
```

## Rendering API

### Render Context

```zig
pub const RenderContext = struct {
    pub fn init(allocator: Allocator, backend: BackendType,
                width: u32, height: u32, format: ShmFormat) !RenderContext;
    pub fn deinit(self: *RenderContext) void;
    pub fn renderSurface(self: *RenderContext, surface_data: []const u8,
                         x: i32, y: i32) !void;
    pub fn present(self: *RenderContext) !void;
};

pub const BackendType = enum { software, egl, vulkan };
```

### EGL Backend

```zig
pub const EGLContext = struct {
    pub fn init(allocator: Allocator, config: EGLConfig) !EGLContext;
    pub fn deinit(self: *EGLContext) void;

    pub const EGLConfig = struct {
        version_major: u32 = 3,
        version_minor: u32 = 2,
        vsync: bool = true,
        debug_context: bool = false,
    };
};

pub const EGLRenderer = struct {
    pub fn init(allocator: Allocator, context: *EGLContext) !EGLRenderer;
    pub fn deinit(self: *EGLRenderer) void;
    pub fn beginFrame(self: *EGLRenderer) !void;
    pub fn drawSurface(self: *EGLRenderer, texture: *EGLTexture,
                       x: f32, y: f32, width: f32, height: f32) !void;
    pub fn endFrame(self: *EGLRenderer) !void;
};
```

### Vulkan Backend

```zig
pub const VulkanContext = struct {
    pub fn init(allocator: Allocator, config: VulkanConfig) !VulkanContext;
    pub fn deinit(self: *VulkanContext) void;

    pub const VulkanConfig = struct {
        api_version: u32 = vk_make_version(1, 3, 0),
        enable_validation: bool = false,
        prefer_discrete_gpu: bool = true,
        max_frames_in_flight: u32 = 3,
    };
};
```

## Color Management API

```zig
pub const ColorManager = struct {
    pub fn init(allocator: Allocator) !ColorManager;
    pub fn deinit(self: *ColorManager) void;
    pub fn setDisplayProfile(self: *ColorManager, profile: ColorProfile) !void;
    pub fn setSurfaceProfile(self: *ColorManager, surface_id: ObjectId,
                             profile: ColorProfile) !void;
    pub fn getTransform(self: *ColorManager, from: *const ColorProfile,
                        to: *const ColorProfile) !ColorTransform;
};

pub const ColorProfile = struct {
    name: []const u8,
    color_space: ColorSpace,
    transfer_function: TransferFunction,
    hdr_metadata: ?HDRMetadata = null,
};

pub const ColorSpace = enum {
    srgb, display_p3, rec2020, adobe_rgb, dci_p3, linear_srgb, scrgb
};
```

## Screen Capture API

```zig
pub const ScreenCapture = struct {
    pub fn init(allocator: Allocator, config: CaptureConfig) !ScreenCapture;
    pub fn deinit(self: *ScreenCapture) void;
    pub fn start(self: *ScreenCapture) !void;
    pub fn stop(self: *ScreenCapture) void;
    pub fn captureFrame(self: *ScreenCapture) !CaptureFrame;

    pub fn setFrameCallback(self: *ScreenCapture,
                            callback: *const fn(frame: *CaptureFrame) void) void;
};

pub const CaptureConfig = struct {
    method: CaptureMethod = .xdg_portal,
    region: CaptureRegion = .{ .full_screen = {} },
    include_cursor: bool = true,
    framerate: u32 = 30,
    format: ShmFormat = .xrgb8888,
};

pub const CaptureMethod = enum {
    pipewire, xdg_portal, wlr_screencopy, dmabuf, shm
};
```

## Input Handling API

### Multi-Touch

```zig
pub const TouchManager = struct {
    pub fn init(allocator: Allocator, config: TouchConfig) !TouchManager;
    pub fn deinit(self: *TouchManager) void;
    pub fn processTouchEvent(self: *TouchManager, event: TouchEvent) !void;
    pub fn setGestureCallback(self: *TouchManager, callback: GestureCallback) void;
};

pub const GestureRecognizer = struct {
    pub fn detectTap(touches: []const TouchPoint, duration_ms: u32) ?TapGesture;
    pub fn detectPinch(touches: []const TouchPoint) ?PinchGesture;
    pub fn detectSwipe(touches: []const TouchPoint) ?SwipeGesture;
};
```

### Tablet Input

```zig
pub const TabletManager = struct {
    pub fn init(allocator: Allocator) !TabletManager;
    pub fn deinit(self: *TabletManager) void;
    pub fn addTablet(self: *TabletManager, tablet: TabletDevice) !void;
    pub fn processTabletEvent(self: *TabletManager, event: TabletEvent) !void;
};

pub const TabletTool = struct {
    tool_type: ToolType,
    serial: u64,
    hardware_id: u64,
    capabilities: ToolCapabilities,

    pub const ToolType = enum { pen, eraser, brush, pencil, airbrush, mouse, lens };
};
```

## Remote Desktop API

```zig
pub const RemoteDesktopServer = struct {
    pub fn init(allocator: Allocator, config: RemoteDesktopConfig) !RemoteDesktopServer;
    pub fn deinit(self: *RemoteDesktopServer) void;
    pub fn run(self: *RemoteDesktopServer) !void;
    pub fn stop(self: *RemoteDesktopServer) void;

    pub fn broadcastFrame(self: *RemoteDesktopServer, framebuffer: []const u8) !void;
    pub fn handleRemoteInput(self: *RemoteDesktopServer, input: RemoteInput) !void;
};

pub const RemoteDesktopConfig = struct {
    listen_port: u16 = 21118,
    enable_password: bool = true,
    password: []const u8 = "",
    max_peers: u32 = 8,
    enable_clipboard_sync: bool = true,
};
```

## QUIC Streaming API

```zig
pub const QuicServer = struct {
    pub fn init(allocator: Allocator, config: StreamingConfig) !QuicServer;
    pub fn deinit(self: *QuicServer) void;
    pub fn run(self: *QuicServer) !void;
    pub fn stop(self: *QuicServer) void;
    pub fn broadcastFrame(self: *QuicServer, framebuffer: []const u8,
                          metadata: FrameMetadata) !void;
};

pub const StreamingConfig = struct {
    listen_address: []const u8 = "0.0.0.0",
    listen_port: u16 = 4433,
    enable_0rtt: bool = true,
    congestion_control: enum { cubic, bbr, bbr2 } = .bbr2,
};
```

## Memory Management API

```zig
pub const TrackingAllocator = struct {
    pub fn init(backing_allocator: Allocator) TrackingAllocator;
    pub fn deinit(self: *TrackingAllocator) void;
    pub fn allocator(self: *TrackingAllocator) Allocator;
    pub fn getTotalAllocated(self: *const TrackingAllocator) usize;
    pub fn getPeakAllocated(self: *const TrackingAllocator) usize;
    pub fn dumpLeaks(self: *const TrackingAllocator) void;
};

pub const PoolAllocator = struct {
    pub fn init(backing_allocator: Allocator, comptime T: type,
                count: usize) !PoolAllocator(T);
    pub fn create(self: *PoolAllocator(T)) !*T;
    pub fn destroy(self: *PoolAllocator(T), item: *T) void;
};
```

## Error Handling

```zig
pub const WaylandError = error{
    ConnectionFailed,
    ProtocolError,
    InvalidMessage,
    OutOfMemory,
    Timeout,
    PermissionDenied,
    NotSupported,
};

pub const ErrorContext = struct {
    pub fn init(allocator: Allocator, error_code: WaylandError,
                message: []const u8) ErrorContext;
    pub fn addContext(self: *ErrorContext, key: []const u8, value: []const u8) !void;
    pub fn format(self: *const ErrorContext, writer: anytype) !void;
};
```

## Build Configuration

### Feature Flags

```zig
// In your build.zig
const wzl = b.dependency("wzl", .{
    .target = target,
    .optimize = optimize,
    .touch_input = true,
    .egl_backend = true,
    .vulkan_backend = true,
    .color_management = true,
    .remote_desktop = true,
});
```

### Available Features

- `touch_input`: Multi-touch and gesture support
- `tablet_input`: Tablet/stylus input support
- `egl_backend`: EGL/OpenGL ES rendering
- `vulkan_backend`: Vulkan rendering
- `color_management`: HDR and color space support
- `remote_desktop`: Remote desktop capabilities
- `quic_streaming`: QUIC-based streaming
- `memory_tracking`: Debug memory allocator