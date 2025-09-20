const std = @import("std");
const protocol = @import("protocol.zig");

// Shared memory formats
pub const ShmFormat = enum(u32) {
    argb8888 = 0,
    xrgb8888 = 1,
    c8 = 0x20203843,
    rgb332 = 0x38424752,
    bgr233 = 0x38524742,
    xrgb4444 = 0x32315258,
    xbgr4444 = 0x32314258,
    rgbx4444 = 0x32315852,
    bgrx4444 = 0x32315842,
    argb4444 = 0x32315241,
    abgr4444 = 0x32314241,
    rgba4444 = 0x32314152,
    bgra4444 = 0x32314142,
    xrgb1555 = 0x35315258,
    xbgr1555 = 0x35314258,
    rgbx5551 = 0x35315852,
    bgrx5551 = 0x35315842,
    argb1555 = 0x35315241,
    abgr1555 = 0x35314241,
    rgba5551 = 0x35314152,
    bgra5551 = 0x35314142,
    rgb565 = 0x36314752,
    bgr565 = 0x36314742,
    r8 = 0x20203852,
    r16 = 0x20363152,
    rg88 = 0x38384752,
    gr88 = 0x38384547,
    rg1616 = 0x32334752,
    gr1616 = 0x32334547,
    xrgb2101010 = 0x30335258,
    xbgr2101010 = 0x30334258,
    rgbx1010102 = 0x30335852,
    bgrx1010102 = 0x30335842,
    argb2101010 = 0x30335241,
    abgr2101010 = 0x30334241,
    rgba1010102 = 0x30334152,
    bgra1010102 = 0x30334142,
    yuyv = 0x56595559,
    yvyu = 0x55595659,
    uyvy = 0x59565955,
    vyuy = 0x59555956,
    ayuv = 0x56555941,
    nv12 = 0x3231564e,
    nv21 = 0x3132564e,
    nv16 = 0x3631564e,
    nv61 = 0x3136564e,
    yuv410 = 0x39565559,
    yvu410 = 0x39555659,
    yuv411 = 0x31315559,
    yvu411 = 0x31315659,
    yuv420 = 0x32315559,
    yvu420 = 0x32315659,
    yuv422 = 0x36315559,
    yvu422 = 0x36315659,
    yuv444 = 0x34345559,
    yvu444 = 0x34345659,
    r8_snorm = 0x20203853,
    rg88_snorm = 0x38534752,
    rgb888 = 0x34324752,
    bgr888 = 0x34324742,
    rgba8888 = 0x34324152,
    bgra8888 = 0x34324142,
    xrgb8888_a8 = 0x38415258,
    xbgr8888_a8 = 0x38414258,
    rgbx8888_a8 = 0x38415852,
    bgrx8888_a8 = 0x38415842,
    rgb888_a8 = 0x38413852,
    bgr888_a8 = 0x38413842,
    rgb565_a8 = 0x38413536,
    bgr565_a8 = 0x38413635,
};

// Buffer transform enum
pub const BufferTransform = enum(i32) {
    normal = 0,
    @"90" = 1,
    @"180" = 2,
    @"270" = 3,
    flipped = 4,
    flipped_90 = 5,
    flipped_180 = 6,
    flipped_270 = 7,
};

// Shared memory pool
pub const ShmPool = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    fd: std.fs.File.Handle,
    size: i32,

    const Self = @This();

    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId, fd: std.fs.File.Handle, size: i32) Self {
        return Self{
            .object_id = object_id,
            .client = client,
            .fd = fd,
            .size = size,
        };
    }

    pub fn createBuffer(self: *Self, offset: i32, width: i32, height: i32, stride: i32, format: ShmFormat) !protocol.ObjectId {
        const buffer_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // create_buffer opcode
            &[_]protocol.Argument{
                .{ .new_id = buffer_id },
                .{ .int = offset },
                .{ .int = width },
                .{ .int = height },
                .{ .int = stride },
                .{ .uint = @intFromEnum(format) },
            },
        );
        try self.client.connection.sendMessage(message);
        return buffer_id;
    }

    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }

    pub fn resize(self: *Self, new_size: i32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            2, // resize opcode
            &[_]protocol.Argument{
                .{ .int = new_size },
            },
        );
        try self.client.connection.sendMessage(message);
        self.size = new_size;
    }
};

// Shared memory manager
pub const Shm = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    supported_formats: std.ArrayList(ShmFormat),

    const Self = @This();

    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client,
            .supported_formats = std.ArrayList(ShmFormat).init(client.allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.supported_formats.deinit();
    }

    pub fn createPool(self: *Self, fd: std.fs.File.Handle, size: i32) !protocol.ObjectId {
        const pool_id = self.client.nextId();
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // create_pool opcode
            &[_]protocol.Argument{
                .{ .new_id = pool_id },
                .{ .fd = fd },
                .{ .int = size },
            },
        );
        try self.client.connection.sendMessage(message);
        return pool_id;
    }

    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => { // format
                if (message.arguments.len >= 1) {
                    const format = switch (message.arguments[0]) {
                        .uint => |v| @as(ShmFormat, @enumFromInt(v)),
                        else => return error.InvalidArgument,
                    };
                    try self.supported_formats.append(format);
                }
            },
            else => {},
        }
    }

    pub fn isFormatSupported(self: *Self, format: ShmFormat) bool {
        for (self.supported_formats.items) |supported| {
            if (supported == format) return true;
        }
        return false;
    }
};

