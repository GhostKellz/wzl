//! Compositor stub - minimal no-op implementation when compositor framework is disabled

const std = @import("std");

pub const CompositorFramework = struct {
    pub fn init(allocator: std.mem.Allocator, config: CompositorConfig) !CompositorFramework {
        _ = allocator;
        _ = config;
        return .{};
    }

    pub fn deinit(self: *CompositorFramework) void {
        _ = self;
    }

    pub fn run(self: *CompositorFramework) !void {
        _ = self;
    }

    pub fn detectArchLinuxFeatures(self: *CompositorFramework) !void {
        _ = self;
    }

    pub fn printStats(self: *CompositorFramework) void {
        _ = self;
    }

    pub fn optimizeForArch(self: *CompositorFramework) !void {
        _ = self;
    }
};

pub const CompositorConfig = struct {
    socket_name: []const u8 = "wayland-0",
    enable_xdg_shell: bool = true,
    enable_input: bool = true,
    enable_output: bool = true,
    max_clients: u32 = 16,
};