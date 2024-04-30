// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const starknet_felt = @import("../math/fields/starknet.zig");

// Local imports.
const segments = @import("memory/segments.zig");
const memory = @import("memory/memory.zig");
const MemoryCell = memory.MemoryCell;
const Memory = memory.Memory;
const relocatable = @import("memory/relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const instructions = @import("instructions.zig");
const RunContext = @import("run_context.zig").RunContext;
const CairoVMError = @import("error.zig").CairoVMError;
const ExecScopeError = @import("error.zig").ExecScopeError;
const TraceError = @import("error.zig").TraceError;
const MemoryError = @import("error.zig").MemoryError;
const MathError = @import("error.zig").MathError;
const Config = @import("config.zig").Config;
const TraceEntry = @import("trace_context.zig").TraceEntry;
const RelocatedTraceEntry = @import("trace_context.zig").RelocatedTraceEntry;
const build_options = @import("../build_options.zig");
const BuiltinRunner = @import("./builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const BitwiseBuiltinRunner = @import("./builtins/builtin_runner/bitwise.zig").BitwiseBuiltinRunner;
const KeccakBuiltinRunner = @import("./builtins/builtin_runner/keccak.zig").KeccakBuiltinRunner;
const KeccakInstanceDef = @import("./types/keccak_instance_def.zig").KeccakInstanceDef;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HashBuiltinRunner = @import("./builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const EcOpBuiltinRunner = @import("./builtins/builtin_runner/ec_op.zig").EcOpBuiltinRunner;
const Instruction = @import("instructions.zig").Instruction;
const CairoVM = @import("core.zig").CairoVM;
const OperandsResult = @import("core.zig").OperandsResult;
const HintData = @import("../hint_processor/hint_processor_def.zig").HintData;
const HintRange = @import("./types/program.zig").HintRange;
const HintType = @import("./types/execution_scopes.zig").HintType;
const ExecutionScopes = @import("./types/execution_scopes.zig").ExecutionScopes;
const HintProcessor = @import("../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;
const HintReference = @import("../hint_processor/hint_processor_def.zig").HintReference;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

test "CairoVM: deduceMemoryCell no builtin" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try expectEqual(
        @as(?MaybeRelocatable, null),
        try vm.deduceMemoryCell(
            std.testing.allocator,
            .{},
        ),
    );
}

test "CairoVM: deduceMemoryCell with pedersen builtin" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{
        .Hash = HashBuiltinRunner.init(
            std.testing.allocator,
            8,
            true,
        ),
    });

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 3 }, .{32} },
            .{ .{ 0, 4 }, .{72} },
            .{ .{ 0, 5 }, .{0} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x73b3ec210cccbb970f80c6826fb1c40ae9f487617696234ff147451405c339f),
        try vm.deduceMemoryCell(
            std.testing.allocator,
            Relocatable.init(0, 5),
        ),
    );
}

test "CairoVM: deduceMemoryCell with elliptic curve operation builtin" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) });

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0x68caa9509b7c2e90b4d92661cbf7c465471c1e8598c5f989691eef6653e0f38} },
            .{ .{ 0, 1 }, .{0x79a8673f498531002fc549e06ff2010ffc0c191cceb7da5532acb95cdcb591} },
            .{ .{ 0, 2 }, .{0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca} },
            .{ .{ 0, 3 }, .{0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f} },
            .{ .{ 0, 4 }, .{34} },
            .{ .{ 0, 5 }, .{0x6245403e2fafe5df3b79ea28d050d477771bc560fc59e915b302cc9b70a92f5} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x7f49de2c3a7d1671437406869edb1805ba43e1c0173b35f8c2e8fcc13c3fa6d),
        try vm.deduceMemoryCell(
            std.testing.allocator,
            Relocatable.init(0, 6),
        ),
    );
}

test "CairoVM: deduceMemoryCell builtin valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try vm.builtin_runners.append(
        BuiltinRunner{
            .Bitwise = BitwiseBuiltinRunner.init(
                &.{},
                true,
            ),
        },
    );

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 5 }, .{10} },
            .{ .{ 0, 6 }, .{12} },
            .{ .{ 0, 7 }, .{0} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 8),
        (try vm.deduceMemoryCell(std.testing.allocator, Relocatable.init(
            0,
            7,
        ))).?,
    );
}

test "update pc regular no imm" {
    // Test setup
    const allocator = std.testing.allocator;

    const operands = OperandsResult{};
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .AP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    const pc = vm.run_context.pc;
    try expectEqual(
        @as(
            u64,
            1,
        ),
        pc.offset,
    );
}

test "update pc regular with imm" {
    // Test setup
    const allocator = std.testing.allocator;
    const operands = OperandsResult{};
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    const pc = vm.run_context.pc;
    try expectEqual(
        @as(
            u64,
            2,
        ),
        pc.offset,
    );
}

