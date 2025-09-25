const std = @import("std");
const protocol = @import("../protocol.zig");

pub const GpuVendor = enum {
    intel,
    amd,
    nvidia,
    qualcomm,
    arm,
    imagination,
    unknown,

    pub fn fromVendorId(id: u32) GpuVendor {
        _ = id;
        return .unknown;
    }

    pub fn getName(self: GpuVendor) []const u8 {
        return switch (self) {
            .intel => "Intel",
            .amd => "AMD",
            .nvidia => "NVIDIA",
            .qualcomm => "Qualcomm",
            .arm => "ARM",
            .imagination => "Imagination Technologies",
            .unknown => "Unknown",
        };
    }
};

pub const GpuDevice = struct {
    pub const WorkloadType = enum {
        compositing,
        gaming,
        compute,
        video_encoding,
    };

    pub fn init(allocator: std.mem.Allocator, id: u32) GpuDevice {
        _ = allocator;
        _ = id;
        return undefined;
    }

    pub fn deinit(self: *GpuDevice) void {
        _ = self;
    }

    pub fn getScore(self: *const GpuDevice, workload: WorkloadType) u32 {
        _ = self;
        _ = workload;
        return 0;
    }
};

pub const MultiGpuManager = struct {
    pub fn init(allocator: std.mem.Allocator) !MultiGpuManager {
        _ = allocator;
        return error.FeatureDisabled;
    }

    pub fn deinit(self: *MultiGpuManager) void {
        _ = self;
    }

    pub fn assignGpu(self: *MultiGpuManager, surface_id: protocol.ObjectId, workload_type: GpuDevice.WorkloadType, priority: u8, performance_hint: anytype) !u32 {
        _ = self;
        _ = surface_id;
        _ = workload_type;
        _ = priority;
        _ = performance_hint;
        return error.FeatureDisabled;
    }
};