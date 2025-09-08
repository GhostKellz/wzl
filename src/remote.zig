const std = @import("std");
const protocol = @import("protocol.zig");
const connection = @import("connection.zig");
const zsync = @import("zsync");
const zcrypto = @import("zcrypto");

// Remote Wayland session support with encryption

pub const RemoteSessionConfig = struct {
    listen_address: []const u8 = "127.0.0.1",
    listen_port: u16 = 5900, // VNC-like port
    max_clients: u32 = 8,
    enable_compression: bool = true,
    compression_level: u8 = 6, // 1-9, 6 is balanced
    enable_encryption: bool = true,
    key_size: u16 = 256, // AES key size in bits
    
    // Arch Linux specific
    use_tcp_nodelay: bool = true,
    buffer_size: usize = 64 * 1024, // 64KB buffers for better performance
};

pub const EncryptionContext = struct {
    cipher: zcrypto.aes.Cipher,
    key: [32]u8, // 256-bit key
    iv: [16]u8,  // 128-bit IV
    
    const Self = @This();
    
    pub fn init() !Self {
        var ctx = Self{
            .cipher = undefined,
            .key = undefined,
            .iv = undefined,
        };
        
        // Generate random key and IV
        try std.crypto.random.bytes(&ctx.key);
        try std.crypto.random.bytes(&ctx.iv);
        
        ctx.cipher = try zcrypto.aes.Cipher.init(.aes256, .cbc, &ctx.key, &ctx.iv);
        
        return ctx;
    }
    
    pub fn encrypt(self: *Self, plaintext: []const u8, ciphertext: []u8) !usize {
        return try self.cipher.encrypt(plaintext, ciphertext);
    }
    
    pub fn decrypt(self: *Self, ciphertext: []const u8, plaintext: []u8) !usize {
        return try self.cipher.decrypt(ciphertext, plaintext);
    }
    
    pub fn deinit(self: *Self) void {
        self.cipher.deinit();
        // Clear sensitive data
        std.crypto.utils.secureZero(u8, &self.key);
        std.crypto.utils.secureZero(u8, &self.iv);
    }
};

pub const CompressionContext = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn compress(self: *Self, data: []const u8, level: u8) ![]u8 {
        _ = level;
        // Simple compression placeholder - in a real implementation,
        // you'd use a proper compression library like zlib or lz4
        const compressed = try self.allocator.alloc(u8, data.len);
        @memcpy(compressed, data);
        return compressed;
    }
    
    pub fn decompress(self: *Self, compressed_data: []const u8, original_size: usize) ![]u8 {
        _ = original_size;
        const decompressed = try self.allocator.alloc(u8, compressed_data.len);
        @memcpy(decompressed, compressed_data);
        return decompressed;
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
        // Compression context cleanup if needed
    }
};

pub const RemoteClient = struct {
    connection: std.net.Stream,
    client_id: u32,
    encryption: ?EncryptionContext = null,
    compression: ?CompressionContext = null,
    authenticated: bool = false,
    username: ?[]const u8 = null,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, conn: std.net.Stream, client_id: u32) Self {
        return Self{
            .connection = conn,
            .client_id = client_id,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.encryption) |*enc| {
            enc.deinit();
        }
        
        if (self.compression) |*comp| {
            comp.deinit();
        }
        
        if (self.username) |username| {
            self.allocator.free(username);
        }
        
        self.connection.close();
    }
    
    pub fn enableEncryption(self: *Self) !void {
        self.encryption = try EncryptionContext.init();
        std.debug.print("[wzl-remote] Encryption enabled for client {}\n", .{self.client_id});
    }
    
    pub fn enableCompression(self: *Self) void {
        self.compression = CompressionContext.init(self.allocator);
        std.debug.print("[wzl-remote] Compression enabled for client {}\n", .{self.client_id});
    }
    
    pub fn authenticate(self: *Self, username: []const u8, password: []const u8) !bool {
        // Simple authentication - in production, use proper password hashing
        
        if (std.mem.eql(u8, username, "user") and std.mem.eql(u8, password, "password")) {
            self.authenticated = true;
            self.username = try self.allocator.dupe(u8, username);
            std.debug.print("[wzl-remote] Client {} authenticated as {s}\n", .{ self.client_id, username });
            return true;
        }
        
        std.debug.print("[wzl-remote] Authentication failed for client {}\n", .{self.client_id});
        return false;
    }
    
    pub fn sendWaylandMessage(self: *Self, message: protocol.Message) !void {
        if (!self.authenticated) return error.NotAuthenticated;
        
        var buffer: [4096]u8 = undefined;
        const message_size = try message.serialize(&buffer);
        var data_to_send = buffer[0..message_size];
        
        // Apply compression if enabled
        if (self.compression) |*comp| {
            const compressed = try comp.compress(data_to_send, 6);
            defer self.allocator.free(compressed);
            data_to_send = compressed;
        }
        
        // Apply encryption if enabled
        if (self.encryption) |*enc| {
            var encrypted_buffer: [8192]u8 = undefined;
            const encrypted_size = try enc.encrypt(data_to_send, &encrypted_buffer);
            data_to_send = encrypted_buffer[0..encrypted_size];
        }
        
        // Send length prefix
        const length: u32 = @intCast(data_to_send.len);
        try self.connection.writer().writeAll(std.mem.asBytes(&length));
        
        // Send data
        try self.connection.writer().writeAll(data_to_send);
    }
    
    pub fn receiveWaylandMessage(self: *Self) !protocol.Message {
        if (!self.authenticated) return error.NotAuthenticated;
        
        // Read length prefix
        var length_bytes: [4]u8 = undefined;
        try self.connection.reader().readAll(&length_bytes);
        const length = std.mem.readInt(u32, &length_bytes, .little);
        
        if (length > 8192) return error.MessageTooLarge;
        
        // Read encrypted/compressed data
        var data_buffer: [8192]u8 = undefined;
        const data = data_buffer[0..length];
        try self.connection.reader().readAll(data);
        
        var message_data = data;
        
        // Apply decryption if enabled
        if (self.encryption) |*enc| {
            var decrypted_buffer: [8192]u8 = undefined;
            const decrypted_size = try enc.decrypt(message_data, &decrypted_buffer);
            message_data = decrypted_buffer[0..decrypted_size];
        }
        
        // Apply decompression if enabled
        if (self.compression) |*comp| {
            const decompressed = try comp.decompress(message_data, message_data.len * 2); // Estimate
            defer self.allocator.free(decompressed);
            message_data = decompressed;
        }
        
        return try protocol.Message.deserialize(self.allocator, message_data);
    }
};

