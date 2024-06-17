const std = @import("std");
const hint_utils = @import("hint_utils.zig");
const testing_utils = @import("testing_utils.zig");

const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const Allocator = std.mem.Allocator;
const CairoVM = @import("../vm/core.zig").CairoVM;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const HintType = @import("../vm/types/execution_scopes.zig").HintType;
const HintReference = @import("hint_processor_def.zig").HintReference;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintError = @import("../vm/error.zig").HintError;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("hint_processor_def.zig").HintData;
const vm_error = @import("../vm/error.zig");

//Implements hint: memory[ap] = segments.add()
pub fn addSegment(allocator: Allocator, vm: *CairoVM) !void {
    const new_segment_base = try vm.addMemorySegment();
    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromRelocatable(new_segment_base));
}

//Implements hint: vm_enter_scope()
pub fn enterScope(allocator: Allocator, exec_scopes: *ExecutionScopes) !void {
    const scope = std.StringHashMap(HintType).init(allocator);
    try exec_scopes.enterScope(scope);
}

//  Implements hint:
//  %{ vm_exit_scope() %}
pub fn exitScope(exec_scopes: *ExecutionScopes) !void {
    try exec_scopes.exitScope();
}

//  Implements hint:
//  %{ vm_enter_scope({'n': ids.len}) %}
pub fn memcpyEnterScope(
    allocator: Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const len = try hint_utils.getIntegerFromVarName("len", vm, ids_data, ap_tracking);
    var scope = std.StringHashMap(HintType).init(allocator);
    errdefer scope.deinit();

    try scope.put("n", .{ .felt = len });
    try exec_scopes.enterScope(scope);
}

test "MemCpyHintUtils: getIntegerFromVarNameValid" {
    const var_name = "variable";

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = var_name,
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 10)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    try std.testing.expectEqual(Felt252.fromInt(u16, 10), try hint_utils.getIntegerFromVarName(var_name, &vm, ids_data, .{}));
}

test "MemCpyHintUtils: getIntegerFromVarNameValid invalid expected integer" {
    const var_name = "variable";

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = var_name,
            .elems = &.{},
        },
    }, &vm);
    defer ids_data.deinit();

    try std.testing.expectError(HintError.IdentifierNotInteger, hint_utils.getIntegerFromVarName(var_name, &vm, ids_data, .{}));
}