test "update pc jump with operands res null" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(
        error.ResUnconstrainedUsedWithPcUpdateJump,
        vm.updatePc(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .FP,
                .op_0_reg = .FP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .Jump,
                .ap_update = .Add,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "update pc jump with operands res not relocatable" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = MaybeRelocatable.fromInt(u64, 0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(
        error.PcUpdateJumpResNotRelocatable,
        vm.updatePc(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .FP,
                .op_0_reg = .FP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .Jump,
                .ap_update = .Add,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "update pc jump with operands res relocatable" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = MaybeRelocatable.fromRelocatable(Relocatable.init(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    const pc = vm.run_context.pc;
    try expectEqual(
        @as(
            u64,
            42,
        ),
        pc.offset,
    );
}

test "update pc jump rel with operands res null" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(
        error.ResUnconstrainedUsedWithPcUpdateJumpRel,
        vm.updatePc(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .FP,
                .op_0_reg = .FP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .JumpRel,
                .ap_update = .Add,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "update pc jump rel with operands res not felt" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = MaybeRelocatable.fromRelocatable(Relocatable.init(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(
        error.PcUpdateJumpRelResNotFelt,
        vm.updatePc(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .FP,
                .op_0_reg = .FP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .JumpRel,
                .ap_update = .Add,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "update pc jump rel with operands res felt" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = MaybeRelocatable.fromInt(u64, 42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .JumpRel,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    const pc = vm.run_context.pc;
    try expectEqual(
        @as(
            u64,
            42,
        ),
        pc.offset,
    );
}

test "update pc update jnz with operands dst zero" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.dst = MaybeRelocatable.fromInt(u64, 0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jnz,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    const pc = vm.run_context.pc;
    try expectEqual(
        @as(
            u64,
            2,
        ),
        pc.offset,
    );
}

test "update pc update jnz with operands dst not zero op1 not felt" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.dst = MaybeRelocatable.fromInt(u64, 1);
    operands.op_1 = MaybeRelocatable.fromRelocatable(Relocatable.init(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(
        error.TypeMismatchNotFelt,
        vm.updatePc(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .FP,
                .op_0_reg = .FP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .Jnz,
                .ap_update = .Add,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "update pc update jnz with operands dst not zero op1 felt" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.dst = MaybeRelocatable.fromInt(u64, 1);
    operands.op_1 = MaybeRelocatable.fromInt(u64, 42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jnz,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    const pc = vm.run_context.pc;
    try expectEqual(
        @as(
            u64,
            42,
        ),
        pc.offset,
    );
}

test "CairoVM: updateAp using Add for AP update with null operands res" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.res = null; // Simulate unconstrained res
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(
        error.ApUpdateAddResUnconstrained,
        vm.updateAp(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .FP,
                .op_0_reg = .FP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .Jump,
                .ap_update = .Add,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "CairoVM: updateAp using Add for AP update with non-null operands result" {
    // Create an allocator for testing purposes.
    const allocator = std.testing.allocator;
    // Initialize operands result with a non-null result value.
    var operands = OperandsResult{};
    operands.res = MaybeRelocatable.fromInt(u8, 10);

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    // Ensure VM instance is deallocated after the test.
    defer vm.deinit();

    // Invoke the updateAp function with specified parameters.
    try vm.updateAp(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Expectation: The AP offset should be updated to the expected value after the operation.
    try expectEqual(
        @as(u64, 10),
        vm.run_context.ap,
    );
}

test "CairoVM: updateAp using Add1 for AP update" {
    // Test setup
    const allocator = std.testing.allocator;
    const operands = OperandsResult{};
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateAp(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add1,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    // Verify the AP offset was incremented by 1.
    const ap = vm.run_context.ap;
    try expectEqual(@as(u64, 1), ap);
}

test "update ap add2" {
    // Test setup
    const allocator = std.testing.allocator;
    const operands = OperandsResult{};
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateAp(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add2,
            .fp_update = .Regular,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    // Verify the AP offset was incremented by 2.
    const ap = vm.run_context.ap;
    try expectEqual(@as(u64, 2), ap);
}

test "update fp appplus2" {
    // Test setup
    const allocator = std.testing.allocator;
    const operands = OperandsResult{};
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateFp(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add,
            .fp_update = .APPlus2,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    // Verify the FP offset was incremented by 2.
    const fp = vm.run_context.fp;
    try expectEqual(@as(u64, 2), fp);
}

test "update fp dst relocatable" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.dst = MaybeRelocatable.fromRelocatable(Relocatable.init(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateFp(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add,
            .fp_update = .Dst,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    // Verify the FP offset was incremented by 2.
    const fp = vm.run_context.fp;
    try expectEqual(@as(u64, 42), fp);
}

test "update fp dst felt" {
    // Test setup
    const allocator = std.testing.allocator;
    var operands = OperandsResult{};
    operands.dst = MaybeRelocatable.fromInt(u64, 42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateFp(
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .Imm,
            .res_logic = .Add,
            .pc_update = .Jump,
            .ap_update = .Add,
            .fp_update = .Dst,
            .opcode = .Call,
        },
        operands,
    );

    // Test checks
    // Verify the FP offset was incremented by 2.
    const fp = vm.run_context.fp;
    try expectEqual(@as(u64, 42), fp);
}

test "trace is enabled" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    const config = Config{ .proof_mode = false, .enable_trace = true };

    var vm = try CairoVM.init(
        allocator,
        config,
    );
    defer vm.deinit();

    // Test body
    // Do nothing

    // Test checks
    // Check that trace was initialized
    if (vm.trace == null) {
        return error.TraceShouldHaveBeenEnabled;
    }
}

test "trace is disabled" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    // Do nothing

    // Test checks
    // Check that trace was initialized
    if (vm.trace != null) {
        return error.TraceShouldHaveBeenDisabled;
    }
}

test "get relocate trace without relocating trace" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    const config = Config{ .proof_mode = false, .enable_trace = true };

    var vm = try CairoVM.init(
        allocator,
        config,
    );
    defer vm.deinit();
    try expectError(TraceError.TraceNotRelocated, vm.getRelocatedTrace());
}

test "CairoVM: relocateTrace should return Trace Error if trace_relocated already set to true" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{},
    );
    defer vm.deinit();

    vm.relocated_trace = std.ArrayList(RelocatedTraceEntry).init(allocator);

    // Create a relocation table
    // Initialize an empty relocation table.
    var relocation_table = ArrayList(usize).init(std.testing.allocator);
    defer relocation_table.deinit();

    // Expect TraceError.AlreadyRelocated error
    // Assert that calling relocateTrace with trace_relocated already true results in an error.
    try expectError(
        TraceError.AlreadyRelocated,
        vm.relocateTrace(relocation_table.items),
    );
}

test "CairoVM: relocateTrace should return Trace Error if relocation_table len is less than 2" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{},
    );
    defer vm.deinit();

    // Create a relocation table
    // Initialize an empty relocation table.
    var relocation_table = ArrayList(usize).init(std.testing.allocator);
    defer relocation_table.deinit();

    // Expect TraceError.NoRelocationFound error
    // Assert that calling relocateTrace with a relocation_table length less than 2 results in an error.
    try expectError(
        TraceError.NoRelocationFound,
        vm.relocateTrace(relocation_table.items),
    );
}

test "CairoVM: relocateTrace should return Trace Error if trace context state is disabled" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{},
    );
    defer vm.deinit();

    // Create a relocation table
    // Initialize an empty relocation table and add specific values to it.
    var relocation_table = ArrayList(usize).init(std.testing.allocator);
    defer relocation_table.deinit();
    try relocation_table.append(1);
    try relocation_table.append(15);
    try relocation_table.append(27);
    try relocation_table.append(29);
    try relocation_table.append(29);

    // Expect TraceError.TraceNotEnabled error
    // Assert that calling relocateTrace when the trace context state is disabled results in an error.
    try expectError(
        TraceError.TraceNotEnabled,
        vm.relocateTrace(relocation_table.items),
    );
}

test "CairoVM: relocateTrace and trace comparison (simple use case)" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    const config = Config{ .proof_mode = false, .enable_trace = true };

    var vm = try CairoVM.init(
        allocator,
        config,
    );
    defer vm.deinit();
    const pc = .{};
    const ap = Relocatable.init(2, 0);
    const fp = Relocatable.init(2, 0);

    try vm.trace.?.append(.{ .pc = pc, .ap = ap, .fp = fp });

    for (0..4) |_| {
        _ = try vm.segments.addSegment();
    }

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.computeSegmentsEffectiveSizes(false);

    const relocation_table = try vm.segments.relocateSegments(allocator);
    defer allocator.free(relocation_table);
    try vm.relocateTrace(relocation_table);

    try expectEqualSlices(
        RelocatedTraceEntry,
        &[_]RelocatedTraceEntry{
            .{
                .pc = 1,
                .ap = 4,
                .fp = 4,
            },
        },
        try vm.getRelocatedTrace(),
    );
}

test "CairoVM: test step for preset memory" {
    // Test for a simple program execution
    // Used program code:
    // func main():
    //     let a = 1
    //     let b = 2
    //     let c = a + b
    //     return()
    // end
    // Memory taken from original vm
    // {RelocatableValue(segment_index=0, offset=0): 2345108766317314046,
    //  RelocatableValue(segment_index=1, offset=0): RelocatableValue(segment_index=2, offset=0),
    //  RelocatableValue(segment_index=1, offset=1): RelocatableValue(segment_index=3, offset=0)}
    // Current register values:
    // AP 1:2
    // FP 1:2
    // PC 0:0

    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );
    defer vm.deinit();

    vm.run_context.ap = 2;
    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(allocator);
    defer exec_scopes.deinit();

    var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
    defer hint_datas.deinit();

    var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
    defer hint_ranges.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try vm.stepExtensive(
        std.testing.allocator,
        .{},
        &exec_scopes,
        &hint_datas,
        &hint_ranges,
        &constants,
    );

    try expectEqual(Relocatable.init(3, 0), vm.run_context.pc);
    try expectEqual(Relocatable.init(1, 2), vm.run_context.getAP());
    try expectEqual(Relocatable.init(1, 0), vm.run_context.getFP());

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 2),
                .fp = Relocatable.init(1, 2),
            },
        },
        vm.trace.?.items,
    );

    // Check that the following addresses have been accessed
    try expect(vm.segments.memory.data.items[1].items[0].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[1].?.is_accessed);
}

test "CairoVM: relocateTrace and trace comparison (more complex use case)" {
    // ProgramJson used:
    // %builtins output

    // from starkware.cairo.common.serialize import serialize_word

    // func main{output_ptr: felt*}():
    //    let a = 1
    //    serialize_word(a)
    //    let b = 17 * a
    //    serialize_word(b)
    //    return()
    // end

    // Relocated Trace:
    // [TraceEntry(pc=5, ap=18, fp=18),
    // TraceEntry(pc=6, ap=19, fp=18),
    // TraceEntry(pc=8, ap=20, fp=18),
    // TraceEntry(pc=1, ap=22, fp=22),
    // TraceEntry(pc=2, ap=22, fp=22),
    // TraceEntry(pc=4, ap=23, fp=22),
    // TraceEntry(pc=10, ap=23, fp=18),

    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );
    defer vm.deinit();

    // Initial Trace Entries
    // Define and append initial trace entries to the VM trace context.
    // pc, ap, and fp values are initialized and appended in pairs.
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 4),
        .ap = Relocatable.init(1, 3),
        .fp = Relocatable.init(1, 3),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 5),
        .ap = Relocatable.init(1, 4),
        .fp = Relocatable.init(1, 3),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 7),
        .ap = Relocatable.init(1, 5),
        .fp = Relocatable.init(1, 3),
    });
    try vm.trace.?.append(.{
        .pc = .{},
        .ap = Relocatable.init(1, 7),
        .fp = Relocatable.init(1, 7),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 1),
        .ap = Relocatable.init(1, 7),
        .fp = Relocatable.init(1, 7),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 3),
        .ap = Relocatable.init(1, 8),
        .fp = Relocatable.init(1, 7),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 9),
        .ap = Relocatable.init(1, 8),
        .fp = Relocatable.init(1, 3),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 11),
        .ap = Relocatable.init(1, 9),
        .fp = Relocatable.init(1, 3),
    });
    try vm.trace.?.append(.{
        .pc = .{},
        .ap = Relocatable.init(1, 11),
        .fp = Relocatable.init(1, 11),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 1),
        .ap = Relocatable.init(1, 11),
        .fp = Relocatable.init(1, 11),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 3),
        .ap = Relocatable.init(1, 12),
        .fp = Relocatable.init(1, 11),
    });
    try vm.trace.?.append(.{
        .pc = Relocatable.init(0, 13),
        .ap = Relocatable.init(1, 12),
        .fp = Relocatable.init(1, 3),
    });

    // Create a relocation table
    // Create a relocation table and append specific values to it.
    var relocation_table = ArrayList(usize).init(std.testing.allocator);
    defer relocation_table.deinit();

    try relocation_table.append(1);
    try relocation_table.append(15);
    try relocation_table.append(27);
    try relocation_table.append(29);
    try relocation_table.append(29);

    // Assert trace relocation status
    // Ensure the trace relocation status flag is set as expected (false).
    try expect(vm.relocated_trace == null);

    try vm.relocateTrace(relocation_table.items);

    // Expected Relocated Entries
    // Define the expected relocated entries after the trace relocation process.
    var expected_relocated_entries = ArrayList(RelocatedTraceEntry).init(std.testing.allocator);
    defer expected_relocated_entries.deinit();

    // Append expected relocated entries using Felt252 values.
    // pc, ap, and fp values are appended in pairs similar to the initial entries.
    try expected_relocated_entries.append(.{
        .pc = 5,
        .ap = 18,
        .fp = 18,
    });
    try expected_relocated_entries.append(.{
        .pc = 6,
        .ap = 19,
        .fp = 18,
    });
    try expected_relocated_entries.append(.{
        .pc = 8,
        .ap = 20,
        .fp = 18,
    });
    try expected_relocated_entries.append(.{
        .pc = 1,
        .ap = 22,
        .fp = 22,
    });
    try expected_relocated_entries.append(.{
        .pc = 2,
        .ap = 22,
        .fp = 22,
    });
    try expected_relocated_entries.append(.{
        .pc = 4,
        .ap = 23,
        .fp = 22,
    });
    try expected_relocated_entries.append(.{
        .pc = 10,
        .ap = 23,
        .fp = 18,
    });
    try expected_relocated_entries.append(.{
        .pc = 12,
        .ap = 24,
        .fp = 18,
    });
    try expected_relocated_entries.append(.{
        .pc = 1,
        .ap = 26,
        .fp = 26,
    });
    try expected_relocated_entries.append(.{
        .pc = 2,
        .ap = 26,
        .fp = 26,
    });
    try expected_relocated_entries.append(.{
        .pc = 4,
        .ap = 27,
        .fp = 26,
    });
    try expected_relocated_entries.append(.{
        .pc = 14,
        .ap = 27,
        .fp = 18,
    });

    // Assert relocated entries match the expected entries
    // Ensure the relocated trace entries in the VM match the expected relocated entries.
    try expectEqualSlices(
        RelocatedTraceEntry,
        expected_relocated_entries.items,
        vm.relocated_trace.?.items,
    );
    // Assert trace relocation status
    // Ensure the trace relocation status flag is set as expected (true).
    try expect(vm.relocated_trace != null);
}

// This instruction is used in the functions that test the `deduceOp1` function. Only the
// `opcode` and `res_logic` fields are usually changed.
const deduceOpTestInstr = Instruction{
    .off_0 = 1,
    .off_1 = 2,
    .off_2 = 3,
    .dst_reg = .FP,
    .op_0_reg = .AP,
    .op_1_addr = .AP,
    .res_logic = .Add,
    .pc_update = .Jump,
    .ap_update = .Regular,
    .fp_update = .Regular,
    .opcode = .Call,
};

test "deduceOp0 when opcode == .Call" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    const deduceOp0 = try vm.deduceOp0(&instr, &null, &null);

    // Test checks
    const expected_op_0: ?MaybeRelocatable = MaybeRelocatable.fromRelocatable(Relocatable.init(0, 1)); // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, deduceOp0.op_0);
    try expectEqual(expected_res, deduceOp0.res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Add, input is felt" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 3);
    const op1: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 2);

    const deduceOp0 = try vm.deduceOp0(&instr, &dst, &op1);

    // Test checks
    try expect(deduceOp0.op_0.?.eq(MaybeRelocatable.fromInt(u64, 1)));
    try expect(deduceOp0.res.?.eq(MaybeRelocatable.fromInt(u64, 3)));
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Add, with no input" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const deduceOp0 = try vm.deduceOp0(&instr, &null, &null);

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, deduceOp0.op_0);
    try expectEqual(expected_res, deduceOp0.res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Mul, input is felt 1" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    const op1: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 2);

    const deduceOp0 = try vm.deduceOp0(&instr, &dst, &op1);

    // Test checks
    const expected_op_0: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 2); // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    try expectEqual(expected_op_0, deduceOp0.op_0);
    try expectEqual(expected_res, deduceOp0.res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Op1, input is felt" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    const op1: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 0);

    const deduceOp0 = try vm.deduceOp0(&instr, &dst, &op1);

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, deduceOp0.op_0);
    try expectEqual(expected_res, deduceOp0.res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Mul, input is felt 2" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    const op1: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 0);

    const deduceOp0 = try vm.deduceOp0(&instr, &dst, &op1);

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, deduceOp0.op_0);
    try expectEqual(expected_res, deduceOp0.res);
}

test "deduceOp0 when opcode == .Ret, res_logic == .Mul, input is felt" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .Ret;
    instr.res_logic = .Mul;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    const op1: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 0);

    const deduceOp0 = try vm.deduceOp0(&instr, &dst, &op1);

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, deduceOp0.op_0);
    try expectEqual(expected_res, deduceOp0.res);
}

test "set get value in vm memory" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    const address = Relocatable.init(1, 0);
    const value = MaybeRelocatable.fromFelt(starknet_felt.Felt252.fromInt(u8, 42));

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 0 }, .{42} }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test checks
    // Verify the value is correctly set to 42.
    const actual_value = vm.segments.memory.get(address);
    const expected_value = value;
    try expectEqual(
        expected_value,
        actual_value.?,
    );
}

test "CairoVM: compute operands add AP" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap = 0;

    // Test body
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{5} },
            .{ .{ 1, 1 }, .{2} },
            .{ .{ 1, 2 }, .{3} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const expected_operands: OperandsResult = .{
        .dst_addr = .{ .segment_index = 1, .offset = 0 },
        .op_0_addr = .{ .segment_index = 1, .offset = 1 },
        .op_1_addr = .{ .segment_index = 1, .offset = 2 },
        .dst = .{ .felt = Felt252.fromInt(u8, 5) },
        .op_0 = .{ .felt = Felt252.two() },
        .op_1 = .{ .felt = Felt252.three() },
        .res = .{ .felt = Felt252.fromInt(u8, 5) },
        .deduced_operands = 0,
    };

    const actual_operands = try vm.computeOperands(
        std.testing.allocator,
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .AP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        },
    );

    // Test checks
    try expectEqual(
        expected_operands,
        actual_operands,
    );
}

