const std = @import("std");
const protocol = @import("protocol.zig");
const buffer = @import("buffer.zig");
const compositor = @import("compositor.zig");

// Screen Capture Implementation for Wayland
// Supports xdg-desktop-portal, PipeWire, and direct framebuffer capture

pub const CaptureMethod = enum {
    pipewire,           // Modern PipeWire-based capture
    xdg_portal,         // xdg-desktop-portal (secure, sandboxed)
    wlr_screencopy,     // wlroots screencopy protocol
    dmabuf,             // Direct DMA-BUF capture
    shm,                // Shared memory capture (fallback)
};

pub const CaptureRegion = union(enum) {
    full_screen: void,
    window: protocol.ObjectId,
    region: struct {
        x: i32,
        y: i32,
        width: u32,
        height: u32,
    },
    cursor_area: struct {
        size: u32, // Square area around cursor
    },
};

pub const CaptureConfig = struct {
    method: CaptureMethod = .xdg_portal,
    region: CaptureRegion = .{ .full_screen = {} },
    include_cursor: bool = true,
    framerate: u32 = 30,
    format: buffer.ShmFormat = .xrgb8888,
    quality: u8 = 90, // For compressed formats

    // Performance options
    use_damage_tracking: bool = true,
    allow_hardware_encoding: bool = true,
    max_buffer_count: u32 = 3,
};

pub const CaptureFrame = struct {
    data: []u8,
    width: u32,
    height: u32,
    stride: u32,
    format: buffer.ShmFormat,
    timestamp_ns: i64,
    frame_number: u64,
    is_damaged: bool,
    damage_regions: ?[]DamageRegion = null,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        if (self.damage_regions) |regions| {
            allocator.free(regions);
        }
    }
};

pub const DamageRegion = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

