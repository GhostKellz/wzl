# wzl Listener API Migration Guide

## Overview

The wzl library now supports **backward-compatible callback-based listeners** alongside its modern event-driven architecture. This means existing code using `setListener()` will continue to work without modification.

## For Ghostshell Developers

### ✅ No Code Changes Required!

Your existing Ghostshell code should work as-is with the updated wzl library:

```zig
// This now works!
registry.setListener(*Context, registryListener, context);
deco_manager.setListener(*Context, decoManagerListener, context);
token.setListener(*Window, onActivationTokenEvent, self);
```

### Quick Start

1. **Update wzl dependency** (if using package manager):
   ```
   zig fetch --save https://github.com/ghostkellz/wzl/archive/main.tar.gz
   ```

2. **Rebuild your project**:
   ```bash
   zig build
   ```

3. **Test Wayland features**:
   - Window decorations should work
   - Activation tokens should work
   - Registry events should work

## API Reference

### Registry Listener

**Signature:**
```zig
pub fn setListener(
    self: *Registry,
    comptime T: type,
    comptime listener: struct {  // Note: listener must be comptime in Zig 0.16
        global: ?*const fn (data: ?*T, registry: *Registry, name: u32, interface_name: []const u8, version: u32) void = null,
        global_remove: ?*const fn (data: ?*T, registry: *Registry, name: u32) void = null,
    },
    data: ?*T,
) void
```

**Important:** The `listener` parameter must be known at compile time (comptime). This is a Zig 0.16 requirement for nested function capture.

**Example:**
```zig
const Context = struct {
    compositor_id: ?ObjectId = null,
};

fn onGlobal(ctx: ?*Context, registry: *Registry, name: u32, interface_name: []const u8, version: u32) void {
    if (std.mem.eql(u8, interface_name, "wl_compositor")) {
        const id = registry.bind(name, interface_name, version) catch return;
        ctx.?.compositor_id = id;
    }
}

fn onGlobalRemove(ctx: ?*Context, registry: *Registry, name: u32) void {
    std.debug.print("Global {} removed\n", .{name});
}

// Register callbacks - listener struct is comptime-known
var context = Context{};
var registry = try client.getRegistry();
registry.setListener(*Context, .{
    .global = onGlobal,
    .global_remove = onGlobalRemove,
}, &context);
```

### DecorationManager Listener

**Signature:**
```zig
pub fn setListener(
    self: *DecorationManager,
    comptime T: type,
    comptime listener: struct {  // Note: listener must be comptime in Zig 0.16
        mode: ?*const fn (data: ?*T, manager: *DecorationManager, surface_id: ObjectId, mode: u32) void = null,
    },
    data: ?*T,
) void
```

**Example:**
```zig
fn onDecorationMode(ctx: ?*MyWindow, manager: *DecorationManager, surface_id: ObjectId, mode: u32) void {
    const self = ctx orelse return;
    
    switch (mode) {
        1 => self.use_client_side_decorations = true,  // Client-side
        2 => self.use_client_side_decorations = false, // Server-side
        else => {},
    }
}

var deco_config = DecorationConfig{ .theme = Theme.defaultDark() };
var deco_manager = try DecorationManager.init(allocator, deco_config);
deco_manager.setListener(*MyWindow, .{
    .mode = onDecorationMode,
}, &my_window);
```

### ActivationToken Listener

**Signature:**
```zig
pub fn setListener(
    self: *ActivationToken,
    comptime T: type,
    comptime listener: struct {  // Note: listener must be comptime in Zig 0.16
        done: ?*const fn (data: ?*T, token: *ActivationToken, token_string: []const u8) void = null,
    },
    data: ?*T,
) void
```

**Example:**
```zig
fn onActivationTokenDone(ctx: ?*MyWindow, token: *ActivationToken, token_string: []const u8) void {
    const self = ctx orelse return;
    
    // Use the activation token to request focus
    std.debug.print("Got activation token: {s}\n", .{token_string});
    
    // Store or use the token as needed
    self.activation_token = allocator.dupe(u8, token_string) catch return;
}

var token = ActivationToken.init(allocator, &client, token_id);
token.setListener(*MyWindow, .{
    .done = onActivationTokenDone,
}, &my_window);

// Request activation
try token.setSurface(surface_id);
try token.setAppId("com.example.myapp");
try token.commit();
```

## Event Processing

### Automatic Dispatch

When you use `setListener()`, callbacks are automatically invoked when events arrive:

```zig
// Events are dispatched automatically during:
try client.dispatch();        // Single event
try client.roundtrip();       // All pending events until sync
try client.run();             // Continuous event loop
```

### Manual Event Handling (Advanced)

If you prefer explicit control, you can still use the event-driven API:

```zig
const message = try client.connection.receiveMessage();

// Manually process events
if (message.header.object_id == registry.object.id) {
    try registry.handleEvent(message);
    // Callbacks are invoked inside handleEvent()
}
```

## Architecture

### Hybrid Design

The wzl library supports both patterns simultaneously:

```
┌─────────────────────────────────────────┐
│         Your Application Code           │
│                                         │
│  Option 1:              Option 2:      │
│  Callbacks              Event Loop     │
│  (Easy)                 (Advanced)     │
└────────────┬──────────────┬─────────────┘
             │              │
             ▼              ▼
     ┌───────────────────────────────┐
     │   wzl Listener/Event Layer   │
     │                               │
     │  • setListener() registers    │
     │  • handleEvent() dispatches   │
     │  • Type-safe callbacks        │
     └──────────────┬────────────────┘
                    │
                    ▼
          ┌──────────────────┐
          │  Wayland Protocol │
          │  Message Handling │
          └──────────────────┘
```

### Performance

- **Zero overhead** when listeners not used
- **Single function call** per event when using callbacks
- **No allocations** for listener registration
- **Compile-time type checking** for safety

## Migration Checklist

For projects migrating from older wzl versions:

- [ ] Update wzl dependency to latest version
- [ ] Rebuild project: `zig build`
- [ ] Verify `setListener()` calls compile
- [ ] Test Wayland functionality:
  - [ ] Registry enumeration
  - [ ] Window decorations
  - [ ] Activation tokens
  - [ ] Other protocol features
- [ ] Consider async integration with zsync (optional)

## Common Patterns

### GTK Integration

If you're integrating wzl with GTK's main loop:

```zig
// Add Wayland event source to GTK main loop
fn waylandEventSourceFunc(user_data: ?*anyopaque) callconv(.C) c_int {
    const client = @as(*wzl.Client, @ptrCast(@alignCast(user_data)));
    
    // Process one event (callbacks invoked automatically)
    client.dispatch() catch return 0;
    
    return 1; // Continue watching
}

// Register with GTK
const source = g_unix_fd_add(
    client.connection.socket_fd,
    G_IO_IN,
    waylandEventSourceFunc,
    @ptrCast(&client),
);
```

### Terminal Emulator Integration

For terminal emulators like Ghostty/Ghostshell:

```zig
const TerminalContext = struct {
    surface: ?wzl.Surface = null,
    xdg_toplevel: ?wzl.XdgToplevel = null,
    width: u32 = 800,
    height: u32 = 600,
};

fn handleConfigure(
    ctx: ?*TerminalContext,
    toplevel: *wzl.XdgToplevel,
    width: i32,
    height: i32,
    states: []const u32,
) void {
    const self = ctx orelse return;
    
    if (width > 0 and height > 0) {
        self.width = @intCast(width);
        self.height = @intCast(height);
        
        // Resize terminal grid
        self.resizeTerminal(width, height);
    }
}

var term_ctx = TerminalContext{};
xdg_toplevel.setListener(*TerminalContext, .{
    .configure = handleConfigure,
}, &term_ctx);
```

## Troubleshooting

### Listener Not Called

**Problem:** Callbacks aren't being invoked
**Solution:** Ensure you're processing events:
```zig
// Add event processing loop
while (running) {
    try client.dispatch(); // This invokes callbacks
}
```

### Type Mismatch

**Problem:** Compiler error about type mismatch in callback
**Solution:** Ensure your context type matches:
```zig
// Correct: Types match
ctx.setListener(*MyType, .{ .callback = myFunc }, &my_data);

// Incorrect: Type mismatch
ctx.setListener(*OtherType, .{ .callback = myFunc }, &my_data);
```

### Multiple Listeners

**Problem:** Only one callback works
**Solution:** Register all callbacks at once:
```zig
registry.setListener(*Context, .{
    .global = onGlobal,           // Both registered
    .global_remove = onRemove,    // together
}, &context);
```

## Advanced Topics

### Combining Patterns

You can mix listeners with manual event handling:

```zig
// Some objects use listeners
registry.setListener(*Context, .{ .global = onGlobal }, &ctx);

// Others use manual handling
while (true) {
    const msg = try client.dispatch();
    
    // Custom processing for specific cases
    if (special_condition) {
        try customEventHandler(msg);
    }
}
```

### Async Integration

With zsync runtime:

```zig
var runtime = try zsync.Runtime.init(allocator);
defer runtime.deinit();

var client = try wzl.Client.init(allocator, .{ .runtime = &runtime });
defer client.deinit();

// Listeners work seamlessly with async
registry.setListener(*Context, .{ .global = onGlobal }, &ctx);

// Async event loop
try runtime.spawn(struct {
    fn eventLoop(c: *wzl.Client) !void {
        while (true) {
            try c.dispatch(); // Callbacks invoked asynchronously
        }
    }
}.eventLoop, .{&client});
```

## Additional Resources

- [wzl Examples](../examples/) - Complete working examples
- [API Documentation](../docs/api/) - Detailed API reference
- [Architecture Guide](../docs/ARCHITECTURE.md) - System design
- [Ghostshell Integration](WAYLAND_FIX.md) - Specific Ghostshell notes

## Support

If you encounter issues:
1. Check this migration guide
2. Review example code in `examples/`
3. Ensure wzl version is up to date
4. File an issue on GitHub with details

## Version History

- **v0.0.0** (October 2025): Added backward-compatible listener API
  - Registry listener support
  - DecorationManager listener support
  - ActivationToken implementation and listener
  - Zero-overhead callback dispatch
  - Full backward compatibility

---

**Status:** ✅ Production Ready - Backward compatible with existing code
