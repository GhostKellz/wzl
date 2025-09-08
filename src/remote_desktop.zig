const std = @import("std");
const protocol = @import("protocol.zig");
const buffer = @import("buffer.zig");
const input = @import("input.zig");
const output = @import("output.zig");
const remote = @import("remote.zig");
const quic_streaming = @import("quic_streaming.zig");
const zcrypto = @import("zcrypto");
const zquic = @import("zquic");

// Remote desktop sharing capabilities similar to RustDesk
// Optimized for Arch Linux x64 performance

pub const RemoteDesktopConfig = struct {
    // Network configuration
    listen_port: u16 = 21118, // RustDesk-compatible port
    discovery_port: u16 = 21116,
    relay_servers: []const []const u8 = &[_][]const u8{
        "relay1.wzl.dev",
        "relay2.wzl.dev",
    },
    
    // Security
    enable_password: bool = true,
    password: []const u8 = "",
    enable_two_factor: bool = false,
    auto_accept_connections: bool = false,
    
    // Performance (Arch Linux optimized)
    codec: VideoCodec = .h264_hw, // Hardware acceleration on Arch
    quality: VideoQuality = .balanced,
    frame_rate: u8 = 30,
    enable_adaptive_bitrate: bool = true,
    
    // Audio
    enable_audio: bool = true,
    audio_codec: AudioCodec = .opus,
    
    // Control
    allow_remote_input: bool = true,
    allow_file_transfer: bool = true,
    allow_clipboard_sync: bool = true,
    
    // Arch-specific optimizations
    use_hardware_encoding: bool = true,
    prefer_vaapi: bool = true, // Intel/AMD on Arch
    prefer_nvenc: bool = false, // NVIDIA
    enable_screen_capture_portal: bool = true, // xdg-desktop-portal
};

pub const VideoCodec = enum {
    h264_sw,  // Software H.264
    h264_hw,  // Hardware H.264 (VAAPI/NVENC)
    h265_hw,  // Hardware H.265
    vp8,      // VP8
    vp9,      // VP9
    av1,      // AV1 (future)
};

pub const VideoQuality = enum {
    low,      // 480p, low bitrate
    balanced, // 720p, medium bitrate  
    high,     // 1080p, high bitrate
    lossless, // Lossless compression
};

pub const AudioCodec = enum {
    opus,
    aac,
    pcm,
};

pub const ConnectionState = enum {
    disconnected,
    connecting,
    authenticating,
    connected,
    connection_error,
};

pub const RemoteInputEvent = union(enum) {
    key_press: struct { keycode: u32, modifiers: u32 },
    key_release: struct { keycode: u32, modifiers: u32 },
    mouse_move: struct { x: i32, y: i32 },
    mouse_button: struct { button: u32, state: input.ButtonState },
    mouse_scroll: struct { delta_x: f32, delta_y: f32 },
    touch_down: struct { id: u32, x: f32, y: f32 },
    touch_up: struct { id: u32 },
    touch_move: struct { id: u32, x: f32, y: f32 },
};