// Buffer implementation
pub const Buffer = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    width: i32,
    height: i32,
    stride: i32,
    format: ShmFormat,
    released: bool,

    const Self = @This();

    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId, width: i32, height: i32, stride: i32, format: ShmFormat) Self {
        return Self{
            .object_id = object_id,
            .client = client,
            .width = width,
            .height = height,
            .stride = stride,
            .format = format,
            .released = false,
        };
    }

    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }

    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => { // release
                self.released = true;
            },
            else => {},
        }
    }

    pub fn isReleased(self: *Self) bool {
        return self.released;
    }
};

// Utility functions for buffer management
pub fn createMemoryMappedBuffer(allocator: std.mem.Allocator, width: i32, height: i32, format: ShmFormat) !struct {
    fd: std.fs.File.Handle,
    data: []u8,
    stride: i32,
    size: i32,
} {
    _ = allocator;
    const bytes_per_pixel: i32 = switch (format) {
        .argb8888, .xrgb8888, .rgba8888, .bgra8888 => 4,
        .rgb565, .bgr565, .xrgb4444, .xbgr4444, .rgbx4444, .bgrx4444, .argb4444, .abgr4444, .rgba4444, .bgra4444, .xrgb1555, .xbgr1555, .rgbx5551, .bgrx5551, .argb1555, .abgr1555, .rgba5551, .bgra5551 => 2,
        .rgb888, .bgr888 => 3,
        .c8, .r8, .r8_snorm => 1,
        else => return error.UnsupportedFormat,
    };

    const stride = width * bytes_per_pixel;
    const size = stride * height;

    // Create anonymous memory mapping
    const fd = try std.posix.memfd_create("wayland-shm", 0);
    try std.posix.ftruncate(fd, size);

    const data = try std.posix.mmap(
        null,
        @intCast(size),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    return .{
        .fd = fd,
        .data = data,
        .stride = stride,
        .size = size,
    };
}

pub fn destroyMemoryMappedBuffer(data: []u8, fd: std.fs.File.Handle) void {
    std.posix.munmap(data);
    std.posix.close(fd);
}

// DMA-BUF buffer support for GPU-accelerated compositing
pub const DmabufFormat = enum(u32) {
    // Reuse SHM formats for compatibility
    argb8888 = 0,
    xrgb8888 = 1,
    // Add dmabuf-specific formats if needed
};

pub const DmabufPlane = struct {
    fd: std.fs.File.Handle,
    offset: u32,
    stride: u32,
};

pub const DmabufBuffer = struct {
    width: u32,
    height: u32,
    format: DmabufFormat,
    planes: []DmabufPlane,
    modifier: u64, // DRM format modifier
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, format: DmabufFormat, modifier: u64) !Self {
        // In real implementation, planes would be created from actual dmabuf
        const planes = try allocator.alloc(DmabufPlane, 1); // Single plane for simplicity
        planes[0] = DmabufPlane{
            .fd = 0, // Placeholder
            .offset = 0,
            .stride = width * 4, // Assume 4 bytes per pixel
        };

        return Self{
            .width = width,
            .height = height,
            .format = format,
            .planes = planes,
            .modifier = modifier,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.planes);
        // Close file descriptors in real implementation
    }

    pub fn getPlaneData(self: *Self, plane_index: usize) ![]u8 {
        if (plane_index >= self.planes.len) return error.InvalidPlane;
        const plane = &self.planes[plane_index];

        // Map the dmabuf for CPU access
        // This is a placeholder - real implementation would use mmap
        _ = plane;
        return &[_]u8{}; // Return empty slice as placeholder
    }
};

// Linux dmabuf interface definitions
pub const linux_dmabuf_interface = protocol.Interface{
    .name = "zwp_linux_dmabuf_v1",
    .version = 4,
    .method_count = 3,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "create_params", .signature = "n", .types = &[_]?*const protocol.Interface{&linux_dmabuf_params_interface} },
        .{ .name = "get_default_feedback", .signature = "n", .types = &[_]?*const protocol.Interface{&linux_dmabuf_feedback_interface} },
    },
    .event_count = 1,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "format", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
};

pub const linux_dmabuf_params_interface = protocol.Interface{
    .name = "zwp_linux_dmabuf_params_v1",
    .version = 4,
    .method_count = 6,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "add", .signature = "huuuuu", .types = &[_]?*const protocol.Interface{ null, null, null, null, null, null } },
        .{ .name = "create", .signature = "iiuu", .types = &[_]?*const protocol.Interface{ null, null, null, null } },
        .{ .name = "create_immed", .signature = "niuuv", .types = &[_]?*const protocol.Interface{ null, null, null, null, null, null } },
    },
    .event_count = 1,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "created", .signature = "n", .types = &[_]?*const protocol.Interface{&protocol.wl_buffer_interface} },
    },
};

pub const linux_dmabuf_feedback_interface = protocol.Interface{
    .name = "zwp_linux_dmabuf_feedback_v1",
    .version = 4,
    .method_count = 1,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 4,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "done", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "format_table", .signature = "hu", .types = &[_]?*const protocol.Interface{ null, null } },
        .{ .name = "main_device", .signature = "a", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "tranche_done", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
};
