const std = @import("std");
const protocol = @import("protocol.zig");

// Color Management and HDR Support for Wayland
// Implements color space conversion, HDR tone mapping, and ICC profile support

pub const ColorSpace = enum {
    srgb,           // Standard RGB (default)
    display_p3,     // Display P3 wide gamut
    rec2020,        // Rec. 2020 ultra wide gamut
    adobe_rgb,      // Adobe RGB (1998)
    dci_p3,         // DCI-P3 cinema standard
    linear_srgb,    // Linear sRGB for computation
    scrgb,          // scRGB extended range
};

pub const TransferFunction = enum {
    srgb,           // sRGB gamma curve
    gamma_2_2,      // Simple 2.2 gamma
    gamma_2_4,      // Simple 2.4 gamma
    pq,             // Perceptual Quantizer (HDR10)
    hlg,            // Hybrid Log-Gamma (broadcast HDR)
    linear,         // Linear (no transfer function)
};

pub const HDRMetadata = struct {
    max_luminance: f32 = 1000.0,        // nits
    min_luminance: f32 = 0.005,         // nits
    max_content_light_level: f32 = 1000.0,
    max_frame_average_light_level: f32 = 500.0,

    // Primary color coordinates (CIE xy)
    red_primary: [2]f32 = .{ 0.680, 0.320 },
    green_primary: [2]f32 = .{ 0.265, 0.690 },
    blue_primary: [2]f32 = .{ 0.150, 0.060 },
    white_point: [2]f32 = .{ 0.3127, 0.3290 }, // D65
};

pub const ColorProfile = struct {
    name: []const u8,
    color_space: ColorSpace,
    transfer_function: TransferFunction,
    hdr_metadata: ?HDRMetadata = null,
    icc_data: ?[]const u8 = null, // ICC profile blob

    const Self = @This();

    pub fn isHDR(self: *const Self) bool {
        return self.hdr_metadata != null or
               self.transfer_function == .pq or
               self.transfer_function == .hlg;
    }

    pub fn requiresConversion(self: *const Self, target: *const ColorProfile) bool {
        return self.color_space != target.color_space or
               self.transfer_function != target.transfer_function;
    }
};

pub const ColorTransform = struct {
    // 3x3 color matrix for RGB transformations
    matrix: [3][3]f32,
    // Pre and post offset for the transform
    pre_offset: [3]f32 = .{ 0, 0, 0 },
    post_offset: [3]f32 = .{ 0, 0, 0 },

    const Self = @This();

    pub fn identity() Self {
        return Self{
            .matrix = .{
                .{ 1.0, 0.0, 0.0 },
                .{ 0.0, 1.0, 0.0 },
                .{ 0.0, 0.0, 1.0 },
            },
        };
    }

    pub fn apply(self: *const Self, r: f32, g: f32, b: f32) [3]f32 {
        const r_in = r + self.pre_offset[0];
        const g_in = g + self.pre_offset[1];
        const b_in = b + self.pre_offset[2];

        return .{
            r_in * self.matrix[0][0] + g_in * self.matrix[0][1] + b_in * self.matrix[0][2] + self.post_offset[0],
            r_in * self.matrix[1][0] + g_in * self.matrix[1][1] + b_in * self.matrix[1][2] + self.post_offset[1],
            r_in * self.matrix[2][0] + g_in * self.matrix[2][1] + b_in * self.matrix[2][2] + self.post_offset[2],
        };
    }
};

