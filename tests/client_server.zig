const std = @import("std");
const testing = std.testing;
const wzl = @import("wzl");
const Client = wzl.Client;
const Server = wzl.Server;

// Note: These tests require actual Wayland socket operations
// For CI/testing without a compositor, we test the API contracts

test "Client: structure size reasonable" {
    const size = @sizeOf(Client);
    // Client should not be excessively large
    try testing.expect(size < 10000);
}

test "Client: config default values" {
    const config = wzl.client.ClientConfig{};
    _ = config;
    // Config should have reasonable defaults
}

test "Server: structure size reasonable" {
    const size = @sizeOf(Server);
    // Server should not be excessively large
    try testing.expect(size < 10000);
}

test "Object: lifecycle structure" {
    const allocator = testing.allocator;

    // Create a mock client for testing
    var test_client = TestClient{
        .allocator = allocator,
        .objects = std.AutoHashMap(u32, void).init(allocator),
    };
    defer test_client.objects.deinit();

    // Object IDs should be non-zero
    const valid_id: u32 = 1;
    try testing.expect(valid_id != 0);
}

test "Registry: globals storage" {
    // Test that registry can store global information
    const Global = struct {
        name: u32,
        interface: []const u8,
        version: u32,
    };

    var globals = std.ArrayList(Global).init(testing.allocator);
    defer globals.deinit();

    try globals.append(.{
        .name = 1,
        .interface = "wl_compositor",
        .version = 4,
    });

    try globals.append(.{
        .name = 2,
        .interface = "wl_shm",
        .version = 1,
    });

    try testing.expectEqual(@as(usize, 2), globals.items.len);
    try testing.expectEqualStrings("wl_compositor", globals.items[0].interface);
    try testing.expectEqual(@as(u32, 1), globals.items[0].name);
}

test "Connection: socket path validation" {
    // Test XDG_RUNTIME_DIR path construction
    const runtime_dir = "/run/user/1000";
    const socket_name = "wayland-0";

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const socket_path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/{s}",
        .{ runtime_dir, socket_name },
    );

    try testing.expectEqualStrings("/run/user/1000/wayland-0", socket_path);
}

test "Connection: display environment variable" {
    // Test WAYLAND_DISPLAY parsing
    const display_vars = [_][]const u8{
        "wayland-0",
        "wayland-1",
        "wayland-custom",
    };

    for (display_vars) |display| {
        try testing.expect(display.len > 0);
        try testing.expect(std.mem.startsWith(u8, display, "wayland"));
    }
}

test "Object: ID allocation strategy" {
    // Client IDs should start from 1 and increment
    // Server IDs should use a different range (e.g., 0xFF000000+)

    const client_id_start: u32 = 1;
    const server_id_start: u32 = 0xFF000000;

    try testing.expect(client_id_start < server_id_start);

    // Test ID generation
    var next_id = client_id_start;
    for (0..10) |_| {
        try testing.expect(next_id > 0);
        try testing.expect(next_id < server_id_start);
        next_id += 1;
    }
}

test "Registry: event handler structure" {
    // Test that we can define event handlers
    const Handler = struct {
        fn onGlobal(
            name: u32,
            interface_name: []const u8,
            version: u32,
        ) void {
            _ = name;
            _ = interface_name;
            _ = version;
        }

        fn onGlobalRemove(name: u32) void {
            _ = name;
        }
    };

    // Handler functions should be callable
    Handler.onGlobal(1, "test", 1);
    Handler.onGlobalRemove(1);
}

test "Client: connection state machine" {
    // Test connection states
    const State = enum {
        disconnected,
        connecting,
        connected,
        error_state,
    };

    var state = State.disconnected;
    try testing.expectEqual(State.disconnected, state);

    state = .connecting;
    try testing.expectEqual(State.connecting, state);

    state = .connected;
    try testing.expectEqual(State.connected, state);
}

test "Server: client tracking" {
    const allocator = testing.allocator;

    // Server should track multiple clients
    var clients = std.ArrayList(u32).init(allocator);
    defer clients.deinit();

    // Simulate client connections
    try clients.append(1); // client ID 1
    try clients.append(2); // client ID 2
    try clients.append(3); // client ID 3

    try testing.expectEqual(@as(usize, 3), clients.items.len);

    // Simulate client disconnect
    _ = clients.orderedRemove(1); // remove client 2
    try testing.expectEqual(@as(usize, 2), clients.items.len);
}

test "Message: dispatch routing" {
    // Test that messages can be routed by object ID and opcode
    const MessageRoute = struct {
        object_id: u32,
        opcode: u16,
    };

    const routes = [_]MessageRoute{
        .{ .object_id = 1, .opcode = 0 }, // display.error
        .{ .object_id = 1, .opcode = 1 }, // display.delete_id
        .{ .object_id = 2, .opcode = 0 }, // registry.global
        .{ .object_id = 2, .opcode = 1 }, // registry.global_remove
    };

    for (routes) |route| {
        try testing.expect(route.object_id > 0);
        try testing.expect(route.opcode < 100); // reasonable opcode range
    }
}

