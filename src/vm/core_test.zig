// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const starknet_felt = @import("../math/fields/starknet.zig");

// Local imports.
const segments = @import("memory/segments.zig");
const relocatable = @import("memory/relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const instructions = @import("instructions.zig");
const RunContext = @import("run_context.zig").RunContext;
const CairoVMError = @import("error.zig").CairoVMError;
const Config = @import("config.zig").Config;
const TraceContext = @import("trace_context.zig").TraceContext;
const build_options = @import("../build_options.zig");
const BuiltinRunner = @import("./builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const builtin = @import("./builtins/bitwise/bitwise.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HashBuiltinRunner = @import("./builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const Instruction = @import("instructions.zig").Instruction;
const CairoVM = @import("core.zig").CairoVM;
const computeRes = @import("core.zig").computeRes;
const OperandsResult = @import("core.zig").OperandsResult;
const deduceOp1 = @import("core.zig").deduceOp1;

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "CairoVM: deduceMemoryCell no builtin" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try expectEqual(
        @as(?MaybeRelocatable, null),
        try vm.deduceMemoryCell(Relocatable.new(
            0,
            0,
        )),
    );
}

test "CairoVM: deduceMemoryCell builtin valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try vm.builtin_runners.append(BuiltinRunner{ .Hash = HashBuiltinRunner.new(
        std.testing.allocator,
        8,
        true,
    ) });
    try vm.segments.memory.set(
        Relocatable.new(
            0,
            5,
        ),
        relocatable.fromFelt(Felt252.fromInteger(10)),
    );
    try vm.segments.memory.set(
        Relocatable.new(
            0,
            6,
        ),
        relocatable.fromFelt(Felt252.fromInteger(12)),
    );
    try vm.segments.memory.set(
        Relocatable.new(
            0,
            7,
        ),
        relocatable.fromFelt(Felt252.fromInteger(0)),
    );
    try expectEqual(
        MaybeRelocatable{ .felt = Felt252.fromInteger(8) },
        (try vm.deduceMemoryCell(Relocatable.new(
            0,
            7,
        ))).?,
    );
}

test "update pc regular no imm" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Regular;
    instruction.op_1_addr = instructions.Op1Src.AP;
    const operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        @as(
            u64,
            1,
        ),
        pc.offset,
    );
}

test "update pc regular with imm" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Regular;
    instruction.op_1_addr = instructions.Op1Src.Imm;
    const operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        @as(
            u64,
            2,
        ),
        pc.offset,
    );
}

test "update pc jump with operands res null" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jump;
    var operands = OperandsResult.default();
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.ResUnconstrainedUsedWithPcUpdateJump, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump with operands res not relocatable" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jump;
    var operands = OperandsResult.default();
    operands.res = relocatable.fromU64(0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.PcUpdateJumpResNotRelocatable, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump with operands res relocatable" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jump;
    var operands = OperandsResult.default();
    operands.res = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        @as(
            u64,
            42,
        ),
        pc.offset,
    );
}

test "update pc jump rel with operands res null" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.JumpRel;
    var operands = OperandsResult.default();
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.ResUnconstrainedUsedWithPcUpdateJumpRel, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump rel with operands res not felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.JumpRel;
    var operands = OperandsResult.default();
    operands.res = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.PcUpdateJumpRelResNotFelt, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump rel with operands res felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.JumpRel;
    var operands = OperandsResult.default();
    operands.res = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        @as(
            u64,
            42,
        ),
        pc.offset,
    );
}

test "update pc update jnz with operands dst zero" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        @as(
            u64,
            2,
        ),
        pc.offset,
    );
}

test "update pc update jnz with operands dst not zero op1 not felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(1);
    operands.op_1 = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(
        error.TypeMismatchNotFelt,
        vm.updatePc(
            &instruction,
            operands,
        ),
    );
}

