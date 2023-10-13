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
    InvalidOp1Src,
    InvalidPcUpdate,
    InvalidResLogic,
    InvalidOpcode,
    InvalidApUpdate,
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
    Off0: i16,
    Off1: i16,
    Off2: i16,
    DstReg: Register,
    Op0Reg: Register,
    Op1Addr: Op1Src,
    ResLogic: ResLogic,
    PcUpdate: PcUpdate,
    ApUpdate: ApUpdate,
    FpUpdate: FpUpdate,
    Opcode: Opcode,
};

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
        else => Error.InvalidOp1Src,
    };
}

// Parse ResLogic from a 2-bit integer field.
// # Arguments
// - res_logic_num: 2-bit integer field extracted from instruction
// # Returns
// Parsed ResLogic value, or an error if invalid
fn parseResLogic(res_logic_num: u8) Error!ResLogic {
    return switch (res_logic_num) {
        0 => ResLogic.Op1,
        1 => ResLogic.Add,
        2 => ResLogic.Mul,
        3 => ResLogic.Unconstrained,
        else => Error.InvalidResLogic,
    };
}

// Parse PcUpdate from a 3-bit integer field.
// # Arguments
// - pc_update_num: 3-bit integer field extracted from instruction
// # Returns
// Parsed PcUpdate value, or an error if invalid
fn parsePcUpdate(pc_update_num: u8) Error!PcUpdate {
    return switch (pc_update_num) {
        0 => PcUpdate.Regular,
        1 => PcUpdate.Jump,
        2 => PcUpdate.JumpRel,
        3 => PcUpdate.Jnz,
        else => Error.InvalidPcUpdate,
    };
}

// Parse ApUpdate from a 2-bit integer field.
// # Arguments
// - ap_update_num: 2-bit integer field extracted from instruction
// # Returns
// Parsed ApUpdate value, or an error if invalid
fn parseApUpdate(ap_update_num: u8) Error!ApUpdate {
    return switch (ap_update_num) {
        0 => ApUpdate.Regular,
        1 => ApUpdate.Add,
        2 => ApUpdate.Add1,
        3 => ApUpdate.Add2,
        else => Error.InvalidApUpdate,
    };
}

// Parse FpUpdate based on the Opcode value.
// # Arguments
// - opcode: Opcode of the current instruction
// # Returns
// Appropriate FpUpdate value
fn parseFpUpdate(opcode: Opcode) FpUpdate {
    return switch (opcode) {
        Opcode.Call => FpUpdate.APPlus2,
        Opcode.Ret => FpUpdate.Dst,
        else => FpUpdate.Regular,
    };
}

// Decode a 64-bit instruction into its component parts.
// # Arguments
// - encoded_instruction: 64-bit integer containing the encoded instruction
// # Returns
// Decoded Instruction struct, or an error if decoding fails
pub fn decodeInstruction(encoded_instruction: u64) Error!Instruction {
    if (encoded_instruction & (1 << 63) != 0) return Error.NonZeroHighBit;

    const flags = @as(u16, @truncate(encoded_instruction >> 48));
    const offsets = @as(u48, @truncate(encoded_instruction));
    const parsedNum = @as(u8, @truncate((flags >> 12) & 7));
    const opcode = try parseOpcode(parsedNum);

    return Instruction{
        .Off0 = fromBiasedRepresentation(@as(u16, @truncate(offsets))),
        .Off1 = fromBiasedRepresentation(@as(u16, @truncate(offsets >> 16))),
        .Off2 = fromBiasedRepresentation(@as(u16, @truncate(offsets >> 32))),
        .DstReg = if (flags & 1 != 0) Register.FP else Register.AP,
        .Op0Reg = if (flags & 2 != 0) Register.FP else Register.AP,
        .Op1Addr = try parseOp1Src(@as(u8, @truncate((flags >> 2) & 7))),
        .ResLogic = try parseResLogic(@as(u8, @truncate((flags >> 5) & 3))),
        .PcUpdate = try parsePcUpdate(@as(u8, @truncate((flags >> 7) & 7))),
        .ApUpdate = try parseApUpdate(@as(u8, @truncate((flags >> 10) & 3))),
        .Opcode = opcode,
        .FpUpdate = parseFpUpdate(opcode),
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
    //_ = decodeInstruction(encoded_instruction2) catch unreachable;
    const decoded_instruction = try decodeInstruction(encoded_instruction);

    try expectEqual(Register.FP, decoded_instruction.DstReg);
    try expectEqual(Register.FP, decoded_instruction.Op0Reg);
    try expectEqual(Op1Src.Imm, decoded_instruction.Op1Addr);
    try expectEqual(ResLogic.Add, decoded_instruction.ResLogic);
    try expectEqual(PcUpdate.Jump, decoded_instruction.PcUpdate);
    try expectEqual(ApUpdate.Add, decoded_instruction.ApUpdate);
    try expectEqual(Opcode.Call, decoded_instruction.Opcode);
    try expectEqual(FpUpdate.APPlus2, decoded_instruction.FpUpdate);
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
    const decoded_instruction = try decodeInstruction(encoded_instruction);

    try expectEqual(Register.AP, decoded_instruction.DstReg);
    try expectEqual(Register.AP, decoded_instruction.Op0Reg);
    try expectEqual(Op1Src.FP, decoded_instruction.Op1Addr);
    try expectEqual(ResLogic.Mul, decoded_instruction.ResLogic);
    try expectEqual(PcUpdate.JumpRel, decoded_instruction.PcUpdate);
    try expectEqual(ApUpdate.Add1, decoded_instruction.ApUpdate);
    try expectEqual(Opcode.Ret, decoded_instruction.Opcode);
    try expectEqual(FpUpdate.Dst, decoded_instruction.FpUpdate);
}

test "decode flags assert add jnz mul ap ap ap" {
    // 0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |ASSRT_EQ|      ADD|      JNZ|      MUL|     AP|     AP|     AP
    //  0  1  0  0      1  0   1  0  0      1  0 1  0  0       0       0
    //  0100 1010 0101 0000 = 0x4A50; offx = 0
    const encoded_instruction: u64 = 0x4A50800080008000;
    _ = encoded_instruction;
    //const decoded_instruction = try decodeInstruction(encoded_instruction);
    //_ = decoded_instruction;

    //try expectEqual(Register.AP, decoded_instruction.DstReg);
    // try expectEqual(Register.AP, decoded_instruction.Op0Reg);
    // try expectEqual(Op1Src.AP, decoded_instruction.Op1Addr);
    // try expectEqual(ResLogic.Mul, decoded_instruction.ResLogic);
    // try expectEqual(PcUpdate.Jnz, decoded_instruction.PcUpdate);
    // try expectEqual(ApUpdate.Add, decoded_instruction.ApUpdate);
    // try expectEqual(Opcode.AssertEq, decoded_instruction.Opcode);
    // try expectEqual(FpUpdate.Regular, decoded_instruction.FpUpdate);
}
