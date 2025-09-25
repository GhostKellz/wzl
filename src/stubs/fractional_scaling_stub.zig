const std = @import("std");
const protocol = @import("../protocol.zig");

pub const FractionalScale = packed struct {
    raw: u32,

    pub fn fromFloat(value: f32) FractionalScale {
        _ = value;
        return .{ .raw = 120 }; // Default to 1.0
    }

    pub fn toFloat(self: FractionalScale) f32 {
        return @as(f32, @floatFromInt(self.raw)) / 120.0;
    }

    pub fn isValid(self: FractionalScale) bool {
        _ = self;
        return false;
    }

    pub const SCALE_100 = FractionalScale{ .raw = 120 };
    pub const SCALE_125 = FractionalScale{ .raw = 150 };
    pub const SCALE_150 = FractionalScale{ .raw = 180 };
    pub const SCALE_200 = FractionalScale{ .raw = 240 };
};

pub const SurfaceScale = struct {
    surface_id: protocol.ObjectId,

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

    pub fn getEffectiveScale(self: *const SurfaceScale) FractionalScale {
        _ = self;
        return FractionalScale.SCALE_100;
    }

    pub fn needsScaling(self: *const SurfaceScale) bool {
        _ = self;
        return false;
    }
};

pub const FractionalScalingManager = struct {
    pub fn init(allocator: std.mem.Allocator) !FractionalScalingManager {
        _ = allocator;
        return error.FeatureDisabled;
    }

    pub fn deinit(self: *FractionalScalingManager) void {
        _ = self;
    }

    pub fn setOutputScale(self: *FractionalScalingManager, output_id: protocol.ObjectId, scale: FractionalScale) !void {
        _ = self;
        _ = output_id;
        _ = scale;
        return error.FeatureDisabled;
    }

    pub fn setSurfaceScale(self: *FractionalScalingManager, surface_id: protocol.ObjectId, preferred_scale: FractionalScale, buffer_scale: u32) !void {
        _ = self;
        _ = surface_id;
        _ = preferred_scale;
        _ = buffer_scale;
        return error.FeatureDisabled;
    }
};