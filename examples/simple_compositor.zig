const std = @import("std");
const wzl = @import("wzl");

// Example compositor demonstrating wzl capabilities
// Optimized for Arch Linux x64 systems

const ExampleCompositor = struct {
    framework: wzl.CompositorFramework,
    remote_server: ?wzl.RemoteServer = null,
    quic_server: ?wzl.QuicServer = null,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        // Configure compositor for Arch Linux
        const config = wzl.CompositorConfig{
            .socket_name = "wzl-example",
            .enable_xdg_shell = true,
            .enable_input = true,
            .enable_output = true,
            .max_clients = 16,
        };
        
        const framework = try wzl.CompositorFramework.init(allocator, config);
        
        return Self{
            .framework = framework,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.remote_server) |*remote| {
            remote.deinit();
        }
        
        if (self.quic_server) |*quic| {
            quic.deinit();
        }
        
        self.framework.deinit();
    }
    
    pub fn enableRemoteAccess(self: *Self) !void {
        const remote_config = wzl.RemoteSessionConfig{
            .listen_address = "0.0.0.0",
            .listen_port = 5900,
            .enable_encryption = true,
            .enable_compression = true,
            .use_tcp_nodelay = true, // Arch Linux optimization
        };
        
        self.remote_server = try wzl.RemoteServer.init(self.allocator, remote_config);
        try self.remote_server.?.optimizeForArch();
        
        std.debug.print("[example] Remote access enabled on port 5900\n", .{});
    }
    
    pub fn enableQuicStreaming(self: *Self) !void {
        const quic_config = wzl.StreamingConfig{
            .listen_address = "0.0.0.0",
            .listen_port = 4433,
            .enable_0rtt = true,
            .congestion_control = .bbr2, // Best for Arch Linux
            .enable_gso = true,
            .enable_gro = true,
            .use_io_uring = true,
        };
        
        self.quic_server = try wzl.QuicServer.init(self.allocator, quic_config);
        std.debug.print("[example] QUIC streaming enabled on port 4433\n", .{});
    }
    
    pub fn run(self: *Self) !void {
        std.debug.print("=== wzl Example Compositor ===\n", .{});
        std.debug.print("Optimized for Arch Linux x64\n\n", .{});
        
        // Initialize Arch Linux optimizations
        try self.framework.detectArchLinuxFeatures();
        try self.framework.optimizeForArch();
        
        std.debug.print("\nFeatures enabled:\n", .{});
        std.debug.print("✓ Core Wayland protocol\n", .{});
        std.debug.print("✓ XDG Shell (windows, popups)\n", .{});
        std.debug.print("✓ Input devices (keyboard, mouse, touch)\n", .{});
        std.debug.print("✓ Output management\n", .{});
        std.debug.print("✓ Buffer management (SHM)\n", .{});
        
        if (self.remote_server != null) {
            std.debug.print("✓ Remote access (encrypted)\n", .{});
        }
        
        if (self.quic_server != null) {
            std.debug.print("✓ QUIC streaming (low latency)\n", .{});
        }
        
        std.debug.print("\nStarting compositor...\n", .{});
        
        // Create some example surfaces for demonstration
        try self.createDemoContent();
        
        // Start the main compositor loop
        try self.framework.run();
    }
    
    fn createDemoContent(self: *Self) !void {
        std.debug.print("[example] Creating demonstration content...\n", .{});
        
        // Create a demo window
        const demo_surface_id: wzl.ObjectId = 1000;
        const demo_view = try self.framework.createView(demo_surface_id);
        demo_view.state.role = .xdg_toplevel;
        
        // Map the window
        self.framework.mapView(demo_surface_id, 100, 100, 800, 600);
        
        std.debug.print("[example] Demo window created: 800x600 at (100,100)\n", .{});
        
        // Create demo framebuffer data
        if (self.quic_server != null) {
            const demo_framebuffer = try self.allocator.alloc(u8, 800 * 600 * 4); // RGBA
            defer self.allocator.free(demo_framebuffer);
            
            // Fill with gradient pattern
            for (0..600) |y| {
                for (0..800) |x| {
                    const pixel_index = (y * 800 + x) * 4;
                    demo_framebuffer[pixel_index + 0] = @intCast(x % 256); // R
                    demo_framebuffer[pixel_index + 1] = @intCast(y % 256); // G
                    demo_framebuffer[pixel_index + 2] = 128; // B
                    demo_framebuffer[pixel_index + 3] = 255; // A
                }
            }
            
            // Create frame metadata
            const metadata = wzl.FrameMetadata{
                .timestamp_us = @intCast(std.time.microTimestamp()),
                .sequence_number = 1,
                .width = 800,
                .height = 600,
                .format = @intFromEnum(wzl.ShmFormat.argb8888),
                .stride = 800 * 4,
                .damage_x = 0,
                .damage_y = 0,
                .damage_width = 800,
                .damage_height = 600,
                .flags = wzl.FrameFlags{ .is_keyframe = true },
            };
            
            // Broadcast frame
            try self.quic_server.?.broadcastFrame(demo_framebuffer, metadata);
            std.debug.print("[example] Demo framebuffer broadcasted via QUIC\n", .{});
        }
    }
    
    pub fn stop(self: *Self) void {
        self.framework.stop();
        
        if (self.remote_server) |*remote| {
            remote.stop();
        }
        
        if (self.quic_server) |*quic| {
            quic.stop();
        }
        
        std.debug.print("[example] Compositor stopped\n", .{});
    }
    
    pub fn printStats(self: *Self) void {
        std.debug.print("\n=== Compositor Statistics ===\n", .{});
        std.debug.print("Views: {}\n", .{self.framework.views.count()});
        std.debug.print("Outputs: {}\n", .{self.framework.output_manager.outputs.items.len});
        std.debug.print("Seats: {}\n", .{self.framework.input_manager.seats.items.len});
        
        if (self.remote_server) |*remote| {
            std.debug.print("Remote clients: {}\n", .{remote.getAuthenticatedClientCount()});
        }
        
        if (self.quic_server) |*quic| {
            std.debug.print("QUIC connections: {}\n", .{quic.getConnectionCount()});
            std.debug.print("QUIC streams: {}\n", .{quic.getStreamCount()});
        }
        
        std.debug.print("=============================\n", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    
    var compositor = try ExampleCompositor.init(allocator);
    defer compositor.deinit();
    
    // Enable advanced features
    try compositor.enableRemoteAccess();
    try compositor.enableQuicStreaming();
    
    // Handle Ctrl+C gracefully
    const original_handler = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.INT, &original_handler, null);
    
    // Print system information
    printSystemInfo();
    
    // Run compositor (this would run indefinitely in a real compositor)
    compositor.run() catch |err| {
        std.debug.print("Compositor error: {}\n", .{err});
    };
    
    // Print final statistics
    compositor.printStats();
}