test "CairoVM: compute operands mul FP" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.fp = 0;

    // Test body
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{6} },
            .{ .{ 1, 1 }, .{2} },
            .{ .{ 1, 2 }, .{3} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const expected_operands: OperandsResult = .{
        .dst_addr = .{ .segment_index = 1, .offset = 0 },
        .op_0_addr = .{ .segment_index = 1, .offset = 1 },
        .op_1_addr = .{ .segment_index = 1, .offset = 2 },
        .dst = .{ .felt = Felt252.fromInt(u8, 6) },
        .op_0 = .{ .felt = Felt252.two() },
        .op_1 = .{ .felt = Felt252.three() },
        .res = .{ .felt = Felt252.fromInt(u8, 6) },
        .deduced_operands = 0,
    };

    const actual_operands = try vm.computeOperands(
        std.testing.allocator,
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 2,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .FP,
            .res_logic = .Mul,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        },
    );

    // Test checks
    try expectEqual(
        expected_operands,
        actual_operands,
    );
}

test "CairoVM: compute operands JNZ" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0x206800180018001} },
            .{ .{ 1, 1 }, .{0x4} },
            .{ .{ 0, 1 }, .{0x4} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const expected_operands: OperandsResult = .{
        .dst_addr = .{ .segment_index = 1, .offset = 1 },
        .op_0_addr = .{ .segment_index = 1, .offset = 1 },
        .op_1_addr = .{ .segment_index = 0, .offset = 1 },
        .dst = .{ .felt = Felt252.fromInt(u8, 4) },
        .op_0 = .{ .felt = Felt252.fromInt(u8, 4) },
        .op_1 = .{ .felt = Felt252.fromInt(u8, 4) },
        .res = null,
        .deduced_operands = 0,
    };

    const actual_operands = try vm.computeOperands(
        std.testing.allocator,
        &.{
            .off_0 = 1,
            .off_1 = 1,
            .off_2 = 1,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .Imm,
            .res_logic = .Unconstrained,
            .pc_update = .Jnz,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        },
    );

    // Test checks
    try expectEqual(expected_operands, actual_operands);

    var exec_scopes = try ExecutionScopes.init(allocator);
    defer exec_scopes.deinit();

    var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
    defer hint_datas.deinit();

    var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
    defer hint_ranges.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try vm.stepExtensive(
        std.testing.allocator,
        .{},
        &exec_scopes,
        &hint_datas,
        &hint_ranges,
        &constants,
    );

    try expectEqual(Relocatable.init(0, 4), vm.run_context.pc);
}

test "CairoVM: compute operands deduce dst none" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap = 0;

    // Test body
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 0 }, .{145944781867024385} }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        CairoVMError.NoDst,
        vm.computeOperands(
            std.testing.allocator,
            &.{
                .off_0 = 2,
                .off_1 = 0,
                .off_2 = 0,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Unconstrained,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
        ),
    );
}

test "CairoVM: compute operands with op_1_addr as Op0" {
    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap = 0;

    // Test body
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0x206800180018001} },
            .{ .{ 1, 1 }, .{ 1, 4 } },
            .{ .{ 1, 5 }, .{ 1, 2 } },
            .{ .{ 0, 1 }, .{0x4} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const expected_operands: OperandsResult = .{
        .dst_addr = .{ .segment_index = 1, .offset = 1 },
        .op_0_addr = .{ .segment_index = 1, .offset = 1 },
        .op_1_addr = .{ .segment_index = 1, .offset = 5 },
        .dst = .{ .relocatable = .{ .segment_index = 1, .offset = 4 } },
        .op_0 = .{ .relocatable = .{ .segment_index = 1, .offset = 4 } },
        .op_1 = .{ .relocatable = .{ .segment_index = 1, .offset = 2 } },
        .res = null,
        .deduced_operands = 0,
    };

    const actual_operands = try vm.computeOperands(
        std.testing.allocator,
        &.{
            .off_0 = 1,
            .off_1 = 1,
            .off_2 = 1,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .Op0,
            .res_logic = .Unconstrained,
            .pc_update = .Jnz,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        },
    );

    // Test checks
    try expectEqual(
        expected_operands,
        actual_operands,
    );
}

test "memory is not leaked upon allocation failure during initialization" {
    var i: usize = 0;
    while (i < 20) {
        // ************************************************************
        // *                 SETUP TEST CONTEXT                       *
        // ************************************************************
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = i });
        i += 1;

        //         // ************************************************************
        //         // *                      TEST BODY                           *
        //         // ************************************************************
        //         // Nothing.

        //         // ************************************************************
        //         // *                      TEST CHECKS                         *
        //         // ************************************************************
        //         // Error must have occured!

        //         // It's not given that the final error will be an OutOfMemory. It's likely though.
        //         // Plus we're not certain that the error will be thrown at the same place as the
        //         // VM is upgraded. For this reason, we should just ensure that no memory has
        //         // been leaked.
        //         // try expectError(error.OutOfMemory, CairoVM.init(allocator.allocator(), .{}));

        // Note that `.deinit()` is not called in case of failure (obviously).
        // If error handling is done correctly, no memory should be leaked.
        var vm = CairoVM.init(allocator.allocator(), .{}) catch continue;
        vm.deinit();
    }
}

test "updateRegisters all regular" {
    // Test setup
    const operands = OperandsResult{
        .dst = .{ .felt = Felt252.fromInt(u8, 11) },
        .res = .{ .felt = Felt252.fromInt(u8, 8) },
        .op_0 = .{ .felt = Felt252.fromInt(u8, 9) },
        .op_1 = .{ .felt = Felt252.fromInt(u8, 10) },
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    vm.run_context.pc = Relocatable.init(0, 4);
    vm.run_context.ap = 5;
    vm.run_context.fp = 6;

    // Test body
    try vm.updateRegisters(
        &.{
            .off_0 = 1,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .FP,
            .op_0_reg = .AP,
            .op_1_addr = .AP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        },
        operands,
    );

    // Test checks
    // Verify the PC offset was incremented by 5.
    try expectEqual(
        Relocatable.init(0, 5),
        vm.run_context.pc,
    );

    // Verify the AP offset was incremented by 5.
    try expectEqual(
        Relocatable.init(1, 5),
        vm.run_context.getAP(),
    );

    // Verify the FP offset was incremented by 6.
    try expectEqual(
        Relocatable.init(1, 6),
        vm.run_context.getFP(),
    );
}

test "updateRegisters with mixed types" {
    // Test setup

    var instruction = deduceOpTestInstr;
    instruction.pc_update = .JumpRel;
    instruction.ap_update = .Add2;
    instruction.fp_update = .Dst;

    const operands = OperandsResult{
        .dst = .{ .relocatable = Relocatable.init(
            1,
            11,
        ) },
        .res = .{ .felt = Felt252.fromInt(u8, 8) },
        .op_0 = .{ .felt = Felt252.fromInt(u8, 9) },
        .op_1 = .{ .felt = Felt252.fromInt(u8, 10) },
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    vm.run_context.pc = Relocatable.init(0, 4);
    vm.run_context.ap = 5;
    vm.run_context.fp = 6;

    // Test body
    try vm.updateRegisters(
        &instruction,
        operands,
    );

    // Test checks
    // Verify the PC offset was incremented by 12.
    try expectEqual(
        Relocatable.init(0, 12),
        vm.run_context.pc,
    );

    // Verify the AP offset was incremented by 7.
    try expectEqual(
        Relocatable.init(1, 7),
        vm.run_context.getAP(),
    );

    // Verify the FP offset was incremented by 11.
    try expectEqual(
        Relocatable.init(1, 11),
        vm.run_context.getFP(),
    );
}

test "CairoVM: computeOp0Deductions should return op0 from deduceOp0 if deduceMemoryCell is null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    var res: ?MaybeRelocatable = null;

    // Test check
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 1),
        try vm.computeOp0Deductions(
            std.testing.allocator,
            Relocatable.init(0, 7),
            &res,
            &instr,
            &null,
            &null,
        ),
    );
}

test "CairoVM: computeOp0Deductions with a valid built in and non null deduceMemoryCell should return deduceMemoryCell" {
    // Test setup
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try vm.builtin_runners.append(
        BuiltinRunner{
            .Bitwise = BitwiseBuiltinRunner.init(
                &.{},
                true,
            ),
        },
    );
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 5 }, .{10} },
            .{ .{ 0, 6 }, .{12} },
            .{ .{ 0, 7 }, .{0} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var res: ?MaybeRelocatable = null;

    // Test check
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 8),
        try vm.computeOp0Deductions(
            std.testing.allocator,
            Relocatable.init(0, 7),
            &res,
            &deduceOpTestInstr,
            &.{ .relocatable = .{} },
            &.{ .relocatable = .{} },
        ),
    );
}

test "CairoVM: computeOp0Deductions should return VM error if deduceOp0 and deduceMemoryCell are null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instr = deduceOpTestInstr;
    instr.opcode = .Ret;
    instr.res_logic = .Mul;

    var res: ?MaybeRelocatable = null;

    // Test check
    try expectError(
        CairoVMError.FailedToComputeOp0,
        vm.computeOp0Deductions(
            std.testing.allocator,
            Relocatable.init(0, 7),
            &res,
            &instr,
            &MaybeRelocatable.fromInt(u64, 4),
            &MaybeRelocatable.fromInt(u64, 0),
        ),
    );
}

test "CairoVM: computeSegmentsEffectiveSizes should return the computed effective size for the VM segments" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{1} },
            .{ .{ 0, 2 }, .{1} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var actual = try vm.computeSegmentsEffectiveSizes(false);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 3), actual.get(0).?);
}

test "CairoVM: deduceDst should return res if AssertEq opcode" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    const res = MaybeRelocatable.fromInt(u8, 7);

    // Test check
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 7),
        try vm.deduceDst(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .AssertEq,
            },
            res,
        ),
    );
}

test "CairoVM: deduceDst should return VM error No dst if AssertEq opcode without res" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test check
    try expectError(
        CairoVMError.NoDst,
        vm.deduceDst(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .AssertEq,
            },
            null,
        ),
    );
}

test "CairoVM: deduceDst should return fp Relocatable if Call opcode" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    vm.run_context.fp = 23;

    // Test check
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 23),
        try vm.deduceDst(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            null,
        ),
    );
}

test "CairoVM: deduceDst should return VM error No dst if not AssertEq or Call opcode" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test check
    try expectError(
        CairoVMError.NoDst,
        vm.deduceDst(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .Ret,
            },
            null,
        ),
    );
}

test "CairoVM: addMemorySegment should return a proper relocatable address for the new segment." {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test check
    try expectEqual(
        Relocatable{},
        try vm.addMemorySegment(),
    );
}

test "CairoVM: addMemorySegment should increase by one the number of segments in the VM" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    // Test check
    try expectEqual(
        @as(u32, 3),
        vm.segments.memory.num_segments,
    );
}

test "CairoVM: getRelocatable without value raises error" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test check
    try expectError(
        error.ExpectedRelocatable,
        vm.getRelocatable(.{}),
    );
}

test "CairoVM: getRelocatable with value should return a MaybeRelocatable" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 34, 12 }, .{ 5, 5 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test check
    try expectEqual(
        Relocatable.init(5, 5),
        try (vm.getRelocatable(Relocatable.init(34, 12))),
    );
}

test "CairoVM: getBuiltinRunners should return a reference to the builtin runners ArrayList" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try vm.builtin_runners.append(
        BuiltinRunner{
            .Bitwise = BitwiseBuiltinRunner.init(
                &.{ .ratio = null, .total_n_bits = 2 },
                true,
            ),
        },
    );

    // Test check
    try expectEqual(&vm.builtin_runners, vm.getBuiltinRunners());

    var expected = ArrayList(BuiltinRunner).init(std.testing.allocator);
    defer expected.deinit();
    try expected.append(
        BuiltinRunner{
            .Bitwise = BitwiseBuiltinRunner.init(
                &.{ .ratio = null, .total_n_bits = 2 },
                true,
            ),
        },
    );
    try expectEqualSlices(
        BuiltinRunner,
        expected.items,
        vm.getBuiltinRunners().*.items,
    );
}

test "CairoVM: getSegmentUsedSize should return the size of a memory segment by its index if available" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(10, 4);
    try expectEqual(
        @as(u32, @intCast(4)),
        vm.getSegmentUsedSize(10).?,
    );
}

