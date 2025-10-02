const std = @import("std");
const protocol = @import("protocol.zig");
const features = @import("features.zig");
const thread_safety = @import("thread_safety.zig");
const errors = @import("errors.zig");

/// Hardware cursor planes and management
pub const CursorPlane = struct {
    id: u32,
    name: []const u8,
    width_max: u32,
    height_max: u32,
    formats: std.ArrayList(u32),
    in_use: bool,
    current_surface: ?protocol.ObjectId,

    // Hardware properties
    supports_alpha: bool,
    supports_scaling: bool,
    supports_rotation: bool,
    min_scale: f32,
    max_scale: f32,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8) !CursorPlane {
        return CursorPlane{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .width_max = 64,
            .height_max = 64,
            .formats = std.ArrayList(u32){},
            .in_use = false,
            .current_surface = null,
            .supports_alpha = true,
            .supports_scaling = false,
            .supports_rotation = false,
            .min_scale = 1.0,
            .max_scale = 1.0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CursorPlane) void {
        self.allocator.free(self.name);
        self.formats.deinit(self.allocator);
    }

    pub fn addFormat(self: *CursorPlane, format: u32) !void {
        try self.formats.append(self.allocator, format);
    }

    pub fn supportsFormat(self: *CursorPlane, format: u32) bool {
        for (self.formats.items) |f| {
            if (f == format) return true;
        }
        return false;
    }

    pub fn canDisplay(self: *CursorPlane, width: u32, height: u32, format: u32) bool {
        return width <= self.width_max and
               height <= self.height_max and
               self.supportsFormat(format) and
               !self.in_use;
    }
};

