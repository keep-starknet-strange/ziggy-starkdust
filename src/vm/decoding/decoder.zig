const Instruction = @import("../instructions.zig").Instruction;
const std = @import("std");
const CairoVMError = @import("../error.zig").CairoVMError;
const Instructions = @import("../instructions.zig");
const Register = Instructions.Register;
const PcUpdate = Instructions.PcUpdate;
const Op1Src = Instructions.Op1Src;
const ResLogic = Instructions.ResLogic;
const Opcode = Instructions.Opcode;
const FpUpdate = Instructions.FpUpdate;
const ApUpdate = Instructions.ApUpdate;

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

//  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
// 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0

/// Decodes an instruction. The encoding is little endian, so flags go from bit 63 to 48.
pub inline fn decodeInstructions(encoded_instr: u64) !Instruction {
    const HIGH_BIT: u64 = 1 << 63;
    const DST_REG_MASK: u64 = 0x0001;
    const DST_REG_OFF: u64 = 0;
    const OP0_REG_MASK: u64 = 0x0002;
    const OP0_REG_OFF: u64 = 1;
    const OP1_SRC_MASK: u64 = 0x001C;
    const OP1_SRC_OFF: u64 = 2;
    const RES_LOGIC_MASK: u64 = 0x0060;
    const RES_LOGIC_OFF: u64 = 5;
    const PC_UPDATE_MASK: u64 = 0x0380;
    const PC_UPDATE_OFF: u64 = 7;
    const AP_UPDATE_MASK: u64 = 0x0C00;
    const AP_UPDATE_OFF: u64 = 10;
    const OPCODE_MASK: u64 = 0x7000;
    const OPCODE_OFF: u64 = 12;

    // Flags start on the 48th bit.
    const FLAGS_OFFSET: u64 = 48;
    const OFF0_OFF: u64 = 0;
    const OFF1_OFF: u64 = 16;
    const OFF2_OFF: u64 = 32;
    const OFFX_MASK: u64 = 0xFFFF;

    if (encoded_instr & HIGH_BIT != 0)
        return CairoVMError.InstructionNonZeroHighBit;

    // Grab flags
    const flags = encoded_instr >> FLAGS_OFFSET;

    // Grab individual flags
    const dst_reg_num = (flags & DST_REG_MASK) >> DST_REG_OFF;
    const op0_reg_num = (flags & OP0_REG_MASK) >> OP0_REG_OFF;
    const op1_src_num = (flags & OP1_SRC_MASK) >> OP1_SRC_OFF;

    const res_logic_num = (flags & RES_LOGIC_MASK) >> RES_LOGIC_OFF;
    const pc_update_num = (flags & PC_UPDATE_MASK) >> PC_UPDATE_OFF;
    const ap_update_num = (flags & AP_UPDATE_MASK) >> AP_UPDATE_OFF;
    const opcode_num = (flags & OPCODE_MASK) >> OPCODE_OFF;

    const pc_update: PcUpdate = switch (pc_update_num) {
        0 => .Regular,
        1 => .Jump,
        2 => .JumpRel,
        4 => .Jnz,
        else => return CairoVMError.InvalidPcUpdate,
    };

    const opcode: Opcode = switch (opcode_num) {
        0 => .NOp,
        1 => .Call,
        2 => .Ret,
        4 => .AssertEq,
        else => return CairoVMError.InvalidOpcode,
    };

    return .{
        .off_0 = try decodeOffset(encoded_instr >> OFF0_OFF & OFFX_MASK),
        .off_1 = try decodeOffset(encoded_instr >> OFF1_OFF & OFFX_MASK),
        .off_2 = try decodeOffset(encoded_instr >> OFF2_OFF & OFFX_MASK),
        .dst_reg = switch (dst_reg_num) {
            1 => .FP,
            else => .AP,
        },
        .op_0_reg = switch (op0_reg_num) {
            1 => .FP,
            else => .AP,
        },
        .op_1_addr = switch (op1_src_num) {
            0 => .Op0,
            1 => .Imm,
            2 => .FP,
            4 => .AP,
            else => return CairoVMError.InvalidOp1Reg,
        },
        .res_logic = switch (res_logic_num) {
            0 => if (pc_update == .Jnz) .Unconstrained else .Op1,
            1 => .Add,
            2 => .Mul,
            else => return CairoVMError.InvalidResLogic,
        },
        .pc_update = pc_update,
        .ap_update = switch (ap_update_num) {
            0 => if (opcode == .Call) .Add2 else .Regular,
            1 => .Add,
            2 => .Add1,
            else => return CairoVMError.InvalidApUpdate,
        },
        .fp_update = switch (opcode) {
            .Call => .APPlus2,
            .Ret => .Dst,
            else => .Regular,
        },
        .opcode = opcode,
    };
}

pub fn decodeOffset(offset: u64) !i16 {
    var vectorized_offset: [8]u8 = std.mem.toBytes(offset);
    return @bitCast(
        @subWithOverflow(
            std.mem.readInt(u16, vectorized_offset[0..2], .little),
            0x8000,
        )[0],
    );
}

test "decodeInstructions: non-zero high bit" {
    try expectError(CairoVMError.InstructionNonZeroHighBit, decodeInstructions(0x94A7800080008000));
}

test "decodeInstructions: invalid op register" {
    try expectError(CairoVMError.InvalidOp1Reg, decodeInstructions(0x294F800080008000));
}

test "decodeInstructions: invalid pc update" {
    try expectError(CairoVMError.InvalidPcUpdate, decodeInstructions(0x29A8800080008000));
}

test "decodeInstructions: invalid res logic" {
    try expectError(CairoVMError.InvalidResLogic, decodeInstructions(0x2968800080008000));
}

