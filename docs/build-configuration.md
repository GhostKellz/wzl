# WZL Build Configuration Guide

## Overview

WZL now supports modular builds thanks to the updated zcrypto v0.9.0 and zquic v0.9.0 dependencies. This allows you to build exactly the features you need, reducing binary size and compilation time significantly.

## Build Profiles

### Default Build
```bash
zig build
```
- **Size**: ~15-20MB
- **Features**: Core Wayland protocol, basic remote desktop, hardware acceleration
- **Use case**: General development and testing

### Minimal Build
```bash
zig build minimal
```
- **Size**: ~3-5MB
- **Features**: Core Wayland protocol only, minimal crypto
- **Use case**: Embedded systems, basic Wayland clients

### Full-Featured Build
```bash
zig build full -Dpost-quantum=true
```
- **Size**: ~25-35MB
- **Features**: All features enabled including post-quantum crypto
- **Use case**: Production servers, security-critical applications

### Embedded Build
```bash
zig build embedded -Doptimize-size=true
```
- **Size**: ~1.5-3MB
- **Features**: Core protocol only, optimized for size
- **Use case**: IoT devices, memory-constrained environments

## Build Options

### Core Options

| Flag | Default | Description |
|------|---------|-------------|
| `--remote-desktop` | `true` | Enable QUIC-based remote desktop streaming |
| `--post-quantum` | `false` | Enable post-quantum cryptography (ML-KEM-768) |
| `--hardware-accel` | `true` | Enable hardware-accelerated cryptography |
| `--optimize-size` | `false` | Prioritize binary size over features |

### Examples

#### Secure Remote Desktop Server
```bash
zig build -Dpost-quantum=true -Dhardware-accel=true -Dremote-desktop=true
```

#### Minimal Wayland Client
```bash
zig build minimal -Dremote-desktop=false -Doptimize-size=true
```

#### Development Build
```bash
zig build -Doptimize=Debug -Dhardware-accel=false
```

## Feature Matrix

### ZCrypto Features

| Feature | Default | Binary Impact | Use Case |
|---------|---------|---------------|----------|
| `core` | ✅ Always | +1MB | Basic cryptographic primitives |
| `tls` | ✅ (if remote-desktop) | +2-3MB | QUIC/TLS for remote desktop |
| `async` | ✅ Always | +0.5MB | Non-blocking crypto operations |
| `hardware_accel` | ✅ | +1-2MB | Hardware crypto acceleration |
| `post_quantum` | ❌ | +5-10MB | ML-KEM-768, Kyber, Dilithium |
| `blockchain` | ❌ Disabled | +3-5MB | Not needed for Wayland |
| `vpn` | ❌ Disabled | +2-4MB | Not needed for Wayland |
| `enterprise` | ❌ Disabled | +3-6MB | Not needed for Wayland |
| `zkp` | ❌ Disabled | +4-8MB | Not needed for Wayland |

### ZQuic Features

| Feature | Default | Binary Impact | Use Case |
|---------|---------|---------------|----------|
| `quic_core` | ✅ (if remote-desktop) | +2MB | Core QUIC transport |
| `http3` | ✅ (if remote-desktop) | +1MB | HTTP/3 for control channels |
| `services` | ✅ (unless optimize-size) | +2-3MB | High-level services |
| `ffi` | ❌ | +0.5MB | C interoperability |

## Performance Characteristics

### Compilation Times
- **Minimal**: ~5-8 seconds
- **Default**: ~12-15 seconds
- **Full**: ~20-25 seconds
- **Previous monolithic**: ~45+ seconds

### Binary Sizes
- **Embedded**: 1.5-3MB
- **Minimal**: 3-5MB
- **Default**: 15-20MB
- **Full**: 25-35MB
- **Previous monolithic**: 40-50MB

### Runtime Performance
- Hardware acceleration: 2-5x crypto performance improvement
- Post-quantum: 10-20% crypto overhead
- Minimal builds: Faster startup, lower memory usage

## Migration from v0.8.x

### Breaking Changes
1. **Dependency Configuration**: Build flags now required for feature selection
2. **Module Structure**: Some crypto/QUIC APIs moved to feature-specific modules
3. **Binary Size**: Default builds are now smaller but may lack some features

### Update Steps
1. **Update dependencies**:
   ```bash
   zig build --fetch
   ```

2. **Review feature requirements**:
   - Do you need remote desktop? Keep `--remote-desktop=true`
   - Need post-quantum crypto? Add `--post-quantum=true`
   - Building for embedded? Use `zig build minimal`

3. **Test your build**:
   ```bash
   zig build test
   ```

4. **Update deployment scripts** to use appropriate build profile

## Troubleshooting

### Common Issues

#### "Module not found" errors
- **Cause**: Missing feature flag for required functionality
- **Solution**: Add appropriate build flag (e.g., `--remote-desktop=true`)

#### Large binary size
- **Cause**: All features enabled by default in some configurations
- **Solution**: Use `zig build minimal` or `--optimize-size=true`

#### Crypto/QUIC version conflicts
- **Cause**: Different feature flags between zcrypto and zquic
- **Solution**: Ensure consistent post-quantum and hardware acceleration settings

#### Missing hardware acceleration
- **Cause**: `--hardware-accel=false` or missing system libraries
- **Solution**: Enable hardware acceleration and install required system packages

### Debug Build Issues

For debugging dependency issues:
```bash
# Verbose build to see module resolution
zig build -Dverbose=true

# List all build options
zig build --help

# Check dependency tree
zig build --summary all
```

## Recommended Configurations

### Development
```bash
zig build -Doptimize=Debug -Dhardware-accel=false
```

### Production Desktop
```bash
zig build -Dhardware-accel=true -Dremote-desktop=true
```

### Embedded/IoT
```bash
zig build embedded -Doptimize-size=true -Dremote-desktop=false
```

### High Security
```bash
zig build full -Dpost-quantum=true -Dhardware-accel=true
```

---

For more details, see the [zcrypto documentation](https://github.com/ghostkellz/zcrypto) and [zquic documentation](https://github.com/ghostkellz/zquic).