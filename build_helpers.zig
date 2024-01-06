const std = @import("std");

/// Represents a dependency on an external package.
pub const Dependency = struct {
    name: []const u8,
    module_name: []const u8,
};

/// Generate an array of Build.Module.Import from the external dependencies.
/// # Arguments
/// * `b` - The build object.
/// * `external_dependencies` - The external dependencies.
/// * `dependencies_opts` - The options to use when generating the dependency modules.
/// # Returns
/// A new array of Build.Module.Import.
pub fn generateModuleDependencies(
    b: *std.Build,
    external_dependencies: []const Dependency,
    dependencies_opts: anytype,
) ![]std.Build.Module.Import {
    var dependency_modules = std.ArrayList(*std.Build.Module).init(b.allocator);
    defer _ = dependency_modules.deinit();

    // Populate dependency modules.
    for (external_dependencies) |dep| {
        const module = b.dependency(
            dep.name,
            dependencies_opts,
        ).module(dep.module_name);
        _ = dependency_modules.append(module) catch unreachable;
    }
    return try toModuleDependencyArray(
        b.allocator,
        dependency_modules.items,
        external_dependencies,
    );
}

/// Convert an array of Build.Module pointers to an array of Build.Module.Import.
/// # Arguments
/// * `allocator` - The allocator to use for the new array.
/// * `modules` - The array of Build.Module pointers to convert.
/// * `ext_deps` - The array of external dependencies.
/// # Returns
/// A new array of Build.Module.Import.
fn toModuleDependencyArray(
    allocator: std.mem.Allocator,
    modules: []const *std.Build.Module,
    ext_deps: []const Dependency,
) ![]std.Build.Module.Import {
    var deps = std.ArrayList(std.Build.Module.Import).init(allocator);
    defer deps.deinit();

    for (
        modules,
        0..,
    ) |module_ptr, i| {
        try deps.append(.{
            .name = ext_deps[i].name,
            .module = module_ptr,
        });
    }

    return deps.toOwnedSlice();
}
