// Touch input stub - provides no-op implementations when touch is disabled

pub const TouchPoint = struct {
    id: i32 = 0,
    x: f32 = 0,
    y: f32 = 0,
};

pub const GestureType = enum { none };

pub const GestureRecognizer = struct {
    pub fn init(allocator: anytype) !GestureRecognizer {
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *GestureRecognizer) void {
        _ = self;
    }

    pub fn addCallback(self: *GestureRecognizer, gesture: GestureType, callback: anytype) !void {
        _ = self;
        _ = gesture;
        _ = callback;
    }
};

pub const TouchHandler = struct {
    pub fn init(allocator: anytype, object_id: u32) !TouchHandler {
        _ = allocator;
        _ = object_id;
        return .{};
    }

    pub fn deinit(self: *TouchHandler) void {
        _ = self;
    }

    pub fn handleMessage(self: *TouchHandler, message: anytype) !void {
        _ = self;
        _ = message;
    }
};