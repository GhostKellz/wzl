//! wzl (Wayland Zig Library) - Modern Wayland protocol implementation in Zig
const std = @import("std");
const zsync = @import("zsync");

// Feature configuration
pub const features = @import("features.zig");
pub const Features = features.Features;

// Core protocol implementation (always available)
pub const protocol = @import("protocol.zig");
pub const connection = @import("connection.zig");
pub const client = @import("client.zig");
pub const server = @import("server.zig");

// Conditional feature imports
pub const xdg_shell = if (Features.xdg_shell) @import("xdg_shell.zig") else @import("stubs/xdg_shell_stub.zig");
pub const input = @import("input.zig"); // Always needed for basic input
pub const output = @import("output.zig"); // Always needed for displays
pub const buffer = @import("buffer.zig"); // Always needed for surfaces

// Touch and tablet input features
pub const touch_input = if (Features.touch_input) @import("touch_input.zig") else @import("stubs/touch_stub.zig");
pub const tablet_input = if (Features.tablet_input) @import("tablet_input.zig") else @import("stubs/tablet_stub.zig");

// Clipboard and data transfer
pub const clipboard = if (Features.clipboard) @import("clipboard.zig") else @import("stubs/clipboard_stub.zig");

// Phase 2 Advanced Features
pub const hardware_cursor = if (Features.hardware_cursor) @import("hardware_cursor.zig") else @import("stubs/hardware_cursor_stub.zig");
pub const multi_gpu = if (Features.multi_gpu) @import("multi_gpu.zig") else @import("stubs/multi_gpu_stub.zig");
pub const fractional_scaling = if (Features.fractional_scaling) @import("fractional_scaling.zig") else @import("stubs/fractional_scaling_stub.zig");

// Advanced features
pub const compositor = if (Features.compositor_framework) @import("compositor.zig") else @import("stubs/compositor_stub.zig");
pub const remote = if (Features.remote_desktop) @import("remote.zig") else @import("stubs/remote_stub.zig");
pub const quic_streaming = if (Features.quic_streaming) @import("quic_streaming.zig") else @import("stubs/quic_stub.zig");
pub const remote_desktop = if (Features.remote_desktop) @import("remote_desktop.zig") else @import("stubs/remote_desktop_stub.zig");
pub const terminal = if (Features.terminal_integration) @import("terminal.zig") else @import("stubs/terminal_stub.zig");

// Rendering backends
pub const rendering = @import("rendering.zig");

// Utility modules
pub const errors = @import("errors.zig");
pub const memory = if (Features.memory_tracking) @import("memory.zig") else @import("stubs/memory_stub.zig");
pub const thread_safety = @import("thread_safety.zig");

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

// Phase 2 Feature exports
pub const HardwareCursorManager = hardware_cursor.HardwareCursorManager;
pub const CursorPlane = hardware_cursor.CursorPlane;
pub const CursorTheme = hardware_cursor.CursorTheme;
pub const MultiGpuManager = multi_gpu.MultiGpuManager;
pub const GpuDevice = multi_gpu.GpuDevice;
pub const GpuVendor = multi_gpu.GpuVendor;
pub const FractionalScalingManager = fractional_scaling.FractionalScalingManager;
pub const FractionalScale = fractional_scaling.FractionalScale;
pub const SurfaceScale = fractional_scaling.SurfaceScale;

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
