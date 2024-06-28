const std = @import("std");

const cairo_runner_lib = @import("runners/cairo_runner.zig");
const CairoVM = @import("core.zig").CairoVM;
const Program = @import("types/program.zig").Program;
const Relocatable = @import("memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("memory/relocatable.zig").MaybeRelocatable;
const Felt252 = @import("starknet").fields.Felt252;
const errors = @import("error.zig");

/// Verify that the completed run in a runner is safe to be relocated and be
/// used by other Cairo programs.
///
/// Checks include:
///   - (Only if `verify_builtins` is set to true) All accesses to the builtin segments must be within the range defined by
///     the builtins themselves.
///   - There must not be accesses to the program segment outside the program
///     data range. This check will use the `program_segment_size` instead of the program data length if available.
///   - All addresses in memory must be real (not temporary)
///
/// Note: Each builtin is responsible for checking its own segments' data.
pub fn verifySecureRunner(
    allocator: std.mem.Allocator,
    runner: *cairo_runner_lib.CairoRunner,
    verify_builtins: bool,
    _program_segment_size: ?usize,
) !void {
    const builtins_segment_info = if (verify_builtins)
        try runner.getBuiltinSegmentsInfo(allocator)
    else
        std.ArrayList(cairo_runner_lib.BuiltinInfo).init(allocator);
    defer builtins_segment_info.deinit();

    // Check builtin segment out of bounds.
    for (builtins_segment_info.items) |bi| {
        const current_size = runner
            .vm
            .segments
            .memory
            .data.items[bi.segment_index].items.len;
        // + 1 here accounts for maximum segment offset being segment.len() -1
        if (current_size >= bi.stop_pointer + 1)
            return errors.CairoVMError.OutOfBoundsBuiltinSegmentAccess;
    }
    // Check out of bounds for program segment.
    const program_segment_index: usize = if (runner
        .program_base) |rel| @intCast(rel.segment_index) else return errors.RunnerError.NoProgBase;

    const program_segment_size =
        _program_segment_size orelse runner.program.shared_program_data.data.items.len;

    const program_length = runner
        .vm
        .segments
        .memory
        .data
        .items[program_segment_index].items.len;

    // + 1 here accounts for maximum segment offset being segment.len() -1
    if (program_length >= program_segment_size + 1)
        return errors.CairoVMError.OutOfBoundsProgramSegmentAccess;

    // Check that the addresses in memory are valid
    // This means that every temporary address has been properly relocated to a real address
    // Asumption: If temporary memory is empty, this means no temporary memory addresses were generated and all addresses in memory are real
    if (runner.vm.segments.memory.temp_data.items.len != 0) {
        for (runner.vm.segments.memory.data.items) |segment| {
            for (segment.items) |value| {
                if (value.getValue()) |v| switch (v) {
                    .relocatable => |addr| if (addr.segment_index < 0) return errors.CairoVMError.InvalidMemoryAddress,
                    else => {},
                };
            }
        }
    }

    for (runner.vm.builtin_runners.items) |*builtin| {
        try builtin.runSecurityChecks(allocator, runner.vm);
    }
}

test "Security: VerifySecureRunner without program base" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    const program = try Program.initDefault(std.testing.allocator);

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );

    defer cairo_runner.deinit(std.testing.allocator);

    try std.testing.expectError(errors.RunnerError.NoProgBase, verifySecureRunner(std.testing.allocator, &cairo_runner, true, null));
}

test "Security: VerifySecureRunner empty memory" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    // defer vm.segments.memory.deinitData(std.testing.allocator);

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);
    _ = try cairo_runner.vm.segments.computeEffectiveSize(false);

    try verifySecureRunner(std.testing.allocator, &cairo_runner, true, null);
}

test "Security: VerifySecureRunner program access out of bounds" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{
            .{ 0, 0 },
            .{100},
        },
    });

    // used_sizes already empty, making arraylist equal [1]
    try cairo_runner.vm.segments.segment_used_sizes.append(1);

    try std.testing.expectError(errors.CairoVMError.OutOfBoundsProgramSegmentAccess, verifySecureRunner(std.testing.allocator, &cairo_runner, true, null));
}

test "Security: VerifySecureRunner program with program size" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{
            .{ 0, 0 },
            .{100},
        },
    });

    // used_sizes already empty, making arraylist equal [1]
    try cairo_runner.vm.segments.segment_used_sizes.append(1);

    try verifySecureRunner(std.testing.allocator, &cairo_runner, true, 1);
}

test "Security: VerifySecureRunner program builtin access out of bounds" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{
            .{ 0, 0 },
            .{100},
        },
    });

    // used_sizes already empty, making arraylist equal [1]
    try cairo_runner.vm.segments.segment_used_sizes.append(1);

    try verifySecureRunner(std.testing.allocator, &cairo_runner, true, 1);
}

