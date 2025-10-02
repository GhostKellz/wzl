const std = @import("std");
const wzl = @import("wzl");

// Basic Wayland client example
// Creates a simple window and handles basic events

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print("WZL Basic Client Example\n");
    std.debug.print("========================\n");

    // Initialize client
    var client = try wzl.Client.init(allocator);
    defer client.deinit();

    // Connect to Wayland display
    const display_name = std.posix.getenv("WAYLAND_DISPLAY");
    try client.connect(display_name);

    std.debug.print("Connected to Wayland display: {s}\n", .{display_name orelse "wayland-0"});

    // Get registry
    const registry = try client.getRegistry();

    // Wait for globals to be advertised
    try client.roundtrip();

    std.debug.print("Available globals:\n");
    const globals = registry.listGlobals();
    for (globals) |global| {
        std.debug.print("  {s} v{}\n", .{ global.interface, global.version });
    }

    // Bind to compositor
    const compositor_global = registry.getGlobal("wl_compositor") orelse {
        std.debug.print("No wl_compositor found!\n");
        return;
    };

    const compositor = try registry.bind(wzl.Compositor, compositor_global.name, 6);
    defer compositor.deinit();

    std.debug.print("Bound to wl_compositor\n");

    // Create surface
    const surface = try compositor.createSurface();
    defer surface.deinit();

    std.debug.print("Created wl_surface\n");

    // Bind to shell (if available)
    if (registry.getGlobal("xdg_wm_base")) |shell_global| {
        const xdg_wm_base = try registry.bind(wzl.XdgWmBase, shell_global.name, 1);
        defer xdg_wm_base.deinit();

        const xdg_surface = try xdg_wm_base.getXdgSurface(surface);
        defer xdg_surface.deinit();

        const xdg_toplevel = try xdg_surface.getToplevel();
        defer xdg_toplevel.deinit();

        // Configure window
        try xdg_toplevel.setTitle("WZL Basic Client");
        try xdg_toplevel.setAppId("org.wzl.basic-client");

        std.debug.print("Created XDG shell window\n");

        // Commit surface
        try surface.commit();
    }

    // Bind to shared memory
    if (registry.getGlobal("wl_shm")) |shm_global| {
        const shm = try registry.bind(wzl.Shm, shm_global.name, 2);
        defer shm.deinit();

        // Create buffer
        const width: u32 = 640;
        const height: u32 = 480;
        const stride: u32 = width * 4; // 4 bytes per pixel (ARGB8888)
        const size: usize = stride * height;

        const shm_pool = try shm.createPool(size);
        defer shm_pool.deinit();

        const buffer = try shm_pool.createBuffer(0, width, height, stride, .argb8888);
        defer buffer.deinit();

        // Map buffer and draw
        const pixels = try shm_pool.map();
        defer shm_pool.unmap();

        // Fill with gradient
        for (0..height) |y| {
            for (0..width) |x| {
                const pixel_offset = y * stride + x * 4;
                const r: u8 = @intCast((x * 255) / width);
                const g: u8 = @intCast((y * 255) / height);
                const b: u8 = 128;
                const a: u8 = 255;

                pixels[pixel_offset + 0] = b; // B
                pixels[pixel_offset + 1] = g; // G
                pixels[pixel_offset + 2] = r; // R
                pixels[pixel_offset + 3] = a; // A
            }
        }

        // Attach buffer to surface
        try surface.attach(buffer, 0, 0);
        try surface.damage(0, 0, width, height);
        try surface.commit();

        std.debug.print("Drew {}x{} gradient to surface\n", .{ width, height });
    }

    // Main event loop
    std.debug.print("Entering event loop (press Ctrl+C to exit)\n");

    var running = true;
    var frame_count: u32 = 0;

    while (running) {
        // Process events
        client.dispatchEvents() catch |err| {
            if (err == error.ConnectionClosed) {
                std.debug.print("Connection closed by compositor\n");
                break;
            }
            return err;
        };

        frame_count += 1;

        // Print status every 100 frames
        if (frame_count % 100 == 0) {
            std.debug.print("Frame {}: Still running...\n", .{frame_count});
        }

        // Small delay to prevent busy waiting
        std.Thread.sleep(16_666_666); // ~60 FPS
    }

    std.debug.print("Client shutting down\n");
}

// Signal handler for graceful shutdown
const SignalHandler = struct {
    var running: bool = true;

    fn handleSignal(sig: c_int) callconv(.C) void {
        if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
            std.debug.print("\nReceived signal {}, shutting down...\n", .{sig});
            running = false;
        }
    }
};