test "update pc update jnz with operands dst not zero op1 felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(1);
    operands.op_1 = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        @as(
            u64,
            42,
        ),
        pc.offset,
    );
}

test "update ap add with operands res unconstrained" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = instructions.ApUpdate.Add;
    var operands = OperandsResult.default();
    operands.res = null; // Simulate unconstrained res
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.ApUpdateAddResUnconstrained, vm.updateAp(
        &instruction,
        operands,
    ));
}

test "update ap add1" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = instructions.ApUpdate.Add1;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateAp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the AP offset was incremented by 1.
    const ap = vm.getAp();
    try expectEqual(
        @as(
            u64,
            1,
        ),
        ap.offset,
    );
}

test "update ap add2" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = instructions.ApUpdate.Add2;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateAp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the AP offset was incremented by 2.
    const ap = vm.getAp();
    try expectEqual(
        @as(
            u64,
            2,
        ),
        ap.offset,
    );
}

test "update fp appplus2" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = instructions.FpUpdate.APPlus2;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateFp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the FP offset was incremented by 2.
    const fp = vm.getFp();
    try expectEqual(
        @as(
            u64,
            2,
        ),
        fp.offset,
    );
}

test "update fp dst relocatable" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = instructions.FpUpdate.Dst;
    var operands = OperandsResult.default();
    operands.dst = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateFp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the FP offset was incremented by 2.
    const fp = vm.getFp();
    try expectEqual(
        @as(
            u64,
            42,
        ),
        fp.offset,
    );
}

test "update fp dst felt" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = instructions.FpUpdate.Dst;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateFp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the FP offset was incremented by 2.
    const fp = vm.getFp();
    try expectEqual(
        @as(
            u64,
            42,
        ),
        fp.offset,
    );
}

test "trace is enabled" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var config = Config{ .proof_mode = false, .enable_trace = true };

    var vm = try CairoVM.init(
        allocator,
        config,
    );
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    // Do nothing

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Check that trace was initialized
    if (!vm.trace_context.isEnabled()) {
        return error.TraceShouldHaveBeenEnabled;
    }
}

test "trace is disabled" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    // Do nothing

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Check that trace was initialized
    if (vm.trace_context.isEnabled()) {
        return error.TraceShouldHaveBeenDisabled;
    }
}