test "CairoVM: getSegmentUsedSize should return the size of the segment if contained in segment_sizes" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_sizes.put(10, 105);
    try expectEqual(@as(u32, 105), vm.getSegmentSize(10).?);
}

test "CairoVM: getSegmentSize should return the size of the segment via getSegmentUsedSize if not contained in segment_sizes" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(3, 6);
    try expectEqual(@as(u32, 6), vm.getSegmentSize(3).?);
}

test "CairoVM: getFelt should return UnknownMemoryCell error if no value at the given address" {
    // Test setup
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // Test checks
    try expectError(
        error.UnknownMemoryCell,
        vm.getFelt(Relocatable.init(10, 30)),
    );
}

test "CairoVM: getFelt should return Felt252 if available at the given address" {
    // Test setup
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 10, 30 }, .{23} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        Felt252.fromInt(u8, 23),
        try vm.getFelt(Relocatable.init(10, 30)),
    );
}

test "CairoVM: getFelt should return ExpectedInteger error if Relocatable instead of Felt at the given address" {
    // Test setup
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 10, 30 }, .{ 3, 7 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        error.ExpectedInteger,
        vm.getFelt(Relocatable.init(10, 30)),
    );
}

test "CairoVM: computeOp1Deductions should return op1 from deduceMemoryCell if not null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.builtin_runners.append(
        BuiltinRunner{
            .Bitwise = BitwiseBuiltinRunner.init(
                &.{},
                true,
            ),
        },
    );
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 5 }, .{10} },
            .{ .{ 0, 6 }, .{12} },
            .{ .{ 0, 7 }, .{0} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var instr = deduceOpTestInstr;
    var res: ?MaybeRelocatable = null;

    // Test check
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 8),
        try vm.computeOp1Deductions(
            std.testing.allocator,
            Relocatable.init(0, 7),
            &res,
            &instr,
            &null,
            &null,
        ),
    );
}

test "CairoVM: computeOp1Deductions should return op1 from deduceOp1 if deduceMemoryCell is null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 7);
    var res: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 7);

    // Test check
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        try vm.computeOp1Deductions(
            std.testing.allocator,
            Relocatable.init(0, 7),
            &res,
            &instr,
            &dst,
            &null,
        ),
    );
}

test "CairoVM: computeOp1Deductions should modify res (if null) using res from deduceOp1 if deduceMemoryCell is null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 7);
    var res: ?MaybeRelocatable = null;

    _ = try vm.computeOp1Deductions(
        std.testing.allocator,
        Relocatable.init(0, 7),
        &res,
        &instr,
        &dst,
        &null,
    );

    // Test check
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        res.?,
    );
}

test "CairoVM: computeOp1Deductions should return CairoVMError error if deduceMemoryCell is null and deduceOp1.op_1 is null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const op0: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 0);
    var res: ?MaybeRelocatable = null;

    // Test check
    try expectError(
        CairoVMError.FailedToComputeOp1,
        vm.computeOp1Deductions(
            std.testing.allocator,
            Relocatable.init(0, 7),
            &res,
            &instr,
            &null,
            &op0,
        ),
    );
}

test "CairoVM: core utility function for testing test" {
    const allocator = std.testing.allocator;

    var cairo_vm = try CairoVM.init(allocator, .{});
    defer cairo_vm.deinit();

    try segments.segmentsUtil(
        cairo_vm.segments,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{1} },
            .{ .{ 0, 2 }, .{1} },
        },
    );
    defer cairo_vm.segments.memory.deinitData(std.testing.allocator);

    var actual = try cairo_vm.computeSegmentsEffectiveSizes(false);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 3), actual.get(0).?);
}

test "CairoVM: OperandsResult set " {
    // Test setup
    var operands = OperandsResult{};
    operands.setDst(true);

    // Test body
    try expectEqual(operands.deduced_operands, 1);
}

test "CairoVM: OperandsResult set Op1" {
    // Test setup
    var operands = OperandsResult{};
    operands.setOp0(true);
    operands.setOp1(true);
    operands.setDst(true);

    // Test body
    try expectEqual(operands.deduced_operands, 7);
}

test "CairoVM: OperandsResult deduced set and was functionality" {
    // Test setup
    var operands = OperandsResult{};
    operands.setOp1(true);

    // Test body
    try expect(operands.wasOp1Deducted());
}

test "CairoVM: InserDeducedOperands should insert operands if set as deduced" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    // Test body

    const dst_addr = Relocatable.init(1, 0);
    const dst_val = MaybeRelocatable{ .felt = Felt252.fromInt(u8, 6) };

    const op0_addr = Relocatable.init(1, 1);
    const op0_val = MaybeRelocatable{ .felt = Felt252.two() };

    const op1_addr = Relocatable.init(1, 2);
    const op1_val = MaybeRelocatable{ .felt = Felt252.three() };
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var test_operands = OperandsResult{};
    test_operands.dst_addr = dst_addr;
    test_operands.op_0_addr = op0_addr;
    test_operands.op_1_addr = op1_addr;
    test_operands.dst = dst_val;
    test_operands.op_0 = op0_val;
    test_operands.op_1 = op1_val;
    test_operands.res = dst_val;
    test_operands.deduced_operands = 7;

    try vm.insertDeducedOperands(allocator, test_operands);

    // Test checks
    try expectEqual(
        vm.segments.memory.get(Relocatable.init(1, 0)),
        dst_val,
    );
    try expectEqual(
        vm.segments.memory.get(Relocatable.init(1, 1)),
        op0_val,
    );
    try expectEqual(
        vm.segments.memory.get(Relocatable.init(1, 2)),
        op1_val,
    );
}

test "CairoVM: InserDeducedOperands insert operands should not be inserted if not set as deduced" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    // Test body

    const dst_addr = Relocatable.init(1, 0);
    const dst_val = MaybeRelocatable{ .felt = Felt252.fromInt(u8, 6) };

    const op0_addr = Relocatable.init(1, 1);
    const op0_val = MaybeRelocatable{ .felt = Felt252.two() };

    const op1_addr = Relocatable.init(1, 2);
    const op1_val = MaybeRelocatable{ .felt = Felt252.three() };
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var test_operands = OperandsResult{};
    test_operands.dst_addr = dst_addr;
    test_operands.op_0_addr = op0_addr;
    test_operands.op_1_addr = op1_addr;
    test_operands.dst = dst_val;
    test_operands.op_0 = op0_val;
    test_operands.op_1 = op1_val;
    test_operands.res = dst_val;
    // 0 means no operands should be inserted
    test_operands.deduced_operands = 0;

    try vm.insertDeducedOperands(allocator, test_operands);

    // Test checks
    try expectEqual(
        @as(?MaybeRelocatable, null),
        vm.segments.memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        @as(?MaybeRelocatable, null),
        vm.segments.memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        @as(?MaybeRelocatable, null),
        vm.segments.memory.get(Relocatable.init(1, 2)),
    );
}

test "CairoVM: markAddressRangeAsAccessed should mark memory segments as accessed" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.is_run_finished = true;
    try segments.segmentsUtil(
        vm.segments,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0} },
            .{ .{ 0, 1 }, .{0} },
            .{ .{ 0, 2 }, .{1} },
            .{ .{ 0, 10 }, .{10} },
            .{ .{ 1, 1 }, .{1} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.markAddressRangeAsAccessed(.{}, 3);
    try vm.markAddressRangeAsAccessed(Relocatable.init(0, 10), 2);
    try vm.markAddressRangeAsAccessed(Relocatable.init(1, 1), 1);

    try expect(vm.segments.memory.data.items[0].items[0].?.is_accessed);
    try expect(vm.segments.memory.data.items[0].items[1].?.is_accessed);
    try expect(vm.segments.memory.data.items[0].items[2].?.is_accessed);
    try expect(vm.segments.memory.data.items[0].items[10].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[1].?.is_accessed);
    try expectEqual(
        @as(?usize, 4),
        vm.segments.memory.countAccessedAddressesInSegment(0),
    );
    try expectEqual(
        @as(?usize, 1),
        vm.segments.memory.countAccessedAddressesInSegment(1),
    );
}

test "CairoVM: markAddressRangeAsAccessed should return an error if the run is not finished" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try expectError(
        CairoVMError.RunNotFinished,
        vm.markAddressRangeAsAccessed(.{}, 3),
    );
}

test "CairoVM: opcodeAssertions should throw UnconstrainedAssertEq error" {
    const operands = OperandsResult{
        .dst = .{ .felt = Felt252.fromInt(u8, 8) },
        .res = null,
        .op_0 = .{ .felt = Felt252.fromInt(u8, 9) },
        .op_1 = .{ .felt = Felt252.fromInt(u8, 10) },
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try expectError(
        CairoVMError.UnconstrainedResAssertEq,
        vm.opcodeAssertions(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .AssertEq,
            },
            operands,
        ),
    );
}

test "CairoVM: opcodeAssertions instructions failed - should throw DiffAssertValues error" {
    const operands = OperandsResult{
        .dst = MaybeRelocatable.fromInt(u64, 9),
        .res = MaybeRelocatable.fromInt(u64, 8),
        .op_0 = MaybeRelocatable.fromInt(u64, 9),
        .op_1 = MaybeRelocatable.fromInt(u64, 10),
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try expectError(
        CairoVMError.DiffAssertValues,
        vm.opcodeAssertions(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .AssertEq,
            },
            operands,
        ),
    );
}

test "CairoVM: opcodeAssertions instructions failed relocatables - should throw DiffAssertValues error" {
    const operands = OperandsResult{
        .dst = MaybeRelocatable.fromSegment(1, 1),
        .res = MaybeRelocatable.fromSegment(1, 2),
        .op_0 = MaybeRelocatable.fromInt(u64, 9),
        .op_1 = MaybeRelocatable.fromInt(u64, 10),
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try expectError(
        CairoVMError.DiffAssertValues,
        vm.opcodeAssertions(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .AssertEq,
            },
            operands,
        ),
    );
}

test "CairoVM: opcodeAssertions inconsistent op0 - should throw CantWriteReturnPC error" {
    const operands = OperandsResult{
        .dst = MaybeRelocatable.fromSegment(0, 1),
        .res = MaybeRelocatable.fromInt(u64, 8),
        .op_0 = MaybeRelocatable.fromInt(u64, 9),
        .op_1 = MaybeRelocatable.fromInt(u64, 10),
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    vm.run_context.pc = Relocatable.init(0, 4);

    try expectError(
        CairoVMError.CantWriteReturnPc,
        vm.opcodeAssertions(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "CairoVM: opcodeAssertions inconsistent dst - should throw CantWriteReturnFp error" {
    const operands = OperandsResult{
        .dst = MaybeRelocatable.fromInt(u64, 8),
        .res = MaybeRelocatable.fromInt(u64, 8),
        .op_0 = MaybeRelocatable.fromSegment(0, 1),
        .op_1 = MaybeRelocatable.fromInt(u64, 10),
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
        .deduced_operands = 0,
    };

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    vm.run_context.fp = 6;

    try expectError(
        CairoVMError.CantWriteReturnFp,
        vm.opcodeAssertions(
            &.{
                .off_0 = 0,
                .off_1 = 1,
                .off_2 = 2,
                .dst_reg = .AP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .Call,
            },
            operands,
        ),
    );
}

test "CairoVM: getFeltRange for continuous memory" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.is_run_finished = true;
    try segments.segmentsUtil(
        vm.segments,
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{2} },
            .{ .{ 1, 1 }, .{3} },
            .{ .{ 1, 2 }, .{4} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var expected_vec = std.ArrayList(Felt252).init(std.testing.allocator);
    defer expected_vec.deinit();

    try expected_vec.append(Felt252.two());
    try expected_vec.append(Felt252.three());
    try expected_vec.append(Felt252.fromInt(u8, 4));

    var actual = try vm.getFeltRange(
        Relocatable.init(1, 0),
        3,
    );
    defer actual.deinit();

    // Test checks
    try expectEqualSlices(
        Felt252,
        expected_vec.items,
        actual.items,
    );
}

test "CairoVM: getFeltRange for Relocatable instead of Felt" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.is_run_finished = true;
    try segments.segmentsUtil(
        vm.segments,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0} },
            .{ .{ 0, 1 }, .{0} },
            .{ .{ 0, 2 }, .{ 1, 4 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectError(
        MemoryError.ExpectedInteger,
        vm.getFeltRange(
            .{},
            3,
        ),
    );
}

test "CairoVM: getFeltRange for out of bounds memory" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.is_run_finished = true;
    try segments.segmentsUtil(
        vm.segments,
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{4} },
            .{ .{ 1, 1 }, .{5} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        MemoryError.UnknownMemoryCell,
        vm.getFeltRange(
            Relocatable.init(1, 0),
            4,
        ),
    );
}

test "CairoVM: getFeltRange for non continuous memory" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.is_run_finished = true;
    try segments.segmentsUtil(
        vm.segments,
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{4} },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 3 }, .{6} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        MemoryError.UnknownMemoryCell,
        vm.getFeltRange(
            Relocatable.init(1, 0),
            4,
        ),
    );
}

