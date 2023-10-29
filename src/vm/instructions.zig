// Core imports.
const std = @import("std");

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

// *****************************************************************************
// *                       CUSTOM ERROR TYPE                                   *
// *****************************************************************************

/// Error type to represent different error conditions during instruction decoding.
pub const Error = error{
    NonZeroHighBit,
    InvalidOp1Reg,
    Invalidpc_update,
    Invalidres_logic,
    InvalidOpcode,
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

    off_0: i16,
    off_1: i16,
    off_2: i16,
    dst_reg: Register,
    op_0_reg: Register,
    op_1_addr: Op1Src,
    res_logic: ResLogic,
    pc_update: PcUpdate,
    ap_update: ApUpdate,
    fp_update: FpUpdate,
    opcode: Opcode,

    /// Returns the size of an instruction.
    /// # Returns
    /// Size of the instruction.
    pub fn size(self: Self) usize {
        if (self.op_1_addr == Op1Src.Imm) {
            return 2;
        } else {
            return 1;
        }
    }

    /// Returns a default instruction.
    pub fn default() Self {
        //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
        // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
        //   |    CALL|      ADD|     JUMP|      ADD|    IMM|     FP|     FP
        //  0  0  0  1      0  1   0  0  1      0  1 0  0  1       1       1
        //  0001 0100 1010 0111 = 0x14A7; offx = 0
        return decode(0x14A7800080008000) catch unreachable;
    }
};

/// Decode a 64-bit instruction into its component parts.
/// # Arguments
/// - encoded_instruction: 64-bit integer containing the encoded instruction
/// # Returns
/// Decoded Instruction struct, or an error if decoding fails
pub fn decode(encoded_instruction: u64) Error!Instruction {
    if (encoded_instruction & (1 << 63) != 0) return Error.NonZeroHighBit;
    const flags = @as(
        u16,
        @truncate(encoded_instruction >> 48),
    );
    const offsets = @as(
        u48,
        @truncate(encoded_instruction),
    );
    const parsedNum = @as(
        u8,
        @truncate((flags >> 12) & 7),
    );
    const opcode = try parseOpcode(parsedNum);

    const pc_update = try parsePcUpdate(
        @as(
            u8,
            @truncate((flags >> 7) & 7),
        ),
    );

    return .{
        .off_0 = fromBiasedRepresentation(
            @as(
                u16,
                @truncate(offsets),
            ),
        ),
        .off_1 = fromBiasedRepresentation(
            @as(
                u16,
                @truncate(offsets >> 16),
            ),
        ),
        .off_2 = fromBiasedRepresentation(
            @as(
                u16,
                @truncate(offsets >> 32),
            ),
        ),
        .dst_reg = if (flags & 1 != 0) Register.FP else Register.AP,
        .op_0_reg = if (flags & 2 != 0) Register.FP else Register.AP,
        .op_1_addr = try parseOp1Src(
            @as(
                u8,
                @truncate((flags >> 2) & 7),
            ),
        ),
        .res_logic = try parseResLogic(
            @as(
                u8,
                @truncate((flags >> 5) & 3),
            ),
            pc_update,
        ),
        .pc_update = pc_update,
        .ap_update = try parseApUpdate(
            @as(
                u8,
                @truncate((flags >> 10) & 3),
            ),
            opcode,
        ),
        .opcode = opcode,
        .fp_update = parseFpUpdate(opcode),
    };
}

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
        0 => {
            if (pc_update == .Jnz) {
                return .Unconstrained;
            } else {
                return .Op1;
            }
        },
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
        0 => if (opcode == .Call) {
            return .Add2;
        } else {
            return .Regular;
        },
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
    const as_i32 = @as(
        i32,
        @intCast(biased_repr),
    );
    return @as(
        i16,
        @intCast(as_i32 - 32768),
    );
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "decode flags call add jmp add imm fp fp" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |    CALL|      ADD|     JUMP|      ADD|    IMM|     FP|     FP
    //  0  0  0  1      0  1   0  0  1      0  1 0  0  1       1       1
    //  0001 0100 1010 0111 = 0x14A7; offx = 0

    const encoded_instruction: u64 = 0x14A7800080008000;
    const decoded_instruction = try decode(encoded_instruction);

    try expectEqual(
        Register.FP,
        decoded_instruction.dst_reg,
    );
    try expectEqual(
        Register.FP,
        decoded_instruction.op_0_reg,
    );
    try expectEqual(
        Op1Src.Imm,
        decoded_instruction.op_1_addr,
    );
    try expectEqual(
        ResLogic.Add,
        decoded_instruction.res_logic,
    );
    try expectEqual(
        PcUpdate.Jump,
        decoded_instruction.pc_update,
    );
    try expectEqual(
        ApUpdate.Add,
        decoded_instruction.ap_update,
    );
    try expectEqual(
        Opcode.Call,
        decoded_instruction.opcode,
    );
    try expectEqual(
        FpUpdate.APPlus2,
        decoded_instruction.fp_update,
    );
}

