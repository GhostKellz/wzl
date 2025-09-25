//! Clipboard stub - minimal no-op implementation when clipboard feature is disabled

const std = @import("std");

pub const ClipboardManager = struct {
    pub fn init() ClipboardManager {
        return .{};
    }

    pub fn deinit(self: *ClipboardManager) void {
        _ = self;
    }
};

pub const ClipboardData = struct {};
pub const DataSource = struct {};
pub const MimeType = []const u8;