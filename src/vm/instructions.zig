// Core imports.
const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const CairoVMError = @import("./error.zig").CairoVMError;
const decoder = @import("./decoding/decoder.zig");

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
    off_0: i16 = 0,
    /// Offset 1
    ///
    /// In the range [-2**15, 2*15) = [-2**(OFFSET_BITS-1), 2**(OFFSET_BITS-1)).
    off_1: i16 = 0,
    /// Offset 2
    ///
    /// In the range [-2**15, 2*15) = [-2**(OFFSET_BITS-1), 2**(OFFSET_BITS-1)).
    off_2: i16 = 0,
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
    return (decoder.decodeInstructions(encoded_instruction.tryIntoU64() catch return false) catch return false).isCallInstruction();
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "isCallInstruction" {
    try expect(isCallInstruction(Felt252.fromInt(u256, 1226245742482522112)));
    try expect(!isCallInstruction(Felt252.fromInt(u256, 4612671187288031229)));
    try expect(!isCallInstruction(Felt252.fromInt(u256, 1 << 63)));
}
