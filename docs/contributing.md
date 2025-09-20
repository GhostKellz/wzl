# wzl Build System

This guide covers building, integrating, and deploying applications with the wzl library.

## 🏗️ Building wzl

### Basic Build

```bash
# Clone the repository
git clone https://github.com/ghostkellz/wzl.git
cd wzl

# Build the library
zig build

# Build with optimizations
zig build -Doptimize=ReleaseFast

# Build examples
zig build examples

# Run tests
zig build test

# Clean build artifacts
zig build clean
```

### Build Options

```bash
# Build with debug information
zig build -Doptimize=Debug

# Build for release
zig build -Doptimize=ReleaseSafe

# Build with maximum optimization
zig build -Doptimize=ReleaseFast

# Build with size optimization
zig build -Doptimize=ReleaseSmall

# Cross-compilation
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
```

## 📦 Integrating wzl in Your Project

### Using as a Dependency

#### Method 1: Git Submodule

```bash
# Add wzl as a submodule
git submodule add https://github.com/ghostkellz/wzl.git deps/wzl

# In your build.zig
const wzl = b.dependency("wzl", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("wzl", wzl.module("wzl"));
```

#### Method 2: Package Manager

```bash
# Using zigmod
zigmod init
zigmod add --git https://github.com/ghostkellz/wzl.git

# Using gyro
gyro init
gyro add ghostkellz/wzl
```

#### Method 3: Manual Integration

```zig
// In your build.zig
const wzl_path = "deps/wzl";

// Add wzl module
exe.addModule("wzl", .{
    .source_file = .{ .path = wzl_path ++ "/src/root.zig" },
    .dependencies = &[_]std.Build.ModuleDependency{
        .{ .name = "zsync", .module = zsync_mod },
        .{ .name = "zcrypto", .module = zcrypto_mod },
        .{ .name = "zquic", .module = zquic_mod },
    },
});
```