fn handleSignal(sig: c_int) callconv(.C) void {
    if (sig == std.posix.SIG.INT) {
        std.debug.print("\nReceived SIGINT, shutting down gracefully...\n", .{});
        std.process.exit(0);
    }
}

fn printSystemInfo() void {
    std.debug.print("\n=== System Information ===\n", .{});
    
    // Print OS info
    const uname_info = std.posix.uname();
    std.debug.print("OS: {s} {s}\n", .{ uname_info.sysname, uname_info.release });
    std.debug.print("Architecture: {s}\n", .{uname_info.machine});
    
    // Check for Arch Linux
    const os_release = std.fs.openFileAbsolute("/etc/os-release", .{}) catch null;
    if (os_release) |file| {
        defer file.close();
        var buffer: [1024]u8 = undefined;
        const bytes_read = file.readAll(&buffer) catch 0;
        const content = buffer[0..bytes_read];
        
        if (std.mem.indexOf(u8, content, "Arch Linux")) |_| {
            std.debug.print("Distribution: ✓ Arch Linux (Optimized)\n", .{});
        } else {
            std.debug.print("Distribution: Other Linux\n", .{});
        }
    }
    
    // Check CPU info
    const cpuinfo = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch null;
    if (cpuinfo) |file| {
        defer file.close();
        var buffer: [2048]u8 = undefined;
        const bytes_read = file.readAll(&buffer) catch 0;
        const content = buffer[0..bytes_read];
        
        if (std.mem.indexOf(u8, content, "model name")) |start| {
            const line_end = std.mem.indexOf(u8, content[start..], "\n") orelse content.len - start;
            const line = content[start..start + line_end];
            if (std.mem.indexOf(u8, line, ":")) |colon| {
                const cpu_name = std.mem.trim(u8, line[colon + 1..], " \t");
                std.debug.print("CPU: {s}\n", .{cpu_name});
            }
        }
    }
    
    // Check memory info
    const meminfo = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch null;
    if (meminfo) |file| {
        defer file.close();
        var buffer: [1024]u8 = undefined;
        const bytes_read = file.readAll(&buffer) catch 0;
        const content = buffer[0..bytes_read];
        
        if (std.mem.indexOf(u8, content, "MemTotal:")) |start| {
            const line_end = std.mem.indexOf(u8, content[start..], "\n") orelse content.len - start;
            const line = content[start..start + line_end];
            std.debug.print("Memory: {s}\n", .{std.mem.trim(u8, line, " \t")});
        }
    }
    
    // Check graphics info
    const dri_devices = [_][]const u8{ "/dev/dri/card0", "/dev/dri/card1" };
    var gpu_found = false;
    for (dri_devices) |device| {
        if (std.fs.openFileAbsolute(device, .{})) |file| {
            file.close();
            std.debug.print("GPU: ✓ DRM device available ({s})\n", .{device});
            gpu_found = true;
            break;
        } else |_| {}
    }
    
    if (!gpu_found) {
        std.debug.print("GPU: ⚠ No DRM devices found\n", .{});
    }
    
    std.debug.print("=========================\n", .{});
}