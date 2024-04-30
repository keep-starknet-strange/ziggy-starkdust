const hint_utils = @import("hint_utils.zig");
const std = @import("std");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const testing_utils = @import("testing_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const hint_codes = @import("builtin_hint_codes.zig");
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintData = @import("hint_processor_def.zig").HintData;

const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const HintType = @import("../vm/types/execution_scopes.zig").HintType;

const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

//  Implements hint:
//  %{ vm_enter_scope({'n': ids.n}) %}
pub fn memsetEnterScope(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n =
        try hint_utils.getIntegerFromVarName("n", vm, ids_data, ap_tracking);

    var scope = std.StringHashMap(HintType).init(allocator);
    errdefer scope.deinit();

    try scope.put("n", .{ .felt = n });
    try exec_scopes.enterScope(scope);
}

// %{
//     n -= 1
//     ids.`i_name` = 1 if n > 0 else 0
// %}
pub fn memsetStepLoop(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    i_name: []const u8,
) !void {
    // get `n` variable from vm scope
    var n = try exec_scopes.getValueRef(Felt252, "n");
    // this variable will hold the value of `n - 1`
    n.* = n.sub(Felt252.one());
    // if `new_n` is positive, insert 1 in the address of `continue_loop`
    // else, insert 0
    const flag = if (n.gt(Felt252.zero())) Felt252.one() else Felt252.zero();
    try hint_utils.insertValueFromVarName(allocator, i_name, MaybeRelocatable.fromFelt(flag), vm, ids_data, ap_tracking);
    // Reassign `n` with `n - 1`
    // we do it at the end of the function so that the borrow checker doesn't complain
}

test "MemsetUtils: enterScope valid" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // initialize vm
    vm.run_context.fp = 2;
    // insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{5} },
    });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n",
    });
    defer ids_data.deinit();

    const hint_processor = HintProcessor{};

    var hint_data = HintData.init(hint_codes.MEMSET_ENTER_SCOPE, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try hint_processor.executeHint(
        std.testing.allocator,
        &vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    try std.testing.expectEqual(Felt252.fromInt(u8, 5), try exec_scopes.getFelt("n"));
}

test "MemsetUtils: enterScope invalid" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // initialize vm
    vm.run_context.fp = 2;
    // insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{ 1, 0 } },
    });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n",
    });
    defer ids_data.deinit();

    const hint_processor = HintProcessor{};

    var hint_data = HintData.init(hint_codes.MEMSET_ENTER_SCOPE, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try std.testing.expectError(HintError.IdentifierNotInteger, hint_processor.executeHint(
        std.testing.allocator,
        &vm,
        &hint_data,
        undefined,
        &exec_scopes,
    ));
}

test "MemsetUtils: continue loop valid continue loop equal 1" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // initialize vm
    vm.run_context.fp = 1;
    // insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{5} },
    });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "continue_loop",
    });
    defer ids_data.deinit();

    const hint_processor = HintProcessor{};

    var hint_data = HintData.init(hint_codes.MEMSET_CONTINUE_LOOP, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("n", .{ .felt = Felt252.one() });

    try hint_processor.executeHint(
        std.testing.allocator,
        &vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    // assert ids.continue_loop = 0
    try std.testing.expectEqual(Felt252.fromInt(u8, 0), try vm.getFelt(Relocatable.init(1, 0)));
}

test "MemsetUtils: continue loop valid continue loop equal 5" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // initialize vm
    vm.run_context.fp = 1;
    // insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{5} },
    });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "continue_loop",
    });
    defer ids_data.deinit();

    const hint_processor = HintProcessor{};

    var hint_data = HintData.init(hint_codes.MEMSET_CONTINUE_LOOP, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("n", .{ .felt = Felt252.fromInt(u8, 5) });

    try hint_processor.executeHint(
        std.testing.allocator,
        &vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    // assert ids.continue_loop = 0
    try std.testing.expectEqual(Felt252.fromInt(u8, 1), try vm.getFelt(Relocatable.init(1, 0)));
}

test "MemsetUtils: continue loop " {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // initialize vm
    vm.run_context.fp = 1;
    // insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{5} },
    });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "continue_loop",
    });
    defer ids_data.deinit();

    const hint_processor = HintProcessor{};

    var hint_data = HintData.init(hint_codes.MEMSET_CONTINUE_LOOP, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    // try exec_scopes.assignOrUpdateVariable("n", .{ .felt = Felt252.fromInt(u8, 5) });

    try std.testing.expectError(HintError.VariableNotInScopeError, hint_processor.executeHint(
        std.testing.allocator,
        &vm,
        &hint_data,
        undefined,
        &exec_scopes,
    ));
}
