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

// Error type to represent different error conditions during instruction decoding.
const Error = error{
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

const Register = enum { AP, FP };

const Op1Src = enum { Imm, AP, FP, Op0 };

const ResLogic = enum { Op1, Add, Mul, Unconstrained };

const PcUpdate = enum { Regular, Jump, JumpRel, Jnz };

const ApUpdate = enum { Regular, Add, Add1, Add2 };

const FpUpdate = enum { Regular, APPlus2, Dst };

const Opcode = enum { NOp, AssertEq, Call, Ret };

// Represents a decoded instruction.
pub const Instruction = struct {
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
};

// Decode a 64-bit instruction into its component parts.
// # Arguments
// - encoded_instruction: 64-bit integer containing the encoded instruction
// # Returns
// Decoded Instruction struct, or an error if decoding fails
pub fn decode(encoded_instruction: u64) Error!Instruction {
    if (encoded_instruction & (1 << 63) != 0) return Error.NonZeroHighBit;
    const flags = @as(u16, @truncate(encoded_instruction >> 48));
    const offsets = @as(u48, @truncate(encoded_instruction));
    const parsedNum = @as(u8, @truncate((flags >> 12) & 7));
    const opcode = try parseOpcode(parsedNum);

    const pc_update = try parsepc_update(@as(u8, @truncate((flags >> 7) & 7)));

    return Instruction{
        .off_0 = fromBiasedRepresentation(@as(u16, @truncate(offsets))),
        .off_1 = fromBiasedRepresentation(@as(u16, @truncate(offsets >> 16))),
        .off_2 = fromBiasedRepresentation(@as(u16, @truncate(offsets >> 32))),
        .dst_reg = if (flags & 1 != 0) Register.FP else Register.AP,
        .op_0_reg = if (flags & 2 != 0) Register.FP else Register.AP,
        .op_1_addr = try parseOp1Src(@as(u8, @truncate((flags >> 2) & 7))),
        .res_logic = try parseres_logic(@as(u8, @truncate((flags >> 5) & 3)), pc_update),
        .pc_update = pc_update,
        .ap_update = try parseap_update(@as(u8, @truncate((flags >> 10) & 3)), opcode),
        .opcode = opcode,
        .fp_update = parsefp_update(opcode),
    };
}

// Parse opcode from a 3-bit integer field.
// # Arguments
// - opcode_num: 3-bit integer field extracted from instruction
// # Returns
// Parsed Opcode value, or an error if invalid
fn parseOpcode(opcode_num: u8) Error!Opcode {
    return switch (opcode_num) {
        0 => Opcode.NOp,
        1 => Opcode.Call,
        2 => Opcode.Ret,
        4 => Opcode.AssertEq,
        else => Error.InvalidOpcode,
    };
}

// Parse Op1Src from a 3-bit integer field.
// # Arguments
// - op1_src_num: 3-bit integer field extracted from instruction
// # Returns
// Parsed Op1Src value, or an error if invalid
fn parseOp1Src(op1_src_num: u8) Error!Op1Src {
    return switch (op1_src_num) {
        0 => Op1Src.Op0,
        1 => Op1Src.Imm,
        2 => Op1Src.FP,
        4 => Op1Src.AP,
        else => Error.InvalidOp1Reg,
    };
}

// Parse res_logic from a 2-bit integer field.
// # Arguments
// - res_logic_num: 2-bit integer field extracted from instruction
// - pc_update: pc_update value of the current instruction
// # Returns
// Parsed res_logic value, or an error if invalid
fn parseres_logic(res_logic_num: u8, pc_update: PcUpdate) Error!ResLogic {
    return switch (res_logic_num) {
        0 => {
            if (pc_update == PcUpdate.Jnz) {
                return ResLogic.Unconstrained;
            } else {
                return ResLogic.Op1;
            }
        },
        1 => ResLogic.Add,
        2 => ResLogic.Mul,
        else => Error.Invalidres_logic,
    };
}

// Parse pc_update from a 3-bit integer field.
// # Arguments
// - pc_update_num: 3-bit integer field extracted from instruction
// # Returns
// Parsed pc_update value, or an error if invalid
fn parsepc_update(pc_update_num: u8) Error!PcUpdate {
    return switch (pc_update_num) {
        0 => PcUpdate.Regular,
        1 => PcUpdate.Jump,
        2 => PcUpdate.JumpRel,
        4 => PcUpdate.Jnz,
        else => Error.Invalidpc_update,
    };
}

// Parse ap_update from a 2-bit integer field.
// # Arguments
// - ap_update_num: 2-bit integer field extracted from instruction
// - opcode: Opcode of the current instruction
// # Returns
// Parsed ap_update value, or an error if invalid
fn parseap_update(ap_update_num: u8, opcode: Opcode) Error!ApUpdate {
    return switch (ap_update_num) {
        0 => if (opcode == Opcode.Call) {
            return ApUpdate.Add2;
        } else {
            return ApUpdate.Regular;
        },
        1 => ApUpdate.Add,
        2 => ApUpdate.Add1,
        else => Error.Invalidap_update,
    };
}

// Parse fp_update based on the Opcode value.
// # Arguments
// - opcode: Opcode of the current instruction
// # Returns
// Appropriate fp_update value
fn parsefp_update(opcode: Opcode) FpUpdate {
    return switch (opcode) {
        Opcode.Call => FpUpdate.APPlus2,
        Opcode.Ret => FpUpdate.Dst,
        else => FpUpdate.Regular,
    };
}

// Converts a biased 16-bit representation to a 16-bit signed integer.
// # Arguments
// - biased_repr: Biased representation as a 16-bit integer
// # Returns
// 16-bit signed integer
pub fn fromBiasedRepresentation(biased_repr: u16) i16 {
    const as_i32 = @as(i32, @intCast(biased_repr));
    return @as(i16, @intCast(as_i32 - 32768));
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

    try expectEqual(Register.FP, decoded_instruction.dst_reg);
    try expectEqual(Register.FP, decoded_instruction.op_0_reg);
    try expectEqual(Op1Src.Imm, decoded_instruction.op_1_addr);
    try expectEqual(ResLogic.Add, decoded_instruction.res_logic);
    try expectEqual(PcUpdate.Jump, decoded_instruction.pc_update);
    try expectEqual(ApUpdate.Add, decoded_instruction.ap_update);
    try expectEqual(Opcode.Call, decoded_instruction.opcode);
    try expectEqual(FpUpdate.APPlus2, decoded_instruction.fp_update);
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

    try expectEqual(Register.AP, decoded_instruction.dst_reg);
    try expectEqual(Register.AP, decoded_instruction.op_0_reg);
    try expectEqual(Op1Src.FP, decoded_instruction.op_1_addr);
    try expectEqual(ResLogic.Mul, decoded_instruction.res_logic);
    try expectEqual(PcUpdate.JumpRel, decoded_instruction.pc_update);
    try expectEqual(ApUpdate.Add1, decoded_instruction.ap_update);
    try expectEqual(Opcode.Ret, decoded_instruction.opcode);
    try expectEqual(FpUpdate.Dst, decoded_instruction.fp_update);
}

test "decode flags assert add jnz mul ap ap ap" {
    // 0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |ASSRT_EQ|      ADD|      JNZ|      MUL|     AP|     AP|     AP
    //  0  1  0  0      1  0   1  0  0      1  0 1  0  0       0       0
    //  0100 1010 0101 0000 = 0x4A50; offx = 0

    const encoded_instruction: u64 = 0x4A50800080008000;
    const decoded_instruction = try decode(encoded_instruction);

    try expectEqual(Register.AP, decoded_instruction.dst_reg);
    try expectEqual(Register.AP, decoded_instruction.op_0_reg);
    try expectEqual(Op1Src.AP, decoded_instruction.op_1_addr);
    try expectEqual(ResLogic.Mul, decoded_instruction.res_logic);
    try expectEqual(PcUpdate.Jnz, decoded_instruction.pc_update);
    try expectEqual(ApUpdate.Add1, decoded_instruction.ap_update);
    try expectEqual(Opcode.AssertEq, decoded_instruction.opcode);
    try expectEqual(FpUpdate.Regular, decoded_instruction.fp_update);
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

    try expectEqual(Register.AP, decoded_instruction.dst_reg);
    try expectEqual(Register.AP, decoded_instruction.op_0_reg);
    try expectEqual(Op1Src.Op0, decoded_instruction.op_1_addr);
    try expectEqual(ResLogic.Unconstrained, decoded_instruction.res_logic);
    try expectEqual(PcUpdate.Jnz, decoded_instruction.pc_update);
    try expectEqual(ApUpdate.Regular, decoded_instruction.ap_update);
    try expectEqual(Opcode.AssertEq, decoded_instruction.opcode);
    try expectEqual(FpUpdate.Regular, decoded_instruction.fp_update);
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

    try expectEqual(Register.AP, decoded_instruction.dst_reg);
    try expectEqual(Register.AP, decoded_instruction.op_0_reg);
    try expectEqual(Op1Src.Op0, decoded_instruction.op_1_addr);
    try expectEqual(ResLogic.Op1, decoded_instruction.res_logic);
    try expectEqual(PcUpdate.Regular, decoded_instruction.pc_update);
    try expectEqual(ApUpdate.Regular, decoded_instruction.ap_update);
    try expectEqual(Opcode.NOp, decoded_instruction.opcode);
    try expectEqual(FpUpdate.Regular, decoded_instruction.fp_update);
}

test "decode offset negative" {
    const encoded_instruction: u64 = 0x0000800180007FFF;
    const decoded_instruction = try decode(encoded_instruction);
    try expectEqual(@as(i16, -1), decoded_instruction.off_0);
    try expectEqual(@as(i16, 0), decoded_instruction.off_1);
    try expectEqual(@as(i16, 1), decoded_instruction.off_2);
}

test "non zero high bit" {
    const encoded_instruction: u64 = 0x94A7800080008000;
    try expectError(Error.NonZeroHighBit, decode(encoded_instruction));
}

test "invalid op1 reg" {
    const encoded_instruction: u64 = 0x294F800080008000;
    try expectError(Error.InvalidOp1Reg, decode(encoded_instruction));
}

test "invalid pc update" {
    const encoded_instruction: u64 = 0x29A8800080008000;
    try expectError(Error.Invalidpc_update, decode(encoded_instruction));
}

test "invalid res logic" {
    const encoded_instruction: u64 = 0x2968800080008000;
    try expectError(Error.Invalidres_logic, decode(encoded_instruction));
}

test "invalid opcode" {
    const encoded_instruction: u64 = 0x3948800080008000;
    try expectError(Error.InvalidOpcode, decode(encoded_instruction));
}

test "invalid ap update" {
    const encoded_instruction: u64 = 0x2D48800080008000;
    try expectError(Error.Invalidap_update, decode(encoded_instruction));
}
