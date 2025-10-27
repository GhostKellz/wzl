# wzl Error Handling Guide

## Overview

wzl uses Zig's error handling system for robust, explicit error management. This document describes error handling patterns, best practices, and recovery strategies used throughout the library.

---

## Error Types

### Core Protocol Errors

```zig
pub const ProtocolError = error{
    /// Object ID is invalid (zero or out of range)
    InvalidObject,

    /// Argument validation failed (too large, invalid format)
    InvalidArgument,

    /// Buffer too small for serialization
    BufferTooSmall,

    /// Buffer overflow during message construction
    BufferOverflow,

    /// Connection to Wayland server lost
    ConnectionLost,

    /// Protocol violation detected
    ProtocolError,

    /// Version negotiation failed
    VersionMismatch,
};
```

### Memory Errors

```zig
pub const MemoryError = error{
    /// Out of memory
    OutOfMemory,

    /// Memory leak detected
    MemoryLeak,

    /// Double-free attempt
    DoubleFree,

    /// Use-after-free detected
    UseAfterFree,
};
```

### Connection Errors

```zig
pub const ConnectionError = error{
    /// Could not connect to Wayland display
    ConnectionFailed,

    /// Socket creation failed
    SocketError,

    /// I/O operation failed
    IOError,

    /// Connection timeout
    Timeout,

    /// Display server not found
    DisplayNotFound,
};
```

---

## Error Handling Patterns

### Pattern 1: Try-Catch with Recovery

```zig
const message = try protocol.Message.init(
    allocator,
    object_id,
    opcode,
    &arguments,
);
```

**When to use**: When the error is unexpected and should propagate up the call stack.

**Recovery**: None - error propagates to caller.

---

### Pattern 2: Catch with Fallback

```zig
const message = protocol.Message.init(
    allocator,
    object_id,
    opcode,
    &arguments,
) catch |err| {
    std.log.err("Failed to create message: {}", .{err});
    return default_message;
};
```

**When to use**: When there's a reasonable fallback or default value.

**Recovery**: Use default value, log error, continue execution.

---

### Pattern 3: Error Defer Cleanup

```zig
fn allocateResources(allocator: Allocator) !Resource {
    const buffer = try allocator.alloc(u8, 1024);
    errdefer allocator.free(buffer);

    const data = try allocator.create(Data);
    errdefer allocator.destroy(data);

    // If this fails, both buffer and data are cleaned up
    try initializeData(data, buffer);

    return Resource{
        .buffer = buffer,
        .data = data,
    };
}
```

**When to use**: When allocating multiple resources that need cleanup on error.

**Recovery**: Automatic cleanup via `errdefer`, error propagates.

---

### Pattern 4: Retry Logic

```zig
fn connectWithRetry(max_attempts: u32) !void {
    var attempts: u32 = 0;

    while (attempts < max_attempts) : (attempts += 1) {
        connection.connect() catch |err| {
            if (err == error.Timeout and attempts + 1 < max_attempts) {
                std.time.sleep(1 * std.time.ns_per_s);
                continue;
            }
            return err;
        };

        return; // Success
    }

    return error.ConnectionFailed;
}
```

**When to use**: For transient errors like network timeouts.

**Recovery**: Retry with exponential backoff, give up after max attempts.

---

### Pattern 5: Graceful Degradation

```zig
fn initializeWithFallback(allocator: Allocator) !Client {
    var client = Client{};

    // Try hardware acceleration
    client.renderer = Renderer.initVulkan(allocator) catch |err| {
        std.log.warn("Vulkan init failed ({}), trying EGL", .{err});

        // Fall back to EGL
        Renderer.initEGL(allocator) catch |egl_err| {
            std.log.warn("EGL init failed ({}), using software", .{egl_err});

            // Fall back to software renderer
            try Renderer.initSoftware(allocator)
        }
    };

    return client;
}
```

**When to use**: When there are multiple acceptable implementations.