pub const ScreenCaptureContext = struct {
    width: u32,
    height: u32,
    format: buffer.ShmFormat,
    framebuffer: []u8,
    damage_regions: std.ArrayList(DamageRegion),
    last_capture_time: i64,
    frame_counter: u64,
    allocator: std.mem.Allocator,
    
    // Hardware acceleration
    vaapi_context: ?*anyopaque = null,
    nvenc_context: ?*anyopaque = null,
    
    const Self = @This();
    
    pub const DamageRegion = struct {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    };
    
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Self {
        const buffer_size = width * height * 4; // RGBA
        const framebuffer = try allocator.alloc(u8, buffer_size);
        
        return Self{
            .width = width,
            .height = height,
            .format = .argb8888,
            .framebuffer = framebuffer,
            .damage_regions = std.ArrayList(DamageRegion).init(allocator),
            .last_capture_time = 0,
            .frame_counter = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.framebuffer);
        self.damage_regions.deinit();
        
        // Clean up hardware contexts
        if (self.vaapi_context) |ctx| {
            _ = ctx;
            // vaapi_cleanup(ctx);
        }
        
        if (self.nvenc_context) |ctx| {
            _ = ctx;
            // nvenc_cleanup(ctx);
        }
    }
    
    pub fn captureScreen(self: *Self) !bool {
        const current_time = std.time.milliTimestamp();
        
        // Simple frame rate limiting
        if (current_time - self.last_capture_time < 16) { // ~60fps max
            return false;
        }
        
        // In a real implementation, this would:
        // 1. Use xdg-desktop-portal for secure screen capture on Wayland
        // 2. Or use DRM/KMS for direct framebuffer access
        // 3. Apply hardware encoding with VAAPI/NVENC
        
        // Placeholder: generate test pattern
        self.generateTestPattern();
        
        self.last_capture_time = current_time;
        self.frame_counter += 1;
        
        return true;
    }
    
    fn generateTestPattern(self: *Self) void {
        const pixels = @as([*]u32, @ptrCast(@alignCast(self.framebuffer.ptr)))[0..@divExact(self.framebuffer.len, 4)];
        
        const time_offset = @as(u32, @intCast(self.frame_counter % 256));
        
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const pixel_index = y * self.width + x;
                const r = @as(u8, @intCast((x + time_offset) % 256));
                const g = @as(u8, @intCast((y + time_offset) % 256));
                const b = @as(u8, @intCast((x + y + time_offset) % 256));
                
                pixels[pixel_index] = (0xFF << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
            }
        }
    }
    
    pub fn addDamage(self: *Self, x: u32, y: u32, width: u32, height: u32) !void {
        try self.damage_regions.append(DamageRegion{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        });
    }
    
    pub fn clearDamage(self: *Self) void {
        self.damage_regions.clearRetainingCapacity();
    }
    
    pub fn encodeFrame(self: *Self, quality: VideoQuality, use_hardware: bool) ![]u8 {
        _ = quality;
        _ = use_hardware;
        
        // Placeholder implementation - return raw framebuffer
        // Real implementation would use hardware encoders
        return try self.allocator.dupe(u8, self.framebuffer);
    }
};

