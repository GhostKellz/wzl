# wzl - Wayland Zig Library Development Roadmap

**Vision**: Production-ready Wayland protocol implementation in Zig for clients, compositors, and terminal emulators.

**Current State**: ~28K LOC, Core protocol complete, Most features implemented, Stubs minimal, Ready for production hardening.

---

## Current Implementation Status ✅

### Core Protocol (100% Complete)
- ✅ Wayland protocol implementation (`protocol.zig` - 443 LOC)
- ✅ Client API (`client.zig` - 445 LOC)
- ✅ Server API (`server.zig` - 448 LOC)
- ✅ Connection management (`connection.zig`)
- ✅ Message serialization/deserialization
- ✅ Object lifecycle management
- ✅ Buffer management (`buffer.zig` - 408 LOC)
- ✅ Input handling (`input.zig`)
- ✅ Output management (`output.zig`)

### Advanced Features (90% Complete)
- ✅ XDG Shell (`xdg_shell.zig` - 581 LOC)
- ✅ Touch input (`touch_input.zig` - 592 LOC)
- ✅ Tablet input (`tablet_input.zig` - 568 LOC)
- ✅ Clipboard (`clipboard.zig` - 510 LOC)
- ✅ Hardware cursor (`hardware_cursor.zig` - 536 LOC)
- ✅ Multi-GPU support (`multi_gpu.zig` - 755 LOC)
- ✅ Fractional scaling (`fractional_scaling.zig` - 611 LOC)
- ✅ Color management (`color_management.zig`)
- ✅ Decorations (`decorations.zig` - 653 LOC)
- ✅ Screen capture (`screen_capture.zig` - 447 LOC)

### Rendering Backends (95% Complete)
- ✅ Software renderer (`rendering.zig`)
- ✅ EGL backend (`egl_backend.zig` - 420 LOC)
- ✅ Vulkan backend (`vulkan_backend.zig` - 668 LOC)

### Compositor Framework (90% Complete)
- ✅ Compositor framework (`compositor.zig` - 662 LOC)
- ✅ Window management
- ✅ Surface management

### Remote Desktop & Streaming (85% Complete)
- ✅ Remote desktop (`remote_desktop.zig` - 614 LOC)
- ✅ QUIC streaming (`quic_streaming.zig`)
- ✅ Remote session management (`remote.zig`)
- ⚠️ H.264 encoding (flagged as TODO)

### Terminal Integration (90% Complete)
- ✅ Terminal emulator support (`terminal.zig` - 549 LOC)
- ✅ Ghostty integration ready

### Utilities (100% Complete)
- ✅ Memory tracking (`memory.zig` - 471 LOC)
- ✅ Thread safety (`thread_safety.zig` - 480 LOC)
- ✅ Error handling (`errors.zig`)
- ✅ Feature flags (`features.zig`)

---

## PHASE 1: CORE STABILIZATION & TESTING (Weeks 1-2)

**Goal**: Harden the core protocol, fix bugs, comprehensive testing

### 1.1 Protocol Testing & Validation

**Priority**: CRITICAL

**Tasks**:
- [ ] Write comprehensive protocol tests
  - Message serialization/deserialization
  - All argument types (int, uint, fixed, string, object, new_id, array, fd)
  - Edge cases (max sizes, alignment, null handling)
  - Error conditions (invalid objects, buffer overflow)
- [ ] Test client lifecycle
  - Connection establishment
  - Registry discovery
  - Global binding
  - Object creation/destruction
  - Clean disconnection
- [ ] Test server lifecycle
  - Socket creation and binding
  - Client connection handling
  - Multi-client support
  - Client disconnection cleanup
- [ ] Protocol compliance testing
  - Wayland protocol scanner output comparison
  - Wire format validation
  - Version negotiation
  - Interface compatibility

**Files**:
- `src/tests/protocol_test.zig` (exists but needs expansion)
- `tests/core_protocol.zig` (new)
- `tests/client_server.zig` (new)
- `tests/message_codec.zig` (new)

