## wzl (Wayland Zig Library)

### Phase 1 – Core Protocol
- [ ] Implement Wayland core protocol message definitions in Zig
- [ ] Build async client connection API (`wzl.Client`)
- [ ] Build async compositor connection API (`wzl.Server`)
- [ ] Add event loop integration with `zsync`
- [ ] Provide minimal surface creation and destruction

### Phase 2 – Extensions
- [ ] XDG shell support (windows, popups, layers)
- [ ] Input device support (keyboard, mouse, touch, tablet)
- [ ] Output management (monitors, scaling, transforms)
- [ ] Buffer management (shm, dmabuf, EGL)

### Phase 3 – Advanced
Zig fetch --Sav https://url.com # example if we need external deps 
- [ ] Compositor utility framework
- [ ] Remote Wayland sessions encrypted with `zcrypto` - https://githhub.com/ghostkellz/zcrypto
- [ ] Streaming Wayland over QUIC with `zquic` - https://github.com/ghostkellz/zquic
- [ ] Example compositor implementation

---
