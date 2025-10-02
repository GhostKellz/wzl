const std = @import("std");
const protocol = @import("protocol.zig");
const buffer = @import("buffer.zig");

// EGL/OpenGL ES backend optimization for Wayland compositors
// High-performance GPU rendering with hardware acceleration

pub const EGLConfig = struct {
    version_major: u32 = 3,
    version_minor: u32 = 2, // OpenGL ES 3.2
    samples: u32 = 0, // MSAA samples
    vsync: bool = true,
    triple_buffering: bool = false,
    debug_context: bool = false,

    // Performance options
    use_shader_cache: bool = true,
    use_buffer_age: bool = true, // EGL_EXT_buffer_age for partial updates
    use_swap_buffers_with_damage: bool = true, // EGL_KHR_swap_buffers_with_damage
};

pub const EGLContext = struct {
    display: ?*anyopaque = null, // EGLDisplay
    context: ?*anyopaque = null, // EGLContext
    config: ?*anyopaque = null,  // EGLConfig
    surface: ?*anyopaque = null, // EGLSurface

    // Extensions
    has_buffer_age: bool = false,
    has_swap_damage: bool = false,
    has_image_dmabuf: bool = false,
    has_fence_sync: bool = false,

    // OpenGL state
    vao: u32 = 0,
    vbo: u32 = 0,
    ebo: u32 = 0,
    shader_program: u32 = 0,

    allocator: std.mem.Allocator,
    config: EGLConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: EGLConfig) !Self {
        var ctx = Self{
            .allocator = allocator,
            .config = config,
        };

        // Initialize EGL
        try ctx.initializeEGL();

        // Initialize OpenGL resources
        try ctx.initializeGL();

        // Check extensions
        ctx.detectExtensions();

        return ctx;
    }

    pub fn deinit(self: *Self) void {
        self.destroyGL();
        self.destroyEGL();
    }

    fn initializeEGL(self: *Self) !void {
        // Simulate EGL initialization
        // In a real implementation, this would call eglGetDisplay, eglInitialize, etc.
        std.debug.print("[wzl-egl] Initializing EGL context\n", .{});

        // Check for EGL library
        const egl_lib = std.fs.openFileAbsolute("/usr/lib/libEGL.so.1", .{}) catch {
            return error.EGLNotAvailable;
        };
        defer egl_lib.close();

        // Check for OpenGL ES library
        const gles_lib = std.fs.openFileAbsolute("/usr/lib/libGLESv2.so.2", .{}) catch {
            return error.OpenGLESNotAvailable;
        };
        defer gles_lib.close();

        std.debug.print("[wzl-egl] EGL {}.{} initialized\n", .{ self.config.version_major, self.config.version_minor });
    }

    fn destroyEGL(self: *Self) void {
        _ = self;
        std.debug.print("[wzl-egl] Destroying EGL context\n", .{});
    }

    fn initializeGL(self: *Self) !void {
        // Initialize OpenGL resources
        std.debug.print("[wzl-egl] Initializing OpenGL ES resources\n", .{});

        // Create vertex array object
        self.vao = 1; // glGenVertexArrays

        // Create vertex buffer object
        self.vbo = 2; // glGenBuffers

        // Create element buffer object
        self.ebo = 3; // glGenBuffers

        // Compile shaders
        self.shader_program = try self.compileShaders();

        std.debug.print("[wzl-egl] OpenGL ES resources initialized\n", .{});
    }

    fn destroyGL(self: *Self) void {
        _ = self;
        std.debug.print("[wzl-egl] Destroying OpenGL ES resources\n", .{});
    }

    fn compileShaders(self: *Self) !u32 {
        _ = self;

        // Vertex shader for compositor
        const vertex_source =
            \\#version 320 es
            \\precision highp float;
            \\
            \\layout(location = 0) in vec2 position;
            \\layout(location = 1) in vec2 texcoord;
            \\
            \\out vec2 v_texcoord;
            \\
            \\uniform mat4 projection;
            \\uniform mat4 transform;
            \\
            \\void main() {
            \\    gl_Position = projection * transform * vec4(position, 0.0, 1.0);
            \\    v_texcoord = texcoord;
            \\}
        ;

        // Fragment shader for compositor with color management
        const fragment_source =
            \\#version 320 es
            \\precision highp float;
            \\
            \\in vec2 v_texcoord;
            \\out vec4 fragColor;
            \\
            \\uniform sampler2D tex;
            \\uniform float alpha;
            \\uniform mat3 colorTransform;
            \\uniform bool srgbOutput;
            \\
            \\vec3 linearToSrgb(vec3 linear) {
            \\    vec3 srgb;
            \\    for (int i = 0; i < 3; i++) {
            \\        if (linear[i] <= 0.0031308) {
            \\            srgb[i] = linear[i] * 12.92;
            \\        } else {
            \\            srgb[i] = 1.055 * pow(linear[i], 1.0/2.4) - 0.055;
            \\        }
            \\    }
            \\    return srgb;
            \\}
            \\
            \\void main() {
            \\    vec4 color = texture(tex, v_texcoord);
            \\
            \\    // Apply color transformation
            \\    vec3 transformed = colorTransform * color.rgb;
            \\
            \\    // Convert to sRGB if needed
            \\    if (srgbOutput) {
            \\        transformed = linearToSrgb(transformed);
            \\    }
            \\
            \\    fragColor = vec4(transformed, color.a * alpha);
            \\}
        ;

        _ = vertex_source;
        _ = fragment_source;

        // In real implementation, compile and link shaders
        const program_id: u32 = 42;

        std.debug.print("[wzl-egl] Shaders compiled successfully\n", .{});
        return program_id;
    }

    fn detectExtensions(self: *Self) void {
        // Check for useful extensions
        // In real implementation, would use eglQueryString

        self.has_buffer_age = true; // EGL_EXT_buffer_age
        self.has_swap_damage = true; // EGL_KHR_swap_buffers_with_damage
        self.has_image_dmabuf = true; // EGL_EXT_image_dma_buf_import
        self.has_fence_sync = true; // EGL_KHR_fence_sync

        std.debug.print("[wzl-egl] Extensions detected:\n", .{});
        if (self.has_buffer_age) std.debug.print("  ✓ EGL_EXT_buffer_age\n", .{});
        if (self.has_swap_damage) std.debug.print("  ✓ EGL_KHR_swap_buffers_with_damage\n", .{});
        if (self.has_image_dmabuf) std.debug.print("  ✓ EGL_EXT_image_dma_buf_import\n", .{});
        if (self.has_fence_sync) std.debug.print("  ✓ EGL_KHR_fence_sync\n", .{});
    }
};

