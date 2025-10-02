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

pub const RemoteDesktopConfig = struct {
    listen_address: []const u8 = "127.0.0.1",
    listen_port: u16 = 5900,
    enable_encryption: bool = true,
    enable_compression: bool = true,
    use_tcp_nodelay: bool = true,
};