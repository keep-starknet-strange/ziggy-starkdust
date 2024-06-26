const std = @import("std");

const cairo_runner = @import("runners/cairo_runner.zig");
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
    runner: *const cairo_runner.CairoRunner,
    verify_builtins: bool,
    _program_segment_size: ?usize,
) !void {
    const builtins_segment_info = if (verify_builtins) 

    try runner.getBuiltinSegmentsInfo(allocator) else  std.ArrayList(cairo_runner.BuiltinInfo).init(allocator);
    // Check builtin segment out of bounds.
    for (builtins_segment_info.items) |bi| {
        const index, const stop_ptr = bi;
        const current_size = runner
            .vm
            .segments
            .memory
            .data.items[index].items.len;
        // + 1 here accounts for maximum segment offset being segment.len() -1
        if (current_size >= stop_ptr + 1) 
            return errors.CairoVMError.OutOfBoundsBuiltinSegmentAccess;
    }
    // Check out of bounds for program segment.
    const program_segment_index = if (runner
        .program_base) |rel| @intCast(rel.segment_index) else errors.RunnerError.NoProgBase;

    const program_segment_size =
        _program_segment_size orelse runner.program.shared_program_data.data.items.len;

    const program_length = runner
        .vm
        .segments
        .memory
        .data
        .items[program_segment_index].items.len;

    // + 1 here accounts for maximum segment offset being segment.len() -1
    if (program_length >= program_segment_size + 1 )
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

    for (runner.vm.builtin_runners.items) |builtin| {
        
        builtin.runS
    }

    for builtin in runner.vm.builtin_runners.iter() {
        builtin.run_security_checks(&runner.vm)?;
    }

}
