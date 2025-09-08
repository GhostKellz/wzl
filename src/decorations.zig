//! Window decorations and theming support for wzl
//! Provides client-side and server-side decorations with theming capabilities

const std = @import("std");
const protocol = @import("protocol.zig");
const buffer = @import("buffer.zig");

// Color definition for theming
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
    
    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = 255 };
    }
    
    pub fn fromRgba(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
    
    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.a) << 24) | (@as(u32, self.r) << 16) | 
               (@as(u32, self.g) << 8) | @as(u32, self.b);
    }
};

// Theme configuration
pub const Theme = struct {
    // Window chrome colors
    titlebar_bg: Color,
    titlebar_fg: Color,
    titlebar_active_bg: Color,
    titlebar_active_fg: Color,
    border_color: Color,
    border_active_color: Color,
    
    // Button colors
    button_bg: Color,
    button_fg: Color,
    button_hover_bg: Color,
    button_pressed_bg: Color,
    
    // Sizing
    titlebar_height: u32,
    border_width: u32,
    button_size: u32,
    corner_radius: u32,
    
    // Font settings
    font_name: []const u8,
    font_size: u32,
    
    pub fn defaultDark() Theme {
        return Theme{
            .titlebar_bg = Color.fromRgb(45, 45, 45),
            .titlebar_fg = Color.fromRgb(255, 255, 255),
            .titlebar_active_bg = Color.fromRgb(60, 60, 60),
            .titlebar_active_fg = Color.fromRgb(255, 255, 255),
            .border_color = Color.fromRgb(30, 30, 30),
            .border_active_color = Color.fromRgb(100, 100, 100),
            .button_bg = Color.fromRgb(70, 70, 70),
            .button_fg = Color.fromRgb(255, 255, 255),
            .button_hover_bg = Color.fromRgb(90, 90, 90),
            .button_pressed_bg = Color.fromRgb(50, 50, 50),
            .titlebar_height = 30,
            .border_width = 1,
            .button_size = 20,
            .corner_radius = 8,
            .font_name = "sans-serif",
            .font_size = 12,
        };
    }
    
    pub fn defaultLight() Theme {
        return Theme{
            .titlebar_bg = Color.fromRgb(240, 240, 240),
            .titlebar_fg = Color.fromRgb(50, 50, 50),
            .titlebar_active_bg = Color.fromRgb(255, 255, 255),
            .titlebar_active_fg = Color.fromRgb(30, 30, 30),
            .border_color = Color.fromRgb(180, 180, 180),
            .border_active_color = Color.fromRgb(120, 120, 120),
            .button_bg = Color.fromRgb(220, 220, 220),
            .button_fg = Color.fromRgb(60, 60, 60),
            .button_hover_bg = Color.fromRgb(200, 200, 200),
            .button_pressed_bg = Color.fromRgb(160, 160, 160),
            .titlebar_height = 30,
            .border_width = 1,
            .button_size = 20,
            .corner_radius = 8,
            .font_name = "sans-serif",
            .font_size = 12,
        };
    }
    
    pub fn archDark() Theme {
        return Theme{
            .titlebar_bg = Color.fromRgb(24, 32, 48),
            .titlebar_fg = Color.fromRgb(135, 206, 235),
            .titlebar_active_bg = Color.fromRgb(30, 40, 60),
            .titlebar_active_fg = Color.fromRgb(173, 216, 230),
            .border_color = Color.fromRgb(20, 25, 35),
            .border_active_color = Color.fromRgb(70, 130, 180),
            .button_bg = Color.fromRgb(40, 50, 70),
            .button_fg = Color.fromRgb(135, 206, 235),
            .button_hover_bg = Color.fromRgb(60, 70, 90),
            .button_pressed_bg = Color.fromRgb(30, 40, 55),
            .titlebar_height = 32,
            .border_width = 2,
            .button_size = 22,
            .corner_radius = 6,
            .font_name = "Fira Code",
            .font_size = 11,
        };
    }
};

// Decoration configuration
pub const DecorationConfig = struct {
    mode: DecorationMode,
    theme: Theme,
    show_title: bool = true,
    show_buttons: bool = true,
    show_icon: bool = false,
    resizable: bool = true,
    moveable: bool = true,
    
    pub const DecorationMode = enum {
        client_side,
        server_side,
        none,
    };
};

// Button types for window controls
pub const ButtonType = enum {
    minimize,
    maximize,
    close,
    menu,
};

// Button state for rendering
pub const ButtonState = enum {
    normal,
    hover,
    pressed,
    disabled,
};