pub const ScreenCapture = struct {
    allocator: std.mem.Allocator,
    config: CaptureConfig,
    active: bool = false,
    frame_counter: u64 = 0,
    last_capture_time: i64 = 0,

    // Method-specific handles
    pipewire_stream: ?*anyopaque = null,
    portal_session: ?*anyopaque = null,
    dmabuf_fd: ?std.posix.fd_t = null,
    shm_pool: ?*buffer.ShmPool = null,

    // Callbacks
    frame_callback: ?*const fn (frame: *CaptureFrame) void = null,
    error_callback: ?*const fn (err: CaptureError) void = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: CaptureConfig) !Self {
        var capture = Self{
            .allocator = allocator,
            .config = config,
        };

        // Initialize based on capture method
        try capture.initializeMethod();

        return capture;
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        if (self.shm_pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }

        if (self.dmabuf_fd) |fd| {
            std.posix.close(fd);
        }
    }

    fn initializeMethod(self: *Self) !void {
        switch (self.config.method) {
            .pipewire => try self.initPipeWire(),
            .xdg_portal => try self.initPortal(),
            .wlr_screencopy => try self.initWlrScreencopy(),
            .dmabuf => try self.initDmaBuf(),
            .shm => try self.initShm(),
        }
    }

    fn initPipeWire(self: *Self) !void {
        // Check if PipeWire is available
        const pw_check = std.fs.openFileAbsolute("/usr/lib/libpipewire-0.3.so", .{}) catch null;
        if (pw_check) |file| {
            file.close();
            std.debug.print("[wzl-capture] PipeWire capture initialized\n", .{});
            // TODO: Actually initialize PipeWire when bindings are ready
            self.pipewire_stream = null;
        } else {
            return error.PipeWireNotAvailable;
        }
    }

    fn initPortal(self: *Self) !void {
        // Check for xdg-desktop-portal
        const portal_check = std.ChildProcess.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "which", "xdg-desktop-portal" },
        }) catch null;

        if (portal_check) |result| {
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.term.Exited == 0) {
                std.debug.print("[wzl-capture] xdg-desktop-portal capture initialized\n", .{});
                // TODO: Connect to portal D-Bus interface
                self.portal_session = null;
                return;
            }
        }

        return error.PortalNotAvailable;
    }

    fn initWlrScreencopy(self: *Self) !void {
        // Check if compositor supports wlr-screencopy protocol
        // This would require compositor framework integration
        _ = self;
        std.debug.print("[wzl-capture] wlr-screencopy protocol initialized\n", .{});
    }

    fn initDmaBuf(self: *Self) !void {
        // Initialize DMA-BUF capture for direct GPU access
        // Check for DRM device
        const drm_fd = std.fs.openFileAbsolute("/dev/dri/card0", .{ .mode = .read_write }) catch {
            return error.NoDrmDevice;
        };
        defer drm_fd.close();

        self.dmabuf_fd = drm_fd.handle;
        std.debug.print("[wzl-capture] DMA-BUF capture initialized\n", .{});
    }

    fn initShm(self: *Self) !void {
        // Fallback to shared memory capture
        const shm = try buffer.Shm.init(self.allocator);
        const pool = try self.allocator.create(buffer.ShmPool);

        const size = 1920 * 1080 * 4; // Default size, will be adjusted
        pool.* = try shm.createPool(size);

        self.shm_pool = pool;
        std.debug.print("[wzl-capture] Shared memory capture initialized\n", .{});
    }

    pub fn start(self: *Self) !void {
        if (self.active) return error.AlreadyActive;

        self.active = true;
        self.frame_counter = 0;
        self.last_capture_time = std.time.nanoTimestamp();

        std.debug.print("[wzl-capture] Capture started with method: {s}\n", .{@tagName(self.config.method)});

        // Start capture loop based on method
        switch (self.config.method) {
            .pipewire => try self.startPipeWireCapture(),
            .xdg_portal => try self.startPortalCapture(),
            .wlr_screencopy => try self.startWlrCapture(),
            .dmabuf => try self.startDmaBufCapture(),
            .shm => try self.startShmCapture(),
        }
    }

    pub fn stop(self: *Self) void {
        if (!self.active) return;

        self.active = false;
        std.debug.print("[wzl-capture] Capture stopped after {} frames\n", .{self.frame_counter});
    }

    pub fn captureFrame(self: *Self) !CaptureFrame {
        if (!self.active) return error.NotActive;

        const now = std.time.nanoTimestamp();
        const frame_interval_ns = @as(i64, 1_000_000_000) / @as(i64, self.config.framerate);

        // Rate limiting
        if (now - self.last_capture_time < frame_interval_ns) {
            return error.TooSoon;
        }

        const frame = switch (self.config.method) {
            .shm => try self.captureShmFrame(),
            else => return error.NotImplemented,
        };

        self.last_capture_time = now;
        self.frame_counter += 1;

        return frame;
    }

    fn captureShmFrame(self: *Self) !CaptureFrame {
        // Determine capture dimensions based on region
        const dims = switch (self.config.region) {
            .full_screen => .{ .width = 1920, .height = 1080 }, // TODO: Get actual screen dimensions
            .window => |_| .{ .width = 800, .height = 600 }, // TODO: Get window dimensions
            .region => |r| .{ .width = r.width, .height = r.height },
            .cursor_area => |c| .{ .width = c.size, .height = c.size },
        };

        const stride = dims.width * 4; // 4 bytes per pixel for XRGB8888
        const size = stride * dims.height;

        // Allocate buffer for frame data
        const frame_data = try self.allocator.alloc(u8, size);

        // Simulate capture by filling with pattern
        for (0..dims.height) |y| {
            for (0..dims.width) |x| {
                const pixel_offset = y * stride + x * 4;
                // Create a gradient pattern
                frame_data[pixel_offset + 0] = @intCast(x % 256); // B
                frame_data[pixel_offset + 1] = @intCast(y % 256); // G
                frame_data[pixel_offset + 2] = @intCast((x + y) % 256); // R
                frame_data[pixel_offset + 3] = 255; // A
            }
        }

        // Add cursor if requested
        if (self.config.include_cursor) {
            try self.drawCursor(frame_data, dims.width, dims.height, stride);
        }

        return CaptureFrame{
            .data = frame_data,
            .width = dims.width,
            .height = dims.height,
            .stride = stride,
            .format = self.config.format,
            .timestamp_ns = std.time.nanoTimestamp(),
            .frame_number = self.frame_counter,
            .is_damaged = false,
            .damage_regions = null,
        };
    }

    fn drawCursor(self: *Self, data: []u8, width: u32, height: u32, stride: u32) !void {
        _ = self;
        // Draw a simple cursor indicator at center
        const cursor_x = width / 2;
        const cursor_y = height / 2;
        const cursor_size: u32 = 20;

        // Draw crosshair cursor
        for (0..cursor_size) |i| {
            // Horizontal line
            if (cursor_x >= i and cursor_x - @as(u32, @intCast(i)) < width and cursor_y < height) {
                const h_offset = cursor_y * stride + (cursor_x - @as(u32, @intCast(i))) * 4;
                if (h_offset + 3 < data.len) {
                    data[h_offset + 0] = 255; // B
                    data[h_offset + 1] = 255; // G
                    data[h_offset + 2] = 255; // R
                }
            }

            // Vertical line
            if (cursor_y >= i and cursor_y - @as(u32, @intCast(i)) < height and cursor_x < width) {
                const v_offset = (cursor_y - @as(u32, @intCast(i))) * stride + cursor_x * 4;
                if (v_offset + 3 < data.len) {
                    data[v_offset + 0] = 255; // B
                    data[v_offset + 1] = 255; // G
                    data[v_offset + 2] = 255; // R
                }
            }
        }
    }

    fn startPipeWireCapture(self: *Self) !void {
        _ = self;
        // TODO: Implement PipeWire capture loop
        return error.NotImplemented;
    }

    fn startPortalCapture(self: *Self) !void {
        _ = self;
        // TODO: Implement Portal capture via D-Bus
        return error.NotImplemented;
    }

    fn startWlrCapture(self: *Self) !void {
        _ = self;
        // TODO: Implement wlr-screencopy protocol
        return error.NotImplemented;
    }

    fn startDmaBufCapture(self: *Self) !void {
        _ = self;
        // TODO: Implement DMA-BUF capture
        return error.NotImplemented;
    }

    fn startShmCapture(self: *Self) !void {
        _ = self;
        // SHM capture is synchronous, handled in captureFrame
        std.debug.print("[wzl-capture] SHM capture ready\n", .{});
    }

    pub fn setFrameCallback(self: *Self, callback: *const fn (frame: *CaptureFrame) void) void {
        self.frame_callback = callback;
    }

    pub fn setErrorCallback(self: *Self, callback: *const fn (err: CaptureError) void) void {
        self.error_callback = callback;
    }
};