test "CairoVM: loadData should give the correct segment size" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();
    const segment = try vm.segments.addSegment();

    // Prepare data to load into memory
    var data = std.ArrayList(MaybeRelocatable).init(allocator);
    defer data.deinit();
    try data.append(MaybeRelocatable.fromInt(u8, 1));
    try data.append(MaybeRelocatable.fromInt(u8, 2));
    try data.append(MaybeRelocatable.fromInt(u8, 3));
    try data.append(MaybeRelocatable.fromInt(u8, 4));

    // Load data into memory segment
    const actual = try vm.loadData(segment, &data);
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Perform assertions
    try expectEqual(
        Relocatable.init(0, 4),
        actual,
    );

    // Check the segment size
    var segment_size = try vm.segments.computeEffectiveSize(false);

    // Assert segment size count and the value at index 0
    try expectEqual(@as(usize, 1), segment_size.count());
    try expectEqual(@as(u32, 4), segment_size.get(0).?);
}

test "CairoVM: loadData should resize the instruction cache with null elements if ptr segment index is zero" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();
    const segment = try vm.segments.addSegment();

    // Prepare data to load into memory
    var data = std.ArrayList(MaybeRelocatable).init(allocator);
    defer data.deinit();
    try data.append(MaybeRelocatable.fromInt(u8, 1));
    try data.append(MaybeRelocatable.fromInt(u8, 2));
    try data.append(MaybeRelocatable.fromInt(u8, 3));
    try data.append(MaybeRelocatable.fromInt(u8, 4));

    // Load data into memory segment
    const actual = try vm.loadData(segment, &data);
    _ = actual;
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Prepare an expected instruction cache with null elements
    var expected_instruction_cache = ArrayList(?Instruction).init(allocator);
    defer expected_instruction_cache.deinit();
    try expected_instruction_cache.appendNTimes(null, 4);

    // Assert the instruction cache after loading data
    try expectEqualSlices(
        ?Instruction,
        expected_instruction_cache.items,
        vm.instruction_cache.items,
    );
}

test "CairoVM: loadData should not resize the instruction cache if ptr segment index is not zero" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();
    _ = try vm.segments.addSegment();
    const segment = try vm.segments.addSegment();

    // Prepare data to load into memory
    var data = std.ArrayList(MaybeRelocatable).init(allocator);
    defer data.deinit();
    try data.append(MaybeRelocatable.fromInt(u8, 1));
    try data.append(MaybeRelocatable.fromInt(u8, 2));
    try data.append(MaybeRelocatable.fromInt(u8, 3));
    try data.append(MaybeRelocatable.fromInt(u8, 4));

    // Load data into memory segment
    const actual = try vm.loadData(segment, &data);
    _ = actual;
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Prepare an empty expected instruction cache
    var expected_instruction_cache = ArrayList(?Instruction).init(allocator);
    defer expected_instruction_cache.deinit();

    // Assert the instruction cache after loading data
    try expectEqualSlices(
        ?Instruction,
        expected_instruction_cache.items,
        vm.instruction_cache.items,
    );
}

test "CairoVM: addRelocationRule should add new relocation rule to the VM memory" {

    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test checks
    try vm.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(1, 2),
    );
    try vm.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(-1, 1),
    );

    try expectError(
        MemoryError.AddressNotInTemporarySegment,
        vm.addRelocationRule(
            Relocatable.init(5, 0),
            .{},
        ),
    );
    try expectError(
        MemoryError.NonZeroOffset,
        vm.addRelocationRule(
            Relocatable.init(-3, 6),
            .{},
        ),
    );
    try expectError(
        MemoryError.DuplicatedRelocation,
        vm.addRelocationRule(
            Relocatable.init(-1, 0),
            .{},
        ),
    );
}

test "CairoVM: getPublicMemoryAddresses should return UnrelocatedMemory error if no relocation table in CairoVM" {
    // Test setup
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try expectError(
        MemoryError.UnrelocatedMemory,
        vm.getPublicMemoryAddresses(),
    );
}

test "CairoVM: getPublicMemoryAddresses should return Cairo VM Memory error if segment method returns an error" {
    // Test setup
    // Initialize the allocator for testing purposes.
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    // Initialize the relocation table in the VM instance.
    vm.relocation_table = std.ArrayList(usize).init(allocator);
    // Ensure proper deallocation of resources.
    defer vm.deinit();

    // Add five segments to the memory segment manager.
    for (0..5) |_| {
        _ = try vm.segments.addSegment();
    }

    // Initialize lists to hold public memory offsets.
    var public_memory_offsets = std.ArrayList(?std.ArrayList(std.meta.Tuple(&.{ usize, usize }))).init(allocator);
    // Ensure proper deallocation of resources.
    defer public_memory_offsets.deinit();

    // Initialize inner lists to store specific offsets for segments.
    var inner_list_1 = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    // Ensure proper deallocation of resources.
    defer inner_list_1.deinit();
    try inner_list_1.append(.{ 0, 0 });
    try inner_list_1.append(.{ 1, 1 });

    var inner_list_2 = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    // Ensure proper deallocation of resources.
    defer inner_list_2.deinit();
    // Inline to append specific offsets to the list.
    inline for (0..8) |i| {
        try inner_list_2.append(.{ i, 0 });
    }

    var inner_list_5 = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    // Ensure proper deallocation of resources.
    defer inner_list_5.deinit();
    try inner_list_5.append(.{ 1, 2 });

    // Append inner lists containing offsets to public_memory_offsets.
    try public_memory_offsets.append(inner_list_1);
    try public_memory_offsets.append(inner_list_2);
    try public_memory_offsets.append(null);
    try public_memory_offsets.append(null);
    try public_memory_offsets.append(inner_list_5);

    // Perform assertions and memory operations.
    // Add additional segments to the VM's segment manager.
    try expectEqual(
        vm.segments.addSegment(),
        Relocatable.init(5, 0),
    );
    try expectEqual(
        vm.segments.addSegment(),
        Relocatable.init(6, 0),
    );
    // Set memory within segments.
    try vm.segments.memory.set(
        allocator,
        Relocatable.init(5, 4),
        MaybeRelocatable.fromInt(u8, 0),
    );
    // Ensure proper deallocation of memory data.
    defer vm.segments.memory.deinitData(allocator);

    // Finalize segments with sizes and offsets.
    // Iterate through segment sizes and finalize segments.
    for ([_]u8{ 3, 8, 0, 1, 2 }, 0..) |size, i| {
        try vm.segments.finalize(
            i,
            size,
            public_memory_offsets.items[i],
        );
    }

    // Segment offsets less than the number of segments.
    // Append specific segment offsets to the relocation table.
    for ([_]usize{ 1, 4, 12, 13 }) |offset| {
        try vm.relocation_table.?.append(offset);
    }

    // Validate if the function throws the expected CairoVMError.Memory.
    try expectError(
        CairoVMError.Memory,
        vm.getPublicMemoryAddresses(),
    );
}

test "CairoVM: getPublicMemoryAddresses should return a proper ArrayList if success" {
    // Test setup
    // Initialize the allocator for testing purposes.
    const allocator = std.testing.allocator;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    // Initialize the relocation table in the VM instance.
    vm.relocation_table = std.ArrayList(usize).init(allocator);
    // Ensure proper deallocation of resources.
    defer vm.deinit();

    // Add five segments to the memory segment manager.
    for (0..5) |_| {
        _ = try vm.segments.addSegment();
    }

    // Initialize lists to hold public memory offsets.
    var public_memory_offsets = std.ArrayList(?std.ArrayList(std.meta.Tuple(&.{ usize, usize }))).init(allocator);
    // Ensure proper deallocation of resources.
    defer public_memory_offsets.deinit();

    // Initialize inner lists to store specific offsets for segments.
    var inner_list_1 = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    // Ensure proper deallocation of resources.
    defer inner_list_1.deinit();
    try inner_list_1.append(.{ 0, 0 });
    try inner_list_1.append(.{ 1, 1 });

    var inner_list_2 = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    // Ensure proper deallocation of resources.
    defer inner_list_2.deinit();
    // Inline to append specific offsets to the list.
    inline for (0..8) |i| {
        try inner_list_2.append(.{ i, 0 });
    }

    var inner_list_5 = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    // Ensure proper deallocation of resources.
    defer inner_list_5.deinit();
    try inner_list_5.append(.{ 1, 2 });

    // Append inner lists containing offsets to public_memory_offsets.
    try public_memory_offsets.append(inner_list_1);
    try public_memory_offsets.append(inner_list_2);
    try public_memory_offsets.append(null);
    try public_memory_offsets.append(null);
    try public_memory_offsets.append(inner_list_5);

    // Perform assertions and memory operations.
    // Add additional segments to the VM's segment manager.
    try expectEqual(
        vm.segments.addSegment(),
        Relocatable.init(5, 0),
    );
    try expectEqual(
        vm.segments.addSegment(),
        Relocatable.init(6, 0),
    );
    // Set memory within segments.
    try vm.segments.memory.set(
        allocator,
        Relocatable.init(5, 4),
        MaybeRelocatable.fromInt(u8, 0),
    );
    // Ensure proper deallocation of memory data.
    defer vm.segments.memory.deinitData(allocator);

    // Finalize segments with sizes and offsets.
    // Iterate through segment sizes and finalize segments.
    for ([_]u8{ 3, 8, 0, 1, 2 }, 0..) |size, i| {
        try vm.segments.finalize(
            i,
            size,
            public_memory_offsets.items[i],
        );
    }

    // Generate specific segment offsets for the relocation table.
    for ([_]usize{ 1, 4, 12, 12, 13, 15, 20 }) |offset| {
        try vm.relocation_table.?.append(offset);
    }

    // Get public memory addresses based on segment offsets.
    const public_memory_addresses = try vm.getPublicMemoryAddresses();
    // Ensure proper deallocation of retrieved addresses.
    defer public_memory_addresses.deinit();

    // Define the expected list of public memory addresses.
    const expected = [_]std.meta.Tuple(&.{ usize, usize }){
        .{ 1, 0 },
        .{ 2, 1 },
        .{ 4, 0 },
        .{ 5, 0 },
        .{ 6, 0 },
        .{ 7, 0 },
        .{ 8, 0 },
        .{ 9, 0 },
        .{ 10, 0 },
        .{ 11, 0 },
        .{ 14, 2 },
    };

    // Assert equality of expected and retrieved public memory addresses.
    try expectEqualSlices(
        std.meta.Tuple(&.{ usize, usize }),
        &expected,
        public_memory_addresses.items,
    );
}

test "CairoVM: getReturnValues should return a continuous range of memory values starting from a specified address." {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    vm.run_context.ap = 4;
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{1} },
            .{ .{ 1, 1 }, .{2} },
            .{ .{ 1, 2 }, .{3} },
            .{ .{ 1, 3 }, .{4} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer expected.deinit();

    try expected.append(MaybeRelocatable.fromInt(u8, 1));
    try expected.append(MaybeRelocatable.fromInt(u8, 2));
    try expected.append(MaybeRelocatable.fromInt(u8, 3));
    try expected.append(MaybeRelocatable.fromInt(u8, 4));

    var actual = try vm.getReturnValues(4);
    defer actual.deinit();

    try expectEqualSlices(MaybeRelocatable, expected.items, actual.items);
}

