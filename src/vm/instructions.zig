// Core imports.
const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const CairoVMError = @import("./error.zig").CairoVMError;
const MathError = @import("./error.zig").MathError;
const decoder = @import("./decoding/decoder.zig");
const MaybeRelocatable = @import("./memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("./memory/relocatable.zig").Relocatable;

//  Structure of the 63-bit that form the first word of each instruction.
//  See Cairo whitepaper, page 32 - https://eprint.iacr.org/2021/1063.pdf.
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                     off_dst (biased representation)                     │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                     off_op0 (biased representation)                     │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                     off_op1 (biased representation)                     │
// ├─────┬─────┬───────┬───────┬───────────┬────────┬───────────────────┬────┤
// │ dst │ op0 │  op1  │  res  │    pc     │   ap   │      opcode       │ 0  │
// │ reg │ reg │  src  │ logic │  update   │ update │                   │    │
// ├─────┼─────┼───┬───┼───┬───┼───┬───┬───┼───┬────┼────┬────┬────┬────┼────┤
// │  0  │  1  │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │ 8 │ 9 │ 10 │ 11 │ 12 │ 13 │ 14 │ 15 │
// └─────┴─────┴───┴───┴───┴───┴───┴───┴───┴───┴────┴────┴────┴────┴────┴────┘

/// Used to represent 16-bit signed integer offsets
pub const OFFSET_BITS: u32 = 16;

// *****************************************************************************
// *                       CUSTOM ERROR TYPE                                   *
// *****************************************************************************

/// Error type to represent different error conditions during instruction decoding.
pub const Error = error{
    /// Represents an error condition where the high bit in the instruction's first word is non-zero.
    NonZeroHighBit,
    /// Indicates an error when an invalid register value is encountered for the `op1` field in the instruction.
    InvalidOp1Reg,
    /// Represents an error when the `pc_update` field in the instruction is invalid.
    Invalidpc_update,
    /// Signifies an error related to an invalid value for the `res_logic` field in the instruction.
    Invalidres_logic,
    /// Indicates an error condition when the opcode in the instruction is invalid.
    InvalidOpcode,
    /// Represents an error when the `ap_update` field in the instruction is invalid.
    Invalidap_update,
};

// *****************************************************************************
// *                      CUSTOM TYPES DEFINITIONS                              *
// *****************************************************************************

/// Cairo has 2 address registers, called `ap` and `fp`,
/// which are used for specifying which memory cells the instruction operates on.
pub const Register = enum {
    /// Allocation pointer - points to a yet-unused memory cell.
    AP,
    /// Frame pointer - points to the frame of the current function
    FP,
};

/// The `Op1Src` enum provides definitions for operation sources, specifying
/// where an operation retrieves its data from.
pub const Op1Src = enum {
    /// Represents an immediate value, for example, `[ap] = 123456789` - `op1 = [pc + 1]`.
    Imm,
    /// Refers to the allocation pointer, which points to an unused memory cell - `op1 = [ap + off2]`.
    AP,
    /// Refers to the frame pointer, which points to the current function's frame - `op1 = [fp + off2]`.
    FP,
    /// Represents the result of the operation - `op1 = [op0]`.
    Op0,
};

/// The `ResLogic` constants represent different types of results in a program
pub const ResLogic = enum {
    /// Represents the result of the operation - `res = operand_1`.
    Op1,
    /// Addition - `res = operand_0 + operand_1`.
    Add,
    /// Multiplication - `res = operand_0 * operand_1`.
    Mul,
    /// `res` is not constrained.
    Unconstrained,
};

/// The `PcUpdate` constants define different ways to update the program counter
pub const PcUpdate = enum {
    /// Regular update - Next `pc`: `pc + op_size`.
    Regular,
    /// Absolute jump - Next `pc`: `res (jmp abs)`.
    Jump,
    /// Relative jump - Next `pc`: `pc + res (jmp rel)`.
    JumpRel,
    /// Jump Non-Zero - Next `pc`: `jnz_addr (jnz)`,
    /// where `jnz_addr` is a complex expression, representing the `jnz` logic.
    Jnz,
};

/// The `ApUpdate` constants represent various ways of updating an address pointer
pub const ApUpdate = enum {
    /// Regular update - Next `ap`: `ap`.
    Regular,
    /// Additional update using `pc` - Next `ap`: `ap + [pc + 1]`.
    Add,
    /// Additional update with 1 as offset - Next `ap`: `ap + 1`.
    Add1,
    /// Additional update with 2  as offset - Next `ap`: `ap + 2`.
    Add2,
};

/// The `FpUpdate` constants define different ways of updating the frame pointer
pub const FpUpdate = enum {
    /// Regular update - Next `fp`: `fp`.
    Regular,
    /// Addition with a specific offset - Next `fp`: `ap + 2`.
    APPlus2,
    /// Destination update - Next `fp`: `operand_dst`.
    Dst,
};

/// The `Opcode` constants represent different types of operations or instructions.
pub const Opcode = enum {
    /// No operation.
    NOp,
    /// Equality assertion check.
    AssertEq,
    /// Function calls.
    Call,
    /// Returns.
    Ret,
};

/// Represents a decoded instruction.
pub const Instruction = struct {
    const Self = @This();
    /// Offset 0
    ///
    /// In the range [-2**15, 2*15) = [-2**(OFFSET_BITS-1), 2**(OFFSET_BITS-1)).
    off_0: isize = 0,
    /// Offset 1
    ///
    /// In the range [-2**15, 2*15) = [-2**(OFFSET_BITS-1), 2**(OFFSET_BITS-1)).
    off_1: isize = 0,
    /// Offset 2
    ///
    /// In the range [-2**15, 2*15) = [-2**(OFFSET_BITS-1), 2**(OFFSET_BITS-1)).
    off_2: isize = 0,
    /// Destination register.
    dst_reg: Register = .FP,
    /// Operand 0 register.
    op_0_reg: Register = .FP,
    /// Source for Operand 1 data.
    op_1_addr: Op1Src = .Imm,
    /// Logic for result computation.
    res_logic: ResLogic = .Add,
    /// Update method for the program counter.
    pc_update: PcUpdate = .Jump,
    /// Update method for the allocation pointer.
    ap_update: ApUpdate = .Add,
    /// Update method for the frame pointer.
    fp_update: FpUpdate = .APPlus2,
    /// Opcode representing the operation or instruction type.
    opcode: Opcode = .Call,

    /// Returns the size of an instruction.
    /// # Returns
    /// Size of the instruction.
    pub fn size(self: Self) usize {
        return switch (self.op_1_addr) {
            .Imm => 2,
            else => 1,
        };
    }

    /// Checks if the instruction is a CALL instruction.
    ///
    /// Determines if the instruction represents a CALL operation.
    /// # Returns
    /// `true` if the instruction is a CALL instruction; otherwise, `false`.
    pub fn isCallInstruction(self: *const Self) bool {
        return self.res_logic == .Op1 and
            (self.pc_update == .Jump or self.pc_update == .JumpRel) and
            self.ap_update == .Add2 and
            self.fp_update == .APPlus2 and
            self.opcode == .Call;
    }

    /// Attempts to deduce `op1` and `res` for an instruction, given `dst` and `op0`.
    ///
    /// # Arguments
    /// - `inst`: The instruction to deduce `op1` and `res` for.
    /// - `dst`: The destination of the instruction.
    /// - `op0`: The first operand of the instruction.
    ///
    /// # Returns
    /// - `Tuple`: A tuple containing the deduced `op1` and `res`.
    pub fn deduceOp1(
        inst: *const Self,
        dst: *const ?MaybeRelocatable,
        op0: *const ?MaybeRelocatable,
    ) !struct {
        /// The computed operand Op1.
        op_1: ?MaybeRelocatable = null,
        /// The result of the operation involving Op1.
        res: ?MaybeRelocatable = null,
    } {
        if (inst.opcode != .AssertEq) return .{};

        switch (inst.res_logic) {
            .Op1 => if (dst.*) |dst_val| return .{ .op_1 = dst_val, .res = dst_val },
            .Add => if (dst.*) |d|
                if (op0.*) |op| return .{ .op_1 = try d.sub(op), .res = d },
            .Mul => if (dst.*) |d| {
                if (op0.*) |op| {
                    if (d.isFelt() and op.isFelt() and !op.felt.isZero())
                        return .{
                            .op_1 = MaybeRelocatable.fromFelt(try d.felt.div(op.felt)),
                            .res = d,
                        };
                }
            },
            else => {},
        }

        return .{};
    }

    /// Compute the result operand for a given instruction on op 0 and op 1.
    /// # Arguments
    /// - `instruction`: The instruction to compute the operands for.
    /// - `op_0`: The operand 0.
    /// - `op_1`: The operand 1.
    /// # Returns
    /// - `res`: The result of the operation.
    pub fn computeRes(
        instruction: *const Self,
        op_0: MaybeRelocatable,
        op_1: MaybeRelocatable,
    ) !?MaybeRelocatable {
        return switch (instruction.res_logic) {
            .Op1 => op_1,
            .Add => try op_0.add(op_1),
            .Mul => try op_0.mul(op_1),
            .Unconstrained => null,
        };
    }
};

/// Parse opcode from a 3-bit integer field.
/// # Arguments
/// - opcode_num: 3-bit integer field extracted from instruction
/// # Returns
/// Parsed Opcode value, or an error if invalid
fn parseOpcode(opcode_num: u8) Error!Opcode {
    return switch (opcode_num) {
        0 => .NOp,
        1 => .Call,
        2 => .Ret,
        4 => .AssertEq,
        else => Error.InvalidOpcode,
    };
}

/// Parse Op1Src from a 3-bit integer field.
/// # Arguments
/// - op1_src_num: 3-bit integer field extracted from instruction
/// # Returns
/// Parsed Op1Src value, or an error if invalid
fn parseOp1Src(op1_src_num: u8) Error!Op1Src {
    return switch (op1_src_num) {
        0 => .Op0,
        1 => .Imm,
        2 => .FP,
        4 => .AP,
        else => Error.InvalidOp1Reg,
    };
}

/// Parse res_logic from a 2-bit integer field.
/// # Arguments
/// - res_logic_num: 2-bit integer field extracted from instruction
/// - pc_update: pc_update value of the current instruction
/// # Returns
/// Parsed res_logic value, or an error if invalid
fn parseResLogic(
    res_logic_num: u8,
    pc_update: PcUpdate,
) Error!ResLogic {
    return switch (res_logic_num) {
        0 => if (pc_update == .Jnz) .Unconstrained else .Op1,
        1 => .Add,
        2 => .Mul,
        else => Error.Invalidres_logic,
    };
}

/// Parse pc_update from a 3-bit integer field.
/// # Arguments
/// - pc_update_num: 3-bit integer field extracted from instruction
/// # Returns
/// Parsed pc_update value, or an error if invalid
fn parsePcUpdate(pc_update_num: u8) Error!PcUpdate {
    return switch (pc_update_num) {
        0 => .Regular,
        1 => .Jump,
        2 => .JumpRel,
        4 => .Jnz,
        else => Error.Invalidpc_update,
    };
}

/// Parse ap_update from a 2-bit integer field.
/// # Arguments
/// - ap_update_num: 2-bit integer field extracted from instruction
/// - opcode: Opcode of the current instruction
/// # Returns
/// Parsed ap_update value, or an error if invalid
fn parseApUpdate(
    ap_update_num: u8,
    opcode: Opcode,
) Error!ApUpdate {
    return switch (ap_update_num) {
        0 => if (opcode == .Call) .Add2 else .Regular,
        1 => .Add,
        2 => .Add1,
        else => Error.Invalidap_update,
    };
}

/// Parse fp_update based on the Opcode value.
/// # Arguments
/// - opcode: Opcode of the current instruction
/// # Returns
/// Appropriate fp_update value
fn parseFpUpdate(opcode: Opcode) FpUpdate {
    return switch (opcode) {
        .Call => .APPlus2,
        .Ret => .Dst,
        else => .Regular,
    };
}

/// Converts a biased 16-bit representation to a 16-bit signed integer.
/// # Arguments
/// - biased_repr: Biased representation as a 16-bit integer
/// # Returns
/// 16-bit signed integer
pub fn fromBiasedRepresentation(biased_repr: u16) i16 {
    return @intCast(@as(
        i32,
        @intCast(biased_repr),
    ) - 32768);
}

/// Determines if the given encoded instruction represents a CALL instruction.
///
/// Decodes the provided encoded instruction and checks if it corresponds to a CALL instruction.
/// # Parameters
/// - `encoded_instruction`: The encoded instruction to be checked.
/// # Returns
/// `true` if the instruction, after decoding, is identified as a CALL instruction; otherwise, `false`.
pub fn isCallInstruction(encoded_instruction: Felt252) bool {
    return (decoder.decodeInstructions(encoded_instruction.intoU64() catch return false) catch return false).isCallInstruction();
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

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

test "isCallInstruction" {
    try expect(isCallInstruction(Felt252.fromInt(u256, 1226245742482522112)));
    try expect(!isCallInstruction(Felt252.fromInt(u256, 4612671187288031229)));
    try expect(!isCallInstruction(Felt252.fromInt(u256, 1 << 63)));
}

test "deduceOp1 when opcode == .Call" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .Call;

    const op1Deduction = try instr.deduceOp1(&null, &null);

    // Test checks
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_1, op1Deduction.op_1);
    try expectEqual(expected_res, op1Deduction.res);
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Add, input is felt" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Add;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 3);
    const op0: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 2);

    const op1Deduction = try instr.deduceOp1(&dst, &op0);

    // Test checks
    try expect(op1Deduction.op_1.?.eq(MaybeRelocatable.fromInt(u64, 1)));
    try expect(op1Deduction.res.?.eq(MaybeRelocatable.fromInt(u64, 3)));
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Mul, non-zero op0" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    const op0: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 2);

    const op1Deduction = try instr.deduceOp1(&dst, &op0);

    // Test checks
    try expect(op1Deduction.op_1.?.eq(MaybeRelocatable.fromInt(u64, 2)));
    try expect(op1Deduction.res.?.eq(MaybeRelocatable.fromInt(u64, 4)));
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Mul, zero op0" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 4);
    const op0: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 0);

    const op1Deduction = try instr.deduceOp1(&dst, &op0);

    // Test checks
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_1, op1Deduction.op_1);
    try expectEqual(expected_res, op1Deduction.res);
}

