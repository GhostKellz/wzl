//! Remote desktop stub - minimal no-op implementation when remote desktop is disabled

const std = @import("std");

pub const RemoteDesktopServer = struct {
    pub fn init() RemoteDesktopServer {
        return .{};
    }

    pub fn deinit(self: *RemoteDesktopServer) void {
        _ = self;
    }
};

pub const RemoteDesktopConfig = struct {};