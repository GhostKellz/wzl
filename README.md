# wzl

<div align="center">
  <img src="assets/icons/wzl.png" alt="wzl icon" width="128" height="128">

**Wayland Zig Library – Modern Protocol Implementation**

![zig](https://img.shields.io/badge/Zig-v0.16-yellow?logo=zig)
![wayland](https://img.shields.io/badge/Wayland-Protocol-blue?logo=wayland)
![display](https://img.shields.io/badge/Display-Server-orange?logo=gnome)
![async](https://img.shields.io/badge/Async-zsync-green)

</div>

---

## Overview

**wzl** (Wayland Zig Library) is a **Zig-native implementation** of the Wayland protocol.  
It is built for developers who want to create compositors, display servers, remote desktops, or GUI-enabled applications with a clean, async-ready API.

Unlike C-based stacks, **wzl** leverages Zig’s memory safety, predictability, and async ecosystem to make Wayland development approachable and modern.

---

## Features

- 🔹 Full core Wayland protocol bindings  
- 🔹 Client & compositor support  
- 🔹 Event-driven architecture powered by [`zsync`](https://github.com/ghostkellz/zsync)  
- 🔹 Strong typing and safe buffer management  
- 🔹 Extension-ready (XDG shell, input, output, and more)  
- 🔹 Optional [`zcrypto`](https://github.com/ghostkellz/zcrypto) integration for secure remote sessions  

---

## Roadmap

- [ ] Core Wayland protocol (stable)  
- [ ] XDG shell support (windows, popups, layers)  
- [ ] Input devices (keyboard, mouse, touch, tablet)  
- [ ] Rendering backends (EGL, Vulkan, software)  
- [ ] Remote desktop + streaming over QUIC ([`zquic`](https://github.com/ghostkellz/zquic))  
- [ ] High-level compositor framework for custom shells  

---

## Example

```zig
const std = @import("std");
const wzl = @import("wzl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = &gpa.allocator;

    var client = try wzl.Client.init(allocator, .{});
    defer client.deinit();

    try client.connect();
    try client.run();
}