// Window decoration manager
pub const DecorationManager = struct {
    allocator: std.mem.Allocator,
    config: DecorationConfig,
    surfaces: std.HashMap(protocol.ObjectId, *DecorationSurface),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: DecorationConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .surfaces = std.HashMap(protocol.ObjectId, *DecorationSurface).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.surfaces.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.surfaces.deinit();
    }
    
    pub fn createDecoration(self: *Self, surface_id: protocol.ObjectId, title: []const u8) !*DecorationSurface {
        const decoration = try self.allocator.create(DecorationSurface);
        decoration.* = try DecorationSurface.init(self.allocator, self.config, title);
        
        try self.surfaces.put(surface_id, decoration);
        return decoration;
    }
    
    pub fn destroyDecoration(self: *Self, surface_id: protocol.ObjectId) void {
        if (self.surfaces.fetchRemove(surface_id)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }
    
    pub fn getDecoration(self: *Self, surface_id: protocol.ObjectId) ?*DecorationSurface {
        return self.surfaces.get(surface_id);
    }
    
    pub fn setTheme(self: *Self, theme: Theme) void {
        self.config.theme = theme;
        
        // Update all existing decorations
        var iterator = self.surfaces.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.updateTheme(theme);
        }
    }
};

// Individual surface decoration
pub const DecorationSurface = struct {
    allocator: std.mem.Allocator,
    config: DecorationConfig,
    title: []u8,
    
    // Rendering state
    width: u32 = 0,
    height: u32 = 0,
    is_active: bool = false,
    is_maximized: bool = false,
    
    // Button states
    button_states: std.EnumArray(ButtonType, ButtonState),
    
    // Buffers for decoration rendering
    titlebar_buffer: ?buffer.Buffer = null,
    border_buffers: [4]?buffer.Buffer = [_]?buffer.Buffer{null} ** 4, // top, right, bottom, left
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: DecorationConfig, title: []const u8) !Self {
        const owned_title = try allocator.dupe(u8, title);
        
        return Self{
            .allocator = allocator,
            .config = config,
            .title = owned_title,
            .button_states = std.EnumArray(ButtonType, ButtonState).initFill(.normal),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.title);
        
        if (self.titlebar_buffer) |*buf| {
            buf.deinit();
        }
        
        for (&self.border_buffers) |*buf| {
            if (buf.*) |*b| {
                b.deinit();
            }
        }
    }
    
    pub fn setTitle(self: *Self, title: []const u8) !void {
        self.allocator.free(self.title);
        self.title = try self.allocator.dupe(u8, title);
        self.invalidateTitlebar();
    }
    
    pub fn setSize(self: *Self, width: u32, height: u32) !void {
        if (self.width != width or self.height != height) {
            self.width = width;
            self.height = height;
            try self.updateBuffers();
        }
    }
    
    pub fn setActive(self: *Self, active: bool) void {
        if (self.is_active != active) {
            self.is_active = active;
            self.invalidateTitlebar();
        }
    }
    
    pub fn setMaximized(self: *Self, maximized: bool) void {
        if (self.is_maximized != maximized) {
            self.is_maximized = maximized;
            self.invalidateTitlebar();
        }
    }
    
    pub fn updateButtonState(self: *Self, button: ButtonType, state: ButtonState) void {
        if (self.button_states.get(button) != state) {
            self.button_states.set(button, state);
            self.invalidateTitlebar();
        }
    }
    
    pub fn updateTheme(self: *Self, theme: Theme) void {
        self.config.theme = theme;
        self.invalidateTitlebar();
        self.invalidateBorders();
    }
    
    fn invalidateTitlebar(self: *Self) void {
        if (self.titlebar_buffer) |*buf| {
            buf.deinit();
            self.titlebar_buffer = null;
        }
    }
    
    fn invalidateBorders(self: *Self) void {
        for (&self.border_buffers) |*buf| {
            if (buf.*) |*b| {
                b.deinit();
                buf.* = null;
            }
        }
    }
    
    fn updateBuffers(self: *Self) !void {
        if (self.width == 0 or self.height == 0) return;
        
        // Recreate titlebar buffer
        self.invalidateTitlebar();
        if (self.config.show_title) {
            try self.createTitlebarBuffer();
        }
        
        // Recreate border buffers
        self.invalidateBorders();
        if (self.config.theme.border_width > 0) {
            try self.createBorderBuffers();
        }
    }
    
    fn createTitlebarBuffer(self: *Self) !void {
        const theme = &self.config.theme;
        const titlebar_width = self.width;
        const titlebar_height = theme.titlebar_height;
        
        // Create buffer
        const buffer_size = titlebar_width * titlebar_height * 4; // RGBA
        self.titlebar_buffer = try buffer.Buffer.init(
            self.allocator,
            buffer_size,
            titlebar_width,
            titlebar_height,
            buffer.ShmFormat.argb8888
        );
        
        // Render titlebar
        try self.renderTitlebar();
    }
    
    fn createBorderBuffers(self: *Self) !void {
        const theme = &self.config.theme;
        const border_width = theme.border_width;
        
        if (border_width == 0) return;
        
        // Top border
        const top_size = self.width * border_width * 4;
        self.border_buffers[0] = try buffer.Buffer.init(
            self.allocator,
            top_size,
            self.width,
            border_width,
            buffer.ShmFormat.argb8888
        );
        
        // Right border  
        const right_size = border_width * self.height * 4;
        self.border_buffers[1] = try buffer.Buffer.init(
            self.allocator,
            right_size,
            border_width,
            self.height,
            buffer.ShmFormat.argb8888
        );
        
        // Bottom border
        const bottom_size = self.width * border_width * 4;
        self.border_buffers[2] = try buffer.Buffer.init(
            self.allocator,
            bottom_size,
            self.width,
            border_width,
            buffer.ShmFormat.argb8888
        );
        
        // Left border
        const left_size = border_width * self.height * 4;
        self.border_buffers[3] = try buffer.Buffer.init(
            self.allocator,
            left_size,
            border_width,
            self.height,
            buffer.ShmFormat.argb8888
        );
        
        // Render borders
        try self.renderBorders();
    }
    
    fn renderTitlebar(self: *Self) !void {
        if (self.titlebar_buffer == null) return;
        
        const theme = &self.config.theme;
        const buf = &self.titlebar_buffer.?;
        const pixels = @as([*]u32, @ptrCast(@alignCast(buf.data.ptr)))[0..buf.width * buf.height];
        
        // Background color
        const bg_color = if (self.is_active) theme.titlebar_active_bg else theme.titlebar_bg;
        const bg_pixel = bg_color.toU32();
        
        // Fill background
        for (pixels) |*pixel| {
            pixel.* = bg_pixel;
        }
        
        // Render title text (simplified - in practice would use font rendering)
        if (self.config.show_title and self.title.len > 0) {
            try self.renderTitleText(pixels, buf.width, buf.height);
        }
        
        // Render window buttons
        if (self.config.show_buttons) {
            try self.renderButtons(pixels, buf.width, buf.height);
        }
    }
    
    fn renderTitleText(self: *Self, pixels: []u32, width: u32, height: u32) !void {
        // Simplified text rendering - in practice would use proper font rendering
        const theme = &self.config.theme;
        const fg_color = if (self.is_active) theme.titlebar_active_fg else theme.titlebar_fg;
        const fg_pixel = fg_color.toU32();
        
        const text_start_x = theme.button_size + 10; // Leave space for buttons
        const text_y = height / 2;
        
        // Simple character rendering (just for demonstration)
        const chars_to_render = @min(self.title.len, (width - text_start_x) / 8);
        for (0..chars_to_render) |i| {
            const char_x = text_start_x + i * 8;
            if (char_x + 8 >= width) break;
            
            // Simple 8x8 character block
            for (0..8) |dy| {
                for (0..6) |dx| {
                    const pixel_y = text_y - 4 + dy;
                    const pixel_x = char_x + dx;
                    if (pixel_y < height and pixel_x < width) {
                        const pixel_index = pixel_y * width + pixel_x;
                        pixels[pixel_index] = fg_pixel;
                    }
                }
            }
        }
    }
    
    fn renderButtons(self: *Self, pixels: []u32, width: u32, height: u32) !void {
        const theme = &self.config.theme;
        const button_size = theme.button_size;
        const button_y = (height - button_size) / 2;
        
        // Close button (red)
        const close_x = width - button_size - 5;
        try self.renderButton(pixels, width, height, close_x, button_y, 
                             ButtonType.close, Color.fromRgb(255, 100, 100));
        
        // Maximize button (green)
        const maximize_x = close_x - button_size - 5;
        try self.renderButton(pixels, width, height, maximize_x, button_y,
                             ButtonType.maximize, Color.fromRgb(100, 255, 100));
        
        // Minimize button (yellow)
        const minimize_x = maximize_x - button_size - 5;
        try self.renderButton(pixels, width, height, minimize_x, button_y,
                             ButtonType.minimize, Color.fromRgb(255, 255, 100));
    }
    
    fn renderButton(self: *Self, pixels: []u32, width: u32, height: u32, 
                   x: u32, y: u32, button_type: ButtonType, color: Color) !void {
        const theme = &self.config.theme;
        const button_size = theme.button_size;
        const state = self.button_states.get(button_type);
        
        // Adjust color based on state
        var final_color = color;
        switch (state) {
            .hover => {
                final_color.r = @min(255, final_color.r + 30);
                final_color.g = @min(255, final_color.g + 30);
                final_color.b = @min(255, final_color.b + 30);
            },
            .pressed => {
                final_color.r = @max(0, final_color.r - 30);
                final_color.g = @max(0, final_color.g - 30);
                final_color.b = @max(0, final_color.b - 30);
            },
            .disabled => {
                final_color.a = 128;
            },
            .normal => {},
        }
        
        const pixel_value = final_color.toU32();
        
        // Render circular button
        const center_x = x + button_size / 2;
        const center_y = y + button_size / 2;
        const radius = button_size / 2 - 2;
        
        for (y..y + button_size) |py| {
            for (x..x + button_size) |px| {
                if (px >= width or py >= height) continue;
                
                const dx = @as(i32, @intCast(px)) - @as(i32, @intCast(center_x));
                const dy = @as(i32, @intCast(py)) - @as(i32, @intCast(center_y));
                const distance_sq = dx * dx + dy * dy;
                const radius_sq = @as(i32, @intCast(radius)) * @as(i32, @intCast(radius));
                
                if (distance_sq <= radius_sq) {
                    const pixel_index = py * width + px;
                    pixels[pixel_index] = pixel_value;
                }
            }
        }
    }
    
    fn renderBorders(self: *Self) !void {
        const theme = &self.config.theme;
        const border_color = if (self.is_active) theme.border_active_color else theme.border_color;
        const border_pixel = border_color.toU32();
        
        // Render each border
        for (0..4) |i| {
            if (self.border_buffers[i]) |buf| {
                const pixels = @as([*]u32, @ptrCast(@alignCast(buf.data.ptr)))[0..buf.width * buf.height];
                for (pixels) |*pixel| {
                    pixel.* = border_pixel;
                }
            }
        }
    }
    
    // Hit testing for interactive elements
    pub fn hitTest(self: *Self, x: i32, y: i32) ?ButtonType {
        if (!self.config.show_buttons) return null;
        if (y < 0 or y >= self.config.theme.titlebar_height) return null;
        
        const theme = &self.config.theme;
        const button_size = theme.button_size;
        const button_y = (theme.titlebar_height - button_size) / 2;
        
        if (y < button_y or y >= button_y + button_size) return null;
        
        // Check close button
        const close_x = @as(i32, @intCast(self.width)) - @as(i32, @intCast(button_size)) - 5;
        if (x >= close_x and x < close_x + button_size) {
            return .close;
        }
        
        // Check maximize button
        const maximize_x = close_x - @as(i32, @intCast(button_size)) - 5;
        if (x >= maximize_x and x < maximize_x + button_size) {
            return .maximize;
        }
        
        // Check minimize button
        const minimize_x = maximize_x - @as(i32, @intCast(button_size)) - 5;
        if (x >= minimize_x and x < minimize_x + button_size) {
            return .minimize;
        }
        
        return null;
    }
    
    pub fn getTitlebarGeometry(self: *Self) struct { width: u32, height: u32 } {
        return .{ 
            .width = self.width, 
            .height = self.config.theme.titlebar_height 
        };
    }
    
    pub fn getBorderGeometry(self: *Self) struct { width: u32, top: u32, right: u32, bottom: u32, left: u32 } {
        const border_width = self.config.theme.border_width;
        return .{
            .width = border_width,
            .top = border_width,
            .right = border_width,
            .bottom = border_width,
            .left = border_width,
        };
    }
};