**Deliverable**: 90%+ test coverage on core protocol

---

### 1.2 Memory Safety & Leak Detection

**Priority**: CRITICAL

**Tasks**:
- [ ] Audit all allocations
  - Ensure all `allocator.alloc()` have matching `free()`
  - Check arena allocators for proper lifecycle
  - Verify object cleanup in destructors
- [ ] Add allocation tracking
  - Hook into memory.zig tracking
  - Log allocation/free pairs
  - Detect double-free
  - Detect use-after-free
- [ ] Run Valgrind on test suite
  - Zero memory leaks goal
  - Fix any detected issues
- [ ] Stress test object lifecycle
  - Create/destroy 10K+ objects
  - Verify memory usage returns to baseline
  - Check for fragmentation

**Files**:
- `src/memory.zig` (enhance tracking)
- `tests/memory_leak_test.zig` (new)
- `tests/stress_test.zig` (new)

**Deliverable**: Zero memory leaks under Valgrind

---

### 1.3 Thread Safety Audit

**Priority**: HIGH

**Tasks**:
- [ ] Identify shared mutable state
  - Client objects map
  - Server clients list
  - Registry globals
  - Connection socket
- [ ] Add mutex protection where needed
  - Document locking order
  - Prevent deadlocks
  - Minimize critical sections
- [ ] Test concurrent access
  - Multi-threaded client
  - Multi-threaded server
  - Stress test race conditions
- [ ] Enable thread safety debugging
  - Use `thread_safety.zig` utilities
  - Detect unlocked access
  - Validate lock ordering

**Files**:
- `src/thread_safety.zig` (enhance)
- `src/client.zig` (audit locks)
- `src/server.zig` (audit locks)
- `tests/thread_safety_test.zig` (new)

**Deliverable**: Thread-safe client & server

---

### 1.4 Error Handling & Recovery

**Priority**: HIGH

**Tasks**:
- [ ] Audit all error returns
  - Consistent error types
  - Meaningful error messages
  - Proper error propagation
- [ ] Add error recovery paths
  - Graceful degradation
  - Connection recovery
  - Protocol errors handling
- [ ] Test error conditions
  - Invalid messages
  - Protocol violations
  - Out-of-memory scenarios
  - Socket errors
- [ ] Document error handling patterns
  - When to retry
  - When to fail fast
  - Error reporting to users

**Files**:
- `src/errors.zig` (enhance)
- `tests/error_handling_test.zig` (new)
- `docs/error-handling.md` (new)

**Deliverable**: Robust error handling throughout

---

## PHASE 2: ADVANCED FEATURES COMPLETION (Weeks 3-4)

**Goal**: Complete H.264 encoding, polish advanced features, integration testing

### 2.1 H.264 Video Encoding

**Priority**: MEDIUM (for remote desktop users)

**Current State**: Feature flag exists but not implemented

**Tasks**:
- [ ] Evaluate H.264 libraries
  - x264 (C library, battle-tested)
  - OpenH264 (Cisco, BSD licensed)
  - FFmpeg integration
  - Native Zig implementation (long-term)
- [ ] Implement encoder wrapper
  - C FFI bindings if using x264/OpenH264
  - Frame encoding API
  - Bitrate control
  - GOP configuration
- [ ] Integrate with screen capture
  - Frame format conversion (RGB → YUV420)
  - Hardware acceleration (VAAPI/NVENC)
  - Adaptive bitrate
- [ ] QUIC streaming integration
  - H.264 NAL unit packetization
  - Frame prioritization
  - Loss recovery
- [ ] Performance optimization
  - Zero-copy where possible
  - Multi-threaded encoding
  - GPU encoding path

**Files**:
- `src/video_encoding.zig` (new)
- `src/h264_encoder.zig` (new)
- `build.zig` (add H.264 lib linking)
- `tests/video_encoding_test.zig` (new)

**Deliverable**: Working H.264 encoding for remote desktop

---