test "Security: VerifySecureRunner builtin access out of bounds" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    try program.builtins.append(.range_check);
    program.shared_program_data.main = 0;

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    try cairo_runner.endRun(std.testing.allocator, false, false, @constCast(&.{}));

    cairo_runner.vm.builtin_runners.items[0].setStopPtr(0);

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{
            .{ 2, 0 },
            .{1},
        },
    });

    // used_sizes already empty, making arraylist equal [1]
    try cairo_runner.vm.segments.segment_used_sizes.appendSlice(&.{ 0, 0, 0, 0 });

    try std.testing.expectError(
        errors.CairoVMError.OutOfBoundsBuiltinSegmentAccess,
        verifySecureRunner(std.testing.allocator, &cairo_runner, true, null),
    );
}

test "Security: VerifySecureRunner builtin access correct" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    try program.builtins.append(.range_check);
    program.shared_program_data.main = 0;

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    try cairo_runner.endRun(std.testing.allocator, false, false, @constCast(&.{}));

    cairo_runner.vm.builtin_runners.items[0].setStopPtr(1);

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{
            .{ 2, 0 },
            .{1},
        },
    });

    // used_sizes already empty, making arraylist equal [1]
    try cairo_runner.vm.segments.segment_used_sizes.appendSlice(&.{ 0, 0, 1, 0 });

    try verifySecureRunner(std.testing.allocator, &cairo_runner, true, null);
}

test "Security: VerifySecureRunner success" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;
    try program.shared_program_data.data.appendSlice(&.{
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
    });

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);
    cairo_runner.vm.segments.memory.data.clearRetainingCapacity();

    _ = try cairo_runner.vm.segments.addSegment();

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ 1, 0 } },
        .{ .{ 0, 1 }, .{ 2, 1 } },
        .{ .{ 0, 2 }, .{ 3, 2 } },
        .{ .{ 0, 3 }, .{ 4, 3 } },
    });

    // used_sizes already empty, making arraylist equal
    try cairo_runner.vm.segments.segment_used_sizes.appendSlice(&.{ 5, 1, 2, 3, 4 });

    try verifySecureRunner(std.testing.allocator, &cairo_runner, true, null);
}

test "Security: VerifySecureRunner temporary memory properly relocated" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;
    try program.shared_program_data.data.appendSlice(&.{
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
    });

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    // clearing old memory data, to set new one
    cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);
    cairo_runner.vm.segments.memory.data.clearRetainingCapacity();

    _ = try cairo_runner.vm.segments.addSegment();
    // end of set

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 1 }, .{ 1, 0 } },
        .{ .{ 0, 2 }, .{ 2, 1 } },
        .{ .{ 0, 3 }, .{ 3, 2 } },
        .{ .{ -1, 0 }, .{ 1, 2 } },
    });

    // used_sizes already empty, making arraylist equal
    try cairo_runner.vm.segments.segment_used_sizes.appendSlice(&.{ 5, 1, 2, 3, 4 });

    try verifySecureRunner(std.testing.allocator, &cairo_runner, true, null);
}

test "Security: VerifySecureRunner temporary memory not fully relocated" {
    var vm =
        try CairoVM.init(
        std.testing.allocator,
        .{},
    );

    var program = try Program.initDefault(std.testing.allocator);
    program.shared_program_data.main = 0;
    try program.shared_program_data.data.appendSlice(&.{
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
        .{ .felt = Felt252.zero() },
    });

    var cairo_runner = try cairo_runner_lib.CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        std.ArrayList(MaybeRelocatable).init(std.testing.allocator),
        &vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    _ = try cairo_runner.setupExecutionState(false);

    // clearing old memory data, to set new one
    cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);
    cairo_runner.vm.segments.memory.data.clearRetainingCapacity();

    _ = try cairo_runner.vm.segments.addSegment();
    // end of set

    try cairo_runner.vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ 1, 0 } },
        .{ .{ 0, 1 }, .{ 2, 1 } },
        .{ .{ 0, 2 }, .{ -3, 2 } },
        .{ .{ 0, 3 }, .{ 4, 3 } },
        .{ .{ -1, 0 }, .{ 1, 2 } },
    });

    // used_sizes already empty, making arraylist equal
    try cairo_runner.vm.segments.segment_used_sizes.appendSlice(&.{ 5, 1, 2, 3, 4 });

    try std.testing.expectError(errors.CairoVMError.InvalidMemoryAddress, verifySecureRunner(std.testing.allocator, &cairo_runner, true, null));
}
