const std = @import("std");
const protocol = @import("protocol.zig");
const xdg_shell = @import("xdg_shell.zig");
const input = @import("input.zig");
const buffer = @import("buffer.zig");
const output = @import("output.zig");
const client = @import("client.zig");

// Terminal emulation utilities for Ghostty and other terminal emulators
// Optimized for Wayland on Arch Linux x64

pub const TerminalConfig = struct {
    title: []const u8 = "wzl Terminal",
    app_id: []const u8 = "wzl.terminal",
    initial_width: i32 = 800,
    initial_height: i32 = 600,
    cell_width: u8 = 8,   // Character cell width in pixels
    cell_height: u8 = 16, // Character cell height in pixels
    font_size: u8 = 12,
    enable_transparency: bool = false,
    opacity: f32 = 1.0,
    enable_blur: bool = false,
    
    // Wayland-specific options
    enable_csd: bool = true,  // Client-side decorations
    enable_fractional_scaling: bool = true,
    preferred_scale: i32 = 1,
    
    // Performance options (Arch Linux optimized)
    double_buffering: bool = true,
    vsync: bool = true,
    hardware_cursor: bool = true,
    
    // Remote capabilities
    allow_remote_control: bool = false,
    enable_clipboard_sync: bool = true,
    enable_selection_sync: bool = true,
};

pub const CellAttributes = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    blink: bool = false,
    reverse: bool = false,
    invisible: bool = false,
    _padding: u1 = 0,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
    
    pub const BLACK = Color{ .r = 0, .g = 0, .b = 0 };
    pub const WHITE = Color{ .r = 255, .g = 255, .b = 255 };
    pub const RED = Color{ .r = 255, .g = 0, .b = 0 };
    pub const GREEN = Color{ .r = 0, .g = 255, .b = 0 };
    pub const BLUE = Color{ .r = 0, .g = 0, .b = 255 };
    pub const TRANSPARENT = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    
    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.a) << 24) | (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | self.b;
    }
};

pub const Cell = struct {
    codepoint: u21 = ' ',
    fg_color: Color = Color.WHITE,
    bg_color: Color = Color.BLACK,
    attributes: CellAttributes = .{},
};

pub const CursorStyle = enum {
    block,
    underline,
    bar,
};

pub const Cursor = struct {
    row: u16 = 0,
    col: u16 = 0,
    style: CursorStyle = .block,
    visible: bool = true,
    blink: bool = true,
    color: Color = Color.WHITE,
};

pub const TerminalBuffer = struct {
    cells: [][]Cell,
    rows: u16,
    cols: u16,
    cursor: Cursor,
    scrollback: std.ArrayList([]Cell),
    scrollback_limit: u32 = 10000,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Self {
        const cells = try allocator.alloc([]Cell, rows);
        for (cells) |*row| {
            row.* = try allocator.alloc(Cell, cols);
            @memset(row.*, Cell{});
        }
        
        return Self{
            .cells = cells,
            .rows = rows,
            .cols = cols,
            .cursor = Cursor{},
            .scrollback = std.ArrayList([]Cell).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.cells) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.cells);
        
        for (self.scrollback.items) |row| {
            self.allocator.free(row);
        }
        self.scrollback.deinit();
    }
    
    pub fn resize(self: *Self, new_rows: u16, new_cols: u16) !void {
        // Create new buffer
        const new_cells = try self.allocator.alloc([]Cell, new_rows);
        for (new_cells) |*row| {
            row.* = try self.allocator.alloc(Cell, new_cols);
            @memset(row.*, Cell{});
        }
        
        // Copy existing content
        const copy_rows = @min(self.rows, new_rows);
        const copy_cols = @min(self.cols, new_cols);
        
        for (0..copy_rows) |r| {
            @memcpy(new_cells[r][0..copy_cols], self.cells[r][0..copy_cols]);
        }
        
        // Clean up old buffer
        for (self.cells) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.cells);
        
        self.cells = new_cells;
        self.rows = new_rows;
        self.cols = new_cols;
        
        // Adjust cursor position
        if (self.cursor.row >= new_rows) self.cursor.row = new_rows - 1;
        if (self.cursor.col >= new_cols) self.cursor.col = new_cols - 1;
    }
    
    pub fn putChar(self: *Self, codepoint: u21, fg: Color, bg: Color, attrs: CellAttributes) void {
        if (self.cursor.row >= self.rows or self.cursor.col >= self.cols) return;
        
        self.cells[self.cursor.row][self.cursor.col] = Cell{
            .codepoint = codepoint,
            .fg_color = fg,
            .bg_color = bg,
            .attributes = attrs,
        };
        
        self.cursor.col += 1;
        if (self.cursor.col >= self.cols) {
            self.cursor.col = 0;
            self.cursor.row += 1;
            if (self.cursor.row >= self.rows) {
                self.scrollUp(1);
            }
        }
    }
    
    pub fn scrollUp(self: *Self, lines: u16) void {
        if (lines >= self.rows) {
            // Clear entire buffer
            for (self.cells) |row| {
                @memset(row, Cell{});
            }
            self.cursor.row = 0;
            self.cursor.col = 0;
            return;
        }
        
        // Move lines to scrollback
        for (0..lines) |_| {
            const old_row = self.cells[0];
            if (self.scrollback.items.len >= self.scrollback_limit) {
                self.allocator.free(self.scrollback.orderedRemove(0));
            }
            self.scrollback.append(old_row) catch {
                self.allocator.free(old_row);
            };
            
            // Shift remaining rows up
            for (1..self.rows) |i| {
                self.cells[i - 1] = self.cells[i];
            }
            
            // Create new bottom row
            self.cells[self.rows - 1] = self.allocator.alloc(Cell, self.cols) catch {
                // Fallback to reusing memory
                @memset(old_row, Cell{});
                self.cells[self.rows - 1] = old_row;
                continue;
            };
            @memset(self.cells[self.rows - 1], Cell{});
        }
        
        if (self.cursor.row >= lines) {
            self.cursor.row -= lines;
        } else {
            self.cursor.row = 0;
        }
    }
    
    pub fn clear(self: *Self) void {
        for (self.cells) |row| {
            @memset(row, Cell{});
        }
        self.cursor.row = 0;
        self.cursor.col = 0;
    }
    
    pub fn setCursor(self: *Self, row: u16, col: u16) void {
        self.cursor.row = @min(row, self.rows - 1);
        self.cursor.col = @min(col, self.cols - 1);
    }
};