### 2.2 Rendering Backend Polish

**Priority**: HIGH (for visual correctness)

**Tasks**:
- [ ] EGL Backend
  - Test on Mesa/Intel/NVIDIA drivers
  - Verify EGLImage zero-copy path
  - Fix buffer lifecycle issues
  - Add fallback paths for missing extensions
- [ ] Vulkan Backend
  - Test on multiple GPUs
  - Validate image layout transitions
  - Fix synchronization issues
  - Optimize descriptor sets
- [ ] Software Renderer
  - Optimize pixel format conversions
  - Add SIMD optimizations
  - Test color accuracy
  - Benchmark performance
- [ ] Multi-GPU coordination
  - Test GPU → GPU copy
  - Validate DMA-BUF import/export
  - Handle hot-plug events
  - Fallback to software renderer

**Files**:
- `src/egl_backend.zig` (polish)
- `src/vulkan_backend.zig` (polish)
- `src/rendering.zig` (optimize)
- `tests/rendering_test.zig` (new)

**Deliverable**: Rock-solid rendering across all backends

---

### 2.3 XDG Shell & Window Management

**Priority**: CRITICAL (for desktop apps)

**Tasks**:
- [ ] XDG Shell completeness
  - Test xdg_wm_base ping/pong
  - Verify xdg_surface configure
  - Test xdg_toplevel resize/move
  - Validate xdg_popup positioning
  - Test xdg_decoration negotiation
- [ ] Window state handling
  - Maximized state
  - Fullscreen state
  - Minimized state
  - Tiled states
- [ ] Compositor integration
  - Surface commit handling
  - Double-buffered state
  - Subsurface support
  - Role assignment
- [ ] Client integration testing
  - GTK apps
  - Qt apps
  - SDL apps
  - Custom clients

**Files**:
- `src/xdg_shell.zig` (enhance)
- `src/compositor.zig` (enhance)
- `tests/xdg_shell_test.zig` (new)
- `examples/xdg_client.zig` (new)

**Deliverable**: Full XDG Shell compatibility

---

### 2.4 Input Device Polish

**Priority**: HIGH

**Tasks**:
- [ ] Touch input
  - Multi-touch tracking
  - Touch point lifecycle
  - Gesture recognition
  - Palm rejection (future)
- [ ] Tablet input
  - Pressure curve handling
  - Tilt support
  - Button mapping
  - Proximity events
- [ ] Pointer input
  - Cursor themes
  - Scroll wheel
  - Mouse buttons
  - High-resolution scroll
- [ ] Keyboard input
  - Keymap handling
  - Repeat rate
  - Compose key support
  - IME integration (future)

**Files**:
- `src/touch_input.zig` (enhance)
- `src/tablet_input.zig` (enhance)
- `src/input.zig` (enhance)
- `tests/input_test.zig` (new)

**Deliverable**: Complete input device support

---

## PHASE 3: COMPOSITOR & REMOTE DESKTOP (Weeks 5-6)

**Goal**: Production-ready compositor framework and remote desktop

### 3.1 Compositor Framework Hardening

**Priority**: HIGH

**Tasks**:
- [ ] Surface management
  - Surface tree traversal
  - Subsurface ordering
  - Damage tracking
  - Buffer release timing
- [ ] Output management
  - Multi-monitor support
  - Hot-plug handling
  - DPMS control
  - Mode switching
- [ ] Input routing
  - Focus management
  - Keyboard grab
  - Pointer grab
  - Touch grab
- [ ] Client resource tracking
  - Memory limits
  - Object limits
  - Rate limiting
  - DoS prevention
- [ ] Compositor example
  - Minimal Wayland compositor
  - Window stacking
  - Keyboard/mouse routing
  - Multi-output support

**Files**:
- `src/compositor.zig` (harden)
- `examples/simple_compositor.zig` (enhance)
- `examples/full_compositor.zig` (new)
- `tests/compositor_test.zig` (new)

**Deliverable**: Production-ready compositor framework

---