// This instruction is used in the functions that test the `deduceOp1` function. Only the
// `opcode` and `res_logic` fields are usually changed.
const deduceOpTestInstr = instructions.Instruction{
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
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    const tuple = try vm.deduceOp0(&instr, null, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_0: ?MaybeRelocatable = relocatable.newFromRelocatable(relocatable.Relocatable.new(0, 1)); // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op1);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Add, input is felt" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const dst = relocatable.fromU64(3);
    const op1 = relocatable.fromU64(2);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expect(op0.?.eq(relocatable.fromU64(1)));
    try expect(res.?.eq(relocatable.fromU64(3)));
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Add, with no input" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const tuple = try vm.deduceOp0(&instr, null, null);
    const op0 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Mul, input is felt 1" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(2);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_0: ?MaybeRelocatable = relocatable.fromU64(2); // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = relocatable.fromU64(4);
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Op1, input is felt" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(0);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Mul, input is felt 2" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(0);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .Ret, res_logic == .Mul, input is felt" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .Ret;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(0);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp1 when opcode == .Call" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing.

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    const tuple = try deduceOp1(&instr, null, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(
        expected_op_1,
        op1,
    );
    try expectEqual(
        expected_res,
        res,
    );
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Add, input is felt" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing.

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const dst = relocatable.fromU64(3);
    const op0 = relocatable.fromU64(2);

    const tuple = try deduceOp1(&instr, &dst, &op0);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expect(op1.?.eq(relocatable.fromU64(1)));
    try expect(res.?.eq(relocatable.fromU64(3)));
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Mul, non-zero op0" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing.

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op0 = relocatable.fromU64(2);

    const op1_and_result = try deduceOp1(&instr, &dst, &op0);
    const op1 = op1_and_result[0];
    const res = op1_and_result[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expect(op1.?.eq(relocatable.fromU64(2)));
    try expect(res.?.eq(relocatable.fromU64(4)));
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Mul, zero op0" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing.

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op0 = relocatable.fromU64(0);

    const tuple = try deduceOp1(&instr, &dst, &op0);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(
        expected_op_1,
        op1,
    );
    try expectEqual(
        expected_res,
        res,
    );
}

test "deduceOp1 when opcode == .AssertEq, res_logic = .Mul, no input" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing.

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const tuple = try deduceOp1(&instr, null, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(
        expected_op_1,
        op1,
    );
    try expectEqual(
        expected_res,
        res,
    );
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Op1, no dst" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing.

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const op0 = relocatable.fromU64(0);

    const tuple = try deduceOp1(&instr, null, &op0);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(
        expected_op_1,
        op1,
    );
    try expectEqual(
        expected_res,
        res,
    );
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Op1, no op0" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Nothing/

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst = relocatable.fromU64(7);

    const tuple = try deduceOp1(&instr, &dst, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expect(op1.?.eq(relocatable.fromU64(7)));
    try expect(res.?.eq(relocatable.fromU64(7)));
}

test "set get value in vm memory" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    _ = vm.segments.addSegment();
    _ = vm.segments.addSegment();

    const address = Relocatable.new(1, 0);
    const value = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(42));

    _ = try vm.segments.memory.set(address, value);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the value is correctly set to 42.
    const actual_value = try vm.segments.memory.get(address);
    const expected_value = value;
    try expectEqual(
        expected_value,
        actual_value,
    );
}

test "compute res op1 works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Op1,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = value_op1;

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(
        expected_res,
        actual_res,
    );
}

test "compute res add felts works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Add,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(5));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(
        expected_res,
        actual_res,
    );
}

test "compute res add felt to offset works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Add,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = Relocatable.new(1, 1);
    const op0 = relocatable.newFromRelocatable(value_op0);

    const op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, op0, op1);
    const res = Relocatable.new(1, 4);
    const expected_res = relocatable.newFromRelocatable(res);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(
        expected_res,
        actual_res,
    );
}

test "compute res add fails two relocs" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Add,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = Relocatable.new(1, 0);
    const value_op1 = Relocatable.new(1, 1);

    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.newFromRelocatable(value_op1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectError(error.AddRelocToRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res mul works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Mul,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(6));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(
        expected_res,
        actual_res,
    );
}

test "compute res mul fails two relocs" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Mul,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = Relocatable.new(1, 0);
    const value_op1 = Relocatable.new(1, 1);

    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.newFromRelocatable(value_op1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectError(error.MulRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res mul fails felt and reloc" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Mul,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = Relocatable.new(1, 0);
    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectError(error.MulRelocForbidden, computeRes(&instruction, op0, op1));
}

test "memory is not leaked upon allocation failure during initialization" {
    var i: usize = 0;
    while (i < 20) {
        // ************************************************************
        // *                 SETUP TEST CONTEXT                       *
        // ************************************************************
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = i });
        i += 1;

        // ************************************************************
        // *                      TEST BODY                           *
        // ************************************************************
        // Nothing.

        // ************************************************************
        // *                      TEST CHECKS                         *
        // ************************************************************
        // Error must have occured!

        // It's not given that the final error will be an OutOfMemory. It's likely though.
        // Plus we're not certain that the error will be thrown at the same place as the
        // VM is upgraded. For this reason, we should just ensure that no memory has
        // been leaked.
        // try expectError(error.OutOfMemory, CairoVM.init(allocator.allocator(), .{}));

        // Note that `.deinit()` is not called in case of failure (obviously).
        // If error handling is done correctly, no memory should be leaked.
        var vm = CairoVM.init(allocator.allocator(), .{}) catch continue;
        vm.deinit();
    }
}