pub const WaylandTerminal = struct {
    config: TerminalConfig,
    client: *client.Client,
    compositor_id: protocol.ObjectId,
    surface_id: protocol.ObjectId,
    xdg_surface_id: protocol.ObjectId,
    toplevel_id: protocol.ObjectId,
    shm_id: ?protocol.ObjectId = null,
    pool_id: ?protocol.ObjectId = null,
    buffer_id: ?protocol.ObjectId = null,
    
    // Terminal state
    terminal_buffer: TerminalBuffer,
    framebuffer: []u8,
    framebuffer_fd: std.fs.File.Handle,
    width: i32,
    height: i32,
    scale: i32 = 1,
    
    // Input state
    keyboard_focused: bool = false,
    pointer_focused: bool = false,
    
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, wzl_client: *client.Client, config: TerminalConfig) !Self {
        // Calculate terminal dimensions
        const term_cols: u16 = @intCast(@divFloor(config.initial_width, config.cell_width));
        const term_rows: u16 = @intCast(@divFloor(config.initial_height, config.cell_height));
        
        const terminal_buffer = try TerminalBuffer.init(allocator, term_rows, term_cols);
        
        // Create framebuffer
        const stride = config.initial_width * 4; // ARGB8888
        _ = stride; // For future use in manual buffer operations
        
        const fb_result = try buffer.createMemoryMappedBuffer(
            allocator,
            config.initial_width,
            config.initial_height,
            buffer.ShmFormat.argb8888,
        );
        
        return Self{
            .config = config,
            .client = wzl_client,
            .compositor_id = 0, // Will be set during setup
            .surface_id = 0,
            .xdg_surface_id = 0,
            .toplevel_id = 0,
            .terminal_buffer = terminal_buffer,
            .framebuffer = fb_result.data,
            .framebuffer_fd = fb_result.fd,
            .width = config.initial_width,
            .height = config.initial_height,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.terminal_buffer.deinit();
        buffer.destroyMemoryMappedBuffer(self.framebuffer, self.framebuffer_fd);
    }
    
    pub fn setup(self: *Self) !void {
        // Get registry and bind compositor
        const registry = try self.client.getRegistry();
        try self.client.roundtrip();
        
        // Find and bind compositor, xdg_wm_base, and shm
        var compositor_name: u32 = 0;
        var xdg_shell_name: u32 = 0;
        var shm_name: u32 = 0;
        
        var global_iter = registry.globals.iterator();
        while (global_iter.next()) |entry| {
            const global = entry.value_ptr.*;
            if (std.mem.eql(u8, global.interface, "wl_compositor")) {
                compositor_name = global.name;
            } else if (std.mem.eql(u8, global.interface, "xdg_wm_base")) {
                xdg_shell_name = global.name;
            } else if (std.mem.eql(u8, global.interface, "wl_shm")) {
                shm_name = global.name;
            }
        }
        
        if (compositor_name == 0 or xdg_shell_name == 0 or shm_name == 0) {
            return error.RequiredInterfaceMissing;
        }
        
        // Bind interfaces
        self.compositor_id = try registry.bind(compositor_name, "wl_compositor", 6);
        const xdg_wm_base_id = try registry.bind(xdg_shell_name, "xdg_wm_base", 6);
        self.shm_id = try registry.bind(shm_name, "wl_shm", 2);
        
        // Create surface
        const compositor = client.Compositor.init(self.client, self.compositor_id);
        const surface = try compositor.createSurface();
        self.surface_id = surface.object.id;
        
        // Create XDG surface
        const xdg_wm_base = xdg_shell.XdgWmBase.init(self.client, xdg_wm_base_id);
        self.xdg_surface_id = try xdg_wm_base.getXdgSurface(self.surface_id);
        
        // Create toplevel
        const xdg_surface = xdg_shell.XdgSurface.init(self.client, self.xdg_surface_id);
        self.toplevel_id = try xdg_surface.getToplevel();
        
        // Configure toplevel
        const toplevel = xdg_shell.XdgToplevel.init(self.client, self.toplevel_id);
        try toplevel.setTitle(self.config.title);
        try toplevel.setAppId(self.config.app_id);
        
        // Create shared memory pool and buffer
        try self.createBuffer();
        
        // Commit surface
        try surface.commit();
        try self.client.roundtrip();
        
        std.debug.print("[wzl-terminal] Terminal window setup complete\n", .{});
    }
    
    fn createBuffer(self: *Self) !void {
        if (self.shm_id == null) return error.ShmNotAvailable;
        
        const shm = buffer.Shm.init(self.client, self.shm_id.?);
        self.pool_id = try shm.createPool(self.framebuffer_fd, @intCast(self.framebuffer.len));
        
        const pool = buffer.ShmPool.init(self.client, self.pool_id.?, self.framebuffer_fd, @intCast(self.framebuffer.len));
        self.buffer_id = try pool.createBuffer(0, self.width, self.height, self.width * 4, buffer.ShmFormat.argb8888);
    }
    
    pub fn render(self: *Self) !void {
        // Clear framebuffer
        const bg_color = if (self.config.enable_transparency) 
            Color{ .r = 0, .g = 0, .b = 0, .a = @intFromFloat(self.config.opacity * 255) }
        else
            Color.BLACK;
            
        const bg_pixel = bg_color.toU32();
        const pixels = @as([*]u32, @ptrCast(@alignCast(self.framebuffer.ptr)))[0..@divExact(self.framebuffer.len, 4)];
        @memset(pixels, bg_pixel);
        
        // Render terminal cells
        for (0..self.terminal_buffer.rows) |row| {
            for (0..self.terminal_buffer.cols) |col| {
                const cell = self.terminal_buffer.cells[row][col];
                const x = @as(i32, @intCast(col)) * self.config.cell_width;
                const y = @as(i32, @intCast(row)) * self.config.cell_height;
                
                self.renderCell(cell, x, y);
            }
        }
        
        // Render cursor
        if (self.terminal_buffer.cursor.visible) {
            self.renderCursor();
        }
        
        // Attach buffer to surface
        const surface = client.Surface.init(self.client, self.surface_id);
        try surface.attach(self.buffer_id, 0, 0);
        try surface.damage(0, 0, self.width, self.height);
        try surface.commit();
    }
    
    fn renderCell(self: *Self, cell: Cell, x: i32, y: i32) void {
        // Render background
        if (cell.bg_color.a > 0 or !std.meta.eql(cell.bg_color, Color.BLACK)) {
            self.fillRect(x, y, self.config.cell_width, self.config.cell_height, cell.bg_color);
        }
        
        // Render character (simplified - in a real implementation, use a font renderer)
        if (cell.codepoint != ' ') {
            self.renderGlyph(cell.codepoint, x, y, cell.fg_color, cell.attributes);
        }
    }
    
    fn renderCursor(self: *Self) void {
        const x = @as(i32, @intCast(self.terminal_buffer.cursor.col)) * self.config.cell_width;
        const y = @as(i32, @intCast(self.terminal_buffer.cursor.row)) * self.config.cell_height;
        
        switch (self.terminal_buffer.cursor.style) {
            .block => self.fillRect(x, y, self.config.cell_width, self.config.cell_height, self.terminal_buffer.cursor.color),
            .underline => self.fillRect(x, y + self.config.cell_height - 2, self.config.cell_width, 2, self.terminal_buffer.cursor.color),
            .bar => self.fillRect(x, y, 2, self.config.cell_height, self.terminal_buffer.cursor.color),
        }
    }
    
    fn fillRect(self: *Self, x: i32, y: i32, width: u8, height: u8, color: Color) void {
        if (x < 0 or y < 0 or x + width > self.width or y + height > self.height) return;
        
        const pixels = @as([*]u32, @ptrCast(@alignCast(self.framebuffer.ptr)));
        const color_value = color.toU32();
        
        for (@intCast(y)..@intCast(y + height)) |row| {
            const row_start = row * @as(usize, @intCast(self.width));
            @memset(pixels[row_start + @as(usize, @intCast(x))..row_start + @as(usize, @intCast(x + width))], color_value);
        }
    }
    
    fn renderGlyph(self: *Self, codepoint: u21, x: i32, y: i32, fg_color: Color, attrs: CellAttributes) void {
        _ = codepoint;
        _ = attrs;
        
        // Simple fallback rendering - draw a rectangle for visible characters
        if (x >= 0 and y >= 0 and x + self.config.cell_width <= self.width and y + self.config.cell_height <= self.height) {
            // Draw a simple rectangle outline as placeholder
            self.fillRect(x + 1, y + 1, self.config.cell_width - 2, 1, fg_color); // Top
            self.fillRect(x + 1, y + self.config.cell_height - 2, self.config.cell_width - 2, 1, fg_color); // Bottom
            self.fillRect(x + 1, y + 1, 1, self.config.cell_height - 2, fg_color); // Left
            self.fillRect(x + self.config.cell_width - 2, y + 1, 1, self.config.cell_height - 2, fg_color); // Right
        }
    }
    
    pub fn writeText(self: *Self, text: []const u8) !void {
        for (text) |byte| {
            // Simple UTF-8 decoding (basic ASCII for now)
            const codepoint: u21 = if (byte < 128) byte else '?';
            
            if (codepoint == '\n') {
                self.terminal_buffer.cursor.col = 0;
                self.terminal_buffer.cursor.row += 1;
                if (self.terminal_buffer.cursor.row >= self.terminal_buffer.rows) {
                    self.terminal_buffer.scrollUp(1);
                }
            } else if (codepoint == '\r') {
                self.terminal_buffer.cursor.col = 0;
            } else if (codepoint >= 32) {
                self.terminal_buffer.putChar(codepoint, Color.WHITE, Color.BLACK, .{});
            }
        }
        
        try self.render();
    }
    
    pub fn resize(self: *Self, new_width: i32, new_height: i32) !void {
        // Calculate new terminal dimensions
        const new_cols: u16 = @intCast(@divFloor(new_width, self.config.cell_width));
        const new_rows: u16 = @intCast(@divFloor(new_height, self.config.cell_height));
        
        // Resize terminal buffer
        try self.terminal_buffer.resize(new_rows, new_cols);
        
        // Create new framebuffer
        buffer.destroyMemoryMappedBuffer(self.framebuffer, self.framebuffer_fd);
        
        const fb_result = try buffer.createMemoryMappedBuffer(
            self.allocator,
            new_width,
            new_height,
            buffer.ShmFormat.argb8888,
        );
        
        self.framebuffer = fb_result.data;
        self.framebuffer_fd = fb_result.fd;
        self.width = new_width;
        self.height = new_height;
        
        // Recreate buffer
        try self.createBuffer();
        
        std.debug.print("[wzl-terminal] Resized to {}x{} ({}x{} chars)\n", .{ new_width, new_height, new_cols, new_rows });
    }
    
    pub fn handleKeyboard(self: *Self, key: u32, state: input.KeyState) !void {
        if (state == .pressed) {
            // Simple key handling - convert keycodes to characters
            const char = switch (key) {
                10 => '\n', // Enter
                36 => '\n', // Return
                22 => '\x08', // Backspace
                65 => ' ',  // Space
                else => if (key >= 24 and key <= 33) @as(u8, @intCast(key - 24 + 'q')) else 0,
            };
            
            if (char != 0) {
                const text = [_]u8{char};
                try self.writeText(&text);
            }
        }
    }
    
    pub fn setFocus(self: *Self, focused: bool) void {
        self.keyboard_focused = focused;
        if (focused) {
            std.debug.print("[wzl-terminal] Terminal gained focus\n", .{});
        } else {
            std.debug.print("[wzl-terminal] Terminal lost focus\n", .{});
        }
    }
    
    // Ghostty integration helpers
    pub fn ghosttySetTitle(self: *Self, title: []const u8) !void {
        const toplevel = xdg_shell.XdgToplevel.init(self.client, self.toplevel_id);
        try toplevel.setTitle(title);
    }
    
    pub fn ghosttySetOpacity(self: *Self, opacity: f32) !void {
        self.config.opacity = std.math.clamp(opacity, 0.0, 1.0);
        self.config.enable_transparency = opacity < 1.0;
        try self.render();
    }
    
    pub fn ghosttyEnableBlur(self: *Self, enable: bool) void {
        self.config.enable_blur = enable;
        std.debug.print("[wzl-terminal] Blur effect: {}\n", .{enable});
    }
};