**Recovery**: Try preferred option, fall back to alternatives.

---

## Error Handling by Module

### Protocol Layer

**Errors**: `InvalidObject`, `InvalidArgument`, `BufferTooSmall`

**Strategy**: Fail fast - protocol violations should not be recovered from.

```zig
// Do NOT catch protocol errors - let them propagate
const message = try protocol.Message.init(allocator, id, opcode, args);
```

---

### Connection Layer

**Errors**: `ConnectionLost`, `IOError`, `Timeout`

**Strategy**: Retry transient errors, propagate fatal errors.

```zig
fn sendMessage(self: *Connection, message: Message) !void {
    self.socket.write(message.data) catch |err| {
        switch (err) {
            error.WouldBlock => {
                // Transient - retry
                std.time.sleep(1 * std.time.ns_per_ms);
                return self.sendMessage(message);
            },
            error.ConnectionResetByPeer => {
                // Fatal - mark connection dead and propagate
                self.state = .disconnected;
                return error.ConnectionLost;
            },
            else => return err,
        }
    };
}
```

---

### Memory Layer

**Errors**: `OutOfMemory`

**Strategy**: Clean up and propagate - memory errors are usually fatal.

```zig
fn allocateBuffer(self: *Client, size: usize) ![]u8 {
    const buffer = self.allocator.alloc(u8, size) catch |err| {
        // Try to free cached buffers
        self.freeCache();

        // Retry once
        return self.allocator.alloc(u8, size) catch {
            std.log.err("OOM: failed to allocate {} bytes", .{size});
            return err;
        };
    };

    return buffer;
}
```

---

## Error Recovery Strategies

### 1. Automatic Retry

**Use for**: Network timeouts, temporary resource unavailability

**Pattern**:
```zig
var attempts: u32 = 0;
while (attempts < MAX_RETRIES) : (attempts += 1) {
    operation() catch |err| {
        if (shouldRetry(err) and attempts + 1 < MAX_RETRIES) {
            continue;
        }
        return err;
    };
    return; // Success
}
return error.MaxRetriesExceeded;
```

---

### 2. Fallback to Alternative

**Use for**: Feature availability, hardware acceleration

**Pattern**:
```zig
const preferred = tryPreferred() catch {
    return tryFallback();
};
return preferred;
```

---

### 3. Partial Success

**Use for**: Batch operations where some can fail

**Pattern**:
```zig
var errors = std.ArrayList(Error).init(allocator);
defer errors.deinit();

for (items) |item| {
    processItem(item) catch |err| {
        try errors.append(.{ .item = item, .error = err });
        continue; // Process remaining items
    };
}

if (errors.items.len > 0) {
    return error.PartialFailure; // Caller can check errors list
}
```

---

### 4. Resource Cleanup

**Use for**: Always - prevent leaks

**Pattern**:
```zig
fn complexOperation(allocator: Allocator) !Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit(); // Always cleanup

    const temp_allocator = arena.allocator();

    // Use temp_allocator for temporary allocations
    // All cleaned up automatically

    const result = try performWork(temp_allocator);

    // Copy result to parent allocator before arena is destroyed
    return try result.clone(allocator);
}
```

---

## Testing Error Paths

### 1. Inject Errors

```zig
test "handle out of memory" {
    var failing_allocator = testing.FailingAllocator.init(
        testing.allocator,
        .{ .fail_index = 0 }
    );

    const result = operation(failing_allocator.allocator());
    try testing.expectError(error.OutOfMemory, result);
}
```

---

### 2. Verify Cleanup

```zig
test "cleanup on error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok); // No leaks!
    }

    _ = operationThatFails(gpa.allocator());
}
```

---

### 3. Test All Error Paths

```zig
test "all error conditions" {
    try testing.expectError(error.InvalidObject, createWithBadId());
    try testing.expectError(error.BufferTooSmall, serializeToSmallBuffer());
    try testing.expectError(error.OutOfMemory, allocateWithFailingAllocator());
}
```

