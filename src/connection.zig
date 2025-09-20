const std = @import("std");
const net = std.net;
const fs = std.fs;
const os = std.os;
const protocol = @import("protocol.zig");
const zsync = @import("zsync");

pub const Connection = struct {
    socket: net.Stream,
    allocator: std.mem.Allocator,
    receive_buffer: [4096]u8,
    send_buffer: [4096]u8,
    fd_queue: std.ArrayList(std.fs.File.Handle),
    runtime: ?*zsync.Runtime = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, socket: net.Stream) Connection {
        return Connection{
            .socket = socket,
            .allocator = allocator,
            .receive_buffer = undefined,
            .send_buffer = undefined,
            .fd_queue = std.ArrayList(std.fs.File.Handle){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.socket.close();
        // fd_queue doesn't need explicit deinit in this simple case
    }

    pub fn connectToWaylandSocket(allocator: std.mem.Allocator, runtime: ?*zsync.Runtime) !Connection {
        const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";

        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const socket_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ xdg_runtime_dir, wayland_display });

        const socket_addr = try net.Address.initUnix(socket_path);
        const socket = try net.tcpConnectToAddress(socket_addr);

        var conn = init(allocator, socket);
        conn.runtime = runtime;
        return conn;
    }

    pub fn sendMessage(self: *Self, message: protocol.Message) !void {
        const bytes_written = try message.serialize(&self.send_buffer);
        if (self.runtime) |_| {
            // TODO: Use zsync async write
            _ = try self.socket.writeAll(self.send_buffer[0..bytes_written]);
        } else {
            _ = try self.socket.writeAll(self.send_buffer[0..bytes_written]);
        }
    }

    pub fn receiveMessage(self: *Self) !protocol.Message {
        var bytes_read: usize = 0;
        while (bytes_read < @sizeOf(protocol.MessageHeader)) {
            const n = if (self.runtime) |_| blk: {
                // TODO: Use zsync async read
                break :blk try self.socket.read(self.receive_buffer[bytes_read..]);
            } else blk: {
                break :blk try self.socket.read(self.receive_buffer[bytes_read..]);
            };
            if (n == 0) return error.ConnectionClosed;
            bytes_read += n;
        }

        const header = protocol.MessageHeader{
            .object_id = std.mem.readInt(u32, @ptrCast(self.receive_buffer[0..4]), .little),
            .opcode = std.mem.readInt(u16, @ptrCast(self.receive_buffer[4..6]), .little),
            .size = std.mem.readInt(u16, @ptrCast(self.receive_buffer[6..8]), .little),
        };

        if (header.size > self.receive_buffer.len) {
            return error.MessageTooLarge;
        }

        while (bytes_read < header.size) {
            const n = if (self.runtime) |_| blk: {
                // TODO: Use zsync async read
                break :blk try self.socket.read(self.receive_buffer[bytes_read..]);
            } else blk: {
                break :blk try self.socket.read(self.receive_buffer[bytes_read..]);
            };
            if (n == 0) return error.ConnectionClosed;
            bytes_read += n;
        }

        return try protocol.Message.deserialize(self.allocator, self.receive_buffer[0..header.size]);
    }

    pub fn flush(self: *Self) !void {
        _ = self;
        // Wayland protocol doesn't require explicit flushing as messages are sent immediately
    }
};

pub const WaylandSocket = struct {
    socket: std.fs.File,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.NoRuntimeDir;

        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const socket_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ xdg_runtime_dir, wayland_display });

        const socket_fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
        const socket_file = std.fs.File{ .handle = socket_fd };

        const addr = std.posix.sockaddr.un{
            .family = std.posix.AF.UNIX,
            .path = undefined,
        };
        var sockaddr = addr;
        @memcpy(sockaddr.path[0..socket_path.len], socket_path);
        sockaddr.path[socket_path.len] = 0;

        try std.posix.connect(socket_fd, @ptrCast(&sockaddr), @sizeOf(@TypeOf(sockaddr)));

        return Self{
            .socket = socket_file,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.socket.close();
    }

    pub fn send(self: *Self, data: []const u8) !usize {
        return try self.socket.writeAll(data);
    }

    pub fn receive(self: *Self, buffer: []u8) !usize {
        return try self.socket.readAll(buffer);
    }
};

test "Connection buffer operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test FixedPoint in connection context
    const fp = protocol.FixedPoint.fromFloat(2.0);
    try std.testing.expectEqual(@as(f32, 2.0), fp.toFloat());

    // Note: Actual connection tests would require mocking the socket
    _ = allocator;
}
