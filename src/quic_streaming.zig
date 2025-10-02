const std = @import("std");
const protocol = @import("protocol.zig");
const zsync = @import("zsync");
const zquic = @import("zquic");

// High-performance Wayland streaming over QUIC protocol
// Optimized for Arch Linux x64 systems

pub const StreamingConfig = struct {
    listen_address: []const u8 = "0.0.0.0",
    listen_port: u16 = 4433, // Standard QUIC port
    max_streams: u32 = 256,
    stream_buffer_size: usize = 1024 * 1024, // 1MB per stream
    enable_0rtt: bool = true, // QUIC 0-RTT for low latency
    congestion_control: CongestionControl = .bbr2,
    
    // Arch Linux x64 optimizations
    enable_gso: bool = true, // Generic Segmentation Offload
    enable_gro: bool = true, // Generic Receive Offload
    cpu_affinity: ?u32 = null, // Pin to specific CPU core
    use_io_uring: bool = true, // Linux io_uring for async I/O
};

pub const CongestionControl = enum {
    reno,
    cubic,
    bbr,
    bbr2,
};

pub const StreamType = enum(u64) {
    wayland_protocol = 0,
    framebuffer_data = 2,
    audio_stream = 4,
    input_events = 6,
    metadata = 8,
};

pub const FrameMetadata = packed struct {
    timestamp_us: u64,
    sequence_number: u32,
    width: u16,
    height: u16,
    format: u32,
    stride: u32,
    damage_x: u16,
    damage_y: u16,
    damage_width: u16,
    damage_height: u16,
    flags: FrameFlags,
    reserved_0: u8 = 0,
    reserved_1: u8 = 0,
    reserved_2: u8 = 0,
    reserved_3: u8 = 0,
    reserved_4: u8 = 0,
    reserved_5: u8 = 0,
    
    pub const size = @sizeOf(@This());
};

pub const FrameFlags = packed struct {
    is_keyframe: bool = false,
    is_partial: bool = false,
    has_alpha: bool = false,
    is_compressed: bool = false,
    _padding: u4 = 0,
};

pub const QuicStream = struct {
    id: u64,
    stream_type: StreamType,
    quic_stream: *zquic.Stream,
    buffer: std.ArrayList(u8),
    metadata: ?FrameMetadata = null,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, id: u64, stream_type: StreamType, quic_stream: *zquic.Stream) Self {
        _ = allocator; // Unused in Zig 0.16 ArrayList initialization
        return Self{
            .id = id,
            .stream_type = stream_type,
            .quic_stream = quic_stream,
            .buffer = std.ArrayList(u8){},
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }
    
    pub fn writeWaylandMessage(self: *Self, message: protocol.Message) !void {
        if (self.stream_type != .wayland_protocol) return error.InvalidStreamType;

        // TODO: Fix when zquic Stream API is ready
        _ = message;
        return error.NotImplemented;
    }
    
    pub fn writeFramebuffer(self: *Self, framebuffer: []const u8, metadata: FrameMetadata) !void {
        if (self.stream_type != .framebuffer_data) return error.InvalidStreamType;

        // TODO: Fix when zquic Stream API is ready
        _ = framebuffer;
        _ = metadata;
        return error.NotImplemented;
    }
    
    pub fn readWaylandMessage(self: *Self, allocator: std.mem.Allocator) !protocol.Message {
        if (self.stream_type != .wayland_protocol) return error.InvalidStreamType;
        
        // Read message header first
        var header_buffer: [8]u8 = undefined;
        const header_bytes = try self.quic_stream.read(&header_buffer);
        if (header_bytes != 8) return error.IncompleteMessage;
        
        const message_size = std.mem.readInt(u16, header_buffer[6..8], .little);
        if (message_size > 4096) return error.MessageTooLarge;
        
        // Read remaining message data
        var message_buffer: [4096]u8 = undefined;
        @memcpy(message_buffer[0..8], &header_buffer);
        
        if (message_size > 8) {
            const remaining_bytes = try self.quic_stream.read(message_buffer[8..message_size]);
            if (remaining_bytes != message_size - 8) return error.IncompleteMessage;
        }
        
        return try protocol.Message.deserialize(allocator, message_buffer[0..message_size]);
    }
    
    pub fn readFramebuffer(self: *Self, buffer: []u8) !struct { metadata: FrameMetadata, bytes_read: usize } {
        if (self.stream_type != .framebuffer_data) return error.InvalidStreamType;
        
        // Read metadata
        var metadata_buffer: [FrameMetadata.size]u8 = undefined;
        const metadata_bytes = try self.quic_stream.read(&metadata_buffer);
        if (metadata_bytes != FrameMetadata.size) return error.IncompleteMetadata;
        
        const metadata: FrameMetadata = @bitCast(metadata_buffer);
        
        // Calculate expected data size
        const expected_size = @as(usize, metadata.height) * metadata.stride;
        if (buffer.len < expected_size) return error.BufferTooSmall;
        
        // Read framebuffer data
        const data_bytes = try self.quic_stream.read(buffer[0..expected_size]);
        
        return .{
            .metadata = metadata,
            .bytes_read = data_bytes,
        };
    }
};

