const std = @import("std");
const protocol = @import("protocol.zig");
const client = @import("client.zig");
const input = @import("input.zig");

// Wayland clipboard and selection management
// Supports both data device manager and primary selection protocols

pub const wl_data_device_manager_interface = protocol.Interface{
    .name = "wl_data_device_manager",
    .version = 3,
    .method_count = 3,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "create_data_source", .signature = "n", .types = &[_]?*const protocol.Interface{&wl_data_source_interface} },
        .{ .name = "get_data_device", .signature = "no", .types = &[_]?*const protocol.Interface{&wl_data_device_interface, &input.wl_seat_interface} },
    },
    .event_count = 0,
    .events = &[_]protocol.MethodSignature{},
};

pub const wl_data_source_interface = protocol.Interface{
    .name = "wl_data_source",
    .version = 3,
    .method_count = 4,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "offer", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_actions", .signature = "3u", .types = &[_]?*const protocol.Interface{null} },
    },
    .event_count = 4,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "target", .signature = "?s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "send", .signature = "sh", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "cancelled", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "dnd_drop_performed", .signature = "3", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "dnd_finished", .signature = "3", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "action", .signature = "3u", .types = &[_]?*const protocol.Interface{null} },
    },
};

pub const wl_data_device_interface = protocol.Interface{
    .name = "wl_data_device",
    .version = 3,
    .method_count = 3,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "start_drag", .signature = "?oo?ou", .types = &[_]?*const protocol.Interface{&wl_data_source_interface, &protocol.wl_surface_interface, &protocol.wl_surface_interface, null} },
        .{ .name = "set_selection", .signature = "?ou", .types = &[_]?*const protocol.Interface{&wl_data_source_interface, null} },
        .{ .name = "release", .signature = "2", .types = &[_]?*const protocol.Interface{} },
    },
    .event_count = 6,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "data_offer", .signature = "n", .types = &[_]?*const protocol.Interface{&wl_data_offer_interface} },
        .{ .name = "enter", .signature = "uoff?o", .types = &[_]?*const protocol.Interface{null, &protocol.wl_surface_interface, null, null, &wl_data_offer_interface} },
        .{ .name = "leave", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "motion", .signature = "uff", .types = &[_]?*const protocol.Interface{null, null, null} },
        .{ .name = "drop", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "selection", .signature = "?o", .types = &[_]?*const protocol.Interface{&wl_data_offer_interface} },
    },
};

pub const wl_data_offer_interface = protocol.Interface{
    .name = "wl_data_offer",
    .version = 3,
    .method_count = 5,
    .methods = &[_]protocol.MethodSignature{
        .{ .name = "accept", .signature = "u?s", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "receive", .signature = "sh", .types = &[_]?*const protocol.Interface{null, null} },
        .{ .name = "destroy", .signature = "", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "finish", .signature = "3", .types = &[_]?*const protocol.Interface{} },
        .{ .name = "set_actions", .signature = "3uu", .types = &[_]?*const protocol.Interface{null, null} },
    },
    .event_count = 3,
    .events = &[_]protocol.MethodSignature{
        .{ .name = "offer", .signature = "s", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "source_actions", .signature = "3u", .types = &[_]?*const protocol.Interface{null} },
        .{ .name = "action", .signature = "3u", .types = &[_]?*const protocol.Interface{null} },
    },
};

pub const MimeType = struct {
    name: []const u8,
    
    // Common MIME types
    pub const TEXT_PLAIN = MimeType{ .name = "text/plain" };
    pub const TEXT_UTF8 = MimeType{ .name = "text/plain;charset=utf-8" };
    pub const TEXT_HTML = MimeType{ .name = "text/html" };
    pub const IMAGE_PNG = MimeType{ .name = "image/png" };
    pub const IMAGE_JPEG = MimeType{ .name = "image/jpeg" };
    pub const URI_LIST = MimeType{ .name = "text/uri-list" };
    pub const GNOME_FILES = MimeType{ .name = "x-special/gnome-copied-files" };
    
    // Ghostty-specific types
    pub const TERMINAL_ESCAPE = MimeType{ .name = "application/x-terminal-escape" };
    pub const ANSI_TEXT = MimeType{ .name = "text/plain;charset=ansi" };
};