test "deduceOp1 when opcode == .AssertEq, res_logic = .Mul, no input" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Mul;

    const op1Deduction = try instr.deduceOp1(&null, &null);

    // Test checks
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_1, op1Deduction.op_1);
    try expectEqual(expected_res, op1Deduction.res);
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Op1, no dst" {
    // Setup test context
    // Nothing.

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const op0: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 0);

    const op1Deduction = try instr.deduceOp1(&null, &op0);

    // Test checks
    const expected_op_1: ?MaybeRelocatable = null; // temp var needed for type inference
    const expected_res: ?MaybeRelocatable = null;
    try expectEqual(expected_op_1, op1Deduction.op_1);
    try expectEqual(expected_res, op1Deduction.res);
}

test "deduceOp1 when opcode == .AssertEq, res_logic == .Op1, no op0" {
    // Setup test context
    // Nothing/

    // Test body
    var instr = deduceOpTestInstr;
    instr.opcode = .AssertEq;
    instr.res_logic = .Op1;

    const dst: ?MaybeRelocatable = MaybeRelocatable.fromInt(u64, 7);

    const op1Deduction = try instr.deduceOp1(&dst, &null);

    // Test checks
    try expect(op1Deduction.op_1.?.eq(MaybeRelocatable.fromInt(u64, 7)));
    try expect(op1Deduction.res.?.eq(MaybeRelocatable.fromInt(u64, 7)));
}

