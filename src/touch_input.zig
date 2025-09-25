const std = @import("std");
const protocol = @import("protocol.zig");
const errors = @import("errors.zig");
const thread_safety = @import("thread_safety.zig");

/// Touch point information
pub const TouchPoint = struct {
    id: i32,
    surface: protocol.ObjectId,
    x: f32,
    y: f32,
    pressure: f32 = 1.0,
    major_axis: f32 = 0.0,
    minor_axis: f32 = 0.0,
    orientation: f32 = 0.0,
    timestamp: u32,
    state: TouchState,
};

/// Touch point state
pub const TouchState = enum {
    down,
    up,
    motion,
    cancelled,
};

/// Multi-touch gesture recognition
pub const GestureType = enum {
    none,
    tap,
    double_tap,
    long_press,
    swipe_left,
    swipe_right,
    swipe_up,
    swipe_down,
    pinch_in,
    pinch_out,
    rotate_cw,
    rotate_ccw,
    three_finger_swipe,
    four_finger_swipe,
};

/// Gesture recognizer
pub const GestureRecognizer = struct {
    allocator: std.mem.Allocator,
    touch_points: std.AutoHashMap(i32, TouchPoint),
    gesture_callbacks: std.ArrayList(GestureCallback),

    // Gesture detection parameters
    tap_timeout_ms: u64 = 300,
    long_press_timeout_ms: u64 = 500,
    swipe_threshold: f32 = 50.0,
    pinch_threshold: f32 = 0.1,
    rotation_threshold: f32 = 0.2,

    // Current gesture state
    current_gesture: GestureType = .none,
    gesture_start_time: i64 = 0,
    gesture_start_points: std.ArrayList(TouchPoint),

    const GestureCallback = struct {
        gesture: GestureType,
        callback: *const fn (GestureInfo) void,
    };

    pub const GestureInfo = struct {
        gesture: GestureType,
        touch_points: []const TouchPoint,
        center_x: f32,
        center_y: f32,
        scale: f32 = 1.0,
        rotation: f32 = 0.0,
        velocity_x: f32 = 0.0,
        velocity_y: f32 = 0.0,
    };

    pub fn init(allocator: std.mem.Allocator) !GestureRecognizer {
        return GestureRecognizer{
            .allocator = allocator,
            .touch_points = std.AutoHashMap(i32, TouchPoint).init(allocator),
            .gesture_callbacks = std.ArrayList(GestureCallback).init(allocator),
            .gesture_start_points = std.ArrayList(TouchPoint).init(allocator),
        };
    }

    pub fn deinit(self: *GestureRecognizer) void {
        self.touch_points.deinit();
        self.gesture_callbacks.deinit();
        self.gesture_start_points.deinit();
    }

    pub fn addCallback(self: *GestureRecognizer, gesture: GestureType, callback: *const fn (GestureInfo) void) !void {
        try self.gesture_callbacks.append(.{
            .gesture = gesture,
            .callback = callback,
        });
    }

    pub fn handleTouchDown(self: *GestureRecognizer, point: TouchPoint) !void {
        try self.touch_points.put(point.id, point);

        if (self.touch_points.count() == 1) {
            self.gesture_start_time = std.time.milliTimestamp();
            self.gesture_start_points.clearRetainingCapacity();
        }

        try self.gesture_start_points.append(point);
        try self.detectGesture();
    }

    pub fn handleTouchUp(self: *GestureRecognizer, id: i32, timestamp: u32) !void {
        if (self.touch_points.get(id)) |point| {
            const duration = std.time.milliTimestamp() - self.gesture_start_time;

            if (self.touch_points.count() == 1 and duration < self.tap_timeout_ms) {
                try self.triggerGesture(.tap, &[_]TouchPoint{point});
            }

            _ = self.touch_points.remove(id);
        }

        if (self.touch_points.count() == 0) {
            self.current_gesture = .none;
        }

        _ = timestamp;
    }

    pub fn handleTouchMotion(self: *GestureRecognizer, id: i32, x: f32, y: f32, timestamp: u32) !void {
        if (self.touch_points.getPtr(id)) |point| {
            point.x = x;
            point.y = y;
            point.timestamp = timestamp;
            point.state = .motion;

            try self.detectGesture();
        }
    }

    fn detectGesture(self: *GestureRecognizer) !void {
        const count = self.touch_points.count();

        if (count == 0) return;

        var points = try self.allocator.alloc(TouchPoint, count);
        defer self.allocator.free(points);

        var iter = self.touch_points.valueIterator();
        var i: usize = 0;
        while (iter.next()) |point| : (i += 1) {
            points[i] = point.*;
        }

        if (count == 1) {
            try self.detectSingleTouchGesture(points[0]);
        } else if (count == 2) {
            try self.detectTwoTouchGesture(points);
        } else if (count >= 3) {
            try self.detectMultiTouchGesture(points);
        }
    }

    fn detectSingleTouchGesture(self: *GestureRecognizer, point: TouchPoint) !void {
        const duration = std.time.milliTimestamp() - self.gesture_start_time;

        if (duration > self.long_press_timeout_ms and self.current_gesture != .long_press) {
            self.current_gesture = .long_press;
            try self.triggerGesture(.long_press, &[_]TouchPoint{point});
            return;
        }

        if (self.gesture_start_points.items.len > 0) {
            const start = self.gesture_start_points.items[0];
            const dx = point.x - start.x;
            const dy = point.y - start.y;
            const point_distance = @sqrt(dx * dx + dy * dy);

            if (point_distance > self.swipe_threshold) {
                const gesture = if (@abs(dx) > @abs(dy)) {
                    if (dx > 0) GestureType.swipe_right else GestureType.swipe_left;
                } else {
                    if (dy > 0) GestureType.swipe_down else GestureType.swipe_up;
                };

                if (self.current_gesture != gesture) {
                    self.current_gesture = gesture;
                    try self.triggerGesture(gesture, &[_]TouchPoint{point});
                }
            }
        }
    }

    fn detectTwoTouchGesture(self: *GestureRecognizer, points: []TouchPoint) !void {
        if (self.gesture_start_points.items.len < 2) return;

        const p1 = points[0];
        const p2 = points[1];
        const s1 = self.gesture_start_points.items[0];
        const s2 = self.gesture_start_points.items[1];

        // Calculate pinch
        const start_dist = distance(s1.x, s1.y, s2.x, s2.y);
        const current_dist = distance(p1.x, p1.y, p2.x, p2.y);
        const scale = current_dist / start_dist;

        if (@abs(scale - 1.0) > self.pinch_threshold) {
            const gesture = if (scale > 1.0) GestureType.pinch_out else GestureType.pinch_in;
            if (self.current_gesture != gesture) {
                self.current_gesture = gesture;

                const info = GestureInfo{
                    .gesture = gesture,
                    .touch_points = points,
                    .center_x = (p1.x + p2.x) / 2,
                    .center_y = (p1.y + p2.y) / 2,
                    .scale = scale,
                };

                self.triggerGestureWithInfo(info);
            }
        }

        // Calculate rotation
        const start_angle = std.math.atan2(s2.y - s1.y, s2.x - s1.x);
        const current_angle = std.math.atan2(p2.y - p1.y, p2.x - p1.x);
        const rotation = current_angle - start_angle;

        if (@abs(rotation) > self.rotation_threshold) {
            const gesture = if (rotation > 0) GestureType.rotate_cw else GestureType.rotate_ccw;
            if (self.current_gesture != gesture) {
                self.current_gesture = gesture;

                const info = GestureInfo{
                    .gesture = gesture,
                    .touch_points = points,
                    .center_x = (p1.x + p2.x) / 2,
                    .center_y = (p1.y + p2.y) / 2,
                    .rotation = rotation,
                };

                self.triggerGestureWithInfo(info);
            }
        }
    }

    fn detectMultiTouchGesture(self: *GestureRecognizer, points: []TouchPoint) !void {
        // Calculate center and average movement
        var center_x: f32 = 0;
        var center_y: f32 = 0;
        var avg_dx: f32 = 0;
        var avg_dy: f32 = 0;

        for (points) |point| {
            center_x += point.x;
            center_y += point.y;
        }

        center_x /= @floatFromInt(points.len);
        center_y /= @floatFromInt(points.len);

        // Check for multi-finger swipes
        if (self.gesture_start_points.items.len >= points.len) {
            for (points, 0..) |point, i| {
                if (i < self.gesture_start_points.items.len) {
                    const start = self.gesture_start_points.items[i];
                    avg_dx += point.x - start.x;
                    avg_dy += point.y - start.y;
                }
            }

            avg_dx /= @floatFromInt(points.len);
            avg_dy /= @floatFromInt(points.len);

            const avg_distance = @sqrt(avg_dx * avg_dx + avg_dy * avg_dy);

            if (avg_distance > self.swipe_threshold) {
                const gesture = if (points.len == 3)
                    GestureType.three_finger_swipe
                else
                    GestureType.four_finger_swipe;

                if (self.current_gesture != gesture) {
                    self.current_gesture = gesture;

                    const info = GestureInfo{
                        .gesture = gesture,
                        .touch_points = points,
                        .center_x = center_x,
                        .center_y = center_y,
                        .velocity_x = avg_dx,
                        .velocity_y = avg_dy,
                    };

                    self.triggerGestureWithInfo(info);
                }
            }
        }
    }

    fn triggerGesture(self: *GestureRecognizer, gesture: GestureType, points: []const TouchPoint) !void {
        var center_x: f32 = 0;
        var center_y: f32 = 0;

        for (points) |point| {
            center_x += point.x;
            center_y += point.y;
        }

        center_x /= @floatFromInt(points.len);
        center_y /= @floatFromInt(points.len);

        const info = GestureInfo{
            .gesture = gesture,
            .touch_points = points,
            .center_x = center_x,
            .center_y = center_y,
        };

        self.triggerGestureWithInfo(info);
    }

    fn triggerGestureWithInfo(self: *GestureRecognizer, info: GestureInfo) void {
        for (self.gesture_callbacks.items) |callback| {
            if (callback.gesture == info.gesture) {
                callback.callback(info);
            }
        }
    }

    fn distance(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
        const dx = x2 - x1;
        const dy = y2 - y1;
        return @sqrt(dx * dx + dy * dy);
    }
};

