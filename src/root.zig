//! wzl (Wayland Zig Library) - Modern Wayland protocol implementation in Zig
const std = @import("std");
const zsync = @import("zsync");

// Core protocol implementation
pub const protocol = @import("protocol.zig");
pub const connection = @import("connection.zig");

// Extensions
pub const xdg_shell = @import("xdg_shell.zig");
pub const input = @import("input.zig");
pub const output = @import("output.zig");
pub const buffer = @import("buffer.zig");

// Advanced features
pub const compositor = @import("compositor.zig");
pub const remote = @import("remote.zig");
pub const quic_streaming = @import("quic_streaming.zig");
pub const remote_desktop = @import("remote_desktop.zig");
pub const terminal = @import("terminal.zig");
pub const clipboard = @import("clipboard.zig");

// Client and server APIs
pub const client = @import("client.zig");
pub const server = @import("server.zig");

// Main exports
pub const Client = client.Client;
pub const Server = server.Server;
pub const Connection = connection.Connection;
pub const Message = protocol.Message;
pub const ObjectId = protocol.ObjectId;
pub const Interface = protocol.Interface;

// Convenience exports for common interfaces
pub const wl_display_interface = protocol.wl_display_interface;
pub const wl_registry_interface = protocol.wl_registry_interface;
pub const wl_compositor_interface = protocol.wl_compositor_interface;
pub const wl_surface_interface = protocol.wl_surface_interface;
pub const wl_callback_interface = protocol.wl_callback_interface;

// XDG Shell exports
pub const xdg_wm_base_interface = xdg_shell.xdg_wm_base_interface;
pub const xdg_surface_interface = xdg_shell.xdg_surface_interface;
pub const xdg_toplevel_interface = xdg_shell.xdg_toplevel_interface;
pub const xdg_popup_interface = xdg_shell.xdg_popup_interface;
pub const XdgWmBase = xdg_shell.XdgWmBase;
pub const XdgSurface = xdg_shell.XdgSurface;
pub const XdgToplevel = xdg_shell.XdgToplevel;

// Input exports
pub const wl_seat_interface = input.wl_seat_interface;
pub const wl_pointer_interface = input.wl_pointer_interface;
pub const wl_keyboard_interface = input.wl_keyboard_interface;
pub const wl_touch_interface = input.wl_touch_interface;
pub const Seat = input.Seat;
pub const Pointer = input.Pointer;
pub const Keyboard = input.Keyboard;
pub const Touch = input.Touch;

// Output exports  
pub const Output = output.Output;
pub const OutputInfo = output.OutputInfo;
pub const OutputTransform = output.OutputTransform;

// Buffer exports
pub const ShmPool = buffer.ShmPool;
pub const Shm = buffer.Shm;
pub const Buffer = buffer.Buffer;
pub const ShmFormat = buffer.ShmFormat;
pub const createMemoryMappedBuffer = buffer.createMemoryMappedBuffer;

// Advanced feature exports
pub const CompositorFramework = compositor.CompositorFramework;
pub const CompositorConfig = compositor.CompositorConfig;
pub const RemoteServer = remote.RemoteServer;
pub const RemoteClient = remote.RemoteClient;
pub const QuicServer = quic_streaming.QuicServer;
pub const QuicStream = quic_streaming.QuicStream;
pub const FrameMetadata = quic_streaming.FrameMetadata;
pub const FrameFlags = quic_streaming.FrameFlags;
pub const RemoteDesktopServer = remote_desktop.RemoteDesktopServer;
pub const RemoteDesktopConfig = remote_desktop.RemoteDesktopConfig;

// Terminal emulation exports (Ghostty integration)
pub const WaylandTerminal = terminal.WaylandTerminal;
pub const TerminalConfig = terminal.TerminalConfig;
pub const TerminalBuffer = terminal.TerminalBuffer;
pub const Cell = terminal.Cell;
pub const TerminalColor = terminal.Color;
pub const Cursor = terminal.Cursor;

// Clipboard exports
pub const ClipboardManager = clipboard.ClipboardManager;
pub const ClipboardData = clipboard.ClipboardData;
pub const DataSource = clipboard.DataSource;
pub const MimeType = clipboard.MimeType;

// Window decoration and theming exports
pub const decorations = @import("decorations.zig");
pub const DecorationManager = decorations.DecorationManager;
pub const DecorationSurface = decorations.DecorationSurface;
pub const DecorationConfig = decorations.DecorationConfig;
pub const Theme = decorations.Theme;
pub const ThemeLoader = decorations.ThemeLoader;
pub const DecorationColor = decorations.Color;
pub const ButtonType = decorations.ButtonType;
pub const ButtonState = decorations.ButtonState;

pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("wzl - Wayland Zig Library v0.0.0\n", .{});
    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush();
}

test "basic protocol functionality" {
    const allocator = std.testing.allocator;
    
    // Test message creation and serialization
    const message = try protocol.Message.init(
        allocator,
        1, // object_id
        0, // opcode
        &[_]protocol.Argument{
            .{ .uint = 42 },
        },
    );
    
    var msg_buffer: [64]u8 = undefined;
    const size = try message.serialize(&msg_buffer);
    try std.testing.expect(size > 0);
}

test "client initialization" {
    // This test would require a running Wayland compositor
    // For now, just test that the client can be created without connecting    
    // Test that Client struct can be initialized (without actual connection)
    const client_config = .{};
    _ = client_config;
    
    // We can't actually test connection without a running compositor
    // but we can test the struct definitions compile correctly
    try std.testing.expect(@TypeOf(Client) == type);
}