test "CairoVM: getReturnValues should return a memory error when Ap is 0" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{1} },
            .{ .{ 1, 1 }, .{2} },
            .{ .{ 1, 2 }, .{3} },
            .{ .{ 1, 3 }, .{4} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectError(MemoryError.FailedToGetReturnValues, vm.getReturnValues(3));
}

test "CairoVM: verifyAutoDeductionsForAddr bitwise" {
    const allocator = std.testing.allocator;

    var bitwise_builtin = BitwiseBuiltinRunner{};
    bitwise_builtin.base = 2;
    var builtin = BuiltinRunner{ .Bitwise = bitwise_builtin };

    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        allocator,
        .{
            .{ .{ 2, 0 }, .{12} },
            .{ .{ 2, 1 }, .{10} },
            .{ .{ 2, 2 }, .{8} },
        },
    );
    defer vm.segments.memory.deinitData(allocator);

    try expectEqual(void, @TypeOf(try vm.verifyAutoDeductionsForAddr(allocator, Relocatable.init(2, 0), &builtin)));
    try expectEqual(void, @TypeOf(try vm.verifyAutoDeductionsForAddr(allocator, Relocatable.init(2, 1), &builtin)));
    try expectEqual(void, @TypeOf(try vm.verifyAutoDeductionsForAddr(allocator, Relocatable.init(2, 2), &builtin)));
}

test "CairoVM: verifyAutoDeductionsForAddr throws InconsistentAutoDeduction" {
    const allocator = std.testing.allocator;

    var bitwise_builtin = BitwiseBuiltinRunner{};
    bitwise_builtin.base = 2;

    var builtin = BuiltinRunner{ .Bitwise = bitwise_builtin };

    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        allocator,
        .{
            .{ .{ 2, 0 }, .{12} },
            .{ .{ 2, 1 }, .{10} },
            .{ .{ 2, 2 }, .{7} },
        },
    );
    defer vm.segments.memory.deinitData(allocator);

    try expectError(CairoVMError.InconsistentAutoDeduction, vm.verifyAutoDeductionsForAddr(allocator, Relocatable.init(2, 2), &builtin));
}

test "CairoVM: decode current instruction" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{1488298941505110016} }, // 0x14A7800080008000
    });
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const result = try vm.decodeCurrentInstruction();
    try expectEqual(Instruction{}, result);
}

test "CairoVM: decode current instruction expected integer" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ "112233445566778899", 16 } },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectError(MemoryError.ExpectedInteger, vm.decodeCurrentInstruction());
}

test "CairoVM: decode current instruction invalid encoding" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{.{ .{ 0, 0 }, .{std.math.maxInt(u64) + 1} }});
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectError(CairoVMError.InvalidInstructionEncoding, vm.decodeCurrentInstruction());
}

test "CairoVM: verifyAutoDeductions for bitwise builtin runner" {
    const allocator = std.testing.allocator;

    var bitwise_builtin = BitwiseBuiltinRunner{};
    bitwise_builtin.base = 2;
    const builtin = BuiltinRunner{ .Bitwise = bitwise_builtin };

    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try vm.builtin_runners.append(builtin);

    try vm.segments.memory.setUpMemory(
        allocator,
        .{
            .{ .{ 2, 0 }, .{12} },
            .{ .{ 2, 1 }, .{10} },
            .{ .{ 2, 2 }, .{8} },
        },
    );
    defer vm.segments.memory.deinitData(allocator);

    const result = try vm.verifyAutoDeductions(allocator);
    try expectEqual(void, @TypeOf(result));
}

test "CairoVM: verifyAutoDeductions for bitwise builtin runner throws InconsistentAutoDeduction" {
    const allocator = std.testing.allocator;

    var bitwise_builtin = BitwiseBuiltinRunner{};
    bitwise_builtin.base = 2;
    const builtin = BuiltinRunner{ .Bitwise = bitwise_builtin };

    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try vm.builtin_runners.append(builtin);

    try vm.segments.memory.setUpMemory(
        allocator,
        .{
            .{ .{ 2, 0 }, .{12} },
            .{ .{ 2, 1 }, .{10} },
            .{ .{ 2, 2 }, .{7} },
        },
    );

    defer vm.segments.memory.deinitData(allocator);

    try expectError(CairoVMError.InconsistentAutoDeduction, vm.verifyAutoDeductions(allocator));
}

test "CairoVM: verifyAutoDeductions for keccak builtin runner" {
    const allocator = std.testing.allocator;

    var keccak_instance_def = try KeccakInstanceDef.initDefault(allocator);
    defer keccak_instance_def.deinit();

    const keccak_builtin = try KeccakBuiltinRunner.init(
        allocator,
        &keccak_instance_def,
        true,
    );

    const builtin = BuiltinRunner{ .Keccak = keccak_builtin };

    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        allocator,
        .{
            .{ .{ 0, 16 }, .{43} },
            .{ .{ 0, 17 }, .{199} },
            .{ .{ 0, 18 }, .{0} },
            .{ .{ 0, 19 }, .{0} },
            .{ .{ 0, 20 }, .{0} },
            .{ .{ 0, 21 }, .{0} },
            .{ .{ 0, 22 }, .{0} },
            .{ .{ 0, 23 }, .{1} },
            .{ .{ 0, 24 }, .{564514457304291355949254928395241013971879337011439882107889} },
            .{ .{ 0, 25 }, .{1006979841721999878391288827876533441431370448293338267890891} },
            .{ .{ 0, 26 }, .{811666116505725183408319428185457775191826596777361721216040} },
        },
    );
    defer vm.segments.memory.deinitData(allocator);

    try vm.builtin_runners.append(builtin);

    const result = try vm.verifyAutoDeductions(allocator);

    try expectEqual(void, @TypeOf(result));
}

test "CairoVM: runInstruction without any insertion in the memory" {
    // Program used:
    // %builtins output
    // from starkware.cairo.common.serialize import serialize_word
    // func main{output_ptr: felt*}():
    //    let a = 1
    //    serialize_word(a)
    //    let b = 17 * a
    //    serialize_word(b)
    //    return()
    // end
    // Relocated Trace:
    // [TraceEntry(pc=5, ap=18, fp=18),
    //  TraceEntry(pc=6, ap=19, fp=18),
    //  TraceEntry(pc=8, ap=20, fp=18),
    //  TraceEntry(pc=1, ap=22, fp=22),
    //  TraceEntry(pc=2, ap=22, fp=22),
    //  TraceEntry(pc=4, ap=23, fp=22),
    // TraceEntry(pc=10, ap=23, fp=18),

    // Initialize CairoVM instance and defer its cleanup.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Set up memory with predefined data for the VM.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{4612671182993129469} },
            .{ .{ 0, 1 }, .{5198983563776393216} },
            .{ .{ 0, 2 }, .{5198983563776393216} },
            .{ .{ 0, 3 }, .{2345108766317314046} },
            .{ .{ 0, 4 }, .{5191102247248822272} },
            .{ .{ 0, 5 }, .{5189976364521848832} },
            .{ .{ 0, 6 }, .{1} },
            .{ .{ 0, 7 }, .{1226245742482522112} },
            .{ .{ 0, 8 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020474} },
            .{ .{ 0, 9 }, .{5189976364521848832} },
            .{ .{ 0, 10 }, .{17} },
            .{ .{ 0, 11 }, .{1226245742482522112} },
            .{ .{ 0, 12 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020470} },
            .{ .{ 0, 13 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 1, 2 }, .{ 4, 0 } },
            .{ .{ 1, 3 }, .{ 2, 0 } },
            .{ .{ 1, 4 }, .{1} },
            .{ .{ 1, 5 }, .{ 1, 3 } },
            .{ .{ 1, 6 }, .{ 0, 9 } },
            .{ .{ 1, 7 }, .{ 2, 1 } },
            .{ .{ 1, 8 }, .{17} },
            .{ .{ 1, 9 }, .{ 1, 3 } },
            .{ .{ 1, 10 }, .{ 0, 13 } },
            .{ .{ 1, 11 }, .{ 2, 2 } },
            .{ .{ 2, 0 }, .{1} },
            .{ .{ 2, 1 }, .{17} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Mark all cells in memory as accessed except for one specific cell.
    for (vm.segments.memory.data.items) |*d| {
        for (d.items) |*cell| {
            cell.*.?.is_accessed = true;
        }
    }
    vm.segments.memory.data.items[1].items[1].?.is_accessed = false;

    // Add two memory segments to the VM.
    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    // Set relocation limits and initial register values.
    vm.rc_limits = .{ 32764, 32769 };
    vm.run_context.pc = Relocatable.init(0, 13);
    vm.run_context.ap = 12;
    vm.run_context.fp = 3;

    // Ensure that the specific cell marked as not accessed is indeed not accessed.
    try expect(!vm.segments.memory.data.items[1].items[1].?.is_accessed);

    // Ensure the current step counter is initialized to zero.
    try expectEqual(@as(usize, 0), vm.current_step);

    // Execute a specific instruction with predefined properties.
    try vm.runInstruction(
        std.testing.allocator,
        &.{
            .off_0 = -2,
            .off_1 = -1,
            .off_2 = -1,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .FP,
            .res_logic = .Op1,
            .pc_update = .Jump,
            .ap_update = .Regular,
            .fp_update = .Dst,
            .opcode = .Ret,
        },
    );

    // Ensure that relocation limits are correctly updated.
    try expectEqual(
        @as(?struct { isize, isize }, .{ 32764, 32769 }),
        vm.rc_limits,
    );

    // Ensure that registers are updated as expected after the instruction execution.
    try expectEqual(Relocatable.init(4, 0), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 12),
        vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        vm.run_context.getFP(),
    );

    // Ensure the current step counter is incremented.
    try expectEqual(@as(usize, 1), vm.current_step);

    // Initialize an expected memory instance with the same data as the VM's memory.
    var expected_memory = try Memory.init(std.testing.allocator);
    defer expected_memory.deinit();

    // Set a value into the memory.
    try expected_memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{4612671182993129469} },
            .{ .{ 0, 1 }, .{5198983563776393216} },
            .{ .{ 0, 2 }, .{5198983563776393216} },
            .{ .{ 0, 3 }, .{2345108766317314046} },
            .{ .{ 0, 4 }, .{5191102247248822272} },
            .{ .{ 0, 5 }, .{5189976364521848832} },
            .{ .{ 0, 6 }, .{1} },
            .{ .{ 0, 7 }, .{1226245742482522112} },
            .{ .{ 0, 8 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020474} },
            .{ .{ 0, 9 }, .{5189976364521848832} },
            .{ .{ 0, 10 }, .{17} },
            .{ .{ 0, 11 }, .{1226245742482522112} },
            .{ .{ 0, 12 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020470} },
            .{ .{ 0, 13 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 1, 2 }, .{ 4, 0 } },
            .{ .{ 1, 3 }, .{ 2, 0 } },
            .{ .{ 1, 4 }, .{1} },
            .{ .{ 1, 5 }, .{ 1, 3 } },
            .{ .{ 1, 6 }, .{ 0, 9 } },
            .{ .{ 1, 7 }, .{ 2, 1 } },
            .{ .{ 1, 8 }, .{17} },
            .{ .{ 1, 9 }, .{ 1, 3 } },
            .{ .{ 1, 10 }, .{ 0, 13 } },
            .{ .{ 1, 11 }, .{ 2, 2 } },
            .{ .{ 2, 0 }, .{1} },
            .{ .{ 2, 1 }, .{17} },
        },
    );
    defer expected_memory.deinitData(std.testing.allocator);

    // Mark all cells in the expected memory as accessed.
    for (expected_memory.data.items) |*d| {
        for (d.items) |*cell| {
            cell.*.?.is_accessed = true;
        }
    }

    // Compare each cell in VM's memory with the corresponding cell in the expected memory.
    for (vm.segments.memory.data.items, 0..) |d, i| {
        for (d.items, 0..) |cell, j| {
            try expect(cell.?.eql(expected_memory.data.items[i].items[j].?));
        }
    }
}