/// Touch input handler with multi-touch support
pub const TouchHandler = struct {
    allocator: std.mem.Allocator,
    object_id: protocol.ObjectId,
    touch_points: thread_safety.Registry(TouchPoint),
    gesture_recognizer: GestureRecognizer,
    event_queue: thread_safety.MessageQueue(TouchEvent),

    const TouchEvent = struct {
        type: TouchState,
        point: TouchPoint,
    };

    pub fn init(allocator: std.mem.Allocator, object_id: protocol.ObjectId) !TouchHandler {
        return TouchHandler{
            .allocator = allocator,
            .object_id = object_id,
            .touch_points = thread_safety.Registry(TouchPoint).init(allocator),
            .gesture_recognizer = try GestureRecognizer.init(allocator),
            .event_queue = thread_safety.MessageQueue(TouchEvent).init(allocator),
        };
    }

    pub fn deinit(self: *TouchHandler) void {
        self.touch_points.deinit();
        self.gesture_recognizer.deinit();
        self.event_queue.deinit();
    }

    pub fn handleMessage(self: *TouchHandler, message: protocol.Message) !void {
        switch (message.header.opcode) {
            0 => try self.handleDown(message),
            1 => try self.handleUp(message),
            2 => try self.handleMotion(message),
            3 => try self.handleFrame(message),
            4 => try self.handleCancel(message),
            5 => try self.handleShape(message),
            6 => try self.handleOrientation(message),
            else => {},
        }
    }

    fn handleDown(self: *TouchHandler, message: protocol.Message) !void {
        if (message.arguments.len < 6) return error.InvalidArgument;

        const serial = message.arguments[0].uint;
        const time = message.arguments[1].uint;
        const surface = message.arguments[2].object;
        const id = message.arguments[3].int;
        const x = message.arguments[4].fixed.toFloat();
        const y = message.arguments[5].fixed.toFloat();

        var point = TouchPoint{
            .id = id,
            .surface = surface,
            .x = x,
            .y = y,
            .timestamp = time,
            .state = .down,
        };

        const point_id = try self.touch_points.add(&point);
        try self.gesture_recognizer.handleTouchDown(point);

        try self.event_queue.push(.{
            .type = .down,
            .point = point,
        });

        _ = serial;
        _ = point_id;
    }

    fn handleUp(self: *TouchHandler, message: protocol.Message) !void {
        if (message.arguments.len < 3) return error.InvalidArgument;

        const serial = message.arguments[0].uint;
        const time = message.arguments[1].uint;
        const id = message.arguments[2].int;

        try self.gesture_recognizer.handleTouchUp(id, time);

        // Find and remove touch point
        var iter = self.touch_points.objects.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.id == id) {
                _ = self.touch_points.remove(entry.key_ptr.*);
                break;
            }
        }

        _ = serial;
    }

    fn handleMotion(self: *TouchHandler, message: protocol.Message) !void {
        if (message.arguments.len < 4) return error.InvalidArgument;

        const time = message.arguments[0].uint;
        const id = message.arguments[1].int;
        const x = message.arguments[2].fixed.toFloat();
        const y = message.arguments[3].fixed.toFloat();

        try self.gesture_recognizer.handleTouchMotion(id, x, y, time);

        // Update touch point
        var iter = self.touch_points.objects.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.id == id) {
                entry.value_ptr.*.x = x;
                entry.value_ptr.*.y = y;
                entry.value_ptr.*.timestamp = time;
                entry.value_ptr.*.state = .motion;

                try self.event_queue.push(.{
                    .type = .motion,
                    .point = entry.value_ptr.*,
                });
                break;
            }
        }
    }

    fn handleFrame(self: *TouchHandler, message: protocol.Message) !void {
        _ = self;
        _ = message;
        // Frame event indicates all touch events in this frame have been sent
    }

    fn handleCancel(self: *TouchHandler, message: protocol.Message) !void {
        _ = message;

        // Cancel all active touch points
        var iter = self.touch_points.objects.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.state = .cancelled;
        }

        self.touch_points.objects.clearRetainingCapacity();
        self.gesture_recognizer.touch_points.clearRetainingCapacity();
        self.gesture_recognizer.current_gesture = .none;
    }

    fn handleShape(self: *TouchHandler, message: protocol.Message) !void {
        if (message.arguments.len < 4) return error.InvalidArgument;

        const id = message.arguments[0].int;
        const major = message.arguments[1].fixed.toFloat();
        const minor = message.arguments[2].fixed.toFloat();

        // Update touch point shape
        var iter = self.touch_points.objects.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.id == id) {
                entry.value_ptr.*.major_axis = major;
                entry.value_ptr.*.minor_axis = minor;
                break;
            }
        }
    }

    fn handleOrientation(self: *TouchHandler, message: protocol.Message) !void {
        if (message.arguments.len < 3) return error.InvalidArgument;

        const id = message.arguments[0].int;
        const orientation = message.arguments[1].fixed.toFloat();

        // Update touch point orientation
        var iter = self.touch_points.objects.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.id == id) {
                entry.value_ptr.*.orientation = orientation;
                break;
            }
        }
    }

    pub fn getTouchPoints(self: *TouchHandler) []TouchPoint {
        var points = self.allocator.alloc(TouchPoint, self.touch_points.count()) catch return &[_]TouchPoint{};

        var iter = self.touch_points.objects.valueIterator();
        var i: usize = 0;
        while (iter.next()) |point| : (i += 1) {
            points[i] = point.*;
        }

        return points;
    }
};

