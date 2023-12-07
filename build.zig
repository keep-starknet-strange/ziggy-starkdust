const std = @import("std");
const build_helpers = @import("build_helpers.zig");
const package_name = "cairo-zig";
const package_path = "src/lib.zig";

// List of external dependencies that this package requires.
const external_dependencies = [_]build_helpers.Dependency{
    .{
        .name = "zig-cli",
        .module_name = "zig-cli",
    },
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // **************************************************************
    // *            HANDLE DEPENDENCY MODULES                       *
    // **************************************************************
    const dependencies_opts = .{
        .target = target,
        .optimize = optimize,
    };

    // This array can be passed to add the dependencies to lib, executable, tests, etc using `addModule` function.
    const deps = build_helpers.generateModuleDependencies(
        b,
        &external_dependencies,
        dependencies_opts,
    ) catch unreachable;

    // **************************************************************
    // *               CAIRO-ZIG AS A MODULE                        *
    // **************************************************************
    // expose cairo-zig as a module
    _ = b.addModule(package_name, .{
        .source_file = .{ .path = package_path },
        .dependencies = deps,
    });

    // **************************************************************
    // *              CAIRO-ZIG AS A LIBRARY                        *
    // **************************************************************
    const lib = b.addStaticLibrary(.{
        .name = "cairo-zig",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    // Add dependency modules to the library.
    for (deps) |mod| lib.addModule(
        mod.name,
        mod.module,
    );
    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // **************************************************************
    // *              CAIRO-ZIG AS AN EXECUTABLE                    *
    // **************************************************************
    const exe = b.addExecutable(.{
        .name = "cairo-zig",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // Add dependency modules to the executable.
    for (deps) |mod| exe.addModule(
        mod.name,
        mod.module,
    );
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    exe.addIncludePath(.{ .path = "./src/math/crypto/starknet_crypto/" });
    exe.addObjectFile(std.build.LazyPath{ .path = "./src/math/crypto/starknet_crypto/libstarknet_crypto.a" });
    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step(
        "run",
        "Run the app",
    );
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    // Add dependency modules to the tests.
    for (deps) |mod| unit_tests.addModule(
        mod.name,
        mod.module,
    );

    unit_tests.addIncludePath(.{ .path = "./src/math/crypto/starknet_crypto/" });
    unit_tests.addObjectFile(std.build.LazyPath{ .path = "./src/math/crypto/starknet_crypto/libstarknet_crypto.a" });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step(
        "test",
        "Run unit tests",
    );
    test_step.dependOn(&lib.step);
    test_step.dependOn(&run_unit_tests.step);
}