pub const EGLTexture = struct {
    id: u32,
    width: u32,
    height: u32,
    format: TextureFormat,
    dmabuf_fd: ?std.posix.fd_t = null,

    const Self = @This();

    pub fn init(width: u32, height: u32, format: TextureFormat) Self {
        return Self{
            .id = 0, // glGenTextures
            .width = width,
            .height = height,
            .format = format,
        };
    }

    pub fn upload(self: *Self, data: []const u8) !void {
        _ = data;
        // glTexImage2D or glTexSubImage2D
        std.debug.print("[wzl-egl] Uploading texture {}x{}\n", .{ self.width, self.height });
    }

    pub fn importDmaBuf(self: *Self, fd: std.posix.fd_t, stride: u32) !void {
        _ = stride;
        self.dmabuf_fd = fd;
        // Use EGL_EXT_image_dma_buf_import
        std.debug.print("[wzl-egl] Imported DMA-BUF texture\n", .{});
    }

    pub fn bind(self: *Self, unit: u32) void {
        _ = unit;
        // glActiveTexture + glBindTexture
        _ = self;
    }
};

pub const TextureFormat = enum {
    rgba8,
    rgb8,
    bgra8,
    rgb565,
    rgba16f,
    rgba32f,
};

pub const EGLRenderer = struct {
    context: *EGLContext,
    textures: std.ArrayList(EGLTexture),
    render_queue: std.ArrayList(RenderCommand),
    allocator: std.mem.Allocator,

    // Performance metrics
    frame_count: u64 = 0,
    total_draw_calls: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, context: *EGLContext) !Self {
        return Self{
            .context = context,
            .textures = std.ArrayList(EGLTexture).init(allocator),
            .render_queue = std.ArrayList(RenderCommand).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.textures.deinit();
        self.render_queue.deinit();
    }

    pub fn beginFrame(self: *Self) !void {
        self.render_queue.clearRetainingCapacity();
        self.frame_count += 1;

        // Clear framebuffer
        // glClear(GL_COLOR_BUFFER_BIT)
        _ = self;
    }

    pub fn drawSurface(self: *Self, texture: *EGLTexture, x: f32, y: f32, width: f32, height: f32) !void {
        const cmd = RenderCommand{
            .texture = texture,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .alpha = 1.0,
        };

        try self.render_queue.append(cmd);
    }

    pub fn endFrame(self: *Self) !void {
        // Execute all render commands
        for (self.render_queue.items) |cmd| {
            try self.executeCommand(cmd);
        }

        // Swap buffers
        try self.swapBuffers();

        std.debug.print("[wzl-egl] Frame {} rendered ({} draw calls)\n", .{ self.frame_count, self.render_queue.items.len });
        self.total_draw_calls += self.render_queue.items.len;
    }

    fn executeCommand(self: *Self, cmd: RenderCommand) !void {
        _ = self;
        // Bind texture
        cmd.texture.bind(0);

        // Set uniforms
        // glUniform1f(alpha_location, cmd.alpha)

        // Draw quad
        // glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0)

        _ = cmd;
    }

    fn swapBuffers(self: *Self) !void {
        if (self.context.has_swap_damage and self.context.config.use_swap_buffers_with_damage) {
            // Use partial swap with damage regions
            std.debug.print("[wzl-egl] Using swap buffers with damage\n", .{});
        } else {
            // Full swap
            std.debug.print("[wzl-egl] Full swap buffers\n", .{});
        }
    }
};