test "CairoVM: runInstruction with Op0 being deduced" {
    // Program used:
    // %builtins output
    // from starkware.cairo.common.serialize import serialize_word
    // func main{output_ptr: felt*}():
    //    let a = 1
    //    serialize_word(a)
    //    let b = 17 * a
    //    serialize_word(b)
    //    return()
    // end
    // Relocated Trace:
    // [TraceEntry(pc=5, ap=18, fp=18),
    //  TraceEntry(pc=6, ap=19, fp=18),
    //  TraceEntry(pc=8, ap=20, fp=18),
    //  TraceEntry(pc=1, ap=22, fp=22),
    //  TraceEntry(pc=2, ap=22, fp=22),
    //  TraceEntry(pc=4, ap=23, fp=22),
    // TraceEntry(pc=10, ap=23, fp=18),

    // Initialize CairoVM instance and defer its cleanup.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Set up memory with predefined data for the VM.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{4612671182993129469} },
            .{ .{ 0, 1 }, .{5198983563776393216} },
            .{ .{ 0, 2 }, .{1} },
            .{ .{ 0, 3 }, .{2345108766317314046} },
            .{ .{ 0, 4 }, .{5191102247248822272} },
            .{ .{ 0, 5 }, .{5189976364521848832} },
            .{ .{ 0, 6 }, .{1} },
            .{ .{ 0, 7 }, .{1226245742482522112} },
            .{ .{ 0, 8 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020474} },
            .{ .{ 0, 9 }, .{5189976364521848832} },
            .{ .{ 0, 10 }, .{17} },
            .{ .{ 0, 11 }, .{1226245742482522112} },
            .{ .{ 0, 12 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020470} },
            .{ .{ 0, 13 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 1, 2 }, .{ 4, 0 } },
            .{ .{ 1, 3 }, .{ 2, 0 } },
            .{ .{ 1, 4 }, .{1} },
            .{ .{ 1, 5 }, .{ 1, 3 } },
            .{ .{ 1, 6 }, .{ 0, 9 } },
            .{ .{ 1, 7 }, .{ 2, 1 } },
            .{ .{ 1, 8 }, .{17} },
            .{ .{ 2, 0 }, .{1} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Mark all cells in memory as accessed except for one specific cell.
    for (vm.segments.memory.data.items) |*d| {
        for (d.items) |*cell| {
            cell.*.?.is_accessed = true;
        }
    }
    // Mark a specific cell as not accessed.
    vm.segments.memory.data.items[1].items[1].?.is_accessed = false;

    // Add two memory segments to the VM.
    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    // Set relocation limits and initial register values.
    vm.rc_limits = .{ 32764, 32769 };
    vm.run_context.pc = Relocatable.init(0, 11);
    vm.run_context.ap = 9;
    vm.run_context.fp = 3;

    // Ensure that the specific cell marked as not accessed is indeed not accessed.
    try expect(!vm.segments.memory.data.items[1].items[1].?.is_accessed);

    // Ensure the current step counter is initialized to zero.
    try expectEqual(@as(usize, 0), vm.current_step);

    // Execute a specific instruction with Op0 being deduced.
    try vm.runInstruction(
        std.testing.allocator,
        &.{
            .off_0 = 0,
            .off_1 = 1,
            .off_2 = 1,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .Imm,
            .res_logic = .Op1,
            .pc_update = .JumpRel,
            .ap_update = .Add2,
            .fp_update = .APPlus2,
            .opcode = .Call,
        },
    );

    // Ensure that relocation limits are correctly updated.
    try expectEqual(
        @as(?struct { isize, isize }, .{ 32764, 32769 }),
        vm.rc_limits,
    );

    // Ensure that registers are updated as expected after the instruction execution.
    try expectEqual(Relocatable{}, vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 11),
        vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 11),
        vm.run_context.getFP(),
    );

    // Ensure the current step counter is incremented.
    try expectEqual(@as(usize, 1), vm.current_step);

    // Initialize an expected memory instance.
    var expected_memory = try Memory.init(std.testing.allocator);
    defer expected_memory.deinit();

    // Set a value into the memory.
    try expected_memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{4612671182993129469} },
            .{ .{ 0, 1 }, .{5198983563776393216} },
            .{ .{ 0, 2 }, .{1} },
            .{ .{ 0, 3 }, .{2345108766317314046} },
            .{ .{ 0, 4 }, .{5191102247248822272} },
            .{ .{ 0, 5 }, .{5189976364521848832} },
            .{ .{ 0, 6 }, .{1} },
            .{ .{ 0, 7 }, .{1226245742482522112} },
            .{ .{ 0, 8 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020474} },
            .{ .{ 0, 9 }, .{5189976364521848832} },
            .{ .{ 0, 10 }, .{17} },
            .{ .{ 0, 11 }, .{1226245742482522112} },
            .{ .{ 0, 12 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020470} },
            .{ .{ 0, 13 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 1, 2 }, .{ 4, 0 } },
            .{ .{ 1, 3 }, .{ 2, 0 } },
            .{ .{ 1, 4 }, .{1} },
            .{ .{ 1, 5 }, .{ 1, 3 } },
            .{ .{ 1, 6 }, .{ 0, 9 } },
            .{ .{ 1, 7 }, .{ 2, 1 } },
            .{ .{ 1, 8 }, .{17} },
            .{ .{ 1, 9 }, .{ 1, 3 } },
            .{ .{ 1, 10 }, .{ 0, 13 } },
            .{ .{ 2, 0 }, .{1} },
        },
    );
    defer expected_memory.deinitData(std.testing.allocator);

    // Mark all cells in the expected memory as accessed.
    for (expected_memory.data.items) |*d| {
        for (d.items) |*cell| {
            cell.*.?.is_accessed = true;
        }
    }
    // Mark a specific cell in the expected memory as not accessed.
    expected_memory.data.items[1].items[1].?.is_accessed = false;

    // Compare each cell in VM's memory with the corresponding cell in the expected memory.
    for (vm.segments.memory.data.items, 0..) |d, i| {
        for (d.items, 0..) |cell, j| {
            try expect(cell.?.eql(expected_memory.data.items[i].items[j].?));
        }
    }
}

test "CairoVM: test step for preset memory 1" {
    //Test for a simple program execution
    //Used program code:
    //    func myfunc(a: felt) -> (r: felt):
    //        let b = a * 2
    //        return(b)
    //    end
    //    func main():
    //        let a = 1
    //        let b = myfunc(a)
    //        return()
    //    end
    //Memory taken from original vm:
    //{RelocatableValue(segment_index=0, offset=0): 5207990763031199744,
    //RelocatableValue(segment_index=0, offset=1): 2,
    //RelocatableValue(segment_index=0, offset=2): 2345108766317314046,
    //RelocatableValue(segment_index=0, offset=3): 5189976364521848832,
    //RelocatableValue(segment_index=0, offset=4): 1,
    //RelocatableValue(segment_index=0, offset=5): 1226245742482522112,
    //RelocatableValue(segment_index=0, offset=6): 3618502788666131213697322783095070105623107215331596699973092056135872020476,
    //RelocatableValue(segment_index=0, offset=7): 2345108766317314046,
    //RelocatableValue(segment_index=1, offset=0): RelocatableValue(segment_index=2, offset=0),
    //RelocatableValue(segment_index=1, offset=1): RelocatableValue(segment_index=3, offset=0)}
    //Current register values:
    //AP 1:2
    //FP 1:2
    //PC 0:3
    //Final Pc (not executed): 3:0
    //This program consists of 5 steps

    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );
    defer vm.deinit();

    vm.run_context.pc = Relocatable.init(0, 3);
    vm.run_context.ap = 2;
    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{5207990763031199744} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{2345108766317314046} },
            .{ .{ 0, 3 }, .{5189976364521848832} },
            .{ .{ 0, 4 }, .{1} },
            .{ .{ 0, 5 }, .{1226245742482522112} },
            .{ .{ 0, 6 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020476} },
            .{ .{ 0, 7 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const final_pc = Relocatable.init(3, 0);

    while (!vm.run_context.pc.eq(final_pc)) {
        var exec_scopes = try ExecutionScopes.init(allocator);
        defer exec_scopes.deinit();

        var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
        defer hint_datas.deinit();

        var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
        defer hint_ranges.deinit();

        var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
        defer constants.deinit();

        try vm.stepExtensive(
            std.testing.allocator,
            .{},
            &exec_scopes,
            &hint_datas,
            &hint_ranges,
            &constants,
        );
    }

    try expectEqual(Relocatable.init(3, 0), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 6),
        vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(0, 3),
                .ap = Relocatable.init(1, 2),
                .fp = Relocatable.init(1, 2),
            },
            .{
                .pc = Relocatable.init(0, 5),
                .ap = Relocatable.init(1, 3),
                .fp = Relocatable.init(1, 2),
            },
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 5),
                .fp = Relocatable.init(1, 5),
            },
            .{
                .pc = Relocatable.init(0, 2),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 5),
            },
            .{
                .pc = Relocatable.init(0, 7),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 2),
            },
        },
        vm.trace.?.items,
    );

    // Check that the following addresses have been accessed
    try expect(vm.segments.memory.data.items[0].items[1].?.is_accessed);
    try expect(vm.segments.memory.data.items[0].items[4].?.is_accessed);
    try expect(vm.segments.memory.data.items[0].items[6].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[0].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[2].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[3].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[4].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[5].?.is_accessed);

    try expectEqual(
        @as(usize, 3),
        vm.segments.memory.countAccessedAddressesInSegment(0),
    );
    try expectEqual(
        @as(usize, 6),
        vm.segments.memory.countAccessedAddressesInSegment(1),
    );
}

test "CairoVM: test step for preset memory program loaded into user segment" {
    // Test for a simple program execution
    // Used program code:
    // func main():
    //     let a = 1
    //     let b = 2
    //     let c = a + b
    //     return()
    // end
    // Memory taken from original vm
    // {RelocatableValue(segment_index=0, offset=0): 2345108766317314046,
    //  RelocatableValue(segment_index=1, offset=0): RelocatableValue(segment_index=2, offset=0),
    //  RelocatableValue(segment_index=1, offset=1): RelocatableValue(segment_index=3, offset=0)}
    // Current register values:
    // AP 1:2
    // FP 1:2
    // PC 0:0

    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );
    defer vm.deinit();

    vm.run_context.ap = 2;
    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 2, 0 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.pc.segment_index = 2;

    var exec_scopes = try ExecutionScopes.init(allocator);
    defer exec_scopes.deinit();

    var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
    defer hint_datas.deinit();

    var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
    defer hint_ranges.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try vm.stepExtensive(
        std.testing.allocator,
        .{},
        &exec_scopes,
        &hint_datas,
        &hint_ranges,
        &constants,
    );

    try expectEqual(Relocatable.init(3, 0), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 2),
        vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(2, 0),
                .ap = Relocatable.init(1, 2),
                .fp = Relocatable.init(1, 2),
            },
        },
        vm.trace.?.items,
    );

    // Check that the following addresses have been accessed
    try expect(vm.segments.memory.data.items[1].items[0].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[1].?.is_accessed);
}

