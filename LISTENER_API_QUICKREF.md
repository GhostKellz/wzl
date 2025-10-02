# wzl Listener API Quick Reference

## Important Note for Zig 0.16

⚠️ The `listener` parameter must be **comptime-known** in Zig 0.16. This means you must pass a literal struct with function pointers, not a runtime-computed value.

## Registry Events

```zig
var registry = try client.getRegistry();
registry.setListener(*MyContext, .{  // ✅ Literal struct is comptime
    .global = onGlobal,
    .global_remove = onRemove,
}, &my_context);

fn onGlobal(
    ctx: ?*MyContext,
    registry: *wzl.client.Registry,
    name: u32,
    interface_name: []const u8,
    version: u32,
) void {
    // Handle global announcement
}

fn onRemove(
    ctx: ?*MyContext,
    registry: *wzl.client.Registry,
    name: u32,
) void {
    // Handle global removal
}
```

## Decoration Manager Events

```zig
var deco_config = wzl.DecorationConfig{ .theme = wzl.Theme.defaultDark() };
var deco_manager = try wzl.DecorationManager.init(allocator, deco_config);
deco_manager.setListener(*MyContext, .{
    .mode = onDecoMode,
}, &my_context);

fn onDecoMode(
    ctx: ?*MyContext,
    manager: *wzl.DecorationManager,
    surface_id: wzl.ObjectId,
    mode: u32,
) void {
    // mode: 1 = client-side, 2 = server-side
}
```

## Activation Token Events

```zig
var token = wzl.ActivationToken.init(allocator, &client, token_id);
token.setListener(*MyContext, .{
    .done = onTokenDone,
}, &my_context);

// Set token properties
try token.setSurface(surface_id);
try token.setAppId("com.example.app");
try token.commit();

fn onTokenDone(
    ctx: ?*MyContext,
    token: *wzl.ActivationToken,
    token_string: []const u8,
) void {
    // Use token_string to request focus
}
```

## Event Processing

```zig
// Single event
try client.dispatch();

// All pending events
try client.roundtrip();

// Continuous loop
try client.run();
```

## Imports

```zig
const std = @import("std");
const wzl = @import("wzl");

// Available types
const Client = wzl.Client;
const Registry = wzl.client.Registry;
const DecorationManager = wzl.DecorationManager;
const ActivationToken = wzl.ActivationToken;
const ObjectId = wzl.ObjectId;
```

## Common Patterns

### Bind Compositor
```zig
fn onGlobal(ctx: ?*MyCtx, registry: *Registry, name: u32, iface: []const u8, ver: u32) void {
    if (std.mem.eql(u8, iface, "wl_compositor")) {
        const id = registry.bind(name, iface, ver) catch return;
        ctx.?.compositor_id = id;
    }
}
```

### Handle Window Resize
```zig
fn onConfigure(ctx: ?*MyWindow, toplevel: *wzl.XdgToplevel, w: i32, h: i32, states: []u32) void {
    if (w > 0 and h > 0) {
        ctx.?.resize(@intCast(w), @intCast(h));
    }
}
```

### GTK Integration
```zig
fn waylandEventSource(user_data: ?*anyopaque) callconv(.C) c_int {
    const client = @as(*wzl.Client, @ptrCast(@alignCast(user_data)));
    client.dispatch() catch return 0;
    return 1; // Keep watching
}

g_unix_fd_add(client.connection.socket_fd, G_IO_IN, waylandEventSource, &client);
```

## Zero-Overhead Design

- ✅ No allocations for listeners
- ✅ Single function call per event
- ✅ Compile-time type safety
- ✅ Zero cost when not used

## Documentation

- Full guide: `docs/LISTENER_API_MIGRATION.md`
- Examples: `examples/listener_api_example.zig`
- Architecture: `docs/ARCHITECTURE.md`
- Fix details: `WAYLAND_FIX.md`
