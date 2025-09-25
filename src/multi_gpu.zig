const std = @import("std");
const protocol = @import("protocol.zig");
const features = @import("features.zig");
const thread_safety = @import("thread_safety.zig");
const errors = @import("errors.zig");

/// GPU vendor identification
pub const GpuVendor = enum {
    intel,
    amd,
    nvidia,
    qualcomm,
    arm,
    imagination,
    unknown,

    pub fn fromVendorId(id: u32) GpuVendor {
        return switch (id) {
            0x8086 => .intel,
            0x1002, 0x1022 => .amd,
            0x10de => .nvidia,
            0x5143 => .qualcomm,
            0x13B5 => .arm,
            0x1010 => .imagination,
            else => .unknown,
        };
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

/// GPU device type classification
pub const GpuType = enum {
    integrated,
    discrete,
    virtual,
    cpu,
    unknown,
};

/// GPU performance tier for workload distribution
pub const PerformanceTier = enum {
    low,       // Basic 2D, simple compositing
    medium,    // Standard desktop, light gaming
    high,      // Gaming, professional graphics
    extreme,   // High-end workstations, ML/AI
};

/// GPU memory information
pub const MemoryInfo = struct {
    total_vram: u64,
    available_vram: u64,
    shared_memory: u64,
    memory_bandwidth: u64, // GB/s
    memory_type: MemoryType,

    pub const MemoryType = enum {
        gddr6,
        gddr5,
        hbm2,
        hbm3,
        ddr4,
        ddr5,
        unknown,
    };
};

/// Individual GPU device
pub const GpuDevice = struct {
    id: u32,
    name: []const u8,
    vendor: GpuVendor,
    device_id: u32,
    vendor_id: u32,
    gpu_type: GpuType,
    performance_tier: PerformanceTier,
    memory_info: MemoryInfo,

    // Driver information
    driver_name: []const u8,
    driver_version: []const u8,

    // Capabilities
    supports_vulkan: bool,
    supports_opengl: bool,
    supports_compute: bool,
    supports_ray_tracing: bool,
    supports_mesh_shaders: bool,
    supports_variable_rate_shading: bool,

    // DRM/KMS information
    drm_node: ?[]const u8,
    render_node: ?[]const u8,
    primary_node: ?[]const u8,

    // Power management
    power_profile: PowerProfile,
    max_power_draw: u32, // watts
    current_power_draw: u32,
    temperature: u32, // celsius

    // Performance counters
    gpu_utilization: f32,      // 0.0-1.0
    memory_utilization: f32,   // 0.0-1.0
    current_frequency: u32,    // MHz
    max_frequency: u32,        // MHz

    allocator: std.mem.Allocator,
    is_active: bool,

    pub const PowerProfile = enum {
        power_save,
        balanced,
        performance,
        max_performance,
    };

    pub fn init(allocator: std.mem.Allocator, id: u32) GpuDevice {
        return GpuDevice{
            .id = id,
            .name = "",
            .vendor = .unknown,
            .device_id = 0,
            .vendor_id = 0,
            .gpu_type = .unknown,
            .performance_tier = .medium,
            .memory_info = std.mem.zeroes(MemoryInfo),
            .driver_name = "",
            .driver_version = "",
            .supports_vulkan = false,
            .supports_opengl = false,
            .supports_compute = false,
            .supports_ray_tracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .drm_node = null,
            .render_node = null,
            .primary_node = null,
            .power_profile = .balanced,
            .max_power_draw = 0,
            .current_power_draw = 0,
            .temperature = 0,
            .gpu_utilization = 0.0,
            .memory_utilization = 0.0,
            .current_frequency = 0,
            .max_frequency = 0,
            .allocator = allocator,
            .is_active = false,
        };
    }

    pub fn deinit(self: *GpuDevice) void {
        if (self.name.len > 0) self.allocator.free(self.name);
        if (self.driver_name.len > 0) self.allocator.free(self.driver_name);
        if (self.driver_version.len > 0) self.allocator.free(self.driver_version);
        if (self.drm_node) |node| self.allocator.free(node);
        if (self.render_node) |node| self.allocator.free(node);
        if (self.primary_node) |node| self.allocator.free(node);
    }

    pub fn getScore(self: *const GpuDevice, workload: WorkloadType) u32 {
        var score: u32 = 0;

        // Base score from performance tier
        score += switch (self.performance_tier) {
            .low => 100,
            .medium => 300,
            .high => 700,
            .extreme => 1000,
        };

        // Adjust for GPU type
        score += switch (self.gpu_type) {
            .discrete => 200,
            .integrated => 50,
            .virtual => 10,
            .cpu => 5,
            .unknown => 0,
        };

        // Memory considerations
        if (self.memory_info.total_vram > 8 * 1024 * 1024 * 1024) score += 100; // >8GB
        if (self.memory_info.memory_bandwidth > 500) score += 50; // >500 GB/s

        // Workload-specific scoring
        score += switch (workload) {
            .compositing => blk: {
                var workload_score: u32 = 0;
                if (self.supports_opengl) workload_score += 50;
                if (self.gpu_type == .integrated) workload_score += 30; // Prefer integrated for basic compositing
                break :blk workload_score;
            },
            .gaming => blk: {
                var workload_score: u32 = 0;
                if (self.supports_vulkan) workload_score += 100;
                if (self.supports_ray_tracing) workload_score += 200;
                if (self.supports_mesh_shaders) workload_score += 50;
                if (self.gpu_type == .discrete) workload_score += 100;
                break :blk workload_score;
            },
            .compute => blk: {
                var workload_score: u32 = 0;
                if (self.supports_compute) workload_score += 200;
                if (self.supports_vulkan) workload_score += 100;
                if (self.memory_info.total_vram > 16 * 1024 * 1024 * 1024) workload_score += 150; // >16GB for ML
                break :blk workload_score;
            },
            .video_encoding => blk: {
                var workload_score: u32 = 0;
                // Prefer NVIDIA for video encoding (NVENC)
                if (self.vendor == .nvidia) workload_score += 200;
                // Intel QuickSync is also good
                if (self.vendor == .intel and self.gpu_type == .integrated) workload_score += 150;
                // AMD VCE
                if (self.vendor == .amd) workload_score += 100;
                break :blk workload_score;
            },
        };

        // Penalize high temperature and power usage for efficiency
        if (self.temperature > 80) score = score * 80 / 100;
        if (self.current_power_draw > self.max_power_draw * 80 / 100) score = score * 90 / 100;

        return score;
    }

    pub const WorkloadType = enum {
        compositing,
        gaming,
        compute,
        video_encoding,
    };
};

/// Multi-GPU manager and scheduler
pub const MultiGpuManager = struct {
    allocator: std.mem.Allocator,
    gpus: thread_safety.Registry(GpuDevice),
    active_assignments: std.AutoHashMap(protocol.ObjectId, Assignment),
    load_balancer: LoadBalancer,
    thermal_manager: ThermalManager,

    // Performance tracking
    context_switches: std.atomic.Value(u64),
    workload_migrations: std.atomic.Value(u64),

    const Assignment = struct {
        gpu_id: u32,
        workload_type: GpuDevice.WorkloadType,
        priority: u8,
        timestamp: i64,
        performance_hint: PerformanceHint,
    };

    const PerformanceHint = enum {
        power_save,
        balanced,
        performance,
        ultra_performance,
    };

    const LoadBalancer = struct {
        strategy: Strategy,
        workload_history: std.ArrayList(WorkloadHistory),
        migration_threshold: f32,

        const Strategy = enum {
            round_robin,
            performance_based,
            power_efficient,
            workload_aware,
        };

        const WorkloadHistory = struct {
            gpu_id: u32,
            workload_type: GpuDevice.WorkloadType,
            duration_ms: u64,
            avg_utilization: f32,
        };
    };

    const ThermalManager = struct {
        temperature_limits: std.AutoHashMap(u32, TemperatureLimit),
        throttling_active: std.atomic.Value(bool),

        const TemperatureLimit = struct {
            warning_temp: u32,
            critical_temp: u32,
            throttle_temp: u32,
        };
    };

    pub fn init(allocator: std.mem.Allocator) !MultiGpuManager {
        var manager = MultiGpuManager{
            .allocator = allocator,
            .gpus = thread_safety.Registry(GpuDevice).init(allocator),
            .active_assignments = std.AutoHashMap(protocol.ObjectId, Assignment).init(allocator),
            .load_balancer = LoadBalancer{
                .strategy = .workload_aware,
                .workload_history = std.ArrayList(LoadBalancer.WorkloadHistory).init(allocator),
                .migration_threshold = 0.15, // 15% utilization difference
            },
            .thermal_manager = ThermalManager{
                .temperature_limits = std.AutoHashMap(u32, ThermalManager.TemperatureLimit).init(allocator),
                .throttling_active = std.atomic.Value(bool).init(false),
            },
            .context_switches = std.atomic.Value(u64).init(0),
            .workload_migrations = std.atomic.Value(u64).init(0),
        };

        // Discover available GPUs
        try manager.discoverGpus();

        // Initialize thermal limits
        try manager.initializeThermalLimits();

        return manager;
    }

    pub fn deinit(self: *MultiGpuManager) void {
        self.gpus.deinit();
        self.active_assignments.deinit();
        self.load_balancer.workload_history.deinit();
        self.thermal_manager.temperature_limits.deinit();
    }

    fn discoverGpus(self: *MultiGpuManager) !void {
        // In real implementation, this would scan /dev/dri/, query PCI devices, etc.
        // For now, create representative GPU configurations

        // Intel integrated GPU
        var intel_gpu = GpuDevice.init(self.allocator, 0);
        intel_gpu.name = try self.allocator.dupe(u8, "Intel UHD Graphics 620");
        intel_gpu.vendor = .intel;
        intel_gpu.vendor_id = 0x8086;
        intel_gpu.device_id = 0x3EA0;
        intel_gpu.gpu_type = .integrated;
        intel_gpu.performance_tier = .medium;
        intel_gpu.memory_info = MemoryInfo{
            .total_vram = 2 * 1024 * 1024 * 1024, // 2GB shared
            .available_vram = 1536 * 1024 * 1024,
            .shared_memory = 8 * 1024 * 1024 * 1024,
            .memory_bandwidth = 68, // GB/s
            .memory_type = .ddr4,
        };
        intel_gpu.driver_name = try self.allocator.dupe(u8, "i915");
        intel_gpu.driver_version = try self.allocator.dupe(u8, "1.6.0");
        intel_gpu.supports_vulkan = true;
        intel_gpu.supports_opengl = true;
        intel_gpu.supports_compute = true;
        intel_gpu.drm_node = try self.allocator.dupe(u8, "/dev/dri/card0");
        intel_gpu.render_node = try self.allocator.dupe(u8, "/dev/dri/renderD128");
        intel_gpu.max_power_draw = 15;
        intel_gpu.max_frequency = 1100;
        _ = try self.gpus.add(&intel_gpu);

        // NVIDIA discrete GPU
        var nvidia_gpu = GpuDevice.init(self.allocator, 1);
        nvidia_gpu.name = try self.allocator.dupe(u8, "NVIDIA GeForce RTX 4070");
        nvidia_gpu.vendor = .nvidia;
        nvidia_gpu.vendor_id = 0x10de;
        nvidia_gpu.device_id = 0x2786;
        nvidia_gpu.gpu_type = .discrete;
        nvidia_gpu.performance_tier = .high;
        nvidia_gpu.memory_info = MemoryInfo{
            .total_vram = 12 * 1024 * 1024 * 1024, // 12GB GDDR6X
            .available_vram = 11264 * 1024 * 1024,
            .shared_memory = 0,
            .memory_bandwidth = 504, // GB/s
            .memory_type = .gddr6,
        };
        nvidia_gpu.driver_name = try self.allocator.dupe(u8, "nvidia");
        nvidia_gpu.driver_version = try self.allocator.dupe(u8, "545.29.06");
        nvidia_gpu.supports_vulkan = true;
        nvidia_gpu.supports_opengl = true;
        nvidia_gpu.supports_compute = true;
        nvidia_gpu.supports_ray_tracing = true;
        nvidia_gpu.supports_mesh_shaders = true;
        nvidia_gpu.supports_variable_rate_shading = true;
        nvidia_gpu.drm_node = try self.allocator.dupe(u8, "/dev/dri/card1");
        nvidia_gpu.render_node = try self.allocator.dupe(u8, "/dev/dri/renderD129");
        nvidia_gpu.max_power_draw = 200;
        nvidia_gpu.max_frequency = 2610;
        _ = try self.gpus.add(&nvidia_gpu);

        // AMD discrete GPU
        var amd_gpu = GpuDevice.init(self.allocator, 2);
        amd_gpu.name = try self.allocator.dupe(u8, "AMD Radeon RX 7700 XT");
        amd_gpu.vendor = .amd;
        amd_gpu.vendor_id = 0x1002;
        amd_gpu.device_id = 0x7480;
        amd_gpu.gpu_type = .discrete;
        amd_gpu.performance_tier = .high;
        amd_gpu.memory_info = MemoryInfo{
            .total_vram = 12 * 1024 * 1024 * 1024, // 12GB GDDR6
            .available_vram = 11520 * 1024 * 1024,
            .shared_memory = 0,
            .memory_bandwidth = 432, // GB/s
            .memory_type = .gddr6,
        };
        amd_gpu.driver_name = try self.allocator.dupe(u8, "amdgpu");
        amd_gpu.driver_version = try self.allocator.dupe(u8, "23.20");
        amd_gpu.supports_vulkan = true;
        amd_gpu.supports_opengl = true;
        amd_gpu.supports_compute = true;
        amd_gpu.supports_ray_tracing = true;
        amd_gpu.supports_mesh_shaders = true;
        amd_gpu.drm_node = try self.allocator.dupe(u8, "/dev/dri/card2");
        amd_gpu.render_node = try self.allocator.dupe(u8, "/dev/dri/renderD130");
        amd_gpu.max_power_draw = 245;
        amd_gpu.max_frequency = 2544;
        _ = try self.gpus.add(&amd_gpu);
    }

    fn initializeThermalLimits(self: *MultiGpuManager) !void {
        var iter = self.gpus.objects.iterator();
        while (iter.next()) |entry| {
            const gpu = entry.value_ptr.*;
            const limits = switch (gpu.gpu_type) {
                .integrated => ThermalManager.TemperatureLimit{
                    .warning_temp = 85,
                    .critical_temp = 100,
                    .throttle_temp = 95,
                },
                .discrete => ThermalManager.TemperatureLimit{
                    .warning_temp = 75,
                    .critical_temp = 90,
                    .throttle_temp = 83,
                },
                else => ThermalManager.TemperatureLimit{
                    .warning_temp = 80,
                    .critical_temp = 95,
                    .throttle_temp = 88,
                },
            };
            try self.thermal_manager.temperature_limits.put(gpu.id, limits);
        }
    }

    pub fn assignGpu(
        self: *MultiGpuManager,
        surface_id: protocol.ObjectId,
        workload_type: GpuDevice.WorkloadType,
        priority: u8,
        performance_hint: PerformanceHint,
    ) !u32 {
        const best_gpu_id = try self.selectBestGpu(workload_type, performance_hint);

        const assignment = Assignment{
            .gpu_id = best_gpu_id,
            .workload_type = workload_type,
            .priority = priority,
            .timestamp = std.time.milliTimestamp(),
            .performance_hint = performance_hint,
        };

        try self.active_assignments.put(surface_id, assignment);

        // Activate GPU if not already active
        if (self.gpus.get(@intCast(best_gpu_id))) |gpu| {
            if (!gpu.is_active) {
                gpu.is_active = true;
                _ = self.context_switches.fetchAdd(1, .seq_cst);
            }
        }

        return best_gpu_id;
    }

    fn selectBestGpu(self: *MultiGpuManager, workload_type: GpuDevice.WorkloadType, performance_hint: PerformanceHint) !u32 {
        var best_gpu_id: u32 = 0;
        var best_score: u32 = 0;

        var iter = self.gpus.objects.iterator();
        while (iter.next()) |entry| {
            const gpu = entry.value_ptr.*;

            // Skip GPUs that are thermal throttling
            if (self.isGpuThrottling(gpu.id)) continue;

            var score = gpu.getScore(workload_type);

            // Adjust score based on performance hint
            score = switch (performance_hint) {
                .power_save => score * 50 / 100, // Prefer lower power
                .balanced => score,
                .performance => score * 120 / 100,
                .ultra_performance => score * 150 / 100,
            };

            // Consider current load
            const utilization = gpu.gpu_utilization;
            if (utilization > 0.8) score = score * 70 / 100; // Heavy penalty for overloaded GPUs
            if (utilization < 0.3) score = score * 110 / 100; // Bonus for underutilized GPUs

            if (score > best_score) {
                best_score = score;
                best_gpu_id = gpu.id;
            }
        }

        if (best_score == 0) {
            return error.NoSuitableGpu;
        }

        return best_gpu_id;
    }

    fn isGpuThrottling(self: *MultiGpuManager, gpu_id: u32) bool {
        if (self.thermal_manager.temperature_limits.get(gpu_id)) |limits| {
            if (self.gpus.get(@intCast(gpu_id))) |gpu| {
                return gpu.temperature >= limits.throttle_temp;
            }
        }
        return false;
    }

    pub fn migrateWorkload(self: *MultiGpuManager, surface_id: protocol.ObjectId) !?u32 {
        const current_assignment = self.active_assignments.get(surface_id) orelse return null;

        const new_gpu_id = try self.selectBestGpu(current_assignment.workload_type, current_assignment.performance_hint);

        if (new_gpu_id == current_assignment.gpu_id) {
            return null; // No migration needed
        }

        // Check if migration is beneficial
        const current_gpu = self.gpus.get(@intCast(current_assignment.gpu_id)).?;
        const new_gpu = self.gpus.get(@intCast(new_gpu_id)).?;

        const utilization_diff = current_gpu.gpu_utilization - new_gpu.gpu_utilization;
        if (utilization_diff < self.load_balancer.migration_threshold) {
            return null; // Not worth migrating
        }

        // Perform migration
        var updated_assignment = current_assignment;
        updated_assignment.gpu_id = new_gpu_id;
        updated_assignment.timestamp = std.time.milliTimestamp();

        try self.active_assignments.put(surface_id, updated_assignment);
        _ = self.workload_migrations.fetchAdd(1, .seq_cst);

        return new_gpu_id;
    }

    pub fn getRecommendation(self: *MultiGpuManager, workload_type: GpuDevice.WorkloadType) !GpuRecommendation {
        const gpu_id = try self.selectBestGpu(workload_type, .balanced);
        const gpu = self.gpus.get(@intCast(gpu_id)) orelse return error.GpuNotFound;

        return GpuRecommendation{
            .gpu_id = gpu_id,
            .confidence = self.calculateConfidence(gpu, workload_type),
            .reasons = try self.generateReasons(gpu, workload_type),
            .alternative_gpus = try self.getAlternatives(workload_type, gpu_id),
        };
    }

    const GpuRecommendation = struct {
        gpu_id: u32,
        confidence: f32, // 0.0-1.0
        reasons: std.ArrayList([]const u8),
        alternative_gpus: std.ArrayList(u32),
    };

    fn calculateConfidence(self: *MultiGpuManager, gpu: *const GpuDevice, workload_type: GpuDevice.WorkloadType) f32 {
        _ = self;
        var confidence: f32 = 0.5; // Base confidence

        // High confidence for workload-specific capabilities
        switch (workload_type) {
            .gaming => {
                if (gpu.supports_ray_tracing) confidence += 0.2;
                if (gpu.supports_mesh_shaders) confidence += 0.1;
                if (gpu.gpu_type == .discrete) confidence += 0.15;
            },
            .compute => {
                if (gpu.supports_compute) confidence += 0.25;
                if (gpu.memory_info.total_vram > 8 * 1024 * 1024 * 1024) confidence += 0.15;
            },
            .video_encoding => {
                if (gpu.vendor == .nvidia) confidence += 0.3;
                if (gpu.vendor == .intel and gpu.gpu_type == .integrated) confidence += 0.2;
            },
            .compositing => {
                if (gpu.supports_opengl) confidence += 0.2;
                confidence += 0.1; // Most GPUs can handle compositing
            },
        }

        // Reduce confidence for thermal issues
        if (gpu.temperature > 75) confidence *= 0.8;
        if (gpu.gpu_utilization > 0.8) confidence *= 0.7;

        return @min(confidence, 1.0);
    }

    fn generateReasons(self: *MultiGpuManager, gpu: *const GpuDevice, workload_type: GpuDevice.WorkloadType) !std.ArrayList([]const u8) {
        var reasons = std.ArrayList([]const u8).init(self.allocator);

        switch (workload_type) {
            .gaming => {
                if (gpu.supports_ray_tracing) {
                    try reasons.append(try self.allocator.dupe(u8, "Hardware ray tracing support"));
                }
                if (gpu.gpu_type == .discrete) {
                    try reasons.append(try self.allocator.dupe(u8, "Dedicated GPU with high performance"));
                }
            },
            .compute => {
                if (gpu.supports_compute) {
                    try reasons.append(try self.allocator.dupe(u8, "Compute shader support"));
                }
                if (gpu.memory_info.total_vram > 8 * 1024 * 1024 * 1024) {
                    try reasons.append(try self.allocator.dupe(u8, "Large VRAM for compute workloads"));
                }
            },
            .video_encoding => {
                if (gpu.vendor == .nvidia) {
                    try reasons.append(try self.allocator.dupe(u8, "NVENC hardware encoder"));
                }
            },
            .compositing => {
                try reasons.append(try self.allocator.dupe(u8, "Suitable for desktop compositing"));
            },
        }

        if (gpu.gpu_utilization < 0.3) {
            try reasons.append(try self.allocator.dupe(u8, "Low current utilization"));
        }

        return reasons;
    }

    fn getAlternatives(self: *MultiGpuManager, workload_type: GpuDevice.WorkloadType, exclude_gpu_id: u32) !std.ArrayList(u32) {
        var alternatives = std.ArrayList(u32).init(self.allocator);

        var iter = self.gpus.objects.iterator();
        while (iter.next()) |entry| {
            const gpu = entry.value_ptr.*;
            if (gpu.id != exclude_gpu_id and gpu.getScore(workload_type) > 200) {
                try alternatives.append(gpu.id);
            }
        }

        return alternatives;
    }

    pub fn getSystemStats(self: *MultiGpuManager) SystemStats {
        var stats = SystemStats{
            .total_gpus = @intCast(self.gpus.count()),
            .active_gpus = 0,
            .total_vram = 0,
            .available_vram = 0,
            .avg_gpu_utilization = 0,
            .avg_memory_utilization = 0,
            .thermal_throttling_active = self.thermal_manager.throttling_active.load(.seq_cst),
            .context_switches = self.context_switches.load(.seq_cst),
            .workload_migrations = self.workload_migrations.load(.seq_cst),
        };

        var total_gpu_util: f32 = 0;
        var total_mem_util: f32 = 0;
        var active_count: u32 = 0;

        var iter = self.gpus.objects.iterator();
        while (iter.next()) |entry| {
            const gpu = entry.value_ptr.*;
            stats.total_vram += gpu.memory_info.total_vram;
            stats.available_vram += gpu.memory_info.available_vram;

            if (gpu.is_active) {
                active_count += 1;
                total_gpu_util += gpu.gpu_utilization;
                total_mem_util += gpu.memory_utilization;
            }
        }

        stats.active_gpus = active_count;
        if (active_count > 0) {
            stats.avg_gpu_utilization = total_gpu_util / @as(f32, @floatFromInt(active_count));
            stats.avg_memory_utilization = total_mem_util / @as(f32, @floatFromInt(active_count));
        }

        return stats;
    }

    const SystemStats = struct {
        total_gpus: u32,
        active_gpus: u32,
        total_vram: u64,
        available_vram: u64,
        avg_gpu_utilization: f32,
        avg_memory_utilization: f32,
        thermal_throttling_active: bool,
        context_switches: u64,
        workload_migrations: u64,
    };
};

comptime {
    if (!features.Features.multi_gpu) {
        @compileError("multi_gpu.zig should only be compiled when multi_gpu feature is enabled");
    }
}

test "GPU discovery and scoring" {
    var manager = try MultiGpuManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(manager.gpus.count() >= 2); // Should discover multiple GPUs

    // Test GPU scoring for different workloads
    const intel_gpu = manager.gpus.get(0).?; // Intel integrated
    const nvidia_gpu = manager.gpus.get(1).?; // NVIDIA discrete

    const intel_gaming_score = intel_gpu.getScore(.gaming);
    const nvidia_gaming_score = nvidia_gpu.getScore(.gaming);

    // NVIDIA should score higher for gaming
    try std.testing.expect(nvidia_gaming_score > intel_gaming_score);

    const intel_compositing_score = intel_gpu.getScore(.compositing);
    const nvidia_compositing_score = nvidia_gpu.getScore(.compositing);

    // Both should be suitable for compositing, but discrete might be overkill
    try std.testing.expect(intel_compositing_score > 0);
    try std.testing.expect(nvidia_compositing_score > 0);
}

test "workload assignment and migration" {
    var manager = try MultiGpuManager.init(std.testing.allocator);
    defer manager.deinit();

    // Assign a gaming workload
    const gpu_id = try manager.assignGpu(100, .gaming, 5, .performance);
    try std.testing.expect(gpu_id > 0); // Should not assign to integrated GPU for gaming

    // Test migration (would need to simulate load changes)
    const migrated_gpu = try manager.migrateWorkload(100);
    _ = migrated_gpu; // Migration might not be needed if system is balanced

    const stats = manager.getSystemStats();
    try std.testing.expect(stats.total_gpus >= 2);
    try std.testing.expect(stats.active_gpus >= 1);
}