test "decodeInstructions: invalid opcode" {
    try expectError(CairoVMError.InvalidOpcode, decodeInstructions(0x3948800080008000));
}

test "decodeInstructions: invalid ap update" {
    try expectError(CairoVMError.InvalidApUpdate, decodeInstructions(0x2D48800080008000));
}

test "decodeInstructions: decode flags call add jmp add imm fp fp" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |    CALL|      ADD|     JUMP|      ADD|    IMM|     FP|     FP
    //  0  0  0  1      0  1   0  0  1      0  1 0  0  1       1       1
    //  0001 0100 1010 0111 = 0x14A7; offx = 0

    const inst = try decodeInstructions(0x14A7800080008000);

    try expectEqual(inst.dst_reg, Register.FP);
    try expectEqual(inst.op_0_reg, Register.FP);
    try expectEqual(inst.op_1_addr, Op1Src.Imm);
    try expectEqual(inst.res_logic, ResLogic.Add);
    try expectEqual(inst.pc_update, PcUpdate.Jump);
    try expectEqual(inst.ap_update, ApUpdate.Add);
    try expectEqual(inst.opcode, Opcode.Call);
    try expectEqual(inst.fp_update, FpUpdate.APPlus2);
}

test "decodeInstructions: decode flags ret add1 jmp rel mul fp ap ap" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |     RET|     ADD1|   JUMP_REL|      MUL|     AP|     AP|     FP
    //  0  0  1  0      0  1   0  1  0      1  0 0  1  1       0       1
    //  0010 0101 1011 0110 = 0x25B6; offx = 0

    const inst = try decodeInstructions(0x2948800080008000);

    try expectEqual(inst.dst_reg, Register.AP);
    try expectEqual(inst.op_0_reg, Register.AP);
    try expectEqual(inst.op_1_addr, Op1Src.FP);
    try expectEqual(inst.res_logic, ResLogic.Mul);
    try expectEqual(inst.pc_update, PcUpdate.JumpRel);
    try expectEqual(inst.ap_update, ApUpdate.Add1);
    try expectEqual(inst.opcode, Opcode.Ret);
    try expectEqual(inst.fp_update, FpUpdate.Dst);
}

test "decodeInstructions: decode flags assrt add jnz mul ap ap ap" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |ASSERT_EQ|      ADD|      JNZ|      MUL|     AP|     AP|     AP
    //  0  1  0  0      0  1   1  0  0      1  0 0  1  1       0       0
    //  0100 1101 1010 0110 = 0x4DA6; offx = 0

    const inst = try decodeInstructions(0x4A50800080008000);

    try expectEqual(inst.dst_reg, Register.AP);
    try expectEqual(inst.op_0_reg, Register.AP);
    try expectEqual(inst.op_1_addr, Op1Src.AP);
    try expectEqual(inst.res_logic, ResLogic.Mul);
    try expectEqual(inst.pc_update, PcUpdate.Jnz);
    try expectEqual(inst.ap_update, ApUpdate.Add1);
    try expectEqual(inst.opcode, Opcode.AssertEq);
    try expectEqual(inst.fp_update, FpUpdate.Regular);
}

test "decodeInstructions: decode flags assrt add2 jnz uncon op0 ap ap" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |ASSRT_EQ|     REGULAR|      JNZ|UNCONSTRD|    OP0|     AP|     AP
    //  0  1  0  0      0  0   1  0  0      0  0 0  0
    //  0100 0010 0000 0000 = 0x4200; offx = 0

    const inst = try decodeInstructions(0x4200800080008000);

    try expectEqual(inst.dst_reg, Register.AP);
    try expectEqual(inst.op_0_reg, Register.AP);
    try expectEqual(inst.op_1_addr, Op1Src.Op0);
    try expectEqual(inst.res_logic, ResLogic.Unconstrained);
    try expectEqual(inst.pc_update, PcUpdate.Jnz);
    try expectEqual(inst.ap_update, ApUpdate.Regular);
    try expectEqual(inst.opcode, Opcode.AssertEq);
    try expectEqual(inst.fp_update, FpUpdate.Regular);
}

test "decodeInstructions: decode flags nop regu regu op1 op0 ap ap" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |     NOP|  REGULAR|  REGULAR|      OP1|    OP0|     AP|     AP
    //  0  0  0  0      0  0   0  0  0      0  0 0  0  0       0       0
    //  0000 0000 0000 0000 = 0x0000; offx = 0

    const inst = try decodeInstructions(0x0000800080008000);

    try expectEqual(inst.dst_reg, Register.AP);
    try expectEqual(inst.op_0_reg, Register.AP);
    try expectEqual(inst.op_1_addr, Op1Src.Op0);
    try expectEqual(inst.res_logic, ResLogic.Op1);
    try expectEqual(inst.pc_update, PcUpdate.Regular);
    try expectEqual(inst.ap_update, ApUpdate.Regular);
    try expectEqual(inst.opcode, Opcode.NOp);
    try expectEqual(inst.fp_update, FpUpdate.Regular);
}

test "decodeInstructions: decode offset negative" {
    //  0|  opcode|ap_update|pc_update|res_logic|op1_src|op0_reg|dst_reg
    // 15|14 13 12|    11 10|  9  8  7|     6  5|4  3  2|      1|      0
    //   |     NOP|  REGULAR|  REGULAR|      OP1|    OP0|     AP|     AP
    //  0  0  0  0      0  0   0  0  0      0  0 0  0  0       0       0
    //  0000 0000 0000 0000 = 0x0000; offx = 0

    const inst = try decodeInstructions(0x0000800180007FFF);

    try expectEqual(inst.off_0, -1);
    try expectEqual(inst.off_1, 0);
    try expectEqual(inst.off_2, 1);
}