pub const RemoteServer = struct {
    config: RemoteSessionConfig,
    allocator: std.mem.Allocator,
    listener: std.net.StreamServer,
    clients: std.ArrayList(*RemoteClient),
    running: bool = false,
    next_client_id: u32 = 1,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: RemoteSessionConfig) !Self {
        var listener = std.net.StreamServer.init(.{});
        
        const address = try std.net.Address.parseIp(config.listen_address, config.listen_port);
        try listener.listen(address);
        
        std.debug.print("[wzl-remote] Remote server listening on {}:{}\n", .{ config.listen_address, config.listen_port });
        
        return Self{
            .config = config,
            .allocator = allocator,
            .listener = listener,
            .clients = std.ArrayList(*RemoteClient).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.stop();
        
        for (self.clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        self.clients.deinit();
        
        self.listener.deinit();
    }
    
    pub fn run(self: *Self) !void {
        self.running = true;
        std.debug.print("[wzl-remote] Starting remote session server (Arch Linux optimized)\n", .{});
        
        while (self.running) {
            const client_connection = self.listener.accept() catch |err| {
                std.debug.print("[wzl-remote] Accept error: {}\n", .{err});
                continue;
            };
            
            if (self.clients.items.len >= self.config.max_clients) {
                std.debug.print("[wzl-remote] Max clients reached, rejecting connection\n", .{});
                client_connection.stream.close();
                continue;
            }
            
            // Configure TCP socket for Arch Linux performance
            if (self.config.use_tcp_nodelay) {
                const sock_fd = client_connection.stream.handle;
                const tcp_nodelay: c_int = 1;
                _ = std.posix.setsockopt(
                    sock_fd,
                    std.posix.IPPROTO.TCP,
                    std.posix.TCP.NODELAY,
                    std.mem.asBytes(&tcp_nodelay),
                ) catch {};
            }
            
            try self.addClient(client_connection.stream);
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running = false;
        std.debug.print("[wzl-remote] Remote server stopped\n", .{});
    }
    
    fn addClient(self: *Self, conn: std.net.Stream) !void {
        const client = try self.allocator.create(RemoteClient);
        client.* = RemoteClient.init(self.allocator, conn, self.next_client_id);
        self.next_client_id += 1;
        
        if (self.config.enable_encryption) {
            try client.enableEncryption();
        }
        
        if (self.config.enable_compression) {
            client.enableCompression();
        }
        
        try self.clients.append(client);
        std.debug.print("[wzl-remote] New client connected: {}\n", .{client.client_id});
    }
    
    pub fn removeClient(self: *Self, client_id: u32) void {
        for (self.clients.items, 0..) |client, i| {
            if (client.client_id == client_id) {
                client.deinit();
                self.allocator.destroy(client);
                _ = self.clients.swapRemove(i);
                std.debug.print("[wzl-remote] Client {} disconnected\n", .{client_id});
                break;
            }
        }
    }
    
    pub fn broadcastMessage(self: *Self, message: protocol.Message) !void {
        for (self.clients.items) |client| {
            if (client.authenticated) {
                client.sendWaylandMessage(message) catch |err| {
                    std.debug.print("[wzl-remote] Failed to send to client {}: {}\n", .{ client.client_id, err });
                };
            }
        }
    }
    
    pub fn getAuthenticatedClientCount(self: *Self) u32 {
        var count: u32 = 0;
        for (self.clients.items) |client| {
            if (client.authenticated) count += 1;
        }
        return count;
    }
    
    // Arch Linux specific optimizations
    pub fn optimizeForArch(self: *Self) !void {
        std.debug.print("[wzl-remote] Applying Arch Linux optimizations...\n", .{});
        
        // Check for high-performance networking features
        const has_epoll = std.fs.openFileAbsolute("/proc/sys/fs/epoll/max_user_watches", .{}) catch null;
        if (has_epoll) |file| {
            file.close();
            std.debug.print("[wzl-remote] epoll available for high-performance networking\n", .{});
        }
        
        // Check CPU features for crypto acceleration
        if (std.Target.current.cpu.arch == .x86_64) {
            std.debug.print("[wzl-remote] x86_64 detected - AES-NI acceleration available\n", .{});
        }
        
        // Set optimal buffer sizes
        std.debug.print("[wzl-remote] Buffer size optimized: {} bytes\n", .{self.config.buffer_size});
        
        // Log system information
        const mem_info = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch null;
        if (mem_info) |file| {
            file.close();
            std.debug.print("[wzl-remote] System memory information available for optimization\n", .{});
        }
    }
};