/// Hardware cursor manager
pub const HardwareCursorManager = struct {
    allocator: std.mem.Allocator,
    planes: thread_safety.Registry(CursorPlane),
    active_cursors: std.AutoHashMap(protocol.ObjectId, ActiveCursor),
    fallback_enabled: bool,

    // Performance tracking
    hardware_cursor_count: std.atomic.Value(u32),
    software_fallback_count: std.atomic.Value(u32),

    const ActiveCursor = struct {
        plane_id: u32,
        surface_id: protocol.ObjectId,
        hotspot_x: i32,
        hotspot_y: i32,
        width: u32,
        height: u32,
        format: u32,
        buffer: ?[]u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *ActiveCursor) void {
            if (self.buffer) |buf| {
                self.allocator.free(buf);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) !HardwareCursorManager {
        var manager = HardwareCursorManager{
            .allocator = allocator,
            .planes = thread_safety.Registry(CursorPlane).init(allocator),
            .active_cursors = std.AutoHashMap(protocol.ObjectId, ActiveCursor).init(allocator),
            .fallback_enabled = true,
            .hardware_cursor_count = std.atomic.Value(u32).init(0),
            .software_fallback_count = std.atomic.Value(u32).init(0),
        };

        // Detect and initialize hardware cursor planes
        try manager.detectHardwarePlanes();

        return manager;
    }

    pub fn deinit(self: *HardwareCursorManager) void {
        var iter = self.active_cursors.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.active_cursors.deinit(self.allocator);
        self.planes.deinit(self.allocator);
    }

    fn detectHardwarePlanes(self: *HardwareCursorManager) !void {
        // In a real implementation, this would query DRM/KMS
        // For now, create typical hardware cursor planes

        // Primary cursor plane (most hardware)
        var primary_plane = try CursorPlane.init(self.allocator, 0, "primary-cursor");
        try primary_plane.addFormat(0x34325241); // ARGB8888
        try primary_plane.addFormat(0x34324258); // XRGB8888
        primary_plane.width_max = 64;
        primary_plane.height_max = 64;
        primary_plane.supports_alpha = true;
        _ = try self.planes.add(&primary_plane);

        // Secondary cursor plane (newer hardware)
        var secondary_plane = try CursorPlane.init(self.allocator, 1, "secondary-cursor");
        try secondary_plane.addFormat(0x34325241); // ARGB8888
        try secondary_plane.addFormat(0x34324258); // XRGB8888
        secondary_plane.width_max = 128;
        secondary_plane.height_max = 128;
        secondary_plane.supports_alpha = true;
        secondary_plane.supports_scaling = true;
        secondary_plane.min_scale = 0.5;
        secondary_plane.max_scale = 2.0;
        _ = try self.planes.add(&secondary_plane);

        // High-resolution cursor plane (high-end hardware)
        var hires_plane = try CursorPlane.init(self.allocator, 2, "hires-cursor");
        try hires_plane.addFormat(0x34325241); // ARGB8888
        try hires_plane.addFormat(0x34324258); // XRGB8888
        try hires_plane.addFormat(0x36314752); // RG16 (for high-DPI)
        hires_plane.width_max = 256;
        hires_plane.height_max = 256;
        hires_plane.supports_alpha = true;
        hires_plane.supports_scaling = true;
        hires_plane.supports_rotation = true;
        hires_plane.min_scale = 0.25;
        hires_plane.max_scale = 4.0;
        _ = try self.planes.add(&hires_plane);
    }

    pub fn setCursor(
        self: *HardwareCursorManager,
        surface_id: protocol.ObjectId,
        hotspot_x: i32,
        hotspot_y: i32,
        width: u32,
        height: u32,
        format: u32,
        buffer: []const u8,
    ) !bool {
        // Try to find suitable hardware plane
        const plane_id = self.findSuitablePlane(width, height, format) orelse {
            if (self.fallback_enabled) {
                _ = self.software_fallback_count.fetchAdd(1, .seq_cst);
                return false; // Fallback to software cursor
            } else {
                return error.NoSuitableHardwarePlane;
            }
        };

        // Remove existing cursor if any
        if (self.active_cursors.get(surface_id)) |*existing| {
            existing.deinit();
            _ = self.active_cursors.remove(surface_id);

            // Free the plane
            if (self.planes.get(@intCast(existing.plane_id))) |plane| {
                plane.in_use = false;
                plane.current_surface = null;
            }
        }

        // Copy buffer data
        const buffer_copy = try self.allocator.alloc(u8, buffer.len);
        @memcpy(buffer_copy, buffer);

        // Create active cursor
        const active_cursor = ActiveCursor{
            .plane_id = plane_id,
            .surface_id = surface_id,
            .hotspot_x = hotspot_x,
            .hotspot_y = hotspot_y,
            .width = width,
            .height = height,
            .format = format,
            .buffer = buffer_copy,
            .allocator = self.allocator,
        };

        try self.active_cursors.put(surface_id, active_cursor);

        // Mark plane as in use
        if (self.planes.get(@intCast(plane_id))) |plane| {
            plane.in_use = true;
            plane.current_surface = surface_id;
        }

        // Configure hardware plane (in real implementation, this would call DRM/KMS)
        try self.configureHardwarePlane(plane_id, &active_cursor);

        _ = self.hardware_cursor_count.fetchAdd(1, .seq_cst);
        return true;
    }

    fn findSuitablePlane(self: *HardwareCursorManager, width: u32, height: u32, format: u32) ?u32 {
        // Find best matching available plane
        var best_plane: ?u32 = null;
        var best_score: u32 = 0;

        var iter = self.planes.objects.iterator();
        while (iter.next()) |entry| {
            const plane = entry.value_ptr.*;

            if (plane.canDisplay(width, height, format)) {
                var score: u32 = 0;

                // Prefer exact size match
                if (plane.width_max == width and plane.height_max == height) score += 100;

                // Prefer smaller planes for smaller cursors (efficiency)
                if (width <= 64 and height <= 64 and plane.width_max <= 64) score += 50;

                // Prefer planes with more features for larger cursors
                if (width > 64 or height > 64) {
                    if (plane.supports_scaling) score += 30;
                    if (plane.supports_rotation) score += 20;
                }

                // Prefer alpha support
                if (plane.supports_alpha) score += 10;

                if (score > best_score) {
                    best_score = score;
                    best_plane = plane.id;
                }
            }
        }

        return best_plane;
    }

    fn configureHardwarePlane(self: *HardwareCursorManager, plane_id: u32, cursor: *const ActiveCursor) !void {
        _ = self;
        _ = plane_id;
        _ = cursor;

        // In a real implementation, this would:
        // 1. Map the buffer to GPU memory
        // 2. Configure DRM plane properties
        // 3. Set cursor position and hotspot
        // 4. Enable the hardware cursor plane

        // Example DRM calls (pseudocode):
        // drmModeSetCursor2(drm_fd, crtc_id, buffer_handle, width, height);
        // drmModeMoveCursor(drm_fd, crtc_id, x, y);
    }

    pub fn hideCursor(self: *HardwareCursorManager, surface_id: protocol.ObjectId) !void {
        if (self.active_cursors.get(surface_id)) |*cursor| {
            // Disable hardware plane
            try self.disableHardwarePlane(cursor.plane_id);

            // Free resources
            cursor.deinit();
            _ = self.active_cursors.remove(surface_id);

            // Free the plane
            if (self.planes.get(@intCast(cursor.plane_id))) |plane| {
                plane.in_use = false;
                plane.current_surface = null;
            }
        }
    }

    fn disableHardwarePlane(self: *HardwareCursorManager, plane_id: u32) !void {
        _ = self;
        _ = plane_id;

        // In real implementation: drmModeSetCursor2(drm_fd, crtc_id, 0, 0, 0);
    }

    pub fn moveCursor(self: *HardwareCursorManager, surface_id: protocol.ObjectId, x: i32, y: i32) !void {
        if (self.active_cursors.get(surface_id)) |cursor| {
            // Move hardware cursor (in real implementation: drmModeMoveCursor)
            try self.moveHardwareCursor(cursor.plane_id, x - cursor.hotspot_x, y - cursor.hotspot_y);
        }
    }

    fn moveHardwareCursor(self: *HardwareCursorManager, plane_id: u32, x: i32, y: i32) !void {
        _ = self;
        _ = plane_id;
        _ = x;
        _ = y;

        // In real implementation: drmModeMoveCursor(drm_fd, crtc_id, x, y);
    }

    pub fn getCapabilities(self: *HardwareCursorManager) CursorCapabilities {
        var caps = CursorCapabilities{
            .max_width = 0,
            .max_height = 0,
            .plane_count = 0,
            .supports_alpha = false,
            .supports_scaling = false,
            .supports_rotation = false,
            .supported_formats = std.ArrayList(u32).init(self.allocator),
        };

        var iter = self.planes.objects.iterator();
        while (iter.next()) |entry| {
            const plane = entry.value_ptr.*;
            caps.plane_count += 1;
            caps.max_width = @max(caps.max_width, plane.width_max);
            caps.max_height = @max(caps.max_height, plane.height_max);
            caps.supports_alpha = caps.supports_alpha or plane.supports_alpha;
            caps.supports_scaling = caps.supports_scaling or plane.supports_scaling;
            caps.supports_rotation = caps.supports_rotation or plane.supports_rotation;

            // Add unique formats
            for (plane.formats.items) |format| {
                var found = false;
                for (caps.supported_formats.items) |existing| {
                    if (existing == format) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    caps.supported_formats.append(self.allocator, format) catch {};
                }
            }
        }

        return caps;
    }

    pub const CursorCapabilities = struct {
        max_width: u32,
        max_height: u32,
        plane_count: u32,
        supports_alpha: bool,
        supports_scaling: bool,
        supports_rotation: bool,
        supported_formats: std.ArrayList(u32),

        pub fn deinit(self: *CursorCapabilities) void {
            self.supported_formats.deinit(self.allocator);
        }

        pub fn format(
            self: CursorCapabilities,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            try writer.print(
                \\Hardware Cursor Capabilities:
                \\  Max Size: {}x{}
                \\  Planes: {}
                \\  Alpha Support: {}
                \\  Scaling Support: {}
                \\  Rotation Support: {}
                \\  Formats: {}
            , .{
                self.max_width,
                self.max_height,
                self.plane_count,
                self.supports_alpha,
                self.supports_scaling,
                self.supports_rotation,
                self.supported_formats.items.len,
            });
        }
    };

    pub fn getStats(self: *HardwareCursorManager) Stats {
        return Stats{
            .hardware_cursors_active = self.active_cursors.count(),
            .hardware_cursor_total = self.hardware_cursor_count.load(.seq_cst),
            .software_fallback_total = self.software_fallback_count.load(.seq_cst),
            .planes_available = self.planes.count(),
            .planes_in_use = blk: {
                var in_use: u32 = 0;
                var iter = self.planes.objects.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.*.in_use) in_use += 1;
                }
                break :blk in_use;
            },
        };
    }

    pub const Stats = struct {
        hardware_cursors_active: u32,
        hardware_cursor_total: u32,
        software_fallback_total: u32,
        planes_available: u32,
        planes_in_use: u32,

        pub fn getHardwareUtilization(self: Stats) f32 {
            if (self.hardware_cursor_total + self.software_fallback_total == 0) return 0.0;
            return @as(f32, @floatFromInt(self.hardware_cursor_total)) /
                   @as(f32, @floatFromInt(self.hardware_cursor_total + self.software_fallback_total));
        }
    };
};