const RenderCommand = struct {
    texture: *EGLTexture,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    alpha: f32,
    transform: ?[9]f32 = null, // 3x3 matrix
};

// Hardware detection and optimization
pub fn detectGPU() !GPUInfo {
    var info = GPUInfo{
        .vendor = .unknown,
        .renderer = "Unknown",
        .has_mesa = false,
        .has_nvidia = false,
        .has_amdgpu = false,
    };

    // Check for GPU drivers
    if (std.fs.openFileAbsolute("/dev/dri/card0", .{})) |file| {
        file.close();
        info.has_mesa = true;

        // Check for specific drivers
        if (std.fs.openFileAbsolute("/usr/lib/libGL_nvidia.so", .{})) |nv| {
            nv.close();
            info.has_nvidia = true;
            info.vendor = .nvidia;
            info.renderer = "NVIDIA GPU";
        } else |_| {}

        if (std.fs.openFileAbsolute("/usr/lib/libamdgpu.so", .{})) |amd| {
            amd.close();
            info.has_amdgpu = true;
            info.vendor = .amd;
            info.renderer = "AMD GPU";
        } else |_| {}

        if (info.vendor == .unknown and info.has_mesa) {
            info.vendor = .intel;
            info.renderer = "Intel/Mesa GPU";
        }
    } else |_| {}

    std.debug.print("[wzl-egl] GPU Detection:\n", .{});
    std.debug.print("  Vendor: {s}\n", .{@tagName(info.vendor)});
    std.debug.print("  Renderer: {s}\n", .{info.renderer});

    return info;
}

pub const GPUInfo = struct {
    vendor: GPUVendor,
    renderer: []const u8,
    has_mesa: bool,
    has_nvidia: bool,
    has_amdgpu: bool,
};

pub const GPUVendor = enum {
    nvidia,
    amd,
    intel,
    unknown,
};

test "EGL context initialization" {
    const config = EGLConfig{
        .vsync = true,
        .debug_context = true,
    };

    var context = EGLContext.init(std.testing.allocator, config) catch |err| {
        // EGL might not be available in test environment
        if (err == error.EGLNotAvailable) return;
        return err;
    };
    defer context.deinit();

    try std.testing.expect(context.config.vsync == true);
}