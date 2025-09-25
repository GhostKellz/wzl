//! QUIC stub - minimal no-op implementation when QUIC streaming is disabled

const std = @import("std");

pub const QuicServer = struct {
    pub fn init() QuicServer {
        return .{};
    }

    pub fn deinit(self: *QuicServer) void {
        _ = self;
    }
};

pub const QuicStream = struct {};
pub const FrameMetadata = struct {};
pub const FrameFlags = u8;