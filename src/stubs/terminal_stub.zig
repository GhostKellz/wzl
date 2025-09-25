//! Terminal stub - minimal no-op implementation when terminal integration is disabled

const std = @import("std");

pub const WaylandTerminal = struct {
    pub fn init() WaylandTerminal {
        return .{};
    }

    pub fn deinit(self: *WaylandTerminal) void {
        _ = self;
    }
};

pub const TerminalConfig = struct {};
pub const TerminalBuffer = struct {};
pub const Cell = struct {};
pub const Color = u32;
pub const Cursor = struct {};