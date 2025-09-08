const std = @import("std");
const protocol = @import("protocol.zig");

// Output management enums
pub const OutputTransform = enum(i32) {
    normal = 0,
    @"90" = 1,
    @"180" = 2,
    @"270" = 3,
    flipped = 4,
    flipped_90 = 5,
    flipped_180 = 6,
    flipped_270 = 7,
};

pub const OutputMode = packed struct {
    current: bool = false,
    preferred: bool = false,
    _padding: u30 = 0,
    
    pub fn toU32(self: OutputMode) u32 {
        return @bitCast(self);
    }
    
    pub fn fromU32(value: u32) OutputMode {
        return @bitCast(value);
    }
};

pub const OutputSubpixel = enum(i32) {
    unknown = 0,
    none = 1,
    horizontal_rgb = 2,
    horizontal_bgr = 3,
    vertical_rgb = 4,
    vertical_bgr = 5,
};

// Output information structure
pub const OutputInfo = struct {
    x: i32 = 0,
    y: i32 = 0,
    physical_width: i32 = 0,
    physical_height: i32 = 0,
    subpixel: OutputSubpixel = .unknown,
    make: ?[]const u8 = null,
    model: ?[]const u8 = null,
    transform: OutputTransform = .normal,
    scale_factor: i32 = 1,
    modes: std.ArrayList(OutputModeInfo),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .modes = std.ArrayList(OutputModeInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.make) |make| allocator.free(make);
        if (self.model) |model| allocator.free(model);
        self.modes.deinit();
    }
};

pub const OutputModeInfo = struct {
    flags: OutputMode,
    width: i32,
    height: i32,
    refresh: i32, // mHz (millihertz)
};

// Client-side output implementation
pub const Output = struct {
    object_id: protocol.ObjectId,
    client: *@import("client.zig").Client,
    info: OutputInfo,
    version: u32,
    done_received: bool,
    
    const Self = @This();
    
    pub fn init(client: *@import("client.zig").Client, object_id: protocol.ObjectId, version: u32) Self {
        return Self{
            .object_id = object_id,
            .client = client,
            .info = OutputInfo.init(client.allocator),
            .version = version,
            .done_received = false,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.info.deinit(self.client.allocator);
    }
    
    pub fn release(self: *Self) !void {
        if (self.version >= 3) {
            const message = try protocol.Message.init(
                self.client.allocator,
                self.object_id,
                0, // release opcode
                &.{},
            );
            try self.client.connection.sendMessage(message);
        }
    }
    
    pub fn handleEvent(self: *Self, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleGeometry(message),
            1 => try self.handleMode(message),
            2 => self.handleDone(message),
            3 => try self.handleScale(message),
            else => {},
        }
    }
    
    fn handleGeometry(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 8) {
            self.info.x = switch (message.arguments[0]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            self.info.y = switch (message.arguments[1]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            self.info.physical_width = switch (message.arguments[2]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            self.info.physical_height = switch (message.arguments[3]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            self.info.subpixel = switch (message.arguments[4]) {
                .int => |v| @enumFromInt(v),
                else => return error.InvalidArgument,
            };
            
            const make = switch (message.arguments[5]) {
                .string => |s| try self.client.allocator.dupe(u8, s),
                else => return error.InvalidArgument,
            };
            if (self.info.make) |old_make| {
                self.client.allocator.free(old_make);
            }
            self.info.make = make;
            
            const model = switch (message.arguments[6]) {
                .string => |s| try self.client.allocator.dupe(u8, s),
                else => return error.InvalidArgument,
            };
            if (self.info.model) |old_model| {
                self.client.allocator.free(old_model);
            }
            self.info.model = model;
            
            self.info.transform = switch (message.arguments[7]) {
                .int => |v| @enumFromInt(v),
                else => return error.InvalidArgument,
            };
        }
    }
    
    fn handleMode(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 4) {
            const flags = switch (message.arguments[0]) {
                .uint => |v| OutputMode.fromU32(v),
                else => return error.InvalidArgument,
            };
            const width = switch (message.arguments[1]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            const height = switch (message.arguments[2]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            const refresh = switch (message.arguments[3]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
            
            const mode_info = OutputModeInfo{
                .flags = flags,
                .width = width,
                .height = height,
                .refresh = refresh,
            };
            
            try self.info.modes.append(mode_info);
        }
    }
    
    fn handleDone(self: *Self, message: protocol.Message) void {
        _ = message;
        self.done_received = true;
    }
    
    fn handleScale(self: *Self, message: protocol.Message) !void {
        if (message.arguments.len >= 1) {
            self.info.scale_factor = switch (message.arguments[0]) {
                .int => |v| v,
                else => return error.InvalidArgument,
            };
        }
    }
    
    pub fn getCurrentMode(self: *Self) ?OutputModeInfo {
        for (self.info.modes.items) |mode| {
            if (mode.flags.current) {
                return mode;
            }
        }
        return null;
    }
    
    pub fn getPreferredMode(self: *Self) ?OutputModeInfo {
        for (self.info.modes.items) |mode| {
            if (mode.flags.preferred) {
                return mode;
            }
        }
        return null;
    }
};