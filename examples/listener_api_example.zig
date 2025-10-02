//! Example demonstrating the backward-compatible listener API in wzl
//! This shows how to use callback-based event handling for easier integration

const std = @import("std");
const wzl = @import("wzl");

// Context structure for your application
const AppContext = struct {
    allocator: std.mem.Allocator,
    compositor_name: ?[]const u8 = null,
    compositor_id: ?wzl.ObjectId = null,
    
    pub fn init(allocator: std.mem.Allocator) AppContext {
        return AppContext{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AppContext) void {
        if (self.compositor_name) |name| {
            self.allocator.free(name);
        }
    }
};

// Registry event callbacks
fn onRegistryGlobal(
    ctx: ?*AppContext,
    registry: *wzl.client.Registry,
    name: u32,
    interface_name: []const u8,
    version: u32,
) void {
    _ = registry;
    
    const context = ctx orelse return;
    
    std.debug.print("Registry global: name={} interface={s} version={}\n", .{
        name,
        interface_name,
        version,
    });
    
    // Example: Bind to compositor when we see it
    if (std.mem.eql(u8, interface_name, "wl_compositor")) {
        context.compositor_name = context.allocator.dupe(u8, interface_name) catch return;
        
        // In real code, you would bind here:
        // const compositor_id = registry.bind(name, interface_name, version) catch return;
        // context.compositor_id = compositor_id;
    }
}

fn onRegistryGlobalRemove(
    ctx: ?*AppContext,
    registry: *wzl.client.Registry,
    name: u32,
) void {
    _ = registry;
    _ = ctx;
    
    std.debug.print("Registry global removed: name={}\n", .{name});
}

// Decoration manager callback
fn onDecorationMode(
    ctx: ?*AppContext,
    manager: *wzl.DecorationManager,
    surface_id: wzl.ObjectId,
    mode: u32,
) void {
    _ = manager;
    _ = ctx;
    
    std.debug.print("Decoration mode changed: surface={} mode={}\n", .{
        surface_id,
        mode,
    });
}

// Activation token callback
fn onActivationTokenDone(
    ctx: ?*AppContext,
    token: *wzl.ActivationToken,
    token_string: []const u8,
) void {
    _ = token;
    _ = ctx;
    
    std.debug.print("Activation token received: {s}\n", .{token_string});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize your application context
    var app_context = AppContext.init(allocator);
    defer app_context.deinit();
    
    // Create wzl client (this example doesn't actually connect)
    std.debug.print("wzl Listener API Example\n", .{});
    std.debug.print("========================\n\n", .{});
    
    // Example 1: Registry with listener callbacks
    std.debug.print("Example 1: Registry Listener\n", .{});
    std.debug.print("-----------------------------\n", .{});
    std.debug.print("Usage:\n", .{});
    std.debug.print("  var registry = try client.getRegistry();\n", .{});
    std.debug.print("  registry.setListener(*AppContext, .{{\n", .{});
    std.debug.print("      .global = onRegistryGlobal,\n", .{});
    std.debug.print("      .global_remove = onRegistryGlobalRemove,\n", .{});
    std.debug.print("  }}, &app_context);\n\n", .{});
    
    // Example 2: DecorationManager with listener
    std.debug.print("Example 2: DecorationManager Listener\n", .{});
    std.debug.print("--------------------------------------\n", .{});
    std.debug.print("Usage:\n", .{});
    std.debug.print("  var deco_config = wzl.DecorationConfig{{ ... }};\n", .{});
    std.debug.print("  var deco_manager = try wzl.DecorationManager.init(allocator, deco_config);\n", .{});
    std.debug.print("  deco_manager.setListener(*AppContext, .{{\n", .{});
    std.debug.print("      .mode = onDecorationMode,\n", .{});
    std.debug.print("  }}, &app_context);\n\n", .{});
    
    // Example 3: ActivationToken with listener
    std.debug.print("Example 3: ActivationToken Listener\n", .{});
    std.debug.print("------------------------------------\n", .{});
    std.debug.print("Usage:\n", .{});
    std.debug.print("  var token = wzl.ActivationToken.init(allocator, &client, token_id);\n", .{});
    std.debug.print("  token.setListener(*AppContext, .{{\n", .{});
    std.debug.print("      .done = onActivationTokenDone,\n", .{});
    std.debug.print("  }}, &app_context);\n\n", .{});
    
    // Demonstrate the callback signatures
    std.debug.print("Callback Signatures:\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("Registry global: fn(ctx: ?*T, registry: *Registry, name: u32, interface: []const u8, version: u32) void\n", .{});
    std.debug.print("Registry remove: fn(ctx: ?*T, registry: *Registry, name: u32) void\n", .{});
    std.debug.print("Decoration mode: fn(ctx: ?*T, manager: *DecorationManager, surface_id: ObjectId, mode: u32) void\n", .{});
    std.debug.print("Activation done: fn(ctx: ?*T, token: *ActivationToken, token_string: []const u8) void\n", .{});
    
    std.debug.print("\n✅ All listener patterns available!\n", .{});
}
