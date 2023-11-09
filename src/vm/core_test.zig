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
const BitwiseBuiltinRunner = @import("./builtins/builtin_runner/bitwise.zig").BitwiseBuiltinRunner;
const BitwiseInstanceDef = @import("./types/bitwise_instance_def.zig").BitwiseInstanceDef;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HashBuiltinRunner = @import("./builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const Instruction = @import("instructions.zig").Instruction;
const CairoVM = @import("core.zig").CairoVM;
const computeRes = @import("core.zig").computeRes;
const OperandsResult = @import("core.zig").OperandsResult;
const deduceOp1 = @import("core.zig").deduceOp1;

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
    var instance_def: BitwiseInstanceDef = .{ .ratio = null, .total_n_bits = 2 };
    try vm.builtin_runners.append(BuiltinRunner{ .Bitwise = BitwiseBuiltinRunner.new(
        &instance_def,
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Regular;
    instruction.op_1_addr = .AP;
    const operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Regular;
    instruction.op_1_addr = .Imm;
    const operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Jump;
    var operands = OperandsResult.default();
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(error.ResUnconstrainedUsedWithPcUpdateJump, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump with operands res not relocatable" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Jump;
    var operands = OperandsResult.default();
    operands.res = relocatable.fromU64(0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(error.PcUpdateJumpResNotRelocatable, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump with operands res relocatable" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Jump;
    var operands = OperandsResult.default();
    operands.res = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .JumpRel;
    var operands = OperandsResult.default();
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(error.ResUnconstrainedUsedWithPcUpdateJumpRel, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump rel with operands res not felt" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .JumpRel;
    var operands = OperandsResult.default();
    operands.res = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(error.PcUpdateJumpRelResNotFelt, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump rel with operands res felt" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .JumpRel;
    var operands = OperandsResult.default();
    operands.res = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(1);
    operands.op_1 = relocatable.newFromRelocatable(Relocatable.new(
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
            &instruction,
            operands,
        ),
    );
}

test "update pc update jnz with operands dst not zero op1 felt" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = .Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(1);
    operands.op_1 = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updatePc(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = .Add;
    var operands = OperandsResult.default();
    operands.res = null; // Simulate unconstrained res
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try expectError(error.ApUpdateAddResUnconstrained, vm.updateAp(
        &instruction,
        operands,
    ));
}

test "update ap add1" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = .Add1;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateAp(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = .Add2;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateAp(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = .APPlus2;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateFp(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = .Dst;
    var operands = OperandsResult.default();
    operands.dst = relocatable.newFromRelocatable(Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateFp(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = .Dst;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    try vm.updateFp(
        &instruction,
        operands,
    );

    // Test checks
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
    // Test setup
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var config = Config{ .proof_mode = false, .enable_trace = true };

    var vm = try CairoVM.init(
        allocator,
        config,
    );
    defer vm.deinit();

    // Test body
    // Do nothing

    // Test checks
    // Check that trace was initialized
    if (!vm.trace_context.isEnabled()) {
        return error.TraceShouldHaveBeenEnabled;
    }
}

test "trace is disabled" {
    // Test setup
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    // Do nothing

    // Test checks
    // Check that trace was initialized
    if (vm.trace_context.isEnabled()) {
        return error.TraceShouldHaveBeenDisabled;
    }
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

    const tuple = try vm.deduceOp0(&instr, null, null);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    const expected_op_0: ?MaybeRelocatable = relocatable.newFromRelocatable(Relocatable.new(0, 1)); // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Add, input is felt" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const dst = relocatable.fromU64(3);
    const op1 = relocatable.fromU64(2);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    try expect(op0.?.eq(relocatable.fromU64(1)));
    try expect(res.?.eq(relocatable.fromU64(3)));
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Add, with no input" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const tuple = try vm.deduceOp0(&instr, null, null);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Mul, input is felt 1" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(2);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    const expected_op_0: ?MaybeRelocatable = relocatable.fromU64(2); // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = relocatable.fromU64(4);
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Op1, input is felt" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(0);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .AssertEq, res_logic == .Mul, input is felt 2" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(0);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp0 when opcode == .Ret, res_logic == .Mul, input is felt" {
    // Setup test context
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .Ret;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op1 = relocatable.fromU64(0);

    const tuple = try vm.deduceOp0(&instr, &dst, &op1);
    const op0 = tuple[0];
    const res = tuple[1];

    // Test checks
    const expected_op_0: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_0, op0);
    try expectEqual(expected_res, res);
}

test "deduceOp1 when opcode == .Call" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    const tuple = try deduceOp1(&instr, null, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // Test checks
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
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const dst = relocatable.fromU64(3);
    const op0 = relocatable.fromU64(2);

    const tuple = try deduceOp1(&instr, &dst, &op0);
    const op1 = tuple[0];
    const res = tuple[1];

    // Test checks
    try expect(op1.?.eq(relocatable.fromU64(1)));
    try expect(res.?.eq(relocatable.fromU64(3)));
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Mul, non-zero op0" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op0 = relocatable.fromU64(2);

    const op1_and_result = try deduceOp1(&instr, &dst, &op0);
    const op1 = op1_and_result[0];
    const res = op1_and_result[1];

    // Test checks
    try expect(op1.?.eq(relocatable.fromU64(2)));
    try expect(res.?.eq(relocatable.fromU64(4)));
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Mul, zero op0" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst = relocatable.fromU64(4);
    const op0 = relocatable.fromU64(0);

    const tuple = try deduceOp1(&instr, &dst, &op0);
    const op1 = tuple[0];
    const res = tuple[1];

    // Test checks
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
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const tuple = try deduceOp1(&instr, null, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // Test checks
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
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const op0 = relocatable.fromU64(0);

    const tuple = try deduceOp1(&instr, null, &op0);
    const op1 = tuple[0];
    const res = tuple[1];

    // Test checks
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
    // Setup test context
    // Nothing/

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst = relocatable.fromU64(7);

    const tuple = try deduceOp1(&instr, &dst, null);
    const op1 = tuple[0];
    const res = tuple[1];

    // Test checks
    try expect(op1.?.eq(relocatable.fromU64(7)));
    try expect(res.?.eq(relocatable.fromU64(7)));
}

test "set get value in vm memory" {
    // Test setup
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // Test body
    _ = vm.segments.addSegment();
    _ = vm.segments.addSegment();

    const address = Relocatable.new(1, 0);
    const value = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(42));

    _ = try vm.segments.memory.set(address, value);

    // Test checks
    // Verify the value is correctly set to 42.
    const actual_value = try vm.segments.memory.get(address);
    const expected_value = value;
    try expectEqual(
        expected_value,
        actual_value,
    );
}

test "compute res op1 works" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = .AP,
        .op_0_reg = .AP,
        .op_1_addr = .AP,
        .res_logic = .Op1,
        .pc_update = .Regular,
        .ap_update = .Regular,
        .fp_update = .Regular,
        .opcode = .NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = value_op1;

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res add felts works" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
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
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(5));

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res add felt to offset works" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
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
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = Relocatable.new(1, 1);
    const op0 = relocatable.newFromRelocatable(value_op0);

    const op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, op0, op1);
    const res = Relocatable.new(1, 4);
    const expected_res = relocatable.newFromRelocatable(res);

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res add fails two relocs" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
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
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = Relocatable.new(1, 0);
    const value_op1 = Relocatable.new(1, 1);

    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.newFromRelocatable(value_op1);

    // Test checks
    try expectError(error.AddRelocToRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res mul works" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = .AP,
        .op_0_reg = .AP,
        .op_1_addr = .AP,
        .res_logic = .Mul,
        .pc_update = .Regular,
        .ap_update = .Regular,
        .fp_update = .Regular,
        .opcode = .NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(6));

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res mul fails two relocs" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = .AP,
        .op_0_reg = .AP,
        .op_1_addr = .AP,
        .res_logic = .Mul,
        .pc_update = .Regular,
        .ap_update = .Regular,
        .fp_update = .Regular,
        .opcode = .NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = Relocatable.new(1, 0);
    const value_op1 = Relocatable.new(1, 1);

    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.newFromRelocatable(value_op1);

    // Test checks
    try expectError(error.MulRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res mul fails felt and reloc" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = .AP,
        .op_0_reg = .AP,
        .op_1_addr = .AP,
        .res_logic = .Mul,
        .pc_update = .Regular,
        .ap_update = .Regular,
        .fp_update = .Regular,
        .opcode = .NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = Relocatable.new(1, 0);
    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));

    // Test checks
    try expectError(error.MulRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res Unconstrained should return null" {
    // Test setup
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = .AP,
        .op_0_reg = .AP,
        .op_1_addr = .AP,
        .res_logic = .Unconstrained,
        .pc_update = .Regular,
        .ap_update = .Regular,
        .fp_update = .Regular,
        .opcode = .NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = Relocatable.new(1, 0);
    // Test body

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res: ?MaybeRelocatable = null;

    // Test checks
    try expectEqual(
        expected_res,
        actual_res,
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

test "updateRegisters all regular" {
    // Test setup
    var instruction = Instruction{
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
    };

    var operands = OperandsResult{
        .dst = .{ .felt = Felt252.fromInteger(11) },
        .res = .{ .felt = Felt252.fromInteger(8) },
        .op_0 = .{ .felt = Felt252.fromInteger(9) },
        .op_1 = .{ .felt = Felt252.fromInteger(10) },
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    vm.run_context.pc.* = Relocatable.new(0, 4);
    vm.run_context.ap.* = Relocatable.new(0, 5);
    vm.run_context.fp.* = Relocatable.new(0, 6);

    // Test body
    try vm.updateRegisters(
        &instruction,
        operands,
    );

    // Test checks
    // Verify the PC offset was incremented by 5.
    try expectEqual(
        Relocatable.new(0, 5),
        vm.getPc(),
    );

    // Verify the AP offset was incremented by 5.
    try expectEqual(
        Relocatable.new(0, 5),
        vm.getAp(),
    );

    // Verify the FP offset was incremented by 6.
    try expectEqual(
        Relocatable.new(0, 6),
        vm.getFp(),
    );
}

test "updateRegisters with mixed types" {
    // Test setup
    var instruction = Instruction{
        .off_0 = 1,
        .off_1 = 2,
        .off_2 = 3,
        .dst_reg = .FP,
        .op_0_reg = .AP,
        .op_1_addr = .AP,
        .res_logic = .Add,
        .pc_update = .JumpRel,
        .ap_update = .Add2,
        .fp_update = .Dst,
        .opcode = .NOp,
    };

    var operands = OperandsResult{
        .dst = .{ .relocatable = Relocatable.new(
            1,
            11,
        ) },
        .res = .{ .felt = Felt252.fromInteger(8) },
        .op_0 = .{ .felt = Felt252.fromInteger(9) },
        .op_1 = .{ .felt = Felt252.fromInteger(10) },
        .dst_addr = .{},
        .op_0_addr = .{},
        .op_1_addr = .{},
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    vm.run_context.pc.* = Relocatable.new(0, 4);
    vm.run_context.ap.* = Relocatable.new(0, 5);
    vm.run_context.fp.* = Relocatable.new(0, 6);

    // Test body
    try vm.updateRegisters(
        &instruction,
        operands,
    );

    // Test checks
    // Verify the PC offset was incremented by 12.
    try expectEqual(
        Relocatable.new(0, 12),
        vm.getPc(),
    );

    // Verify the AP offset was incremented by 7.
    try expectEqual(
        Relocatable.new(0, 7),
        vm.getAp(),
    );

    // Verify the FP offset was incremented by 11.
    try expectEqual(
        Relocatable.new(1, 11),
        vm.getFp(),
    );
}

test "CairoVM: computeOp0Deductions should return op0 from deduceOp0 if deduceMemoryCell is null" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    // Test check
    try expectEqual(
        MaybeRelocatable{ .relocatable = Relocatable.new(0, 1) },
        try vm.computeOp0Deductions(
            Relocatable.new(0, 7),
            &instr,
            null,
            null,
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
    var instance_def: BitwiseInstanceDef = .{ .ratio = null, .total_n_bits = 2 };
    try vm.builtin_runners.append(BuiltinRunner{ .Bitwise = BitwiseBuiltinRunner.new(
        &instance_def,
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

    // Test check
    try expectEqual(
        MaybeRelocatable{ .felt = Felt252.fromInteger(8) },
        try vm.computeOp0Deductions(
            Relocatable.new(0, 7),
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

    // Test check
    try expectError(
        CairoVMError.FailedToComputeOperands,
        vm.computeOp0Deductions(
            Relocatable.new(0, 7),
            &instr,
            &relocatable.fromU64(4),
            &relocatable.fromU64(0),
        ),
    );
}

test "CairoVM: computeSegmentsEffectiveSizes should return the computed effective size for the VM segments" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.data.put(Relocatable.new(0, 0), .{ .felt = Felt252.fromInteger(1) });
    try vm.segments.memory.data.put(Relocatable.new(0, 1), .{ .felt = Felt252.fromInteger(1) });
    try vm.segments.memory.data.put(Relocatable.new(0, 2), .{ .felt = Felt252.fromInteger(1) });

    var actual = try vm.computeSegmentsEffectiveSizes();

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 3), actual.get(0).?);
}

test "CairoVM: deduceDst should return res if AssertEq opcode" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instruction = Instruction{
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
    };

    var res = MaybeRelocatable{ .felt = Felt252.fromInteger(7) };

    // Test check
    try expectEqual(
        MaybeRelocatable{ .felt = Felt252.fromInteger(7) },
        try vm.deduceDst(&instruction, &res),
    );
}

test "CairoVM: deduceDst should return VM error No dst if AssertEq opcode without res" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instruction = Instruction{
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
    };

    // Test check
    try expectError(
        CairoVMError.NoDst,
        vm.deduceDst(&instruction, null),
    );
}

test "CairoVM: deduceDst should return fp Relocatable if Call opcode" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    vm.run_context.fp.* = Relocatable.new(3, 23);

    var instruction = Instruction{
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
    };

    // Test check
    try expectEqual(
        MaybeRelocatable{ .relocatable = Relocatable.new(3, 23) },
        try vm.deduceDst(&instruction, null),
    );
}

test "CairoVM: deduceDst should return VM error No dst if not AssertEq or Call opcode" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    var instruction = Instruction{
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
    };

    // Test check
    try expectError(
        CairoVMError.NoDst,
        vm.deduceDst(&instruction, null),
    );
}

test "CairoVM: addMemorySegment should return a proper relocatable address for the new segment." {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Test check
    try expectEqual(
        Relocatable.new(0, 0),
        vm.addMemorySegment(),
    );
}

test "CairoVM: addMemorySegment should increase by one the number of segments in the VM" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    _ = vm.addMemorySegment();
    _ = vm.addMemorySegment();
    _ = vm.addMemorySegment();

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
        error.MemoryOutOfBounds,
        vm.getRelocatable(Relocatable.new(0, 0)),
    );
}

test "CairoVM: getRelocatable with value should return a MaybeRelocatable" {
    // Test setup
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.data.put(
        Relocatable.new(34, 12),
        .{ .felt = Felt252.fromInteger(5) },
    );

    // Test check
    try expectEqual(
        MaybeRelocatable{ .felt = Felt252.fromInteger(5) },
        try vm.getRelocatable(Relocatable.new(34, 12)),
    );
}

test "CairoVM: getBuiltinRunners should return a reference to the builtin runners ArrayList" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    var instance_def: BitwiseInstanceDef = .{ .ratio = null, .total_n_bits = 2 };
    try vm.builtin_runners.append(BuiltinRunner{ .Bitwise = BitwiseBuiltinRunner.new(
        &instance_def,
        true,
    ) });

    // Test check
    try expectEqual(&vm.builtin_runners, vm.getBuiltinRunners());

    var expected = ArrayList(BuiltinRunner).init(std.testing.allocator);
    defer expected.deinit();
    try expected.append(BuiltinRunner{ .Bitwise = BitwiseBuiltinRunner.new(
        &instance_def,
        true,
    ) });
    try expectEqualSlices(
        BuiltinRunner,
        expected.items,
        vm.getBuiltinRunners().*.items,
    );
}