test "CairoVM: test step for preset memory program loaded into user segment 1" {
    //Test for a simple program execution
    //Used program code:
    //    func myfunc(a: felt) -> (r: felt):
    //        let b = a * 2
    //        return(b)
    //    end
    //    func main():
    //        let a = 1
    //        let b = myfunc(a)
    //        return()
    //    end
    //Memory taken from original vm:
    //{RelocatableValue(segment_index=0, offset=0): 5207990763031199744,
    //RelocatableValue(segment_index=0, offset=1): 2,
    //RelocatableValue(segment_index=0, offset=2): 2345108766317314046,
    //RelocatableValue(segment_index=0, offset=3): 5189976364521848832,
    //RelocatableValue(segment_index=0, offset=4): 1,
    //RelocatableValue(segment_index=0, offset=5): 1226245742482522112,
    //RelocatableValue(segment_index=0, offset=6): 3618502788666131213697322783095070105623107215331596699973092056135872020476,
    //RelocatableValue(segment_index=0, offset=7): 2345108766317314046,
    //RelocatableValue(segment_index=1, offset=0): RelocatableValue(segment_index=2, offset=0),
    //RelocatableValue(segment_index=1, offset=1): RelocatableValue(segment_index=3, offset=0)}
    //Current register values:
    //AP 1:2
    //FP 1:2
    //PC 0:3
    //Final Pc (not executed): 3:0
    //This program consists of 5 steps

    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );
    defer vm.deinit();

    vm.run_context.pc = Relocatable.init(0, 3);
    vm.run_context.ap = 2;
    vm.run_context.fp = 2;

    vm.run_context.pc.segment_index = 4;

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 4, 0 }, .{5207990763031199744} },
            .{ .{ 4, 1 }, .{2} },
            .{ .{ 4, 2 }, .{2345108766317314046} },
            .{ .{ 4, 3 }, .{5189976364521848832} },
            .{ .{ 4, 4 }, .{1} },
            .{ .{ 4, 5 }, .{1226245742482522112} },
            .{ .{ 4, 6 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020476} },
            .{ .{ 4, 7 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const final_pc = Relocatable.init(3, 0);

    while (!vm.run_context.pc.eq(final_pc)) {
        var exec_scopes = try ExecutionScopes.init(allocator);
        defer exec_scopes.deinit();

        var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
        defer hint_datas.deinit();

        var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
        defer hint_ranges.deinit();

        var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
        defer constants.deinit();

        try vm.stepExtensive(
            std.testing.allocator,
            .{},
            &exec_scopes,
            &hint_datas,
            &hint_ranges,
            &constants,
        );
    }

    try expectEqual(Relocatable.init(3, 0), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 6),
        vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(4, 3),
                .ap = Relocatable.init(1, 2),
                .fp = Relocatable.init(1, 2),
            },
            .{
                .pc = Relocatable.init(4, 5),
                .ap = Relocatable.init(1, 3),
                .fp = Relocatable.init(1, 2),
            },
            .{
                .pc = Relocatable.init(4, 0),
                .ap = Relocatable.init(1, 5),
                .fp = Relocatable.init(1, 5),
            },
            .{
                .pc = Relocatable.init(4, 2),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 5),
            },
            .{
                .pc = Relocatable.init(4, 7),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 2),
            },
        },
        vm.trace.?.items,
    );

    // Check that the following addresses have been accessed
    try expect(vm.segments.memory.data.items[4].items[1].?.is_accessed);
    try expect(vm.segments.memory.data.items[4].items[4].?.is_accessed);
    try expect(vm.segments.memory.data.items[4].items[6].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[0].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[2].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[3].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[4].?.is_accessed);
    try expect(vm.segments.memory.data.items[1].items[5].?.is_accessed);

    try expectEqual(
        @as(usize, 3),
        vm.segments.memory.countAccessedAddressesInSegment(4),
    );
    try expectEqual(
        @as(usize, 6),
        vm.segments.memory.countAccessedAddressesInSegment(1),
    );
}

test "CairoVM: multiplication and different ap increase" {
    // Test the following program:
    // ...
    // [ap] = 4
    // ap += 1
    // [ap] = 5; ap++
    // [ap] = [ap - 1] * [ap - 2]
    // ...
    // Original vm memory:
    // RelocatableValue(segment_index=0, offset=0): '0x400680017fff8000',
    // RelocatableValue(segment_index=0, offset=1): '0x4',
    // RelocatableValue(segment_index=0, offset=2): '0x40780017fff7fff',
    // RelocatableValue(segment_index=0, offset=3): '0x1',
    // RelocatableValue(segment_index=0, offset=4): '0x480680017fff8000',
    // RelocatableValue(segment_index=0, offset=5): '0x5',
    // RelocatableValue(segment_index=0, offset=6): '0x40507ffe7fff8000',
    // RelocatableValue(segment_index=0, offset=7): '0x208b7fff7fff7ffe',
    // RelocatableValue(segment_index=1, offset=0): RelocatableValue(segment_index=2, offset=0),
    // RelocatableValue(segment_index=1, offset=1): RelocatableValue(segment_index=3, offset=0),
    // RelocatableValue(segment_index=1, offset=2): '0x4',
    // RelocatableValue(segment_index=1, offset=3): '0x5',
    // RelocatableValue(segment_index=1, offset=4): '0x14'

    // Test setup
    const allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(
        allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );
    defer vm.deinit();

    vm.run_context.ap = 2;
    vm.run_context.fp = 2;

    try expectEqual(Relocatable.init(0, 0), vm.run_context.pc);
    try expectEqual(Relocatable.init(1, 2), vm.run_context.getAP());

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0x400680017fff8000} },
            .{ .{ 0, 1 }, .{0x4} },
            .{ .{ 0, 2 }, .{0x40780017fff7fff} },
            .{ .{ 0, 3 }, .{0x1} },
            .{ .{ 0, 4 }, .{0x480680017fff8000} },
            .{ .{ 0, 5 }, .{0x5} },
            .{ .{ 0, 6 }, .{0x40507ffe7fff8000} },
            .{ .{ 0, 7 }, .{0x208b7fff7fff7ffe} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 1, 2 }, .{0x4} },
            .{ .{ 1, 3 }, .{0x5} },
            .{ .{ 1, 4 }, .{0x14} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x4),
        vm.segments.memory.get(vm.run_context.getAP()).?,
    );

    var exec_scopes = try ExecutionScopes.init(allocator);
    defer exec_scopes.deinit();

    var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
    defer hint_datas.deinit();

    var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
    defer hint_ranges.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try vm.stepExtensive(
        std.testing.allocator,
        .{},
        &exec_scopes,
        &hint_datas,
        &hint_ranges,
        &constants,
    );

    try expectEqual(Relocatable.init(0, 2), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 2),
        vm.run_context.getAP(),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x4),
        vm.segments.memory.get(vm.run_context.getAP()).?,
    );

    try vm.stepExtensive(
        std.testing.allocator,
        .{},
        &exec_scopes,
        &hint_datas,
        &hint_ranges,
        &constants,
    );

    try expectEqual(Relocatable.init(0, 4), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 3),
        vm.run_context.getAP(),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x5),
        vm.segments.memory.get(vm.run_context.getAP()).?,
    );

    try vm.stepExtensive(
        std.testing.allocator,
        .{},
        &exec_scopes,
        &hint_datas,
        &hint_ranges,
        &constants,
    );

    try expectEqual(Relocatable.init(0, 6), vm.run_context.pc);
    try expectEqual(
        Relocatable.init(1, 4),
        vm.run_context.getAP(),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x14),
        vm.segments.memory.get(vm.run_context.getAP()).?,
    );
}

test "CairoVM: endRun with a no scope error" {

    // Create a new VM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Deallocate the VM resources after the test.
    defer vm.deinit();

    // Initialize execution scopes using the testing allocator.
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    // Deallocate the execution scopes after the test.
    defer exec_scopes.deinit();

    // Initialize a new scope using the testing allocator.
    var new_scope = std.StringHashMap(HintType).init(std.testing.allocator);
    // Deallocate the new scope after the test.
    defer new_scope.deinit();

    // Enter the newly created scope.
    try exec_scopes.enterScope(new_scope);

    // Expect an error of type NoScopeError.
    try expectError(
        ExecScopeError.NoScopeError,
        vm.endRun(std.testing.allocator, &exec_scopes),
    );
}

test "Core: test step for preset memory alloc hint not extensive" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{
            .enable_trace = true,
        },
    );
    defer vm.deinit();

    vm.run_context.pc = Relocatable.init(0, 3);
    vm.run_context.ap = 2;
    vm.run_context.fp = 2;
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{290341444919459839} },
        .{ .{ 0, 1 }, .{1} },
        .{ .{ 0, 2 }, .{2345108766317314046} },
        .{ .{ 0, 3 }, .{1226245742482522112} },
        .{ .{ 0, 4 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020478} },
        .{ .{ 0, 5 }, .{5189976364521848832} },
        .{ .{ 0, 6 }, .{1} },
        .{ .{ 0, 7 }, .{4611826758063128575} },
        .{ .{ 0, 8 }, .{2345108766317314046} },
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{ 3, 0 } },
    });
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const hint_processor: HintProcessor = .{};
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
    defer hint_datas.deinit();

    try hint_datas.append(
        HintData.init("memory[ap] = segments.add()", ids_data, .{}),
    );

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    inline for (0..6) |_| {
        const hint_data = if (vm.run_context.pc.eq(Relocatable.init(0, 0))) hint_datas.items[0..] else hint_datas.items[0..0];

        try vm.stepNotExtensive(std.testing.allocator, hint_processor, &exec_scopes, hint_data, &constants);
    }

    const expected_trace = [_][3][2]u64{
        .{ .{ 0, 3 }, .{ 1, 2 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 1, 4 }, .{ 1, 4 } },
        .{ .{ 0, 2 }, .{ 1, 5 }, .{ 1, 4 } },
        .{ .{ 0, 5 }, .{ 1, 5 }, .{ 1, 2 } },
        .{ .{ 0, 7 }, .{ 1, 6 }, .{ 1, 2 } },
        .{ .{ 0, 8 }, .{ 1, 6 }, .{ 1, 2 } },
    };

    try std.testing.expectEqual(expected_trace.len, vm.trace.?.items.len);

    for (expected_trace, 0..) |trace_entry, idx| {
        // pc, ap, fp
        const trace_entry_a = vm.trace.?.items[idx];
        try std.testing.expectEqual(Relocatable.init(@intCast(trace_entry[0][0]), trace_entry[0][1]), trace_entry_a.pc);
        try std.testing.expectEqual(Relocatable.init(@intCast(trace_entry[1][0]), trace_entry[1][1]), trace_entry_a.ap);
        try std.testing.expectEqual(Relocatable.init(@intCast(trace_entry[2][0]), trace_entry[2][1]), trace_entry_a.fp);
    }
}

test "Core: test step for preset memory alloc hint extensive" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{
            .enable_trace = true,
        },
    );
    defer vm.deinit();

    vm.run_context.pc = Relocatable.init(0, 3);
    vm.run_context.ap = 2;
    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{290341444919459839} },
        .{ .{ 0, 1 }, .{1} },
        .{ .{ 0, 2 }, .{2345108766317314046} },
        .{ .{ 0, 3 }, .{1226245742482522112} },
        .{ .{ 0, 4 }, .{3618502788666131213697322783095070105623107215331596699973092056135872020478} },
        .{ .{ 0, 5 }, .{5189976364521848832} },
        .{ .{ 0, 6 }, .{1} },
        .{ .{ 0, 7 }, .{4611826758063128575} },
        .{ .{ 0, 8 }, .{2345108766317314046} },
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{ 3, 0 } },
    });
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const hint_processor: HintProcessor = .{};
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    var hint_datas = std.ArrayList(HintData).init(std.testing.allocator);
    defer hint_datas.deinit();

    try hint_datas.append(
        HintData.init("memory[ap] = segments.add()", ids_data, .{}),
    );

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    inline for (0..6) |_| {
        var hint_ranges = std.AutoHashMap(Relocatable, HintRange).init(std.testing.allocator);
        defer hint_ranges.deinit();

        try hint_ranges.put(Relocatable.init(0, 0), .{
            .start = 0,
            .length = 1,
        });

        try vm.stepExtensive(std.testing.allocator, hint_processor, &exec_scopes, &hint_datas, &hint_ranges, &constants);
    }

    const expected_trace = [_][3][2]u64{
        .{ .{ 0, 3 }, .{ 1, 2 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 1, 4 }, .{ 1, 4 } },
        .{ .{ 0, 2 }, .{ 1, 5 }, .{ 1, 4 } },
        .{ .{ 0, 5 }, .{ 1, 5 }, .{ 1, 2 } },
        .{ .{ 0, 7 }, .{ 1, 6 }, .{ 1, 2 } },
        .{ .{ 0, 8 }, .{ 1, 6 }, .{ 1, 2 } },
    };

    try std.testing.expectEqual(expected_trace.len, vm.trace.?.items.len);

    for (expected_trace, 0..) |trace_entry, idx| {
        // pc, ap, fp
        const trace_entry_a = vm.trace.?.items[idx];
        try std.testing.expectEqual(Relocatable.init(@intCast(trace_entry[0][0]), trace_entry[0][1]), trace_entry_a.pc);
        try std.testing.expectEqual(Relocatable.init(@intCast(trace_entry[1][0]), trace_entry[1][1]), trace_entry_a.ap);
        try std.testing.expectEqual(Relocatable.init(@intCast(trace_entry[2][0]), trace_entry[2][1]), trace_entry_a.fp);
    }
}
