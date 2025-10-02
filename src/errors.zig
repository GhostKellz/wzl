const std = @import("std");

/// Protocol error types following Wayland specification
pub const ProtocolError = error{
    /// Invalid object ID in request/event
    InvalidObject,
    /// Invalid method/event opcode for interface
    InvalidMethod,
    /// Invalid argument type or value
    InvalidArgument,
    /// Protocol version mismatch
    VersionMismatch,
    /// Out of memory for protocol operations
    OutOfMemory,
    /// Broken connection or socket error
    BrokenPipe,
    /// Permission denied for operation
    PermissionDenied,
    /// Resource temporarily unavailable
    WouldBlock,
    /// Buffer overflow during serialization
    BufferOverflow,
    /// Malformed message received
    MalformedMessage,
    /// Object already exists
    ObjectExists,
    /// Required interface not available
    NoInterface,
    /// Display connection error
    DisplayError,
    /// Authentication failed
    AuthenticationFailed,
};

/// Connection-specific errors
pub const ConnectionError = error{
    ConnectionRefused,
    ConnectionAborted,
    ConnectionReset,
    NetworkUnreachable,
    HostUnreachable,
    Timeout,
    AddressInUse,
    SocketNotConnected,
    PipeBroken,
};

/// Buffer management errors
pub const BufferError = error{
    InvalidSize,
    InvalidFormat,
    InvalidStride,
    MmapFailed,
    ShmError,
    DmaBufError,
    AllocationFailed,
    BufferBusy,
    BufferDestroyed,
};

/// Input handling errors
pub const InputError = error{
    InvalidKeymap,
    InvalidDevice,
    DeviceRemoved,
    InvalidCoordinates,
    InvalidButton,
    InvalidAxis,
    GrabDenied,
    FocusLost,
};

/// Rendering errors
pub const RenderError = error{
    EglInitFailed,
    VulkanInitFailed,
    InvalidContext,
    SwapchainError,
    PresentationError,
    InvalidSurface,
    TextureCreationFailed,
    ShaderCompilationFailed,
    InvalidPixelFormat,
};

/// Combined error set for the entire library
pub const WzlError = ProtocolError || ConnectionError || BufferError || InputError || RenderError;

/// Error context for detailed error information
pub const ErrorContext = struct {
    code: WzlError,
    message: []const u8,
    object_id: ?u32 = null,
    interface: ?[]const u8 = null,
    method: ?[]const u8 = null,
    timestamp: i64,
    severity: Severity,

    pub const Severity = enum {
        debug,
        info,
        warning,
        err,
        critical,
    };

    pub fn init(code: WzlError, message: []const u8, severity: Severity) ErrorContext {
        return .{
            .code = code,
            .message = message,
            .timestamp = std.time.milliTimestamp(),
            .severity = severity,
        };
    }

    pub fn withObject(self: ErrorContext, object_id: u32, interface: []const u8) ErrorContext {
        var ctx = self;
        ctx.object_id = object_id;
        ctx.interface = interface;
        return ctx;
    }

    pub fn withMethod(self: ErrorContext, method: []const u8) ErrorContext {
        var ctx = self;
        ctx.method = method;
        return ctx;
    }

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{s}] {s}: {s}", .{
            @tagName(self.severity),
            @errorName(self.code),
            self.message,
        });

        if (self.object_id) |id| {
            if (self.interface) |iface| {
                try writer.print(" (object: {}@{})", .{ iface, id });
            } else {
                try writer.print(" (object: {})", .{id});
            }
        }

        if (self.method) |method| {
            try writer.print(" in method: {s}", .{method});
        }
    }
};

/// Error handler with recovery strategies
pub const ErrorHandler = struct {
    allocator: std.mem.Allocator,
    log_errors: bool,
    max_retries: u32,
    error_callback: ?*const fn (ErrorContext) void,
    recovery_strategies: std.AutoHashMap(WzlError, RecoveryStrategy),

    pub const RecoveryStrategy = enum {
        retry,
        reconnect,
        ignore,
        fatal,
        custom,
    };

    pub fn init(allocator: std.mem.Allocator) !ErrorHandler {
        var handler = ErrorHandler{
            .allocator = allocator,
            .log_errors = true,
            .max_retries = 3,
            .error_callback = null,
            .recovery_strategies = std.AutoHashMap(WzlError, RecoveryStrategy).init(allocator),
        };

        // Set default recovery strategies
        try handler.recovery_strategies.put(error.WouldBlock, .retry);
        try handler.recovery_strategies.put(error.ConnectionReset, .reconnect);
        try handler.recovery_strategies.put(error.BrokenPipe, .reconnect);
        try handler.recovery_strategies.put(error.Timeout, .retry);
        try handler.recovery_strategies.put(error.BufferBusy, .retry);

        return handler;
    }

    pub fn deinit(self: *ErrorHandler) void {
        self.recovery_strategies.deinit();
    }

    pub fn handle(self: *ErrorHandler, context: ErrorContext) !void {
        // Log error if enabled
        if (self.log_errors) {
            std.log.scoped(.wzl).err("{}", .{context});
        }

        // Call custom error callback if set
        if (self.error_callback) |callback| {
            callback(context);
        }

        // Apply recovery strategy
        if (self.recovery_strategies.get(context.code)) |strategy| {
            switch (strategy) {
                .retry => return error.ShouldRetry,
                .reconnect => return error.ShouldReconnect,
                .ignore => {},
                .fatal => return context.code,
                .custom => {
                    if (self.error_callback == null) {
                        return context.code;
                    }
                },
            }
        } else {
            // No specific strategy, propagate error
            return context.code;
        }
    }

    pub fn setStrategy(self: *ErrorHandler, err: WzlError, strategy: RecoveryStrategy) !void {
        try self.recovery_strategies.put(err, strategy);
    }

    pub fn setCallback(self: *ErrorHandler, callback: *const fn (ErrorContext) void) void {
        self.error_callback = callback;
    }
};