// Theme loader for various theme formats
pub const ThemeLoader = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ThemeLoader {
        return ThemeLoader{ .allocator = allocator };
    }
    
    // Load theme from JSON configuration
    pub fn loadFromJson(self: *ThemeLoader, json_content: []const u8) !Theme {
        _ = self;
        _ = json_content;
        // Simplified - in practice would parse JSON and create theme
        return Theme.defaultDark();
    }
    
    // Load theme from GTK CSS
    pub fn loadFromGtkCss(self: *ThemeLoader, css_content: []const u8) !Theme {
        _ = self;
        _ = css_content;
        // Simplified - in practice would parse GTK CSS
        return Theme.defaultLight();
    }
    
    // Detect system theme preference
    pub fn detectSystemTheme(self: *ThemeLoader) Theme {
        _ = self;
        
        // Check environment variables and system settings
        if (std.posix.getenv("PREFER_DARK_THEME")) |value| {
            if (std.mem.eql(u8, value, "1")) {
                return Theme.defaultDark();
            }
        }
        
        // Check for Arch Linux and use custom theme
        const os_release = std.fs.openFileAbsolute("/etc/os-release", .{}) catch null;
        if (os_release) |file| {
            defer file.close();
            var file_buffer: [1024]u8 = undefined;
            const bytes_read = file.readAll(&file_buffer) catch 0;
            const content = file_buffer[0..bytes_read];
            
            if (std.mem.indexOf(u8, content, "Arch Linux")) |_| {
                return Theme.archDark();
            }
        }
        
        return Theme.defaultLight();
    }
};