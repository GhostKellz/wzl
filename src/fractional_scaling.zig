const std = @import("std");
const protocol = @import("protocol.zig");
const features = @import("features.zig");
const thread_safety = @import("thread_safety.zig");
const errors = @import("errors.zig");

/// Fractional scale manager following Wayland fractional-scale-v1 protocol
pub const fractional_scale_manager_v1_interface = protocol.Interface{
    .name = "wp_fractional_scale_manager_v1",
    .version = 1,
    .method_count = 2,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "get_fractional_scale", .signature = "no", .types = &[_]?*const protocol.Interface{&fractional_scale_v1_interface, &protocol.wl_surface_interface} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

pub const fractional_scale_v1_interface = protocol.Interface{
    .name = "wp_fractional_scale_v1",
    .version = 1,
    .method_count = 1,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 1,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "preferred_scale", .signature = "u", .types = &[_]?*const protocol.Interface{null} },
    },
};

/// Viewport scaling protocol for fine-grained control
pub const viewporter_interface = protocol.Interface{
    .name = "wp_viewporter",
    .version = 1,
    .method_count = 2,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "get_viewport", .signature = "no", .types = &[_]?*const protocol.Interface{&viewport_interface, &protocol.wl_surface_interface} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

pub const viewport_interface = protocol.Interface{
    .name = "wp_viewport",
    .version = 1,
    .method_count = 3,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_source", .signature = "ffff", .types = &[_]?*const protocol.Interface{null, null, null, null} },
        .{ .name = "set_destination", .signature = "ii", .types = &[_]?*const protocol.Interface{null, null} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

/// Fixed-point fractional scale value (24.8 format)
pub const FractionalScale = packed struct {
    raw: u32,

    pub fn fromFloat(value: f32) FractionalScale {
        // Convert to 24.8 fixed point (120 = 1.0 * 120)
        return .{ .raw = @intFromFloat(value * 120.0) };
    }

    pub fn toFloat(self: FractionalScale) f32 {
        return @as(f32, @floatFromInt(self.raw)) / 120.0;
    }

    pub fn fromRatio(numerator: u32, denominator: u32) FractionalScale {
        return .{ .raw = (numerator * 120) / denominator };
    }

    pub fn multiply(self: FractionalScale, other: FractionalScale) FractionalScale {
        const result = (@as(u64, self.raw) * @as(u64, other.raw)) / 120;
        return .{ .raw = @intCast(result) };
    }

    pub fn reciprocal(self: FractionalScale) FractionalScale {
        if (self.raw == 0) return .{ .raw = 0 };
        return .{ .raw = (120 * 120) / self.raw };
    }

    pub fn isValid(self: FractionalScale) bool {
        const scale = self.toFloat();
        return scale >= 0.25 and scale <= 8.0;
    }

    // Common scale presets
    pub const SCALE_100 = FractionalScale{ .raw = 120 }; // 1.0
    pub const SCALE_125 = FractionalScale{ .raw = 150 }; // 1.25
    pub const SCALE_150 = FractionalScale{ .raw = 180 }; // 1.5
    pub const SCALE_175 = FractionalScale{ .raw = 210 }; // 1.75
    pub const SCALE_200 = FractionalScale{ .raw = 240 }; // 2.0
    pub const SCALE_250 = FractionalScale{ .raw = 300 }; // 2.5
    pub const SCALE_300 = FractionalScale{ .raw = 360 }; // 3.0
};

/// Surface-specific scaling information
pub const SurfaceScale = struct {
    surface_id: protocol.ObjectId,
    preferred_scale: FractionalScale,
    buffer_scale: u32,
    output_scale: FractionalScale,
    viewport_scale: ?FractionalScale,

    // Source and destination rectangles for viewport
    source_rect: ?Rectangle,
    destination_size: ?Size,

    // Scaling quality settings
    filter: ScaleFilter,
    quality: ScaleQuality,

    // Performance metrics
    last_scale_time: i64,
    scale_changes: u32,

    pub const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    pub const Size = struct {
        width: i32,
        height: i32,
    };

    pub const ScaleFilter = enum {
        nearest,       // Pixel perfect, fastest
        linear,        // Bilinear, good quality/performance
        cubic,         // Bicubic, higher quality
        lanczos,       // Best quality, slower
    };

    pub const ScaleQuality = enum {
        fast,          // Prioritize performance
        balanced,      // Balance quality and performance
        quality,       // Prioritize visual quality
    };

    pub fn getEffectiveScale(self: *const SurfaceScale) FractionalScale {
        if (self.viewport_scale) |viewport| {
            return viewport.multiply(self.output_scale);
        }
        return self.preferred_scale;
    }

    pub fn needsScaling(self: *const SurfaceScale) bool {
        const effective = self.getEffectiveScale();
        return @abs(effective.toFloat() - 1.0) > 0.01; // 1% tolerance
    }

    pub fn getScaledSize(self: *const SurfaceScale, original_width: u32, original_height: u32) Size {
        const scale = self.getEffectiveScale().toFloat();
        return Size{
            .width = @intFromFloat(@as(f32, @floatFromInt(original_width)) * scale),
            .height = @intFromFloat(@as(f32, @floatFromInt(original_height)) * scale),
        };
    }
};

/// Fractional scaling manager
pub const FractionalScalingManager = struct {
    allocator: std.mem.Allocator,
    surface_scales: thread_safety.Registry(SurfaceScale),
    output_scales: std.AutoHashMap(protocol.ObjectId, FractionalScale),

    // Global scaling settings
    global_scale_factor: FractionalScale,
    automatic_scaling: bool,
    scale_change_threshold: f32,

    // Performance settings
    scaling_backend: ScalingBackend,
    max_scaling_threads: u32,
    enable_caching: bool,

    // Statistics
    total_scale_operations: std.atomic.Value(u64),
    cache_hits: std.atomic.Value(u64),
    cache_misses: std.atomic.Value(u64),

    pub const ScalingBackend = enum {
        software,      // CPU-based scaling
        opengl,        // OpenGL texture scaling
        vulkan,        // Vulkan compute scaling
        hardware,      // Hardware display scaler
    };

    pub fn init(allocator: std.mem.Allocator) !FractionalScalingManager {
        return FractionalScalingManager{
            .allocator = allocator,
            .surface_scales = thread_safety.Registry(SurfaceScale).init(allocator),
            .output_scales = std.AutoHashMap(protocol.ObjectId, FractionalScale).init(allocator),
            .global_scale_factor = FractionalScale.SCALE_100,
            .automatic_scaling = true,
            .scale_change_threshold = 0.1, // 10% change needed to trigger rescaling
            .scaling_backend = .opengl,
            .max_scaling_threads = 4,
            .enable_caching = true,
            .total_scale_operations = std.atomic.Value(u64).init(0),
            .cache_hits = std.atomic.Value(u64).init(0),
            .cache_misses = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *FractionalScalingManager) void {
        self.surface_scales.deinit();
        self.output_scales.deinit();
    }

    pub fn setOutputScale(self: *FractionalScalingManager, output_id: protocol.ObjectId, scale: FractionalScale) !void {
        if (!scale.isValid()) return error.InvalidScale;

        try self.output_scales.put(output_id, scale);

        // Update all surfaces on this output
        try self.updateSurfacesForOutput(output_id);
    }

    pub fn setSurfaceScale(
        self: *FractionalScalingManager,
        surface_id: protocol.ObjectId,
        preferred_scale: FractionalScale,
        buffer_scale: u32,
    ) !void {
        if (!preferred_scale.isValid()) return error.InvalidScale;

        var surface_scale = SurfaceScale{
            .surface_id = surface_id,
            .preferred_scale = preferred_scale,
            .buffer_scale = buffer_scale,
            .output_scale = self.global_scale_factor,
            .viewport_scale = null,
            .source_rect = null,
            .destination_size = null,
            .filter = .linear,
            .quality = .balanced,
            .last_scale_time = std.time.milliTimestamp(),
            .scale_changes = 1,
        };

        _ = try self.surface_scales.add(&surface_scale);

        // Send scale preference to client
        try self.sendPreferredScale(surface_id, preferred_scale);
    }

    pub fn setViewport(
        self: *FractionalScalingManager,
        surface_id: protocol.ObjectId,
        source: ?SurfaceScale.Rectangle,
        destination: ?SurfaceScale.Size,
    ) !void {
        if (self.surface_scales.get(@intCast(surface_id))) |surface_scale| {
            surface_scale.source_rect = source;
            surface_scale.destination_size = destination;

            // Calculate viewport scale
            if (source != null and destination != null) {
                const src = source.?;
                const dst = destination.?;

                const scale_x = @as(f32, @floatFromInt(dst.width)) / src.width;
                const scale_y = @as(f32, @floatFromInt(dst.height)) / src.height;

                // Use average of X and Y scales
                const avg_scale = (scale_x + scale_y) / 2.0;
                surface_scale.viewport_scale = FractionalScale.fromFloat(avg_scale);
            } else {
                surface_scale.viewport_scale = null;
            }

            surface_scale.scale_changes += 1;
            surface_scale.last_scale_time = std.time.milliTimestamp();
        }
    }

    fn updateSurfacesForOutput(self: *FractionalScalingManager, output_id: protocol.ObjectId) !void {
        const output_scale = self.output_scales.get(output_id) orelse return;

        var iter = self.surface_scales.objects.iterator();
        while (iter.next()) |entry| {
            const surface_scale = entry.value_ptr.*;

            // Check if surface is on this output (simplified - would need proper tracking)
            const old_scale = surface_scale.output_scale;
            surface_scale.output_scale = output_scale;

            // Only send update if scale changed significantly
            const old_effective = surface_scale.preferred_scale.multiply(old_scale);
            const new_effective = surface_scale.getEffectiveScale();
            const change = @abs(new_effective.toFloat() - old_effective.toFloat());

            if (change > self.scale_change_threshold) {
                try self.sendPreferredScale(surface_scale.surface_id, new_effective);
                surface_scale.scale_changes += 1;
                surface_scale.last_scale_time = std.time.milliTimestamp();
            }
        }
    }

    fn sendPreferredScale(self: *FractionalScalingManager, surface_id: protocol.ObjectId, scale: FractionalScale) !void {
        _ = self;
        _ = surface_id;
        _ = scale;

        // In real implementation, this would send wp_fractional_scale_v1.preferred_scale event
        // const message = try protocol.Message.init(
        //     allocator,
        //     fractional_scale_object_id,
        //     0, // preferred_scale event
        //     &[_]protocol.Argument{
        //         .{ .uint = scale.raw },
        //     },
        // );
        // try connection.sendMessage(message);
    }

    pub fn scaleSurface(
        self: *FractionalScalingManager,
        surface_id: protocol.ObjectId,
        source_buffer: []const u8,
        source_width: u32,
        source_height: u32,
        source_format: u32,
        destination_buffer: []u8,
    ) !ScaleResult {
        const surface_scale = self.surface_scales.get(@intCast(surface_id)) orelse return error.SurfaceNotFound;

        if (!surface_scale.needsScaling()) {
            // No scaling needed, copy directly
            const copy_size = @min(source_buffer.len, destination_buffer.len);
            @memcpy(destination_buffer[0..copy_size], source_buffer[0..copy_size]);

            return ScaleResult{
                .width = source_width,
                .height = source_height,
                .format = source_format,
                .bytes_processed = copy_size,
                .scaling_time_us = 0,
                .cache_hit = false,
            };
        }

        const start_time = std.time.microTimestamp();

        // Determine target size
        const target_size = surface_scale.getScaledSize(source_width, source_height);

        // Perform scaling based on backend
        const result = switch (self.scaling_backend) {
            .software => try self.scaleSoftware(
                source_buffer, source_width, source_height, source_format,
                destination_buffer, @intCast(target_size.width), @intCast(target_size.height),
                surface_scale.filter
            ),
            .opengl => try self.scaleOpenGL(
                source_buffer, source_width, source_height, source_format,
                destination_buffer, @intCast(target_size.width), @intCast(target_size.height),
                surface_scale.filter
            ),
            .vulkan => try self.scaleVulkan(
                source_buffer, source_width, source_height, source_format,
                destination_buffer, @intCast(target_size.width), @intCast(target_size.height),
                surface_scale.filter
            ),
            .hardware => try self.scaleHardware(
                source_buffer, source_width, source_height, source_format,
                destination_buffer, @intCast(target_size.width), @intCast(target_size.height),
                surface_scale.filter
            ),
        };

        const end_time = std.time.microTimestamp();
        _ = self.total_scale_operations.fetchAdd(1, .seq_cst);

        return ScaleResult{
            .width = @intCast(target_size.width),
            .height = @intCast(target_size.height),
            .format = source_format,
            .bytes_processed = result.bytes_processed,
            .scaling_time_us = end_time - start_time,
            .cache_hit = result.cache_hit,
        };
    }

    pub const ScaleResult = struct {
        width: u32,
        height: u32,
        format: u32,
        bytes_processed: usize,
        scaling_time_us: i64,
        cache_hit: bool,
    };

    fn scaleSoftware(
        self: *FractionalScalingManager,
        source: []const u8, src_width: u32, src_height: u32, format: u32,
        destination: []u8, dst_width: u32, dst_height: u32,
        filter: SurfaceScale.ScaleFilter,
    ) !ScaleResult {
        _ = format;

        // Simplified bilinear scaling implementation
        // In production, would use optimized SIMD implementations

        if (filter == .nearest) {
            return try self.scaleNearest(source, src_width, src_height, destination, dst_width, dst_height);
        } else {
            return try self.scaleBilinear(source, src_width, src_height, destination, dst_width, dst_height);
        }
    }

    fn scaleNearest(
        self: *FractionalScalingManager,
        source: []const u8, src_width: u32, src_height: u32,
        destination: []u8, dst_width: u32, dst_height: u32,
    ) !ScaleResult {
        _ = self;

        const bytes_per_pixel = 4; // Assume ARGB32
        const x_ratio = @as(f32, @floatFromInt(src_width)) / @as(f32, @floatFromInt(dst_width));
        const y_ratio = @as(f32, @floatFromInt(src_height)) / @as(f32, @floatFromInt(dst_height));

        for (0..dst_height) |y| {
            for (0..dst_width) |x| {
                const src_x = @as(u32, @intFromFloat(@as(f32, @floatFromInt(x)) * x_ratio));
                const src_y = @as(u32, @intFromFloat(@as(f32, @floatFromInt(y)) * y_ratio));

                const src_idx = (src_y * src_width + src_x) * bytes_per_pixel;
                const dst_idx = (y * dst_width + x) * bytes_per_pixel;

                if (src_idx + bytes_per_pixel <= source.len and dst_idx + bytes_per_pixel <= destination.len) {
                    @memcpy(destination[dst_idx..dst_idx + bytes_per_pixel], source[src_idx..src_idx + bytes_per_pixel]);
                }
            }
        }

        return ScaleResult{
            .width = dst_width,
            .height = dst_height,
            .format = 0,
            .bytes_processed = dst_width * dst_height * bytes_per_pixel,
            .scaling_time_us = 0,
            .cache_hit = false,
        };
    }

    fn scaleBilinear(
        self: *FractionalScalingManager,
        source: []const u8, src_width: u32, src_height: u32,
        destination: []u8, dst_width: u32, dst_height: u32,
    ) !ScaleResult {
        _ = self;

        // Simplified bilinear implementation
        // Production version would use SIMD and proper interpolation
        const bytes_per_pixel = 4;
        const x_ratio = (@as(f32, @floatFromInt(src_width)) - 1.0) / @as(f32, @floatFromInt(dst_width));
        const y_ratio = (@as(f32, @floatFromInt(src_height)) - 1.0) / @as(f32, @floatFromInt(dst_height));

        for (0..dst_height) |y| {
            const src_y_f = @as(f32, @floatFromInt(y)) * y_ratio;
            const src_y = @as(u32, @intFromFloat(src_y_f));
            const y_diff = src_y_f - @as(f32, @floatFromInt(src_y));

            for (0..dst_width) |x| {
                const src_x_f = @as(f32, @floatFromInt(x)) * x_ratio;
                const src_x = @as(u32, @intFromFloat(src_x_f));
                const x_diff = src_x_f - @as(f32, @floatFromInt(src_x));

                // Simple average of 4 neighboring pixels (simplified)
                const idx1 = (src_y * src_width + src_x) * bytes_per_pixel;
                const dst_idx = (y * dst_width + x) * bytes_per_pixel;

                if (idx1 + bytes_per_pixel <= source.len and dst_idx + bytes_per_pixel <= destination.len) {
                    // Simplified - just copy nearest for now
                    _ = x_diff;
                    _ = y_diff;
                    @memcpy(destination[dst_idx..dst_idx + bytes_per_pixel], source[idx1..idx1 + bytes_per_pixel]);
                }
            }
        }

        return ScaleResult{
            .width = dst_width,
            .height = dst_height,
            .format = 0,
            .bytes_processed = dst_width * dst_height * bytes_per_pixel,
            .scaling_time_us = 0,
            .cache_hit = false,
        };
    }

    fn scaleOpenGL(self: *FractionalScalingManager, source: []const u8, src_width: u32, src_height: u32, format: u32, destination: []u8, dst_width: u32, dst_height: u32, filter: SurfaceScale.ScaleFilter) !ScaleResult {
        _ = self; _ = source; _ = src_width; _ = src_height; _ = format; _ = destination; _ = dst_width; _ = dst_height; _ = filter;
        // OpenGL texture scaling implementation would go here
        return error.NotImplemented;
    }

    fn scaleVulkan(self: *FractionalScalingManager, source: []const u8, src_width: u32, src_height: u32, format: u32, destination: []u8, dst_width: u32, dst_height: u32, filter: SurfaceScale.ScaleFilter) !ScaleResult {
        _ = self; _ = source; _ = src_width; _ = src_height; _ = format; _ = destination; _ = dst_width; _ = dst_height; _ = filter;
        // Vulkan compute scaling implementation would go here
        return error.NotImplemented;
    }

    fn scaleHardware(self: *FractionalScalingManager, source: []const u8, src_width: u32, src_height: u32, format: u32, destination: []u8, dst_width: u32, dst_height: u32, filter: SurfaceScale.ScaleFilter) !ScaleResult {
        _ = self; _ = source; _ = src_width; _ = src_height; _ = format; _ = destination; _ = dst_width; _ = dst_height; _ = filter;
        // Hardware display scaler implementation would go here
        return error.NotImplemented;
    }

    pub fn getOptimalScale(self: *FractionalScalingManager, dpi: f32, diagonal_inches: f32) FractionalScale {
        _ = self;

        // Calculate optimal scale based on DPI and screen size
        // Standard reference: 96 DPI at 1.0 scale
        const base_scale = dpi / 96.0;

        // Adjust for screen size (larger screens can handle smaller UI elements)
        var size_adjustment: f32 = 1.0;
        if (diagonal_inches > 27.0) {
            size_adjustment = 0.9; // Slightly smaller UI on large screens
        } else if (diagonal_inches < 13.0) {
            size_adjustment = 1.1; // Slightly larger UI on small screens
        }

        const optimal_scale = base_scale * size_adjustment;

        // Snap to common scale factors
        const common_scales = [_]f32{ 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0 };
        var best_scale = common_scales[0];
        var min_diff = @abs(optimal_scale - best_scale);

        for (common_scales) |scale| {
            const diff = @abs(optimal_scale - scale);
            if (diff < min_diff) {
                min_diff = diff;
                best_scale = scale;
            }
        }

        return FractionalScale.fromFloat(best_scale);
    }

    pub fn getStats(self: *FractionalScalingManager) Stats {
        const total_ops = self.total_scale_operations.load(.seq_cst);
        const hits = self.cache_hits.load(.seq_cst);
        const misses = self.cache_misses.load(.seq_cst);

        return Stats{
            .total_scale_operations = total_ops,
            .cache_hit_rate = if (hits + misses > 0) @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(hits + misses)) else 0.0,
            .active_surfaces = @intCast(self.surface_scales.count()),
            .tracked_outputs = @intCast(self.output_scales.count()),
            .scaling_backend = self.scaling_backend,
        };
    }

    pub const Stats = struct {
        total_scale_operations: u64,
        cache_hit_rate: f32,
        active_surfaces: u32,
        tracked_outputs: u32,
        scaling_backend: ScalingBackend,
    };
};

comptime {
    if (!features.Features.fractional_scaling) {
        @compileError("fractional_scaling.zig should only be compiled when fractional_scaling feature is enabled");
    }
}

test "fractional scale calculations" {
    const scale_125 = FractionalScale.fromFloat(1.25);
    const scale_150 = FractionalScale.fromFloat(1.5);

    try std.testing.expectApproxEqAbs(@as(f32, 1.25), scale_125.toFloat(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), scale_150.toFloat(), 0.01);

    const multiplied = scale_125.multiply(scale_150);
    try std.testing.expectApproxEqAbs(@as(f32, 1.875), multiplied.toFloat(), 0.01);

    try std.testing.expect(scale_125.isValid());
    try std.testing.expect(!FractionalScale.fromFloat(10.0).isValid());
}

test "scaling manager operations" {
    var manager = try FractionalScalingManager.init(std.testing.allocator);
    defer manager.deinit();

    // Test setting output scale
    try manager.setOutputScale(1, FractionalScale.SCALE_150);

    // Test setting surface scale
    try manager.setSurfaceScale(100, FractionalScale.SCALE_125, 1);

    // Test optimal scale calculation
    const optimal = manager.getOptimalScale(144.0, 24.0); // High DPI large monitor
    try std.testing.expect(optimal.toFloat() >= 1.0);

    const stats = manager.getStats();
    try std.testing.expect(stats.active_surfaces >= 1);
    try std.testing.expect(stats.tracked_outputs >= 1);
}