test "decode flags ret add1 jmp rel mul fp ap ap" {
    //	0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    //
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //
    //	 |     RET|     ADD1| JUMP_REL|      MUL|     FP|     AP|     AP
    //	0  0  1  0      1  0   0  1  0      1  0 0  1  0       0       0
    //	0010 1001 0100 1000 = 0x2948; offx = 0

    const encoded_instruction: u64 = 0x2948800080008000;
    const decoded_instruction = try decode(encoded_instruction);

    try expectEqual(
        Register.AP,
        decoded_instruction.dst_reg,
    );
    try expectEqual(
        Register.AP,
        decoded_instruction.op_0_reg,
    );
    try expectEqual(
        Op1Src.FP,
        decoded_instruction.op_1_addr,
    );
    try expectEqual(
        ResLogic.Mul,
        decoded_instruction.res_logic,
    );
    try expectEqual(
        PcUpdate.JumpRel,
        decoded_instruction.pc_update,
    );
    try expectEqual(
        ApUpdate.Add1,
        decoded_instruction.ap_update,
    );
    try expectEqual(
        Opcode.Ret,
        decoded_instruction.opcode,
    );
    try expectEqual(
        FpUpdate.Dst,
        decoded_instruction.fp_update,
    );
}

test "decode flags assert add jnz mul ap ap ap" {
    // 0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |ASSRT_EQ|      ADD|      JNZ|      MUL|     AP|     AP|     AP
    //  0  1  0  0      1  0   1  0  0      1  0 1  0  0       0       0
    //  0100 1010 0101 0000 = 0x4A50; offx = 0

    const encoded_instruction: u64 = 0x4A50800080008000;
    const decoded_instruction = try decode(encoded_instruction);

    try expectEqual(
        Register.AP,
        decoded_instruction.dst_reg,
    );
    try expectEqual(
        Register.AP,
        decoded_instruction.op_0_reg,
    );
    try expectEqual(
        Op1Src.AP,
        decoded_instruction.op_1_addr,
    );
    try expectEqual(
        ResLogic.Mul,
        decoded_instruction.res_logic,
    );
    try expectEqual(
        PcUpdate.Jnz,
        decoded_instruction.pc_update,
    );
    try expectEqual(
        ApUpdate.Add1,
        decoded_instruction.ap_update,
    );
    try expectEqual(
        Opcode.AssertEq,
        decoded_instruction.opcode,
    );
    try expectEqual(
        FpUpdate.Regular,
        decoded_instruction.fp_update,
    );
}