### 3.2 Remote Desktop Production Readiness

**Priority**: MEDIUM

**Tasks**:
- [ ] QUIC streaming optimization
  - Connection migration
  - 0-RTT resumption
  - Congestion control tuning
  - Packet pacing
- [ ] Frame capture optimization
  - DMA-BUF zero-copy
  - Partial screen updates
  - Cursor compositing
  - Damage regions
- [ ] Network adaptation
  - Bandwidth estimation
  - Dynamic quality adjustment
  - Frame rate adaptation
  - Resolution scaling
- [ ] Security hardening
  - Authentication
  - Authorization
  - Encryption (via zquic)
  - Rate limiting
- [ ] Client reconnection
  - Session resumption
  - State recovery
  - Graceful degradation

**Files**:
- `src/remote_desktop.zig` (harden)
- `src/quic_streaming.zig` (optimize)
- `src/screen_capture.zig` (optimize)
- `examples/remote_desktop_server.zig` (new)
- `tests/remote_desktop_test.zig` (new)

**Deliverable**: Production remote desktop server

---

### 3.3 Terminal Emulator Integration

**Priority**: MEDIUM

**Tasks**:
- [ ] Validate Ghostty integration
  - Test wzl with Ghostty
  - Fix any compatibility issues
  - Performance profiling
  - Memory usage optimization
- [ ] Terminal-specific optimizations
  - Text rendering path
  - Glyph caching
  - Damage tracking for text
  - Cursor updates
- [ ] PTY integration
  - Non-blocking I/O
  - UTF-8 handling
  - Control sequences
  - Window resize signaling
- [ ] Document integration guide
  - How to integrate wzl in terminals
  - Performance best practices
  - Example code
  - Migration guide

**Files**:
- `src/terminal.zig` (validate)
- `docs/integrations/terminal-emulators.md` (enhance)
- `examples/terminal_client.zig` (new)
- `tests/terminal_integration_test.zig` (new)

**Deliverable**: Ghostty running on wzl

---

## PHASE 4: PERFORMANCE & OPTIMIZATION (Week 7)

**Goal**: Optimize hot paths, reduce latency, improve throughput

### 4.1 Protocol Performance

**Priority**: HIGH

**Tasks**:
- [ ] Message batching
  - Batch small messages
  - Flush on sync
  - Tunable batch size
- [ ] Zero-copy paths
  - Use DMA-BUF where possible
  - Avoid memcpy in hot paths
  - Shared memory optimization
- [ ] Syscall reduction
  - Use io_uring (via zsync)
  - Reduce socket writes
  - Batch fd passing
- [ ] Profiling
  - Identify hot paths
  - CPU flamegraphs
  - Memory allocation profiling
  - Lock contention analysis

**Files**:
- `src/protocol.zig` (optimize)
- `src/connection.zig` (optimize)
- `benchmarks/protocol_bench.zig` (new)
- `benchmarks/latency_test.zig` (new)

**Deliverable**: <1ms protocol latency

---

### 4.2 Rendering Performance

**Priority**: HIGH

**Tasks**:
- [ ] GPU upload optimization
  - Persistent mapping
  - Staging buffers
  - Transfer queue
- [ ] Damage tracking
  - Minimize redraws
  - Dirty region optimization
  - Cursor plane optimization
- [ ] Compositor rendering
  - Scene graph optimization
  - Culling invisible surfaces
  - Layer composition
  - Hardware overlays
- [ ] Benchmark suite
  - FPS counter
  - Frame timing
  - Render thread latency
  - Memory bandwidth

**Files**:
- `src/rendering.zig` (optimize)
- `src/egl_backend.zig` (optimize)
- `src/vulkan_backend.zig` (optimize)
- `benchmarks/rendering_bench.zig` (new)

**Deliverable**: 60+ FPS on desktop, <16ms frame time

---

### 4.3 Memory Optimization

**Priority**: MEDIUM

**Tasks**:
- [ ] Reduce allocations
  - Pool common objects
  - Stack allocate small buffers
  - Arena allocators for scoped work
