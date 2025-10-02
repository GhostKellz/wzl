## wzl (Wayland Zig Library)

### Phase 1 – Core Protocol ✅
- [x] Implement Wayland core protocol message definitions in Zig
- [x] Build async client connection API (`wzl.Client`)
- [x] Build async compositor connection API (`wzl.Server`)
- [x] Add event loop integration with `zsync`
- [x] Provide minimal surface creation and destruction

### Phase 2 – Extensions
- [x] XDG shell support (windows, popups, layers)
- [x] Input device support (keyboard, mouse, touch, tablet)
- [x] Output management (monitors, scaling, transforms)
- [x] Buffer management (shm, dmabuf, EGL)

### Phase 3 – Advanced
Zig fetch --Sav https://url.com # example if we need external deps 
- [x] Compositor utility framework
- [x] Remote Wayland sessions encrypted with `zcrypto` - https://githhub.com/ghostkellz/zcrypto
- [x] Streaming Wayland over QUIC with `zquic` - https://github.com/ghostkellz/zquic
- [x] Example compositor implementation

### Phase 1.5 – Polish Core ✅
- [x] Complete Event Loop Integration with zsync
- [x] Add Comprehensive Unit Tests
- [x] Validate Core Functionality
- [x] Update TODO.md

### Phase 2.5 – Enhance Extensions
- [x] Rendering Backends: Add support for EGL, Vulkan, or software rendering backends for actual pixel output
- [x] Buffer Management Expansion: Implement dmabuf support alongside existing SHM buffers
- [x] Clipboard Integration: Flesh out clipboard.zig for data transfer protocols
- [x] Decorations & Terminal: Complete decorations.zig and terminal.zig for window borders and terminal emulation

### Phase 3.5 – Ecosystem & Performance
- [x] High-Level Compositor Framework: Expand compositor.zig with more utilities for scene management, input routing, and output rendering
- [x] Performance Optimizations: Profile and optimize message serialization and high-frequency input event handling
- [x] Cross-Platform Support: Ensure compatibility beyond Arch Linux, testing on other distributions and systems
- [x] Documentation & Examples: Add comprehensive examples, tutorials, and API documentation for the library

---