pub const DragDropAction = packed struct {
    copy: bool = false,
    move: bool = false,
    ask: bool = false,
    _padding: u29 = 0,
    
    pub fn toU32(self: DragDropAction) u32 {
        return @bitCast(self);
    }
    
    pub fn fromU32(value: u32) DragDropAction {
        return @bitCast(value);
    }
};

pub const ClipboardData = struct {
    mime_type: []const u8,
    data: []const u8,
    timestamp: i64,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, mime_type: []const u8, data: []const u8) !Self {
        return Self{
            .mime_type = try allocator.dupe(u8, mime_type),
            .data = try allocator.dupe(u8, data),
            .timestamp = std.time.milliTimestamp(),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.mime_type);
        self.allocator.free(self.data);
    }
    
    pub fn isText(self: *Self) bool {
        return std.mem.startsWith(u8, self.mime_type, "text/");
    }
    
    pub fn isImage(self: *Self) bool {
        return std.mem.startsWith(u8, self.mime_type, "image/");
    }
    
    pub fn isUri(self: *Self) bool {
        return std.mem.eql(u8, self.mime_type, "text/uri-list");
    }
};

pub const DataSource = struct {
    object_id: protocol.ObjectId,
    client: *client.Client,
    offered_types: std.ArrayList([]const u8),
    clipboard_data: std.HashMap([]const u8, ClipboardData, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    drag_actions: DragDropAction = .{},
    
    const Self = @This();
    
    pub fn init(client_ref: *client.Client, object_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client_ref,
            .offered_types = std.ArrayList([]const u8){},
            .clipboard_data = std.HashMap([]const u8, ClipboardData, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(client_ref.allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.offered_types.items) |mime_type| {
            self.client.allocator.free(mime_type);
        }
        self.offered_types.deinit(self.client.allocator);
        
        var data_iter = self.clipboard_data.iterator();
        while (data_iter.next()) |entry| {
            self.client.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.clipboard_data.deinit(self.client.allocator);
    }
    
    pub fn offer(self: *Self, mime_type: []const u8) !void {
        const mime_copy = try self.client.allocator.dupe(u8, mime_type);
        try self.offered_types.append(self.client.allocator, mime_copy);
        
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // offer opcode
            &[_]protocol.Argument{
                .{ .string = mime_type },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn setData(self: *Self, mime_type: []const u8, data: []const u8) !void {
        const clipboard_data = try ClipboardData.init(self.client.allocator, mime_type, data);
        const key = try self.client.allocator.dupe(u8, mime_type);
        try self.clipboard_data.put(key, clipboard_data);
    }
    
    pub fn setDragActions(self: *Self, actions: DragDropAction) !void {
        self.drag_actions = actions;
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            2, // set_actions opcode
            &[_]protocol.Argument{
                .{ .uint = actions.toU32() },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn destroy(self: *Self) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // destroy opcode
            &.{},
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleTarget(message),
            1 => try self.handleSend(message),
            2 => try self.handleCancelled(message),
            else => {},
        }
    }
    
    fn handleTarget(self: *Self, message: protocol.Message) !void {
        _ = self;
        if (message.arguments.len >= 1) {
            const target = switch (message.arguments[0]) {
                .string => |s| s,
                else => null,
            };
            
            if (target) |mime_type| {
                std.debug.print("[wzl-clipboard] Target accepted: {s}\n", .{mime_type});
            } else {
                std.debug.print("[wzl-clipboard] Target rejected\n", .{});
            }
        }
    }
    
    fn handleSend(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 2) {
            const mime_type = switch (message.arguments[0]) {
                .string => |s| s,
                else => return error.InvalidArgument,
            };
            
            const fd = switch (message.arguments[1]) {
                .fd => |f| f,
                else => return error.InvalidArgument,
            };
            
            // Send data through the file descriptor
            if (self.clipboard_data.get(mime_type)) |clipboard_data| {
                const file = std.fs.File{ .handle = fd };
                try file.writeAll(clipboard_data.data);
                file.close();
                std.debug.print("[wzl-clipboard] Sent {} bytes of {s}\n", .{ clipboard_data.data.len, mime_type });
            } else {
                const file = std.fs.File{ .handle = fd };
                file.close();
                std.debug.print("[wzl-clipboard] No data for {s}\n", .{mime_type});
            }
        }
    }
    
    fn handleCancelled(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        std.debug.print("[wzl-clipboard] Data source cancelled\n", .{});
    }
};

pub const DataDevice = struct {
    object_id: protocol.ObjectId,
    client: *client.Client,
    seat_id: protocol.ObjectId,
    current_selection: ?protocol.ObjectId = null,
    
    const Self = @This();
    
    pub fn init(client_ref: *client.Client, object_id: protocol.ObjectId, seat_id: protocol.ObjectId) Self {
        return Self{
            .object_id = object_id,
            .client = client_ref,
            .seat_id = seat_id,
        };
    }
    
    pub fn setSelection(self: *Self, source_id: ?protocol.ObjectId, serial: u32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            1, // set_selection opcode
            &[_]protocol.Argument{
                .{ .object = source_id orelse 0 },
                .{ .uint = serial },
            },
        );
        try self.client.connection.sendMessage(message);
        self.current_selection = source_id;
    }
    
    pub fn startDrag(self: *Self, source_id: ?protocol.ObjectId, origin_surface: protocol.ObjectId, icon_surface: ?protocol.ObjectId, serial: u32) !void {
        const message = try protocol.Message.init(
            self.client.allocator,
            self.object_id,
            0, // start_drag opcode
            &[_]protocol.Argument{
                .{ .object = source_id orelse 0 },
                .{ .object = origin_surface },
                .{ .object = icon_surface orelse 0 },
                .{ .uint = serial },
            },
        );
        try self.client.connection.sendMessage(message);
    }
    
    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleDataOffer(message),
            5 => try self.handleSelection(message),
            else => {},
        }
    }
    
    fn handleDataOffer(self: *Self, message: protocol.Message) !void {
        _ = self;
        if (message.arguments.len >= 1) {
            const offer_id = switch (message.arguments[0]) {
                .new_id => |id| id,
                else => return error.InvalidArgument,
            };
            
            std.debug.print("[wzl-clipboard] New data offer: {}\n", .{offer_id});
            // Store the offer for later use
        }
    }
    
    fn handleSelection(self: *Self, message: protocol.Message) !void {
        _ = self;
        if (message.arguments.len >= 1) {
            const offer_id = switch (message.arguments[0]) {
                .object => |id| if (id == 0) null else id,
                else => null,
            };
            
            if (offer_id) |id| {
                std.debug.print("[wzl-clipboard] Selection changed: {}\n", .{id});
            } else {
                std.debug.print("[wzl-clipboard] Selection cleared\n", .{});
            }
        }
    }
};

pub const ClipboardManager = struct {
    client: *client.Client,
    data_device_manager_id: ?protocol.ObjectId = null,
    data_device_id: ?protocol.ObjectId = null,
    seat_id: protocol.ObjectId,
    
    // Clipboard history
    history: std.ArrayList(ClipboardData),
    max_history_size: usize = 100,
    
    // Remote sync
    remote_sync_enabled: bool = false,
    
    const Self = @This();
    
    pub fn init(client_ref: *client.Client, seat_id: protocol.ObjectId) Self {
        return Self{
            .client = client_ref,
            .seat_id = seat_id,
            .history = std.ArrayList(ClipboardData){},
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.history.items) |*item| {
            item.deinit();
        }
        self.history.deinit(self.client.allocator);
    }
    
    pub fn setup(self: *Self) !void {
        // Find data device manager in registry
        const registry = try self.client.getRegistry();
        try self.client.roundtrip();
        
        var ddm_name: u32 = 0;
        var global_iter = registry.globals.iterator();
        while (global_iter.next()) |entry| {
            const global = entry.value_ptr.*;
            if (std.mem.eql(u8, global.interface, "wl_data_device_manager")) {
                ddm_name = global.name;
                break;
            }
        }
        
        if (ddm_name == 0) return error.DataDeviceManagerNotFound;
        
        // Bind data device manager
        self.data_device_manager_id = try registry.bind(ddm_name, "wl_data_device_manager", 3);
        
        // Get data device for our seat
        const message = try protocol.Message.init(
            self.client.allocator,
            self.data_device_manager_id.?,
            1, // get_data_device opcode
            &[_]protocol.Argument{
                .{ .new_id = self.client.nextId() },
                .{ .object = self.seat_id },
            },
        );
        self.data_device_id = message.arguments[0].new_id;
        try self.client.connection.sendMessage(message);
        
        std.debug.print("[wzl-clipboard] Clipboard manager initialized\n", .{});
    }
    
    pub fn setClipboard(self: *Self, mime_type: []const u8, data: []const u8) !void {
        if (self.data_device_manager_id == null) return error.NotInitialized;
        
        // Create data source
        const source_id = self.client.nextId();
        const create_source_msg = try protocol.Message.init(
            self.client.allocator,
            self.data_device_manager_id.?,
            0, // create_data_source opcode
            &[_]protocol.Argument{
                .{ .new_id = source_id },
            },
        );
        try self.client.connection.sendMessage(create_source_msg);
        
        // Create and configure data source
        var data_source = DataSource.init(self.client, source_id);
        try data_source.offer(mime_type);
        try data_source.setData(mime_type, data);
        
        // Set selection
        const data_device = DataDevice.init(self.client, self.data_device_id.?, self.seat_id);
        try data_device.setSelection(source_id, 0); // TODO: get proper serial from input event
        
        // Add to history
        const clipboard_data = try ClipboardData.init(self.client.allocator, mime_type, data);
        try self.addToHistory(clipboard_data);
        
        std.debug.print("[wzl-clipboard] Set clipboard: {s} ({} bytes)\n", .{ mime_type, data.len });
    }
    
    pub fn getClipboard(self: *Self, mime_type: []const u8) !?[]const u8 {
        _ = mime_type;
        
        if (self.history.items.len == 0) return null;
        
        // Return the most recent item
        const latest = &self.history.items[self.history.items.len - 1];
        return try self.client.allocator.dupe(u8, latest.data);
    }
    
    fn addToHistory(self: *Self, clipboard_data: ClipboardData) !void {
        try self.history.append(self.client.allocator, clipboard_data);
        
        // Limit history size
        while (self.history.items.len > self.max_history_size) {
            var old_item = self.history.orderedRemove(0);
            old_item.deinit();
        }
    }
    
    pub fn clearHistory(self: *Self) void {
        for (self.history.items) |*item| {
            item.deinit();
        }
        self.history.clearRetainingCapacity();
    }
    
    pub fn enableRemoteSync(self: *Self, enable: bool) void {
        self.remote_sync_enabled = enable;
        std.debug.print("[wzl-clipboard] Remote clipboard sync: {}\n", .{enable});
    }
    
    pub fn getHistoryCount(self: *Self) usize {
        return self.history.items.len;
    }
    
    pub fn getHistoryItem(self: *Self, index: usize) ?*const ClipboardData {
        if (index >= self.history.items.len) return null;
        return &self.history.items[index];
    }
    
    // Ghostty terminal integration helpers
    pub fn setTerminalText(self: *Self, text: []const u8, preserve_ansi: bool) !void {
        const mime_type = if (preserve_ansi) MimeType.ANSI_TEXT.name else MimeType.TEXT_UTF8.name;
        try self.setClipboard(mime_type, text);
    }
    
    pub fn setTerminalEscape(self: *Self, escape_sequence: []const u8) !void {
        try self.setClipboard(MimeType.TERMINAL_ESCAPE.name, escape_sequence);
    }
};