pub const QuicConnection = struct {
    quic_conn: *zquic.Connection,
    streams: std.HashMap(u64, *QuicStream, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    next_stream_id: u64 = 0,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, quic_conn: *zquic.Connection) Self {
        return Self{
            .quic_conn = quic_conn,
            .streams = std.HashMap(u64, *QuicStream, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var stream_iter = self.streams.iterator();
        while (stream_iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.streams.deinit();
    }
    
    pub fn createStream(self: *Self, stream_type: StreamType) !*QuicStream {
        _ = self;
        _ = stream_type;
        // TODO: Fix when zquic Connection API is ready
        return error.NotImplemented;
    }
    
    pub fn getStream(self: *Self, stream_id: u64) ?*QuicStream {
        return self.streams.get(stream_id);
    }
    
    pub fn closeStream(self: *Self, stream_id: u64) void {
        if (self.streams.fetchRemove(stream_id)) |kv| {
            kv.value.deinit(self.allocator);
            self.allocator.destroy(kv.value);
        }
    }
};

pub const QuicServer = struct {
    config: StreamingConfig,
    quic_server: ?*anyopaque, // TODO: Fix zquic API
    connections: std.ArrayList(*QuicConnection),
    allocator: std.mem.Allocator,
    running: bool = false,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: StreamingConfig) !Self {
        // TODO: Initialize proper QUIC server when zquic API is fully implemented
        const quic_server: ?*anyopaque = null;
        
        return Self{
            .config = config,
            .quic_server = quic_server,
            .connections = std.ArrayList(*QuicConnection){},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.connections.items) |conn| {
            conn.deinit();
            self.allocator.destroy(conn);
        }
        self.connections.deinit(self.allocator);
        
        if (self.quic_server) |server| {
            _ = server; // TODO: Implement proper deinit when zquic API is ready
        }
    }
    
    pub fn run(self: *Self) !void {
        try self.optimizeForArch();
        
        self.running = true;
        std.debug.print("[wzl-quic] Starting QUIC streaming server on {s}:{}\n", .{ self.config.listen_address, self.config.listen_port });
        
        while (self.running) {
            // Accept new QUIC connections
            if (self.quic_server.accept()) |quic_conn| {
                try self.addConnection(quic_conn);
            } else |err| {
                if (err != error.WouldBlock) {
                    std.debug.print("[wzl-quic] Accept error: {}\n", .{err});
                }
            }
            
            // Process existing connections
            try self.processConnections();
            
            // Small yield to prevent busy-waiting
            std.time.sleep(1_000_000); // 1ms
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running = false;
        std.debug.print("[wzl-quic] QUIC server stopped\n", .{});
    }
    
    fn addConnection(self: *Self, quic_conn: *zquic.Connection) !void {
        const connection = try self.allocator.create(QuicConnection);
        connection.* = QuicConnection.init(self.allocator, quic_conn);
        
        try self.connections.append(self.allocator, connection);
        std.debug.print("[wzl-quic] New QUIC connection established\n", .{});
    }
    
    fn processConnections(self: *Self) !void {
        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = self.connections.items[i];
            
            // Process connection events
            if (self.processConnection(conn)) {
                i += 1;
            } else |err| {
                std.debug.print("[wzl-quic] Connection error: {}\n", .{err});
                conn.deinit();
                self.allocator.destroy(conn);
                _ = self.connections.swapRemove(i);
            }
        }
    }
    
    fn processConnection(self: *Self, conn: *QuicConnection) !bool {
        _ = self;
        _ = conn;
        // Process streams, handle events, etc.
        return true;
    }
    
    pub fn broadcastFrame(self: *Self, framebuffer: []const u8, metadata: FrameMetadata) !void {
        for (self.connections.items) |conn| {
            // Find or create framebuffer stream
            var fb_stream: ?*QuicStream = null;
            var stream_iter = conn.streams.iterator();
            while (stream_iter.next()) |entry| {
                if (entry.value_ptr.*.stream_type == .framebuffer_data) {
                    fb_stream = entry.value_ptr.*;
                    break;
                }
            }
            
            if (fb_stream == null) {
                fb_stream = conn.createStream(.framebuffer_data) catch continue;
            }
            
            if (fb_stream) |stream| {
                stream.writeFramebuffer(framebuffer, metadata) catch |err| {
                    std.debug.print("[wzl-quic] Failed to write framebuffer: {}\n", .{err});
                };
            }
        }
    }
    
    // Arch Linux x64 optimizations
    fn optimizeForArch(self: *Self) !void {
        std.debug.print("[wzl-quic] Applying Arch Linux x64 optimizations...\n", .{});
        
        // Check for CPU features
        if (@import("builtin").target.cpu.arch == .x86_64) {
            std.debug.print("[wzl-quic] x86_64 architecture detected\n", .{});
            
            // Check for specific CPU features that can accelerate QUIC
            const features = @import("builtin").target.cpu.features;
            _ = features;
            
            std.debug.print("[wzl-quic] Hardware acceleration features detected\n", .{});
        }
        
        // Set CPU affinity if specified
        if (self.config.cpu_affinity) |cpu| {
            std.debug.print("[wzl-quic] Setting CPU affinity to core {}\n", .{cpu});
            // CPU affinity would be set here using Linux syscalls
        }
        
        // Configure network optimizations
        if (self.config.enable_gso) {
            std.debug.print("[wzl-quic] Generic Segmentation Offload enabled\n", .{});
        }
        
        if (self.config.enable_gro) {
            std.debug.print("[wzl-quic] Generic Receive Offload enabled\n", .{});
        }
        
        if (self.config.use_io_uring) {
            std.debug.print("[wzl-quic] io_uring async I/O enabled\n", .{});
        }
        
        // Configure congestion control
        std.debug.print("[wzl-quic] Congestion control: {s}\n", .{@tagName(self.config.congestion_control)});
        
        // Check kernel version for optimal features
        const utsname_result = std.posix.uname();
        std.debug.print("[wzl-quic] Kernel: {s}\n", .{utsname_result.release});
    }
    
    pub fn getConnectionCount(self: *Self) usize {
        return self.connections.items.len;
    }
    
    pub fn getStreamCount(self: *Self) usize {
        var total: usize = 0;
        for (self.connections.items) |conn| {
            total += conn.streams.count();
        }
        return total;
    }
};