---

## Best Practices

### ✅ DO

1. **Use `try` for unexpected errors**
   ```zig
   const message = try protocol.Message.init(...);
   ```

2. **Use `errdefer` for resource cleanup**
   ```zig
   const buf = try allocator.alloc(u8, size);
   errdefer allocator.free(buf);
   ```

3. **Document error conditions**
   ```zig
   /// Returns error.InvalidObject if object_id is zero
   /// Returns error.OutOfMemory if allocation fails
   fn init(...) !Message { ... }
   ```

4. **Test error paths**
   ```zig
   test "handles invalid input" {
       try testing.expectError(error.Invalid, badInput());
   }
   ```

5. **Log errors for debugging**
   ```zig
   operation() catch |err| {
       std.log.err("Operation failed: {}", .{err});
       return err;
   };
   ```

---

### ❌ DON'T

1. **Don't ignore errors**
   ```zig
   // BAD - error lost!
   operation() catch {};

   // GOOD
   operation() catch |err| {
       std.log.warn("Optional operation failed: {}", .{err});
       // Continue with default behavior
   };
   ```

2. **Don't mix error and optional semantics**
   ```zig
   // BAD - ambiguous
   fn get(id: u32) ?!Value

   // GOOD - clear semantics
   fn get(id: u32) !?Value  // Can fail OR return null
   ```

3. **Don't return generic errors**
   ```zig
   // BAD - not descriptive
   return error.Error;

   // GOOD - specific
   return error.InvalidObject;
   ```

4. **Don't leak resources on error**
   ```zig
   // BAD
   const buf = try allocator.alloc(u8, size);
   try operation(); // If this fails, buf leaks!

   // GOOD
   const buf = try allocator.alloc(u8, size);
   errdefer allocator.free(buf);
   try operation();
   ```

---

## Error Debugging

### Enable Debug Logging

```zig
// In your application
pub const std_options = struct {
    pub const log_level = .debug;
};
```

### Use Stack Traces

```zig
// Zig provides stack traces on error return
pub fn main() !void {
    operation() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        std.debug.dumpCurrentStackTrace(@returnAddress());
        return err;
    };
}
```

### Memory Leak Detection

```bash
# Run with GeneralPurposeAllocator
zig build test

# Or use Valgrind
valgrind --leak-check=full ./zig-out/bin/test
```

---

## Error Guidelines by Priority

### CRITICAL Errors (Must Handle)
- `OutOfMemory` - Can't proceed without memory
- `InvalidObject` - Protocol corruption
- `ConnectionLost` - Can't communicate
- `ProtocolError` - Wayland violation

**Action**: Log, cleanup, propagate or terminate

---

### HIGH Priority Errors (Should Handle)
- `Timeout` - Network/IPC issues
- `InvalidArgument` - Input validation failed
- `BufferTooSmall` - Insufficient buffer
- `IOError` - I/O operation failed

**Action**: Retry or fallback, then propagate if unsuccessful

---

### MEDIUM Priority Errors (May Handle)
- `VersionMismatch` - Feature not available
- `DisplayNotFound` - Wrong environment
- `SocketError` - Connection setup failed

**Action**: Log, try alternative, or propagate

---

## Summary

wzl error handling philosophy:

1. **Fail fast on protocol errors** - Corruption is unrecoverable
2. **Retry transient errors** - Network/IPC issues may resolve
3. **Clean up resources always** - Use `defer` and `errdefer`
4. **Provide meaningful errors** - Specific error types, clear names
5. **Test error paths** - Every error condition has a test
6. **Document error conditions** - Callers need to know what can fail

For more examples, see the test files:
- `tests/error_handling_test.zig` - Error pattern examples
- `tests/memory_leak_test.zig` - Memory safety patterns
- `tests/stress_test.zig` - Error handling under pressure

---

**Last Updated**: 2025-10-27