- [ ] Cache optimization
  - Hot data in L1 cache
  - Avoid false sharing
  - Align critical structs
- [ ] Memory footprint
  - Measure baseline usage
  - Identify bloat
  - Optimize data structures
  - Release unused memory
- [ ] Fragmentation prevention
  - Use slab allocators
  - Preallocate pools
  - Defragmentation strategy

**Files**:
- `src/memory.zig` (optimize)
- `benchmarks/memory_bench.zig` (new)

**Deliverable**: <50MB memory usage for typical client

---

## PHASE 5: DOCUMENTATION & EXAMPLES (Week 8)

**Goal**: Comprehensive docs, tutorials, example code

### 5.1 API Documentation

**Priority**: HIGH

**Tasks**:
- [ ] Core API docs
  - Client API
  - Server API
  - Protocol types
  - Connection management
- [ ] Feature docs
  - XDG Shell
  - Input devices
  - Rendering backends
  - Compositor framework
  - Remote desktop
- [ ] Auto-generate docs
  - Use `zig build-docs`
  - Publish to GitHub Pages
  - Version docs properly

**Files**:
- `docs/api/` (expand)
- `docs/API.md` (complete)
- All src/*.zig (add doc comments)

**Deliverable**: Complete API documentation

---

### 5.2 User Guides

**Priority**: HIGH

**Tasks**:
- [ ] Getting Started guide
  - Installation
  - First client
  - First server
  - Building from source
- [ ] Architecture guide
  - System design
  - Protocol flow
  - Threading model
  - Memory management
- [ ] Integration guides
  - Terminal emulators
  - GUI toolkits
  - Game engines
  - Remote desktop
- [ ] Performance guide
  - Profiling tools
  - Optimization tips
  - Best practices
  - Common pitfalls

**Files**:
- `docs/getting-started.md` (enhance)
- `docs/ARCHITECTURE.md` (enhance)
- `docs/integrations/` (expand)
- `docs/performance.md` (new)

**Deliverable**: Complete user documentation

---

### 5.3 Example Applications

**Priority**: MEDIUM

**Tasks**:
- [ ] Basic client examples
  - Hello world window
  - Drawing with shm
  - EGL rendering
  - Vulkan rendering
- [ ] Input examples
  - Keyboard input
  - Mouse/pointer
  - Touch gestures
  - Tablet drawing
- [ ] Compositor examples
  - Minimal compositor
  - Multi-output compositor
  - Window manager
  - Tiling compositor
- [ ] Advanced examples
  - Remote desktop server
  - Screen sharing
  - Video player
  - Game using wzl

**Files**:
- `examples/basic_client.zig` (enhance)
- `examples/egl_client.zig` (new)
- `examples/vulkan_client.zig` (new)
- `examples/input_demo.zig` (new)
- `examples/minimal_wm.zig` (new)

**Deliverable**: 10+ working examples

---

## PHASE 6: ECOSYSTEM & TOOLING (Weeks 9-10)

**Goal**: Build tooling, CI/CD, packaging

### 6.1 Build System Enhancements

**Priority**: MEDIUM

**Tasks**:
- [ ] Feature presets validation
  - Test all build profiles (minimal, desktop, server, full, embedded)
  - Verify binary sizes
  - Check feature dependencies
- [ ] Cross-compilation testing
  - x86_64-linux
  - aarch64-linux
  - riscv64-linux (future)
- [ ] Dependency management
  - Pin zsync version
  - Pin zquic version
  - Test with latest Zig
- [ ] Installation targets
  - System-wide install
  - User-local install
  - FHS compliance

**Files**:
- `build.zig` (enhance)
- `build.zig.zon` (validate)
- `.github/workflows/` (new - but no CI/CD for now)

**Deliverable**: Robust build system

---

### 6.2 Developer Tooling

**Priority**: MEDIUM

**Tasks**:
- [ ] Protocol inspector
  - Dump Wayland messages
  - Pretty-print protocol
  - Performance analysis
- [ ] Debug utilities
  - Object tree visualization
  - Memory leak detector
  - Thread contention visualizer
- [ ] Code generation
  - Protocol XML → Zig code
  - Interface bindings generator
  - Event handlers generator

**Files**:
- `tools/wzl-inspect.zig` (new)
- `tools/wzl-debug.zig` (new)
- `tools/protocol-gen.zig` (new)

**Deliverable**: Developer tooling suite

---

### 6.3 Integration Testing

**Priority**: HIGH

**Tasks**:
- [ ] Real-world testing
  - Run GTK apps
  - Run Qt apps
  - Run SDL games
  - Run terminal emulators
- [ ] Compositor testing
  - Run wzl compositor
  - Test with real clients
  - Multi-monitor setup
  - HiDPI displays
- [ ] Remote desktop testing
  - LAN streaming
  - WAN streaming
  - Lossy network
  - High latency network
- [ ] Stress testing
  - 100+ clients
  - 1000+ surfaces
  - Memory pressure
  - CPU throttling

**Files**:
- `tests/integration/` (new)
- `tests/stress/` (new)
- `tests/real_world/` (new)

**Deliverable**: Battle-tested wzl

---

## PHASE 7: PRODUCTION HARDENING (Weeks 11-12)

**Goal**: Security audit, stability fixes, v1.0 release prep

### 7.1 Security Audit

**Priority**: CRITICAL

**Tasks**:
- [ ] Protocol fuzzing
  - Fuzz message parsing
  - Fuzz all opcodes
  - Find crashes/hangs
  - Fix vulnerabilities
- [ ] Input validation
  - Bounds checking
  - Integer overflow checks
  - Null pointer checks
  - Type confusion prevention
- [ ] Resource limits
  - Max objects per client
  - Max buffer size
  - Max message size
  - Rate limiting
- [ ] Privilege separation
  - Client isolation
  - Sandboxing support
  - Capability dropping
  - Secure defaults

**Files**:
- All src/*.zig (security review)
- `tests/fuzzing/` (new)
- `docs/security.md` (new)

**Deliverable**: Security-hardened wzl

---

### 7.2 Stability & Reliability

**Priority**: CRITICAL

**Tasks**:
- [ ] Error path testing
  - Out-of-memory handling
  - Disk full
  - Network errors
  - Protocol violations
- [ ] Resource cleanup
  - Verify all cleanup paths
  - Test abnormal termination
  - Ensure no resource leaks
  - Graceful shutdown
- [ ] Long-running stability
  - 24+ hour stress test
  - Memory stability
  - No performance degradation
  - Clean logs
- [ ] Recovery testing
  - Client crash recovery
  - Compositor crash recovery
  - Network reconnection
  - State recovery

**Files**:
- All src/*.zig (stability review)
- `tests/stability/` (new)
- `tests/recovery/` (new)

**Deliverable**: Production-stable wzl

---

### 7.3 v1.0 Release Preparation

**Priority**: HIGH

**Tasks**:
- [ ] Version bump to 1.0.0
- [ ] Changelog generation
  - All features
  - Breaking changes
  - Migration guide
- [ ] Release notes
  - Highlights
  - Known issues
  - Upgrade instructions
- [ ] GitHub release
  - Source tarball
  - Prebuilt binaries
  - Checksums
  - Signatures
- [ ] Announcement
  - Blog post
  - Reddit/HN
  - Zig community
  - Wayland community

**Files**:
- `CHANGELOG.md` (new)
- `RELEASE_NOTES.md` (new)
- `README.md` (polish)

**Deliverable**: wzl v1.0.0 released!

---

## Success Metrics

### Phase 1 (Weeks 1-2)
- [ ] 90%+ test coverage on core protocol
- [ ] Zero memory leaks under Valgrind
- [ ] Thread-safe client & server
- [ ] All error paths tested

### Phase 2 (Weeks 3-4)
- [ ] H.264 encoding working
- [ ] All rendering backends tested on real hardware
- [ ] XDG Shell fully compliant
- [ ] All input devices working

### Phase 3 (Weeks 5-6)
- [ ] Example compositor running
- [ ] Remote desktop streaming works over LAN/WAN
- [ ] Ghostty runs on wzl
- [ ] Multi-monitor support validated

### Phase 4 (Week 7)
- [ ] <1ms protocol latency
- [ ] 60+ FPS rendering
- [ ] <50MB memory for typical client
- [ ] <10MB for embedded builds

### Phase 5 (Week 8)
- [ ] Complete API docs published
- [ ] 3+ user guides written
- [ ] 10+ working examples
- [ ] Migration guide from libwayland

### Phase 6 (Weeks 9-10)
- [ ] All build profiles tested
- [ ] Developer tools working
- [ ] Real-world integration tests pass
- [ ] Stress tests pass (100+ clients)

### Phase 7 (Weeks 11-12)
- [ ] Security audit complete
- [ ] 24+ hour stability test passed
- [ ] v1.0.0 released
- [ ] Community announcement

---

## Post-v1.0 Future Work

**NOT part of current roadmap** - These are ideas for future releases:

### Performance Enhancements
- io_uring optimization (full async I/O)
- Hardware overlay planes
- Vulkan WSI integration
- OpenGL ES support

### Protocol Extensions
- Linux DMA-BUF protocol
- Linux explicit sync
- Content type hints
- Idle inhibit protocol
- Layer shell protocol

### Advanced Features
- HDR support refinement
- Color management v2
- Presentation time protocol
- Pointer constraints
- Relative pointer

### Platform Support
- FreeBSD support
- NetBSD support
- Haiku support (future)

---

## Key Technical Decisions

### Why Zig?
- Memory safety without GC
- Compile-time guarantees
- C interop for drivers
- Fast compilation
- Small binaries

### Why zsync?
- Native Zig async runtime
- io_uring/epoll/kqueue support
- Better than threads for I/O
- Low overhead
- Composable

### Why zquic?
- Modern transport for remote desktop
- Handles packet loss
- Connection migration
- 0-RTT
- TLS 1.3 security

### Binary Size Strategy
- Feature flags for compile-time stripping
- Minimal: ~1.5MB (core only)
- Desktop: ~8MB (standard features)
- Full: ~25MB (everything)
- Embedded: ~800KB (extreme minimal)

---

## Files to Focus On (Prioritized)

**Phase 1**:
- `src/protocol.zig` - Add validation
- `src/client.zig` - Thread safety
- `src/server.zig` - Thread safety
- `src/memory.zig` - Leak detection
- `tests/` - New comprehensive tests

**Phase 2**:
- `src/video_encoding.zig` - NEW - H.264
- `src/egl_backend.zig` - Polish
- `src/vulkan_backend.zig` - Polish
- `src/xdg_shell.zig` - Completeness

**Phase 3**:
- `src/compositor.zig` - Harden
- `src/remote_desktop.zig` - Production ready
- `src/terminal.zig` - Ghostty validation
- `examples/` - Full compositor

**Phase 4**:
- `src/protocol.zig` - Optimize hot paths
- `src/rendering.zig` - Damage tracking
- `benchmarks/` - NEW - Performance tests

**Phase 5**:
- `docs/` - Complete all docs
- `examples/` - 10+ examples
- All `src/*.zig` - Doc comments

**Phase 6**:
- `build.zig` - Profile testing
- `tools/` - NEW - Developer tools
- `tests/integration/` - Real-world tests

**Phase 7**:
- All files - Security review
- `tests/fuzzing/` - NEW - Fuzz tests
- `CHANGELOG.md` - v1.0 prep

---

**Last Updated**: 2025-10-27
**Current Focus**: Phase 1 - Core Stabilization
**Timeline**: 12 weeks to v1.0
**Owner**: @ghostkellz
**Repository**: https://github.com/ghostkellz/wzl

---