/// Cursor theme and animation support
pub const CursorTheme = struct {
    name: []const u8,
    cursors: std.StringHashMap(CursorImage),
    allocator: std.mem.Allocator,

    pub const CursorImage = struct {
        width: u32,
        height: u32,
        hotspot_x: u32,
        hotspot_y: u32,
        format: u32,
        frames: std.ArrayList(Frame),

        pub const Frame = struct {
            buffer: []u8,
            duration_ms: u32,
        };
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !CursorTheme {
        return CursorTheme{
            .name = try allocator.dupe(u8, name),
            .cursors = std.StringHashMap(CursorImage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CursorTheme) void {
        var iter = self.cursors.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.frames.items) |frame| {
                self.allocator.free(frame.buffer);
            }
            entry.value_ptr.frames.deinit(self.allocator);
        }
        self.cursors.deinit(self.allocator);
        self.allocator.free(self.name);
    }

    pub fn loadFromDirectory(allocator: std.mem.Allocator, path: []const u8) !CursorTheme {
        // Implementation would load cursor theme from filesystem
        // For now, create a basic default theme
        var theme = try CursorTheme.init(allocator, "default");

        // Add standard cursor shapes with placeholder data
        const standard_cursors = [_][]const u8{
            "default", "pointer", "hand", "text", "crosshair",
            "wait", "help", "move", "resize", "not-allowed"
        };

        for (standard_cursors) |name| {
            var cursor_image = CursorImage{
                .width = 24,
                .height = 24,
                .hotspot_x = 12,
                .hotspot_y = 12,
                .format = 0x34325241, // ARGB8888
                .frames = std.ArrayList(CursorImage.Frame){},
            };

            // Create placeholder frame
            const buffer_size = cursor_image.width * cursor_image.height * 4;
            const buffer = try allocator.alloc(u8, buffer_size);
            @memset(buffer, 0xFF); // White cursor for now

            try cursor_image.frames.append(allocator, .{
                .buffer = buffer,
                .duration_ms = 0, // Static cursor
            });

            try theme.cursors.put(name, cursor_image);
        }

        _ = path; // TODO: Actually load from path
        return theme;
    }
};

comptime {
    if (!features.Features.hardware_cursor) {
        @compileError("hardware_cursor.zig should only be compiled when hardware_cursor feature is enabled");
    }
}

test "hardware cursor plane detection" {
    var manager = try HardwareCursorManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(manager.planes.count() >= 1);

    const caps = manager.getCapabilities();
    defer caps.supported_formats.deinit(std.testing.allocator);

    try std.testing.expect(caps.max_width >= 64);
    try std.testing.expect(caps.max_height >= 64);
    try std.testing.expect(caps.plane_count >= 1);
}

test "cursor theme loading" {
    var theme = try CursorTheme.loadFromDirectory(std.testing.allocator, "/usr/share/icons/default");
    defer theme.deinit();

    try std.testing.expect(theme.cursors.count() > 0);
    try std.testing.expect(theme.cursors.contains("default"));
}