### Complete build.zig Example

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zsync = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });

    const zcrypto = b.dependency("zcrypto", .{
        .target = target,
        .optimize = optimize,
    });

    const zquic = b.dependency("zquic", .{
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add wzl module
    exe.root_module.addImport("zsync", zsync.module("zsync"));
    exe.root_module.addImport("zcrypto", zcrypto.module("zcrypto"));
    exe.root_module.addImport("zquic", zquic.module("zquic"));

    const wzl_mod = b.addModule("wzl", .{
        .root_source_file = .{ .path = "deps/wzl/src/root.zig" },
    });

    wzl_mod.addImport("zsync", zsync.module("zsync"));
    wzl_mod.addImport("zcrypto", zcrypto.module("zcrypto"));
    wzl_mod.addImport("zquic", zquic.module("zquic"));

    exe.root_module.addImport("wzl", wzl_mod);

    // System libraries
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("wayland-server");

    // Install and run
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe_tests.root_module.addImport("wzl", wzl_mod);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
```

## 🔧 System Dependencies

### Required Libraries

```bash
# Ubuntu/Debian
sudo apt-get install libwayland-dev libegl1-mesa-dev libgles2-mesa-dev

# Fedora
sudo dnf install wayland-devel mesa-libEGL-devel mesa-libGLES-devel

# Arch Linux
sudo pacman -S wayland libegl libgles

# macOS (experimental)
brew install wayland
```

### Development Tools

```bash
# Install Zig
# Download from https://ziglang.org/download/

# Verify installation
zig version

# Optional: Install wayland-scanner for protocol generation
sudo apt-get install wayland-protocols
```

## 🎯 Build Configurations

### Debug Build

```bash
zig build -Doptimize=Debug
# - Full debug information
# - Safety checks enabled
# - Slower execution
# - Larger binary size
```

### Release Builds

```bash
# Safe release (recommended for production)
zig build -Doptimize=ReleaseSafe
# - Optimizations enabled
# - Safety checks enabled
# - Good performance/safety balance

# Fast release
zig build -Doptimize=ReleaseFast
# - Maximum optimizations
# - Safety checks disabled
# - Best performance
# - Use only with thoroughly tested code

# Small release
zig build -Doptimize=ReleaseSmall
# - Size optimizations
# - Good performance
# - Smaller binary size
```

## 🚀 Deployment

### Creating Distribution Packages

#### AppImage (Linux)

```bash
# Create AppImage structure
mkdir -p MyApp.AppDir
cp my-app MyApp.AppDir/
cp icon.png MyApp.AppDir/
cat > MyApp.AppDir/AppRun << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/my-app" "$@"
EOF
chmod +x MyApp.AppDir/AppRun

# Create desktop file
cat > MyApp.AppDir/my-app.desktop << EOF
[Desktop Entry]
Name=My App
Exec=my-app
Icon=icon
Type=Application
Categories=Utility;
EOF

# Build AppImage
wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage
./appimagetool-x86_64.AppImage MyApp.AppDir/
```

#### Flatpak

```yaml
# my-app.yml
app-id: com.example.MyApp
runtime: org.gnome.Platform
runtime-version: '45'
sdk: org.gnome.Sdk

command: my-app

finish-args:
  - --socket=wayland
  - --socket=fallback-x11
  - --device=dri

modules:
  - name: my-app
    buildsystem: simple
    build-commands:
      - zig build -Doptimize=ReleaseSafe
      - install -Dm755 zig-out/bin/my-app /app/bin/my-app
    sources:
      - type: git
        url: https://github.com/myuser/my-app.git
```

#### Docker

```dockerfile
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    wayland-libs-client \
    mesa-egl \
    mesa-gles

# Copy application
COPY my-app /usr/local/bin/

# Set up user
RUN adduser -D appuser
USER appuser

# Run application
CMD ["my-app"]
```

### Cross-Compilation

```bash
# Build for different architectures
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
zig build -Dtarget=x86_64-windows-gnu

# Build for different operating systems
zig build -Dtarget=x86_64-linux-musl   # Static Linux
zig build -Dtarget=x86_64-macos-gnu    # macOS
```

## 🔍 Troubleshooting

### Common Build Issues

#### Missing Dependencies

```bash
# Check for required tools
which zig
zig version

# Check for system libraries
pkg-config --exists wayland-client
pkg-config --modversion wayland-client
```

#### Linker Errors

```bash
# Check library paths
ldd zig-out/bin/my-app

# Add missing library paths
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
```

#### Protocol Compilation

```bash
# Regenerate protocol files if needed
wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell-client-protocol.h
wayland-scanner private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell-protocol.c
```

### Performance Issues

#### Profiling Build

```bash
# Build with profiling
zig build -Doptimize=Debug

# Run with perf
perf record ./zig-out/bin/my-app
perf report
```

#### Memory Debugging

```bash
# Build with AddressSanitizer
zig build -fsanitize=address

# Run with leak detection
export ASAN_OPTIONS=detect_leaks=1
./zig-out/bin/my-app
```

## 📊 Build Optimization

### Compiler Flags

```zig
// In build.zig
const exe = b.addExecutable(.{
    .name = "my-app",
    .root_source_file = .{ .path = "src/main.zig" },
    .target = target,
    .optimize = optimize,
});

// Enable Link-Time Optimization (LTO)
exe.want_lto = true;

// Strip debug symbols in release
if (optimize != .Debug) {
    exe.strip = true;
}

// Enable compiler optimizations
exe.code_model = .medium;  // For large applications
```

### Dependency Optimization

```zig
// Only include needed modules
const wzl_mod = b.addModule("wzl", .{
    .root_source_file = .{ .path = "deps/wzl/src/root.zig" },
    // Only include needed dependencies
});

// Conditional compilation
if (enable_remote) {
    wzl_mod.addImport("zquic", zquic.module("zquic"));
}
```

## 🔄 CI/CD Integration

### GitHub Actions

```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: 0.16.0

    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y libwayland-dev libegl1-mesa-dev

    - name: Build
      run: zig build

    - name: Test
      run: zig build test

    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: my-app
        path: zig-out/bin/
```

### GitLab CI

```yaml
stages:
  - build
  - test
  - deploy

build:
  stage: build
  image: alpine:latest
  before_script:
    - apk add --no-cache zig wayland-dev mesa-dev
  script:
    - zig build -Doptimize=ReleaseSafe
  artifacts:
    paths:
      - zig-out/bin/
    expire_in: 1 hour

test:
  stage: test
  script:
    - zig build test

deploy:
  stage: deploy
  script:
    - echo "Deploying application..."
  only:
    - main
```

This build system provides a solid foundation for developing, building, and deploying wzl-based applications across different platforms and environments.</content>
<parameter name="filePath">/data/projects/wzl/docs/build-system.md