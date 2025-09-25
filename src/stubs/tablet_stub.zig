//! Tablet stub - minimal no-op implementation when tablet input is disabled

const std = @import("std");

// Stub implementation for when tablet input is disabled
pub const TabletManager = struct {
    pub fn init() TabletManager {
        return .{};
    }

    pub fn deinit(self: *TabletManager) void {
        _ = self;
    }
};

pub const TabletDevice = struct {};
pub const TabletTool = struct {};
pub const ToolType = enum { pen, eraser, brush };