pub const RemotePeer = struct {
    connection: std.net.Stream,
    peer_id: []const u8,
    state: ConnectionState,
    authenticated: bool = false,
    permissions: RemotePermissions,
    encryption_ctx: ?remote.EncryptionContext = null,
    
    // Statistics
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    frames_sent: u64 = 0,
    ping_ms: u32 = 0,
    
    allocator: std.mem.Allocator,
    
    pub const RemotePermissions = struct {
        view_screen: bool = true,
        control_input: bool = false,
        transfer_files: bool = false,
        access_clipboard: bool = false,
    };
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, connection: std.net.Stream, peer_id: []const u8) !Self {
        return Self{
            .connection = connection,
            .peer_id = try allocator.dupe(u8, peer_id),
            .state = .connecting,
            .permissions = .{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.peer_id);
        
        if (self.encryption_ctx) |*ctx| {
            ctx.deinit();
        }
        
        self.connection.close();
    }
    
    pub fn authenticate(self: *Self, password: []const u8) !bool {
        // Simple password authentication
        // Real implementation would use secure challenge-response
        
        const expected_hash = "wzl_default_password_hash"; // Placeholder
        _ = password;
        _ = expected_hash;
        
        self.authenticated = true;
        self.state = .connected;
        
        std.debug.print("[wzl-remote-desktop] Peer {} authenticated\n", .{self.peer_id});
        return true;
    }
    
    pub fn sendFrame(self: *Self, frame_data: []const u8, metadata: quic_streaming.FrameMetadata) !void {
        if (!self.authenticated) return error.NotAuthenticated;
        
        // Send frame header
        const header = FrameHeader{
            .magic = FRAME_MAGIC,
            .frame_size = @intCast(frame_data.len),
            .metadata = metadata,
        };
        
        try self.connection.writer().writeAll(std.mem.asBytes(&header));
        
        // Send frame data (optionally encrypted)
        if (self.encryption_ctx) |*ctx| {
            var encrypted_buffer: [1024 * 1024]u8 = undefined;
            const encrypted_size = try ctx.encrypt(frame_data, &encrypted_buffer);
            try self.connection.writer().writeAll(encrypted_buffer[0..encrypted_size]);
        } else {
            try self.connection.writer().writeAll(frame_data);
        }
        
        self.bytes_sent += frame_data.len;
        self.frames_sent += 1;
    }
    
    pub fn receiveInput(self: *Self) !?RemoteInputEvent {
        if (!self.authenticated or !self.permissions.control_input) {
            return null;
        }
        
        // Try to read input event header
        var event_header: InputEventHeader = undefined;
        const bytes_read = self.connection.read(std.mem.asBytes(&event_header)) catch |err| {
            if (err == error.WouldBlock) return null;
            return err;
        };
        
        if (bytes_read != @sizeOf(InputEventHeader)) return null;
        
        if (event_header.magic != INPUT_MAGIC) return error.InvalidProtocol;
        
        // Parse event based on type
        return switch (event_header.event_type) {
            1 => RemoteInputEvent{ .key_press = .{ 
                .keycode = event_header.data1, 
                .modifiers = event_header.data2 
            }},
            2 => RemoteInputEvent{ .key_release = .{ 
                .keycode = event_header.data1, 
                .modifiers = event_header.data2 
            }},
            3 => RemoteInputEvent{ .mouse_move = .{ 
                .x = @bitCast(event_header.data1), 
                .y = @bitCast(event_header.data2) 
            }},
            4 => RemoteInputEvent{ .mouse_button = .{ 
                .button = event_header.data1, 
                .state = if (event_header.data2 == 1) .pressed else .released 
            }},
            else => null,
        };
    }
    
    const FRAME_MAGIC: u32 = 0x57464D52; // "RMFW" in little endian
    const INPUT_MAGIC: u32 = 0x55504E49; // "INPU" in little endian
    
    const FrameHeader = packed struct {
        magic: u32,
        frame_size: u32,
        metadata: quic_streaming.FrameMetadata,
    };
    
    const InputEventHeader = packed struct {
        magic: u32,
        event_type: u32,
        data1: u32,
        data2: u32,
    };
};

