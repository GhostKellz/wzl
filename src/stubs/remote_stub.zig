//! Remote stub - minimal no-op implementation when remote desktop is disabled

const std = @import("std");

pub const RemoteServer = struct {
    pub fn init(allocator: std.mem.Allocator, config: anytype) !RemoteServer {
        _ = allocator;
        _ = config;
        return .{};
    }

    pub fn deinit(self: *RemoteServer) void {
        _ = self;
    }

    pub fn optimizeForArch(self: *RemoteServer) !void {
        _ = self;
    }
};

pub const RemoteClient = struct {
    pub fn init() RemoteClient {
        return .{};
    }

    pub fn deinit(self: *RemoteClient) void {
        _ = self;
    }
};