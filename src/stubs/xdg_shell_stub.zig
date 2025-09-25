//! XDG Shell stub - minimal no-op implementation when XDG shell is disabled

const std = @import("std");

pub const xdg_wm_base_interface = struct {};
pub const xdg_surface_interface = struct {};
pub const xdg_toplevel_interface = struct {};
pub const xdg_popup_interface = struct {};

pub const XdgWmBase = struct {
    pub fn init() XdgWmBase {
        return .{};
    }

    pub fn deinit(self: *XdgWmBase) void {
        _ = self;
    }
};

pub const XdgSurface = struct {};
pub const XdgToplevel = struct {};