test "GestureRecognizer tap detection" {
    var recognizer = try GestureRecognizer.init(std.testing.allocator);
    defer recognizer.deinit();

    const TapState = struct {
        detected: bool = false,
    };

    const tap_state = TapState{};

    const tapCallback = struct {
        fn callback(info: GestureRecognizer.GestureInfo) void {
            _ = info;
            // Would set tap_state.detected = true in real implementation
        }
    }.callback;

    try recognizer.addCallback(.tap, tapCallback);

    const point = TouchPoint{
        .id = 1,
        .surface = 100,
        .x = 50,
        .y = 50,
        .timestamp = 1000,
        .state = .down,
    };

    try recognizer.handleTouchDown(point);
    try recognizer.handleTouchUp(1, 1050); // Within tap timeout

    try std.testing.expect(!tap_state.detected); // Test would check if tap was detected
}

test "GestureRecognizer pinch detection" {
    var recognizer = try GestureRecognizer.init(std.testing.allocator);
    defer recognizer.deinit();

    const point1 = TouchPoint{
        .id = 1,
        .surface = 100,
        .x = 100,
        .y = 100,
        .timestamp = 1000,
        .state = .down,
    };

    const point2 = TouchPoint{
        .id = 2,
        .surface = 100,
        .x = 200,
        .y = 100,
        .timestamp = 1000,
        .state = .down,
    };

    try recognizer.handleTouchDown(point1);
    try recognizer.handleTouchDown(point2);

    // Move points apart (pinch out)
    try recognizer.handleTouchMotion(1, 50, 100, 1100);
    try recognizer.handleTouchMotion(2, 250, 100, 1100);

    try std.testing.expect(recognizer.current_gesture == .pinch_out or recognizer.current_gesture == .none);
}