test "decode flags assert add2 jnz uncon op0 ap ap" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //
    //     |ASSRT_EQ|     ADD2|      JNZ|UNCONSTRD|    OP0|     AP|     AP
    //  0  1  0  0      0  0   1  0  0      0  0 0  0  0       0       0
    //  0100 0010 0000 0000 = 0x4200; offx = 0

    const encoded_instruction: u64 = 0x4200800080008000;
    const decoded_instruction = try decode(encoded_instruction);

    try expectEqual(
        Register.AP,
        decoded_instruction.dst_reg,
    );
    try expectEqual(
        Register.AP,
        decoded_instruction.op_0_reg,
    );
    try expectEqual(
        Op1Src.Op0,
        decoded_instruction.op_1_addr,
    );
    try expectEqual(
        ResLogic.Unconstrained,
        decoded_instruction.res_logic,
    );
    try expectEqual(
        PcUpdate.Jnz,
        decoded_instruction.pc_update,
    );
    try expectEqual(
        ApUpdate.Regular,
        decoded_instruction.ap_update,
    );
    try expectEqual(
        Opcode.AssertEq,
        decoded_instruction.opcode,
    );
    try expectEqual(
        FpUpdate.Regular,
        decoded_instruction.fp_update,
    );
}

test "decode flags nop regular regular op1 op0 ap ap" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //
    //     |     NOP|  REGULAR|  REGULAR|      OP1|    OP0|     AP|     AP
    //  0  0  0  0      0  0   0  0  0      0  0 0  0  0       0       0
    //  0000 0000 0000 0000 = 0x0000; offx = 0

    const encoded_instruction: u64 = 0x0000800080008000;
    const decoded_instruction = try decode(encoded_instruction);

    try expectEqual(
        Register.AP,
        decoded_instruction.dst_reg,
    );
    try expectEqual(
        Register.AP,
        decoded_instruction.op_0_reg,
    );
    try expectEqual(
        Op1Src.Op0,
        decoded_instruction.op_1_addr,
    );
    try expectEqual(
        ResLogic.Op1,
        decoded_instruction.res_logic,
    );
    try expectEqual(
        PcUpdate.Regular,
        decoded_instruction.pc_update,
    );
    try expectEqual(
        ApUpdate.Regular,
        decoded_instruction.ap_update,
    );
    try expectEqual(
        Opcode.NOp,
        decoded_instruction.opcode,
    );
    try expectEqual(
        FpUpdate.Regular,
        decoded_instruction.fp_update,
    );
}

test "decode offset negative" {
    const encoded_instruction: u64 = 0x0000800180007FFF;
    const decoded_instruction = try decode(encoded_instruction);
    try expectEqual(@as(
        i16,
        @intCast(-1),
    ), decoded_instruction.off_0);
    try expectEqual(@as(
        i16,
        @intCast(0),
    ), decoded_instruction.off_1);
    try expectEqual(@as(
        i16,
        @intCast(1),
    ), decoded_instruction.off_2);
}

test "non zero high bit" {
    const encoded_instruction: u64 = 0x94A7800080008000;
    try expectError(
        Error.NonZeroHighBit,
        decode(encoded_instruction),
    );
}

test "invalid op1 reg" {
    const encoded_instruction: u64 = 0x294F800080008000;
    try expectError(
        Error.InvalidOp1Reg,
        decode(encoded_instruction),
    );
}

test "invalid pc update" {
    const encoded_instruction: u64 = 0x29A8800080008000;
    try expectError(
        Error.Invalidpc_update,
        decode(encoded_instruction),
    );
}

test "invalid res logic" {
    const encoded_instruction: u64 = 0x2968800080008000;
    try expectError(
        Error.Invalidres_logic,
        decode(encoded_instruction),
    );
}

test "invalid opcode" {
    const encoded_instruction: u64 = 0x3948800080008000;
    try expectError(
        Error.InvalidOpcode,
        decode(encoded_instruction),
    );
}

test "invalid ap update" {
    const encoded_instruction: u64 = 0x2D48800080008000;
    try expectError(
        Error.Invalidap_update,
        decode(encoded_instruction),
    );
}
