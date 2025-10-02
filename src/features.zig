const std = @import("std");

/// WZL Feature Configuration
/// Enables compile-time feature selection for optimal binary size and functionality
pub const Features = struct {
    // Core features (always enabled)
    pub const core_protocol: bool = true;
    pub const basic_client: bool = true;
    pub const basic_server: bool = true;

    // Input device features - enable for full functionality
    pub const touch_input: bool = true;
    pub const tablet_input: bool = true;
    pub const gesture_recognition: bool = true;

    // Advanced protocol features
    pub const xdg_shell: bool = true;
    pub const clipboard: bool = true;
    pub const drag_drop: bool = true;

    // Rendering backends
    pub const software_renderer: bool = true;
    pub const egl_backend: bool = true;
    pub const vulkan_backend: bool = true;

    // Remote desktop & streaming
    pub const remote_desktop: bool = true;
    pub const quic_streaming: bool = true;
    pub const h264_encoding: bool = false; // Still needs implementation

    // Advanced features
    pub const fractional_scaling: bool = true;
    pub const hardware_cursor: bool = true;
    pub const multi_gpu: bool = true;
    pub const color_management: bool = true; // Phase 2 implemented

    // Development & debugging
    pub const memory_tracking: bool = true;
    pub const thread_safety_debug: bool = true;
    pub const protocol_logging: bool = true;

    // Compositor framework
    pub const compositor_framework: bool = true;
    pub const window_management: bool = true;

    // Terminal integration
    pub const terminal_integration: bool = true;

    /// Feature dependency validation at compile time
    pub fn validateDependencies() void {
        // Gesture recognition requires touch input
        if (gesture_recognition and !touch_input) {
            @compileError("gesture_recognition requires touch_input to be enabled");
        }

        // Drag & drop requires clipboard
        if (drag_drop and !clipboard) {
            @compileError("drag_drop requires clipboard to be enabled");
        }

        // QUIC streaming requires remote desktop
        if (quic_streaming and !remote_desktop) {
            @compileError("quic_streaming requires remote_desktop to be enabled");
        }

        // H.264 encoding requires remote desktop
        if (h264_encoding and !remote_desktop) {
            @compileError("h264_encoding requires remote_desktop to be enabled");
        }

        // Multi-GPU requires at least one rendering backend
        if (multi_gpu and !egl_backend and !vulkan_backend) {
            @compileError("multi_gpu requires at least one hardware rendering backend");
        }

        // Window management requires compositor framework
        if (window_management and !compositor_framework) {
            @compileError("window_management requires compositor_framework to be enabled");
        }
    }

    /// Get estimated binary size impact for each feature (in KB)
    pub fn getBinarySizeEstimate() u32 {
        var size: u32 = 1024; // Base core protocol ~1MB

        if (touch_input) size += 256;
        if (tablet_input) size += 128;
        if (gesture_recognition) size += 64;
        if (xdg_shell) size += 512;
        if (clipboard) size += 128;
        if (drag_drop) size += 32;
        if (software_renderer) size += 256;
        if (egl_backend) size += 512;
        if (vulkan_backend) size += 1024;
        if (remote_desktop) size += 1024;
        if (quic_streaming) size += 2048;
        if (h264_encoding) size += 3072;
        if (fractional_scaling) size += 64;
        if (hardware_cursor) size += 32;
        if (multi_gpu) size += 256;
        if (color_management) size += 128;
        if (memory_tracking) size += 64;
        if (thread_safety_debug) size += 32;
        if (protocol_logging) size += 64;
        if (compositor_framework) size += 1024;
        if (window_management) size += 512;
        if (terminal_integration) size += 128;

        return size;
    }

    /// Generate feature summary string for logging/debugging
    pub fn getSummary(allocator: std.mem.Allocator) ![]const u8 {
        var features = std.ArrayList([]const u8){};
        defer features.deinit(allocator);

        try features.append(allocator, "core_protocol");
        if (touch_input) try features.append(allocator, "touch_input");
        if (tablet_input) try features.append(allocator, "tablet_input");
        if (gesture_recognition) try features.append(allocator, "gesture_recognition");
        if (xdg_shell) try features.append(allocator, "xdg_shell");
        if (clipboard) try features.append(allocator, "clipboard");
        if (drag_drop) try features.append(allocator, "drag_drop");
        if (software_renderer) try features.append(allocator, "software_renderer");
        if (egl_backend) try features.append(allocator, "egl_backend");
        if (vulkan_backend) try features.append(allocator, "vulkan_backend");
        if (remote_desktop) try features.append(allocator, "remote_desktop");
        if (quic_streaming) try features.append(allocator, "quic_streaming");
        if (h264_encoding) try features.append(allocator, "h264_encoding");
        if (fractional_scaling) try features.append(allocator, "fractional_scaling");
        if (hardware_cursor) try features.append(allocator, "hardware_cursor");
        if (multi_gpu) try features.append(allocator, "multi_gpu");
        if (color_management) try features.append(allocator, "color_management");
        if (memory_tracking) try features.append(allocator, "memory_tracking");
        if (thread_safety_debug) try features.append(allocator, "thread_safety_debug");
        if (protocol_logging) try features.append(allocator, "protocol_logging");
        if (compositor_framework) try features.append(allocator, "compositor_framework");
        if (window_management) try features.append(allocator, "window_management");
        if (terminal_integration) try features.append(allocator, "terminal_integration");

        return try std.mem.join(allocator, ", ", features.items);
    }
};