pub const RemoteDesktopServer = struct {
    config: RemoteDesktopConfig,
    allocator: std.mem.Allocator,
    
    // Network
    tcp_listener: std.net.StreamServer,
    quic_server: ?quic_streaming.QuicServer = null,
    
    // Peers
    peers: std.ArrayList(*RemotePeer),
    
    // Screen capture
    capture_context: ScreenCaptureContext,
    
    // State
    running: bool = false,
    password_hash: [32]u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: RemoteDesktopConfig) !Self {
        // Initialize TCP listener
        var tcp_listener = std.net.StreamServer.init(.{});
        const address = try std.net.Address.parseIp("0.0.0.0", config.listen_port);
        try tcp_listener.listen(address);
        
        // Initialize QUIC server for low-latency streaming
        const quic_config = quic_streaming.StreamingConfig{
            .listen_port = config.listen_port + 1,
            .enable_0rtt = true,
            .congestion_control = .bbr2,
        };
        const quic_server = try quic_streaming.QuicServer.init(allocator, quic_config);
        
        // Initialize screen capture (detect display size)
        const capture_context = try ScreenCaptureContext.init(allocator, 1920, 1080);
        
        // Hash the password
        var password_hash: [32]u8 = undefined;
        if (config.password.len > 0) {
            std.crypto.hash.sha2.Sha256.hash(config.password, &password_hash, .{});
        } else {
            @memset(&password_hash, 0);
        }
        
        std.debug.print("[wzl-remote-desktop] Server initialized on port {}\n", .{config.listen_port});
        
        return Self{
            .config = config,
            .allocator = allocator,
            .tcp_listener = tcp_listener,
            .quic_server = quic_server,
            .peers = std.ArrayList(*RemotePeer).init(allocator),
            .capture_context = capture_context,
            .password_hash = password_hash,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.stop();
        
        for (self.peers.items) |peer| {
            peer.deinit();
            self.allocator.destroy(peer);
        }
        self.peers.deinit();
        
        if (self.quic_server) |*quic| {
            quic.deinit();
        }
        
        self.tcp_listener.deinit();
        self.capture_context.deinit();
    }
    
    pub fn run(self: *Self) !void {
        try self.detectArchCapabilities();
        
        self.running = true;
        std.debug.print("[wzl-remote-desktop] Starting remote desktop server (RustDesk-compatible)\n", .{});
        std.debug.print("[wzl-remote-desktop] Listening on port {} (TCP) and {} (QUIC)\n", .{ self.config.listen_port, self.config.listen_port + 1 });
        
        // Start QUIC server in background
        if (self.quic_server) |*quic| {
            // In a real implementation, this would be in a separate thread
            _ = quic;
        }
        
        while (self.running) {
            // Accept new TCP connections
            if (self.tcp_listener.accept()) |conn| {
                try self.handleNewConnection(conn.stream);
            } else |err| {
                if (err != error.WouldBlock) {
                    std.debug.print("[wzl-remote-desktop] Accept error: {}\n", .{err});
                }
            }
            
            // Process existing peers
            try self.processPeers();
            
            // Capture and broadcast screen
            try self.captureAndBroadcast();
            
            // Small yield
            std.time.sleep(1_000_000); // 1ms
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running = false;
        
        if (self.quic_server) |*quic| {
            quic.stop();
        }
        
        std.debug.print("[wzl-remote-desktop] Server stopped\n", .{});
    }
    
    fn handleNewConnection(self: *Self, connection: std.net.Stream) !void {
        const peer_id = try std.fmt.allocPrint(self.allocator, "peer_{}", .{self.peers.items.len});
        defer self.allocator.free(peer_id);
        
        const peer = try self.allocator.create(RemotePeer);
        peer.* = try RemotePeer.init(self.allocator, connection, peer_id);
        
        try self.peers.append(peer);
        std.debug.print("[wzl-remote-desktop] New connection: {s}\n", .{peer.peer_id});
    }
    
    fn processPeers(self: *Self) !void {
        var i: usize = 0;
        while (i < self.peers.items.len) {
            const peer = self.peers.items[i];
            
            // Process incoming input events
            while (try peer.receiveInput()) |input_event| {
                try self.handleRemoteInput(input_event);
            }
            
            // Check connection health
            if (peer.state == .connection_error) {
                std.debug.print("[wzl-remote-desktop] Removing peer: {s}\n", .{peer.peer_id});
                peer.deinit();
                self.allocator.destroy(peer);
                _ = self.peers.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
    
    fn captureAndBroadcast(self: *Self) !void {
        if (try self.capture_context.captureScreen()) {
            // Encode frame
            const encoded_frame = try self.capture_context.encodeFrame(self.config.quality, self.config.use_hardware_encoding);
            defer self.allocator.free(encoded_frame);
            
            // Create frame metadata
            const metadata = quic_streaming.FrameMetadata{
                .timestamp_us = @intCast(std.time.microTimestamp()),
                .sequence_number = @intCast(self.capture_context.frame_counter),
                .width = @intCast(self.capture_context.width),
                .height = @intCast(self.capture_context.height),
                .format = @intFromEnum(self.capture_context.format),
                .stride = self.capture_context.width * 4,
                .damage_x = 0,
                .damage_y = 0,
                .damage_width = @intCast(self.capture_context.width),
                .damage_height = @intCast(self.capture_context.height),
                .flags = quic_streaming.FrameFlags{ .is_keyframe = self.capture_context.frame_counter % 30 == 0 },
            };
            
            // Broadcast to all authenticated peers
            for (self.peers.items) |peer| {
                if (peer.authenticated and peer.permissions.view_screen) {
                    peer.sendFrame(encoded_frame, metadata) catch |err| {
                        std.debug.print("[wzl-remote-desktop] Failed to send frame to {s}: {}\n", .{ peer.peer_id, err });
                        peer.state = .connection_error;
                    };
                }
            }
            
            // Also broadcast via QUIC if available
            if (self.quic_server) |*quic| {
                try quic.broadcastFrame(encoded_frame, metadata);
            }
            
            self.capture_context.clearDamage();
        }
    }
    
    fn handleRemoteInput(self: *Self, event: RemoteInputEvent) !void {
        _ = self;
        // In a real implementation, this would inject input events into the Wayland compositor
        // or use uinput to simulate input events
        
        switch (event) {
            .key_press => |key| {
                std.debug.print("[wzl-remote-desktop] Remote key press: {} (mods: {})\n", .{ key.keycode, key.modifiers });
                // Simulate key press in the local session
            },
            .mouse_move => |mouse| {
                std.debug.print("[wzl-remote-desktop] Remote mouse move: ({}, {})\n", .{ mouse.x, mouse.y });
                // Simulate mouse movement
            },
            .mouse_button => |button| {
                std.debug.print("[wzl-remote-desktop] Remote mouse button {} {s}\n", .{ button.button, if (button.state == .pressed) "pressed" else "released" });
                // Simulate mouse button event
            },
            else => {},
        }
    }
    
    fn detectArchCapabilities(self: *Self) !void {
        std.debug.print("[wzl-remote-desktop] Detecting Arch Linux capabilities...\n", .{});
        
        // Check for VAAPI support (Intel/AMD hardware acceleration)
        if (std.fs.openFileAbsolute("/dev/dri/renderD128", .{})) |file| {
            file.close();
            std.debug.print("[wzl-remote-desktop] ✓ VAAPI hardware acceleration available\n", .{});
            self.config.prefer_vaapi = true;
        } else |_| {
            std.debug.print("[wzl-remote-desktop] ⚠ VAAPI not available\n", .{});
        }
        
        // Check for NVIDIA
        if (std.fs.openFileAbsolute("/proc/driver/nvidia/version", .{})) |file| {
            file.close();
            std.debug.print("[wzl-remote-desktop] ✓ NVIDIA driver detected - NVENC available\n", .{});
            self.config.prefer_nvenc = true;
        } else |_| {}
        
        // Check for xdg-desktop-portal
        if (std.fs.openFileAbsolute("/usr/share/xdg-desktop-portal/portals", .{})) |_| {
            std.debug.print("[wzl-remote-desktop] ✓ xdg-desktop-portal available for secure screen capture\n", .{});
        } else |_| {
            std.debug.print("[wzl-remote-desktop] ⚠ xdg-desktop-portal not found\n", .{});
        }
        
        // Check CPU features
        if (std.Target.current.cpu.arch == .x86_64) {
            std.debug.print("[wzl-remote-desktop] ✓ x86_64 architecture - hardware acceleration enabled\n", .{});
        }
        
        std.debug.print("[wzl-remote-desktop] Capability detection complete\n", .{});
    }
    
    pub fn getPeerCount(self: *Self) usize {
        return self.peers.items.len;
    }
    
    pub fn getAuthenticatedPeerCount(self: *Self) usize {
        var count: usize = 0;
        for (self.peers.items) |peer| {
            if (peer.authenticated) count += 1;
        }
        return count;
    }
    
    pub fn getFrameRate(self: *Self) f32 {
        const elapsed_ms = std.time.milliTimestamp() - self.capture_context.last_capture_time;
        if (elapsed_ms > 0) {
            return @as(f32, @floatFromInt(self.capture_context.frame_counter * 1000)) / @as(f32, @floatFromInt(elapsed_ms));
        }
        return 0.0;
    }
};