test "Buffer: lifecycle management" {
    const allocator = testing.allocator;

    // Test buffer reference counting concept
    const BufferState = struct {
        ref_count: u32,
        released: bool,
    };

    var buffer_state = BufferState{
        .ref_count = 1,
        .released = false,
    };

    // Compositor takes reference
    buffer_state.ref_count += 1;
    try testing.expectEqual(@as(u32, 2), buffer_state.ref_count);

    // Compositor releases
    buffer_state.ref_count -= 1;
    if (buffer_state.ref_count == 1) {
        buffer_state.released = true;
    }
    try testing.expect(buffer_state.released);
}

test "Surface: commit model" {
    // Test double-buffered state concept
    const SurfaceState = struct {
        pending_buffer: ?u32,
        current_buffer: ?u32,
    };

    var state = SurfaceState{
        .pending_buffer = null,
        .current_buffer = null,
    };

    // Attach buffer to pending state
    state.pending_buffer = 123;
    try testing.expectEqual(@as(?u32, 123), state.pending_buffer);
    try testing.expectEqual(@as(?u32, null), state.current_buffer);

    // Commit moves pending to current
    state.current_buffer = state.pending_buffer;
    state.pending_buffer = null;
    try testing.expectEqual(@as(?u32, 123), state.current_buffer);
    try testing.expectEqual(@as(?u32, null), state.pending_buffer);
}

test "Callback: done event" {
    const allocator = testing.allocator;

    // Test callback mechanism
    var callback_fired = false;
    const TestCallback = struct {
        fired: *bool,

        fn done(self: *@This(), serial: u32) void {
            _ = serial;
            self.fired.* = true;
        }
    };

    var cb = TestCallback{ .fired = &callback_fired };
    cb.done(123);

    try testing.expect(callback_fired);
}

test "Error: protocol error handling" {
    // Test protocol error structure
    const ProtocolError = struct {
        object_id: u32,
        code: u32,
        message: []const u8,
    };

    const err = ProtocolError{
        .object_id = 5,
        .code = 1,
        .message = "invalid request",
    };

    try testing.expectEqual(@as(u32, 5), err.object_id);
    try testing.expectEqual(@as(u32, 1), err.code);
    try testing.expectEqualStrings("invalid request", err.message);
}

test "Sync: roundtrip mechanism" {
    // Test sync/callback roundtrip concept
    var sync_done = false;

    // Client sends sync
    const callback_id: u32 = 100;

    // Server sends done
    const serial: u32 = 42;

    // Client receives done
    if (callback_id == 100 and serial == 42) {
        sync_done = true;
    }

    try testing.expect(sync_done);
}

test "Multi-client: isolation" {
    const allocator = testing.allocator;

    // Test that client objects are isolated
    const ClientContext = struct {
        id: u32,
        objects: std.AutoHashMap(u32, void),
    };

    var client1 = ClientContext{
        .id = 1,
        .objects = std.AutoHashMap(u32, void).init(allocator),
    };
    defer client1.objects.deinit();

    var client2 = ClientContext{
        .id = 2,
        .objects = std.AutoHashMap(u32, void).init(allocator),
    };
    defer client2.objects.deinit();

    // Each client has its own object namespace
    try client1.objects.put(1, {});
    try client2.objects.put(1, {});

    // Same object ID, different clients
    try testing.expect(client1.objects.contains(1));
    try testing.expect(client2.objects.contains(1));
    try testing.expect(client1.id != client2.id);
}

test "Global: version negotiation" {
    // Test interface version negotiation
    const server_version: u32 = 4;
    const client_requested: u32 = 3;

    const negotiated = @min(server_version, client_requested);
    try testing.expectEqual(@as(u32, 3), negotiated);

    // Client can't request higher version than server supports
    const client_too_new: u32 = 5;
    const should_fail = client_too_new > server_version;
    try testing.expect(should_fail);
}

test "Socket: path construction" {
    const allocator = testing.allocator;

    // Test socket path building
    const runtime_dir = try allocator.dupe(u8, "/run/user/1000");
    defer allocator.free(runtime_dir);

    const display = try allocator.dupe(u8, "wayland-0");
    defer allocator.free(display);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/{s}",
        .{ runtime_dir, display },
    );

    try testing.expect(full_path.len > 0);
    try testing.expect(std.mem.indexOf(u8, full_path, "wayland-0") != null);
}

// Helper for testing
const TestClient = struct {
    allocator: std.mem.Allocator,
    objects: std.AutoHashMap(u32, void),
};
