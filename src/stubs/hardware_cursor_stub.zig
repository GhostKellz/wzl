const std = @import("std");
const protocol = @import("../protocol.zig");

pub const CursorPlane = struct {
    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8) !CursorPlane {
        _ = allocator;
        _ = id;
        _ = name;
        return error.FeatureDisabled;
    }

    pub fn deinit(self: *CursorPlane) void {
        _ = self;
    }
};

pub const HardwareCursorManager = struct {
    pub fn init(allocator: std.mem.Allocator) !HardwareCursorManager {
        _ = allocator;
        return error.FeatureDisabled;
    }

    pub fn deinit(self: *HardwareCursorManager) void {
        _ = self;
    }

    pub fn setCursor(self: *HardwareCursorManager, surface_id: protocol.ObjectId, hotspot_x: i32, hotspot_y: i32, width: u32, height: u32, format: u32, buffer: []const u8) !bool {
        _ = self;
        _ = surface_id;
        _ = hotspot_x;
        _ = hotspot_y;
        _ = width;
        _ = height;
        _ = format;
        _ = buffer;
        return false;
    }
};

pub const CursorTheme = struct {
    pub fn init(allocator: std.mem.Allocator, name: []const u8) !CursorTheme {
        _ = allocator;
        _ = name;
        return error.FeatureDisabled;
    }

    pub fn deinit(self: *CursorTheme) void {
        _ = self;
    }
};