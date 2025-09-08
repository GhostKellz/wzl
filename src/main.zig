const std = @import("std");
const wzl = @import("wzl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print("wzl (Wayland Zig Library) - Example Application\n", .{});
    
    // Print library information
    try wzl.bufferedPrint();
    
    // Example: Try to create a client (this will fail if no Wayland compositor is running)
    if (std.posix.getenv("WAYLAND_DISPLAY")) |_| {
        std.debug.print("Wayland display detected. Creating client...\n", .{});
        
        var client = wzl.Client.init(allocator, .{}) catch |err| {
            std.debug.print("Failed to create Wayland client: {}\n", .{err});
            return;
        };
        defer client.deinit();
        
        client.connect() catch |err| {
            std.debug.print("Failed to connect to Wayland display: {}\n", .{err});
            return;
        };
        
        std.debug.print("Successfully connected to Wayland display!\n", .{});
        
        // Get registry and perform a roundtrip
        _ = client.getRegistry() catch |err| {
            std.debug.print("Failed to get registry: {}\n", .{err});
            return;
        };
        
        client.roundtrip() catch |err| {
            std.debug.print("Roundtrip failed: {}\n", .{err});
            return;
        };
        
        std.debug.print("Registry obtained and roundtrip completed!\n", .{});
        
    } else {
        std.debug.print("No Wayland display found (WAYLAND_DISPLAY not set)\n", .{});
        std.debug.print("This is normal if you're not running under Wayland.\n", .{});
    }
}

test "simple test" {
    var list = std.ArrayList(i32){};
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
