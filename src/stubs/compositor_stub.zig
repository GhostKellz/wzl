//! Compositor stub - minimal no-op implementation when compositor framework is disabled

const std = @import("std");

pub const CompositorFramework = struct {
    pub fn init() CompositorFramework {
        return .{};
    }

    pub fn deinit(self: *CompositorFramework) void {
        _ = self;
    }
};

pub const CompositorConfig = struct {};