/// Compile-time feature checking helpers
pub inline fn hasFeature(comptime feature: []const u8) bool {
    return @hasDecl(Features, feature) and @field(Features, feature);
}

/// Runtime feature availability checking
pub const FeatureSet = struct {
    // Input capabilities
    touch_available: bool,
    tablet_available: bool,
    gesture_recognition_available: bool,

    // Rendering capabilities
    software_rendering_available: bool,
    egl_available: bool,
    vulkan_available: bool,

    // Network capabilities
    remote_desktop_available: bool,
    quic_available: bool,

    // System capabilities
    hardware_cursor_available: bool,
    multi_gpu_available: bool,

    pub fn detect() FeatureSet {
        return FeatureSet{
            .touch_available = Features.touch_input,
            .tablet_available = Features.tablet_input,
            .gesture_recognition_available = Features.gesture_recognition,
            .software_rendering_available = Features.software_renderer,
            .egl_available = Features.egl_backend,
            .vulkan_available = Features.vulkan_backend,
            .remote_desktop_available = Features.remote_desktop,
            .quic_available = Features.quic_streaming,
            .hardware_cursor_available = Features.hardware_cursor,
            .multi_gpu_available = Features.multi_gpu,
        };
    }

    pub fn format(
        self: FeatureSet,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("WZL Features Available:\n");
        if (self.touch_available) try writer.writeAll("  ✓ Touch Input\n");
        if (self.tablet_available) try writer.writeAll("  ✓ Tablet Input\n");
        if (self.gesture_recognition_available) try writer.writeAll("  ✓ Gesture Recognition\n");
        if (self.software_rendering_available) try writer.writeAll("  ✓ Software Rendering\n");
        if (self.egl_available) try writer.writeAll("  ✓ EGL Backend\n");
        if (self.vulkan_available) try writer.writeAll("  ✓ Vulkan Backend\n");
        if (self.remote_desktop_available) try writer.writeAll("  ✓ Remote Desktop\n");
        if (self.quic_available) try writer.writeAll("  ✓ QUIC Streaming\n");
        if (self.hardware_cursor_available) try writer.writeAll("  ✓ Hardware Cursor\n");
        if (self.multi_gpu_available) try writer.writeAll("  ✓ Multi-GPU Support\n");
    }
};

// Validate feature dependencies at compile time
comptime {
    Features.validateDependencies();
}

test "feature dependency validation" {
    // This test ensures our feature dependencies are correctly configured
    Features.validateDependencies();
}

test "binary size estimation" {
    const size = Features.getBinarySizeEstimate();
    try std.testing.expect(size >= 1024); // At least core protocol
    try std.testing.expect(size <= 15 * 1024); // Reasonable upper bound
}

test "feature summary generation" {
    const summary = try Features.getSummary(std.testing.allocator);
    defer std.testing.allocator.free(summary);

    try std.testing.expect(std.mem.indexOf(u8, summary, "core_protocol") != null);
}