pub const ColorManager = struct {
    allocator: std.mem.Allocator,
    display_profile: ColorProfile,
    surface_profiles: std.HashMap(protocol.ObjectId, ColorProfile, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage),
    transforms_cache: std.HashMap(u64, ColorTransform, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .display_profile = ColorProfile{
                .name = "sRGB Display",
                .color_space = .srgb,
                .transfer_function = .srgb,
            },
            .surface_profiles = std.HashMap(protocol.ObjectId, ColorProfile, std.hash_map.AutoContext(protocol.ObjectId), std.hash_map.default_max_load_percentage).init(allocator),
            .transforms_cache = std.HashMap(u64, ColorTransform, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.surface_profiles.deinit();
        self.transforms_cache.deinit();
    }

    pub fn setDisplayProfile(self: *Self, profile: ColorProfile) !void {
        self.display_profile = profile;
        // Clear transform cache when display profile changes
        self.transforms_cache.clearRetainingCapacity();
        std.debug.print("[wzl-color] Display profile set to {s}\n", .{profile.name});
    }

    pub fn setSurfaceProfile(self: *Self, surface_id: protocol.ObjectId, profile: ColorProfile) !void {
        try self.surface_profiles.put(surface_id, profile);
        std.debug.print("[wzl-color] Surface {} profile set to {s}\n", .{ surface_id, profile.name });
    }

    pub fn getSurfaceProfile(self: *Self, surface_id: protocol.ObjectId) ?ColorProfile {
        return self.surface_profiles.get(surface_id);
    }

    pub fn getTransform(self: *Self, from: *const ColorProfile, to: *const ColorProfile) !ColorTransform {
        // Create a cache key from the color space and transfer function enums
        const cache_key = (@intFromEnum(from.color_space) << 24) |
                         (@intFromEnum(from.transfer_function) << 16) |
                         (@intFromEnum(to.color_space) << 8) |
                         @intFromEnum(to.transfer_function);

        if (self.transforms_cache.get(cache_key)) |transform| {
            return transform;
        }

        const transform = try self.calculateTransform(from, to);
        try self.transforms_cache.put(cache_key, transform);
        return transform;
    }

    fn calculateTransform(self: *Self, from: *const ColorProfile, to: *const ColorProfile) !ColorTransform {
        _ = self;

        // Identity transform if same color space
        if (from.color_space == to.color_space and from.transfer_function == to.transfer_function) {
            return ColorTransform.identity();
        }

        // sRGB to Display P3 transformation
        if (from.color_space == .srgb and to.color_space == .display_p3) {
            return ColorTransform{
                .matrix = .{
                    .{ 0.8225, 0.1774, 0.0000 },
                    .{ 0.0332, 0.9669, 0.0000 },
                    .{ 0.0171, 0.0724, 0.9108 },
                },
            };
        }

        // Display P3 to sRGB transformation
        if (from.color_space == .display_p3 and to.color_space == .srgb) {
            return ColorTransform{
                .matrix = .{
                    .{ 1.2249, -0.2247, 0.0000 },
                    .{ -0.0420, 1.0419, 0.0000 },
                    .{ -0.0197, -0.0786, 1.0979 },
                },
            };
        }

        // sRGB to Rec. 2020 transformation
        if (from.color_space == .srgb and to.color_space == .rec2020) {
            return ColorTransform{
                .matrix = .{
                    .{ 0.6274, 0.3293, 0.0433 },
                    .{ 0.0691, 0.9195, 0.0114 },
                    .{ 0.0164, 0.0880, 0.8956 },
                },
            };
        }

        // Default identity for unsupported conversions
        std.debug.print("[wzl-color] Warning: No transform from {s} to {s}, using identity\n", .{
            @tagName(from.color_space),
            @tagName(to.color_space),
        });
        return ColorTransform.identity();
    }

    pub fn performToneMapping(self: *Self, value: f32, from_hdr: *const HDRMetadata, to_sdr_peak: f32) f32 {
        _ = self;

        if (from_hdr == null) return value;

        const hdr = from_hdr.?;
        const input_peak = hdr.max_luminance;

        // Simple Reinhard tone mapping
        const scaled = value * (to_sdr_peak / input_peak);
        return scaled / (1.0 + scaled);
    }

    pub fn applyGammaCorrection(self: *Self, value: f32, transfer: TransferFunction, inverse: bool) f32 {
        _ = self;

        return switch (transfer) {
            .srgb => if (inverse) srgbToLinear(value) else linearToSrgb(value),
            .gamma_2_2 => if (inverse) std.math.pow(f32, value, 2.2) else std.math.pow(f32, value, 1.0 / 2.2),
            .gamma_2_4 => if (inverse) std.math.pow(f32, value, 2.4) else std.math.pow(f32, value, 1.0 / 2.4),
            .linear => value,
            .pq => if (inverse) pqToLinear(value) else linearToPq(value),
            .hlg => if (inverse) hlgToLinear(value) else linearToHlg(value),
        };
    }
};

// Transfer function implementations
fn srgbToLinear(value: f32) f32 {
    if (value <= 0.04045) {
        return value / 12.92;
    } else {
        return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
    }
}

fn linearToSrgb(value: f32) f32 {
    if (value <= 0.0031308) {
        return value * 12.92;
    } else {
        return 1.055 * std.math.pow(f32, value, 1.0 / 2.4) - 0.055;
    }
}

fn pqToLinear(value: f32) f32 {
    const m1 = 0.1593017578125;
    const m2 = 78.84375;
    const c1 = 0.8359375;
    const c2 = 18.8515625;
    const c3 = 18.6875;

    const pow_value = std.math.pow(f32, value, 1.0 / m2);
    const numerator = @max(pow_value - c1, 0.0);
    const denominator = c2 - c3 * pow_value;

    if (denominator == 0) return 0;
    return std.math.pow(f32, numerator / denominator, 1.0 / m1);
}

fn linearToPq(value: f32) f32 {
    const m1 = 0.1593017578125;
    const m2 = 78.84375;
    const c1 = 0.8359375;
    const c2 = 18.8515625;
    const c3 = 18.6875;

    const pow_value = std.math.pow(f32, value, m1);
    const numerator = c1 + c2 * pow_value;
    const denominator = 1.0 + c3 * pow_value;

    return std.math.pow(f32, numerator / denominator, m2);
}

fn hlgToLinear(value: f32) f32 {
    const a = 0.17883277;
    const b = 0.28466892;
    const c = 0.55991073;

    if (value <= 0.5) {
        return (value * value) / 3.0;
    } else {
        return (std.math.exp((value - c) / a) + b) / 12.0;
    }
}

fn linearToHlg(value: f32) f32 {
    const a = 0.17883277;
    const b = 0.28466892;
    const c = 0.55991073;

    if (value <= 1.0 / 12.0) {
        return std.math.sqrt(3.0 * value);
    } else {
        return a * std.math.log(std.math.e, 12.0 * value - b) + c;
    }
}

// Wayland protocol extensions for color management
pub const zwp_color_manager_v1_interface = protocol.Interface{
    .name = "zwp_color_manager_v1",
    .version = 1,
};

pub const zwp_color_space_v1_interface = protocol.Interface{
    .name = "zwp_color_space_v1",
    .version = 1,
};

test "color space conversion" {
    var manager = try ColorManager.init(std.testing.allocator);
    defer manager.deinit();

    const srgb_profile = ColorProfile{
        .name = "sRGB",
        .color_space = .srgb,
        .transfer_function = .srgb,
    };

    const p3_profile = ColorProfile{
        .name = "Display P3",
        .color_space = .display_p3,
        .transfer_function = .srgb,
    };

    const transform = try manager.getTransform(&srgb_profile, &p3_profile);
    const result = transform.apply(1.0, 0.5, 0.25);

    try std.testing.expect(result[0] >= 0.0 and result[0] <= 1.1);
    try std.testing.expect(result[1] >= 0.0 and result[1] <= 1.1);
    try std.testing.expect(result[2] >= 0.0 and result[2] <= 1.1);
}

test "gamma correction" {
    var manager = try ColorManager.init(std.testing.allocator);
    defer manager.deinit();

    // Test sRGB gamma
    const linear = manager.applyGammaCorrection(0.5, .srgb, true);
    const back_to_srgb = manager.applyGammaCorrection(linear, .srgb, false);

    try std.testing.expectApproxEqAbs(back_to_srgb, 0.5, 0.001);
}