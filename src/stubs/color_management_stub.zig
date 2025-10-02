const std = @import("std");
const protocol = @import("../protocol.zig");

// Stub implementation for color management when feature is disabled

pub const ColorSpace = enum { srgb };
pub const TransferFunction = enum { srgb };
pub const HDRMetadata = struct {};
pub const ColorProfile = struct {
    name: []const u8 = "sRGB",
    color_space: ColorSpace = .srgb,
    transfer_function: TransferFunction = .srgb,
};
pub const ColorTransform = struct {
    pub fn identity() @This() { return .{}; }
};

pub const ColorManager = struct {
    pub fn init(allocator: std.mem.Allocator) !@This() { _ = allocator; return .{}; }
    pub fn deinit(self: *@This()) void { _ = self; }
};