test "compute res op1 works" {
    // Test body
    const value_op0 = MaybeRelocatable.fromFelt(Felt252.two());
    const value_op1 = MaybeRelocatable.fromFelt(Felt252.three());

    const instruction: Instruction = .{
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

    // Call with Op1 res logic
    const actual_res = try instruction.computeRes(value_op0, value_op1);
    const expected_res = value_op1;

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res add felts works" {
    // Test body
    const value_op0 = MaybeRelocatable.fromFelt(Felt252.two());
    const value_op1 = MaybeRelocatable.fromFelt(Felt252.three());

    const instruction: Instruction = .{
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

    const actual_res = try instruction.computeRes(value_op0, value_op1);
    const expected_res = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 5));

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res add felt to offset works" {
    // Test body
    const value_op0 = Relocatable.init(1, 1);
    const op0 = MaybeRelocatable.fromRelocatable(value_op0);

    const op1 = MaybeRelocatable.fromFelt(Felt252.three());

    const instruction: Instruction = .{
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

    const actual_res = try instruction.computeRes(op0, op1);
    const res = Relocatable.init(1, 4);
    const expected_res = MaybeRelocatable.fromRelocatable(res);

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res add fails two relocs" {

    // Test body
    const value_op0 = Relocatable.init(1, 0);
    const value_op1 = Relocatable.init(1, 1);

    const op0 = MaybeRelocatable.fromRelocatable(value_op0);
    const op1 = MaybeRelocatable.fromRelocatable(value_op1);

    const instruction: Instruction = .{
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

    // Test checks
    try expectError(
        MathError.RelocatableAdd,
        instruction.computeRes(op0, op1),
    );
}

test "compute res mul works" {
    // Test body
    const value_op0 = MaybeRelocatable.fromFelt(Felt252.two());
    const value_op1 = MaybeRelocatable.fromFelt(Felt252.three());

    const instruction: Instruction = .{
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

    // Call with Mul res logic
    const actual_res = try instruction.computeRes(value_op0, value_op1);
    const expected_res = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 6));

    // Test checks
    try expectEqual(
        expected_res,
        actual_res.?,
    );
}

test "compute res mul fails two relocs" {
    // Test bod
    const value_op0 = Relocatable.init(1, 0);
    const value_op1 = Relocatable.init(1, 1);

    const op0 = MaybeRelocatable.fromRelocatable(value_op0);
    const op1 = MaybeRelocatable.fromRelocatable(value_op1);

    const instruction: Instruction = .{
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

    // Test checks
    try expectError(
        MathError.RelocatableMul,
        instruction.computeRes(op0, op1),
    );
}

test "compute res mul fails felt and reloc" {
    // Test body
    const value_op0 = Relocatable.init(1, 0);
    const op0 = MaybeRelocatable.fromRelocatable(value_op0);
    const op1 = MaybeRelocatable.fromFelt(Felt252.two());

    const instruction: Instruction = .{
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

    // Test checks
    try expectError(
        MathError.RelocatableMul,
        instruction.computeRes(op0, op1),
    );
}

test "compute res Unconstrained should return null" {
    // Test body
    const value_op0 = MaybeRelocatable.fromFelt(Felt252.two());
    const value_op1 = MaybeRelocatable.fromFelt(Felt252.three());

    const instruction: Instruction = .{
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

    // Call with unconstrained res logic
    const actual_res = try instruction.computeRes(value_op0, value_op1);
    const expected_res: ?MaybeRelocatable = null;

    // Test checks
    try expectEqual(
        expected_res,
        actual_res,
    );
}
