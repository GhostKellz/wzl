const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // Build options for modular dependencies
    const enable_remote_desktop = b.option(bool, "remote-desktop", "Enable remote desktop streaming features") orelse true;
    const enable_post_quantum = b.option(bool, "post-quantum", "Enable post-quantum cryptography") orelse false;
    _ = b.option(bool, "hardware-accel", "Enable hardware-accelerated cryptography") orelse true;
    _ = b.option(bool, "optimize-size", "Optimize for binary size over features") orelse false;

    // WZL Modular Feature Flags
    const wzl_touch_input = b.option(bool, "touch", "Enable multi-touch input support") orelse true;
    const wzl_tablet_input = b.option(bool, "tablet", "Enable tablet/stylus input support") orelse true;
    const wzl_gesture_recognition = b.option(bool, "gestures", "Enable gesture recognition") orelse true;
    const wzl_xdg_shell = b.option(bool, "xdg-shell", "Enable XDG shell protocol") orelse true;
    const wzl_clipboard = b.option(bool, "clipboard", "Enable clipboard/data device support") orelse true;
    const wzl_drag_drop = b.option(bool, "drag-drop", "Enable drag and drop support") orelse true;
    const wzl_software_renderer = b.option(bool, "software-renderer", "Enable software rendering backend") orelse true;
    const wzl_egl_backend = b.option(bool, "egl", "Enable EGL rendering backend") orelse true;
    const wzl_vulkan_backend = b.option(bool, "vulkan", "Enable Vulkan rendering backend") orelse true;
    const wzl_quic_streaming = b.option(bool, "quic-streaming", "Enable QUIC-based streaming") orelse enable_remote_desktop;
    const wzl_h264_encoding = b.option(bool, "h264", "Enable H.264 video encoding") orelse false;
    const wzl_fractional_scaling = b.option(bool, "fractional-scaling", "Enable fractional scaling support") orelse true;
    const wzl_hardware_cursor = b.option(bool, "hardware-cursor", "Enable hardware cursor support") orelse true;
    const wzl_multi_gpu = b.option(bool, "multi-gpu", "Enable multi-GPU support") orelse false;
    const wzl_color_management = b.option(bool, "color-management", "Enable color management/HDR") orelse false;
    const wzl_memory_tracking = b.option(bool, "memory-tracking", "Enable memory leak tracking") orelse true;
    const wzl_thread_safety_debug = b.option(bool, "thread-debug", "Enable thread safety debugging") orelse false;
    const wzl_protocol_logging = b.option(bool, "protocol-logging", "Enable protocol message logging") orelse false;
    const wzl_compositor_framework = b.option(bool, "compositor", "Enable compositor framework") orelse true;
    const wzl_window_management = b.option(bool, "window-mgmt", "Enable window management") orelse true;
    const wzl_terminal_integration = b.option(bool, "terminal", "Enable terminal emulator integration") orelse true;

    // Dependencies with modular configuration
    const zsync = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });

    // Configure zquic with aligned features - zquic will manage zcrypto dependency
    const zquic = b.dependency("zquic", .{
        .target = target,
        .optimize = optimize,
        // HTTP/3 support (useful for control channels)
        .http3 = enable_remote_desktop,
        // DNS-over-QUIC not needed for remote desktop
        .doq = false,
        // Post-quantum crypto alignment (use correct flag name)
        .@"post-quantum" = enable_post_quantum,
        // Disable features not needed for wzl
        .vpn = false,
        .services = false,
        // Disable monitoring to reduce binary size
        .monitoring = false,
        // Build examples only for development
        .examples = false,
    });

    // Note: Cryptographic functionality is provided through zquic's internal zcrypto

    // Configure WZL feature flags for conditional compilation - simple array approach
    var features_buf: [50][]const u8 = undefined;
    var feature_count: usize = 0;

    if (wzl_touch_input) { features_buf[feature_count] = "touch_input"; feature_count += 1; }
    if (wzl_tablet_input) { features_buf[feature_count] = "tablet_input"; feature_count += 1; }
    if (wzl_gesture_recognition) { features_buf[feature_count] = "gesture_recognition"; feature_count += 1; }
    if (wzl_xdg_shell) { features_buf[feature_count] = "xdg_shell"; feature_count += 1; }
    if (wzl_clipboard) { features_buf[feature_count] = "clipboard"; feature_count += 1; }
    if (wzl_drag_drop) { features_buf[feature_count] = "drag_drop"; feature_count += 1; }
    if (wzl_software_renderer) { features_buf[feature_count] = "software_renderer"; feature_count += 1; }
    if (wzl_egl_backend) { features_buf[feature_count] = "egl_backend"; feature_count += 1; }
    if (wzl_vulkan_backend) { features_buf[feature_count] = "vulkan_backend"; feature_count += 1; }
    if (enable_remote_desktop) { features_buf[feature_count] = "remote_desktop"; feature_count += 1; }
    if (wzl_quic_streaming) { features_buf[feature_count] = "quic_streaming"; feature_count += 1; }
    if (wzl_h264_encoding) { features_buf[feature_count] = "h264_encoding"; feature_count += 1; }
    if (wzl_fractional_scaling) { features_buf[feature_count] = "fractional_scaling"; feature_count += 1; }
    if (wzl_hardware_cursor) { features_buf[feature_count] = "hardware_cursor"; feature_count += 1; }
    if (wzl_multi_gpu) { features_buf[feature_count] = "multi_gpu"; feature_count += 1; }
    if (wzl_color_management) { features_buf[feature_count] = "color_management"; feature_count += 1; }
    if (wzl_memory_tracking) { features_buf[feature_count] = "memory_tracking"; feature_count += 1; }
    if (wzl_thread_safety_debug) { features_buf[feature_count] = "thread_safety_debug"; feature_count += 1; }
    if (wzl_protocol_logging) { features_buf[feature_count] = "protocol_logging"; feature_count += 1; }
    if (wzl_compositor_framework) { features_buf[feature_count] = "compositor_framework"; feature_count += 1; }
    if (wzl_window_management) { features_buf[feature_count] = "window_management"; feature_count += 1; }
    if (wzl_terminal_integration) { features_buf[feature_count] = "terminal_integration"; feature_count += 1; }

    const wzl_features = features_buf[0..feature_count];

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("wzl", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "zquic", .module = zquic.module("zquic") },
        },
    });

    // Add feature flags to the module
    for (wzl_features) |feature| {
        mod.addCMacro(b.fmt("WZL_FEATURE_{s}", .{feature}), "1");
    }

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "wzl",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "wzl" is the name you will use in your source code to
                // import this module (e.g. `@import("wzl")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "wzl", .module = mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Build example compositor
    const example_compositor = b.addExecutable(.{
        .name = "wzl-compositor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple_compositor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wzl", .module = mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });

    const install_example = b.addInstallArtifact(example_compositor, .{});
    const example_step = b.step("example", "Build and install example compositor");
    example_step.dependOn(&install_example.step);

    // Run example step
    const run_example_step = b.step("run-example", "Run the example compositor");
    const run_example_cmd = b.addRunArtifact(example_compositor);
    run_example_cmd.step.dependOn(&install_example.step);
    run_example_step.dependOn(&run_example_cmd.step);

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Predefined build profiles for common use cases
    const minimal_step = b.step("minimal", "Build minimal wzl (core Wayland protocol only, ~1.5MB)");
    const minimal_features = [_][]const u8{ "xdg_shell", "software_renderer", "memory_tracking" };
    const minimal_mod = b.addModule("wzl-minimal", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "zquic", .module = zquic.module("zquic") },
        },
    });
    for (minimal_features) |feature| {
        minimal_mod.addCMacro(b.fmt("WZL_FEATURE_{s}", .{feature}), "1");
    }
    const minimal_exe = b.addExecutable(.{
        .name = "wzl-minimal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "wzl", .module = minimal_mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });
    minimal_step.dependOn(&b.addInstallArtifact(minimal_exe, .{}).step);

    const desktop_step = b.step("desktop", "Build desktop wzl (standard features, ~8MB)");
    const desktop_features = [_][]const u8{
        "touch_input", "tablet_input", "gesture_recognition", "xdg_shell",
        "clipboard", "drag_drop", "software_renderer", "egl_backend",
        "fractional_scaling", "hardware_cursor", "memory_tracking",
        "compositor_framework", "window_management", "terminal_integration"
    };
    const desktop_mod = b.addModule("wzl-desktop", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "zquic", .module = zquic.module("zquic") },
        },
    });
    for (desktop_features) |feature| {
        desktop_mod.addCMacro(b.fmt("WZL_FEATURE_{s}", .{feature}), "1");
    }
    const desktop_exe = b.addExecutable(.{
        .name = "wzl-desktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wzl", .module = desktop_mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });
    desktop_step.dependOn(&b.addInstallArtifact(desktop_exe, .{}).step);

    const server_step = b.step("server", "Build server wzl (remote desktop features, ~15MB)");
    const server_features = [_][]const u8{
        "touch_input", "tablet_input", "gesture_recognition", "xdg_shell",
        "clipboard", "drag_drop", "software_renderer", "egl_backend", "vulkan_backend",
        "remote_desktop", "quic_streaming", "fractional_scaling", "hardware_cursor",
        "multi_gpu", "memory_tracking", "compositor_framework", "window_management"
    };
    const server_mod = b.addModule("wzl-server", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "zquic", .module = zquic.module("zquic") },
        },
    });
    for (server_features) |feature| {
        server_mod.addCMacro(b.fmt("WZL_FEATURE_{s}", .{feature}), "1");
    }
    const server_exe = b.addExecutable(.{
        .name = "wzl-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wzl", .module = server_mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });
    server_step.dependOn(&b.addInstallArtifact(server_exe, .{}).step);

    const full_step = b.step("full", "Build full-featured wzl (all features enabled, ~25MB)");
    const full_features = [_][]const u8{
        "touch_input", "tablet_input", "gesture_recognition", "xdg_shell",
        "clipboard", "drag_drop", "software_renderer", "egl_backend", "vulkan_backend",
        "remote_desktop", "quic_streaming", "h264_encoding", "fractional_scaling",
        "hardware_cursor", "multi_gpu", "color_management", "memory_tracking",
        "thread_safety_debug", "protocol_logging", "compositor_framework",
        "window_management", "terminal_integration"
    };
    const full_mod = b.addModule("wzl-full", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "zquic", .module = zquic.module("zquic") },
        },
    });
    for (full_features) |feature| {
        full_mod.addCMacro(b.fmt("WZL_FEATURE_{s}", .{feature}), "1");
    }
    const full_exe = b.addExecutable(.{
        .name = "wzl-full",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wzl", .module = full_mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });
    full_step.dependOn(&b.addInstallArtifact(full_exe, .{}).step);

    // Embedded/size-optimized build
    const embedded_step = b.step("embedded", "Build size-optimized wzl for embedded use (~800KB)");
    const embedded_features = [_][]const u8{ "software_renderer" };
    const embedded_mod = b.addModule("wzl-embedded", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "zquic", .module = zquic.module("zquic") },
        },
    });
    for (embedded_features) |feature| {
        embedded_mod.addCMacro(b.fmt("WZL_FEATURE_{s}", .{feature}), "1");
    }
    const embedded_exe = b.addExecutable(.{
        .name = "wzl-embedded",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "wzl", .module = embedded_mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "zquic", .module = zquic.module("zquic") },
            },
        }),
    });
    embedded_step.dependOn(&b.addInstallArtifact(embedded_exe, .{}).step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