/// Result type for operations that may fail with context
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ErrorContext,

        pub fn unwrap(self: @This()) !T {
            return switch (self) {
                .ok => |val| val,
                .err => |ctx| ctx.code,
            };
        }

        pub fn isOk(self: @This()) bool {
            return self == .ok;
        }

        pub fn isErr(self: @This()) bool {
            return self == .err;
        }

        pub fn mapErr(self: @This(), comptime f: fn (ErrorContext) ErrorContext) @This() {
            return switch (self) {
                .ok => self,
                .err => |ctx| .{ .err = f(ctx) },
            };
        }
    };
}

/// Thread-safe error accumulator for collecting multiple errors
pub const ErrorAccumulator = struct {
    mutex: std.Thread.Mutex,
    errors: std.ArrayList(ErrorContext),
    max_errors: usize,

    pub fn init(allocator: std.mem.Allocator, max_errors: usize) ErrorAccumulator {
        _ = allocator; // Unused in Zig 0.16 ArrayList initialization
        return .{
            .mutex = std.Thread.Mutex{},
            .errors = std.ArrayList(ErrorContext){},
            .max_errors = max_errors,
        };
    }

    pub fn deinit(self: *ErrorAccumulator) void {
        self.errors.deinit(self.allocator);
    }

    pub fn add(self: *ErrorAccumulator, context: ErrorContext) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.errors.items.len >= self.max_errors) {
            // Remove oldest error
            _ = self.errors.orderedRemove(0);
        }

        try self.errors.append(self.allocator, context);
    }

    pub fn clear(self: *ErrorAccumulator) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.errors.clearRetainingCapacity();
    }

    pub fn getErrors(self: *ErrorAccumulator, allocator: std.mem.Allocator) ![]ErrorContext {
        self.mutex.lock();
        defer self.mutex.unlock();

        const copy = try allocator.alloc(ErrorContext, self.errors.items.len);
        @memcpy(copy, self.errors.items);
        return copy;
    }

    pub fn hasErrors(self: *ErrorAccumulator) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.errors.items.len > 0;
    }

    pub fn count(self: *ErrorAccumulator) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.errors.items.len;
    }
};

test "ErrorContext creation and formatting" {
    const ctx = ErrorContext.init(error.InvalidObject, "Object not found", .err)
        .withObject(42, "wl_surface")
        .withMethod("commit");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ctx.format("", .{}, stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "InvalidObject") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wl_surface") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "42") != null);
}

test "ErrorHandler with recovery strategies" {
    var handler = try ErrorHandler.init(std.testing.allocator);
    defer handler.deinit();

    try handler.setStrategy(error.InvalidObject, .fatal);

    const ctx = ErrorContext.init(error.WouldBlock, "Resource busy", .warning);
    const result = handler.handle(ctx);

    try std.testing.expectError(error.ShouldRetry, result);
}

test "Result type operations" {
    const MyResult = Result(u32);

    const ok_result = MyResult{ .ok = 42 };
    try std.testing.expect(ok_result.isOk());
    try std.testing.expect(!ok_result.isErr());
    try std.testing.expectEqual(@as(u32, 42), try ok_result.unwrap());

    const err_ctx = ErrorContext.init(error.InvalidArgument, "Bad value", .err);
    const err_result = MyResult{ .err = err_ctx };
    try std.testing.expect(!err_result.isOk());
    try std.testing.expect(err_result.isErr());
    try std.testing.expectError(error.InvalidArgument, err_result.unwrap());
}

test "ErrorAccumulator thread safety" {
    var acc = ErrorAccumulator.init(std.testing.allocator, 10);
    defer acc.deinit();

    const ctx1 = ErrorContext.init(error.InvalidObject, "Error 1", .err);
    const ctx2 = ErrorContext.init(error.InvalidMethod, "Error 2", .warning);

    try acc.add(ctx1);
    try acc.add(ctx2);

    try std.testing.expectEqual(@as(usize, 2), acc.count());
    try std.testing.expect(acc.hasErrors());

    const errors = try acc.getErrors(std.testing.allocator);
    defer std.testing.allocator.free(errors);

    try std.testing.expectEqual(@as(usize, 2), errors.len);

    acc.clear();
    try std.testing.expectEqual(@as(usize, 0), acc.count());
}