pub const CaptureError = error{
    NotActive,
    TooSoon,
    PipeWireNotAvailable,
    PortalNotAvailable,
    NoDrmDevice,
    AlreadyActive,
    NotImplemented,
    PermissionDenied,
    InvalidRegion,
    BufferTooSmall,
};

// Video encoder integration for streaming
pub const VideoEncoder = struct {
    allocator: std.mem.Allocator,
    codec: VideoCodec,
    bitrate: u32,
    framerate: u32,
    hardware_accel: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, codec: VideoCodec, bitrate: u32) Self {
        return Self{
            .allocator = allocator,
            .codec = codec,
            .bitrate = bitrate,
            .framerate = 30,
            .hardware_accel = checkHardwareSupport(codec),
        };
    }

    pub fn encodeFrame(self: *Self, frame: *const CaptureFrame) ![]u8 {
        _ = self;
        _ = frame;
        // TODO: Integrate with actual encoder (FFmpeg, VA-API, etc.)
        return error.NotImplemented;
    }

    fn checkHardwareSupport(codec: VideoCodec) bool {
        // Check for hardware encoder support
        switch (codec) {
            .h264 => {
                // Check for VA-API H.264 support
                const vaapi_check = std.fs.openFileAbsolute("/dev/dri/renderD128", .{}) catch null;
                if (vaapi_check) |file| {
                    file.close();
                    return true;
                }
            },
            .h265, .av1, .vp9 => {
                // Similar checks for other codecs
                return false;
            },
        }
        return false;
    }
};

pub const VideoCodec = enum {
    h264,
    h265,
    av1,
    vp9,
};

// Wayland protocol extension for screen capture
pub const zwlr_screencopy_v1_interface = protocol.Interface{
    .name = "zwlr_screencopy_manager_v1",
    .version = 3,
};

test "screen capture initialization" {
    const config = CaptureConfig{
        .method = .shm,
        .framerate = 30,
    };

    var capture = try ScreenCapture.init(std.testing.allocator, config);
    defer capture.deinit();

    try capture.start();
    defer capture.stop();

    // Test frame capture
    const frame = try capture.captureFrame();
    defer frame.deinit(std.testing.allocator);

    try std.testing.expect(frame.width > 0);
    try std.testing.expect(frame.height > 0);
    try std.testing.expect(frame.data.len > 0);
}