// The following code is a port of Gottfried Herold's Bandersnatch library.
// https://github.com/GottfriedHerold/Bandersnatch/blob/f665f90b64892b9c4c89cff3219e70456bb431e5/bandersnatch/fieldElements/field_element_square_root.go

const std = @import("std");
const Fp = @import("fields.zig").BandersnatchFields.BaseField;

const feType_SquareRoot = Fp;

const BaseField2Adicity = 32;
const sqrtParam_TotalBits = BaseField2Adicity; // (p-1) = n^Q. 2^S with Q odd, leads to S = 32.
const sqrtParam_BlockSize = 8; // 8 bit window per chunk
const sqrtParam_Blocks = sqrtParam_TotalBits / sqrtParam_BlockSize;
const sqrtParam_FirstBlockUnusedBits = sqrtParam_Blocks * sqrtParam_BlockSize - sqrtParam_TotalBits; // number of unused bits in the first reconstructed block.
const sqrtParam_BitMask = (1 << sqrtParam_BlockSize) - 1; // bitmask to pick up the last sqrtParam_BlockSize bits.

// NOTE: These "variables" are actually pre-computed constants that must not change.
// sqrtPrecomp_PrimitiveDyadicRoots[i] equals DyadicRootOfUnity^(2^i) for 0 <= i <= 32
//
// This means that it is a 32-i'th primitive root of unitity, obtained by repeatedly squaring a 2^32th primitive root of unity [DyadicRootOfUnity_fe].
const sqrtPrecomp_PrimitiveDyadicRoots: [BaseField2Adicity + 1]feType_SquareRoot = blk: {
    @setEvalBranchQuota(35_000);

    var ret: [BaseField2Adicity + 1]feType_SquareRoot = undefined;
    ret[0] = Fp.fromInteger(10238227357739495823651030575849232062558860180284477541189508159991286009131);
    for (1..BaseField2Adicity + 1) |i| { // Note <= here
        ret[i] = Fp.square(ret[i - 1]);
    }

    if (ret[BaseField2Adicity - 1].toInteger() != Fp.Modulo - 1) {
        @compileError("something is wrong with the dyadic roots of unity");
    }

    break :blk ret;
};

// primitive root of unity of order 2^sqrtParam_BlockSize
const sqrtPrecomp_ReconstructionDyadicRoot: feType_SquareRoot = sqrtPrecomp_PrimitiveDyadicRoots[BaseField2Adicity - sqrtParam_BlockSize];

// sqrtPrecomp_PrecomputedBlocks[i][j] == g^(j << (i* BlockSize)), where g is the fixed primitive 2^32th root of unity.
// This means that the exponent is equal to 0x00000...0000jjjjjj0000....0000, where only the i'th least significant block of size BlockSize is set
// and that value is j.
//
// Note: accessed through sqrtAlg_getPrecomputedRootOfUnity
const sqrtPrecomp_PrecomputedBlocks = blk: {
    @setEvalBranchQuota(750_000);

    var blocks: [sqrtParam_Blocks][1 << sqrtParam_BlockSize]feType_SquareRoot = undefined;
    for (0..sqrtParam_Blocks) |i| {
        blocks[i][0] = Fp.one();
        for (1..1 << sqrtParam_BlockSize) |j| {
            blocks[i][j] = Fp.mul(
                blocks[i][j - 1],
                sqrtPrecomp_PrimitiveDyadicRoots[i * sqrtParam_BlockSize],
            );
        }
    }
    break :blk blocks;
};

// sqrtPrecomp_dlogLUT is a lookup table used to implement the map sqrtPrecompt_reconstructionDyadicRoot^a -> -a
const sqrtPrecomp_dlogLUT_item = struct { key: u16, value: usize };
const sqrtPrecomp_dlogLUT: [256]sqrtPrecomp_dlogLUT_item = blk: {
    @setEvalBranchQuota(300_000);

    const LUTSize = 1 << sqrtParam_BlockSize; // 256
    var ret: [256]sqrtPrecomp_dlogLUT_item = undefined;
    var rootOfUnity = Fp.one();
    var next = 0;
    for (0..LUTSize) |i| {
        // the LUTSize many roots of unity all (by chance) have distinct values for .words[0]&0xFFFF. Note that this uses the Montgomery representation.
        const idx = rootOfUnity.fe[0] & 0xFFFF;

        for (0..next) |j| {
            if (ret[j].key == idx) {
                @compileError("repeated element");
            }
        }
        ret[next] = .{ .key = idx, .value = (LUTSize - i) % LUTSize };
        rootOfUnity = Fp.mul(rootOfUnity, sqrtPrecomp_ReconstructionDyadicRoot);
        next += 1;
    }

    break :blk ret;
};

// sqrtAlg_NegDlogInSmallDyadicSubgroup takes a (not neccessarily primitive) root of unity x of order 2^sqrtParam_BlockSize.
// x has the form sqrtPrecomp_ReconstructionDyadicRoot^a and returns its negative dlog -a.
//
// The returned value is only meaningful modulo 1<<sqrtParam_BlockSize and is fully reduced, i.e. in [0, 1<<sqrtParam_BlockSize )
//
// NOTE: If x is not a root of unity as asserted, the behaviour is undefined.
fn sqrtAlg_NegDlogInSmallDyadicSubgroup(x: feType_SquareRoot) usize {
    for (sqrtPrecomp_dlogLUT) |item| {
        if (item.key == x.fe[0] & 0xFFFF) {
            return item.value;
        }
    }
    @panic("element not found in LUT");
}

// sqrtAlg_GetPrecomputedRootOfUnity sets target to g^(multiplier << (order * sqrtParam_BlockSize)), where g is the fixed primitive 2^32th root of unity.
//
// We assume that order 0 <= order*sqrtParam_BlockSize <= 32 and that multiplier is in [0, 1 <<sqrtParam_BlockSize)
fn sqrtAlg_GetPrecomputedRootOfUnity(target: *feType_SquareRoot, multiplier: usize, order: usize) void {
    target.* = sqrtPrecomp_PrecomputedBlocks[order][multiplier];
}

pub fn invSqrtEqDyadic(z: *feType_SquareRoot) bool {
    // The algorithm works by essentially computing the dlog of z and then halving it.

    // negExponent is intended to hold the negative of the dlog of z.
    // We determine this 32-bit value (usually) _sqrtBlockSize many bits at a time, starting with the least-significant bits.
    //
    // If _sqrtBlockSize does not divide 32, the *first* iteration will determine fewer bits.
    var negExponent: usize = 0;

    var temp: feType_SquareRoot = undefined;
    var temp2: feType_SquareRoot = undefined;

    // set powers[i] to z^(1<< (i*blocksize))
    var powers: [sqrtParam_Blocks]feType_SquareRoot = undefined;
    powers[0] = z.*;
    for (1..sqrtParam_Blocks) |i| {
        powers[i] = powers[i - 1];
        for (0..sqrtParam_BlockSize) |_| {
            powers[i] = Fp.square(powers[i]);
        }
    }

    // looking at the dlogs, powers[i] is essentially the wanted exponent, left-shifted by i*_sqrtBlockSize and taken mod 1<<32
    // dlogHighDyadicRootNeg essentially (up to sign) reads off the _sqrtBlockSize many most significant bits. (returned as low-order bits)

    // first iteration may be slightly special if BlockSize does not divide 32
    negExponent = sqrtAlg_NegDlogInSmallDyadicSubgroup(powers[sqrtParam_Blocks - 1]);
    negExponent >>= sqrtParam_FirstBlockUnusedBits;

    // if the exponent we just got is odd, there is no square root, no point in determining the other bits.
    if (negExponent & 1 == 1) {
        return false;
    }

    // Get remaining bits
    for (1..sqrtParam_Blocks) |i| {
        temp2 = powers[sqrtParam_Blocks - 1 - i];

        // We essentially un-set the bits we already know from powers[_sqrtNumBlocks-1-i]
        for (0..i) |j| {
            sqrtAlg_GetPrecomputedRootOfUnity(
                &temp,
                (negExponent >> @intCast(j * sqrtParam_BlockSize)) & sqrtParam_BitMask,
                (j + sqrtParam_Blocks - 1 - i),
            );
            temp2 = Fp.mul(temp2, temp);
        }

        const newBits = sqrtAlg_NegDlogInSmallDyadicSubgroup(temp2);
        negExponent |= newBits << @intCast(sqrtParam_BlockSize * i - sqrtParam_FirstBlockUnusedBits);
    }

    // var tmp _FESquareRoot

    // negExponent is now the negative dlog of z.

    // Take the square root
    negExponent >>= 1;
    // Write to z:
    z.* = Fp.one();
    for (0..sqrtParam_Blocks) |i| {
        sqrtAlg_GetPrecomputedRootOfUnity(
            &temp,
            (negExponent >> @intCast(i * sqrtParam_BlockSize)) & sqrtParam_BitMask,
            (i),
        );
        z.* = Fp.mul(z.*, temp);
    }

    return true;
}

fn SquareEqNTimes(z: *feType_SquareRoot, n: usize) void {
    for (0..n) |_| {
        z.* = Fp.square(z.*);
    }
}

pub fn sqrtAlg_ComputeRelevantPowers(
    z: feType_SquareRoot,
    squareRootCandidate: *feType_SquareRoot,
    rootOfUnity: *feType_SquareRoot,
) void {
    // hand-crafted sliding window-type algorithm with window-size 5
    // Note that we precompute and use z^255 multiple times (even though it's not size 5)
    // and some windows actually overlap(!)

    const z2 = Fp.square(z); // 0b10
    const z3 = Fp.mul(z, z2); // 0b11
    const z6 = Fp.square(z3); // 0b110
    const z7 = Fp.mul(z, z6); // 0b111
    const z9 = Fp.mul(z7, z2); // 0b1001
    const z11 = Fp.mul(z9, z2); // 0b1011
    const z13 = Fp.mul(z11, z2); // 0b1101
    const z19 = Fp.mul(z13, z6); // 0b10011
    const z21 = Fp.mul(z2, z19); // 0b10101
    const z25 = Fp.mul(z19, z6); // 0b11001
    const z27 = Fp.mul(z25, z2); // 0b11011
    const z29 = Fp.mul(z27, z2); // 0b11101
    const z31 = Fp.mul(z29, z2); // 0b11111
    var acc = Fp.mul(z27, z29); // 56
    acc = Fp.square(acc); // 112
    acc = Fp.square(acc); // 224
    const z255 = Fp.mul(acc, z31); // 0b11111111 = 255
    acc = Fp.square(acc); // 448
    acc = Fp.square(acc); // 896
    acc = Fp.mul(acc, z31); // 0b1110011111 = 927
    SquareEqNTimes(&acc, 6); // 0b1110011111000000
    acc = Fp.mul(acc, z27); // 0b1110011111011011
    SquareEqNTimes(&acc, 6); // 0b1110011111011011000000
    acc = Fp.mul(acc, z19); // 0b1110011111011011010011
    SquareEqNTimes(&acc, 5); // 0b111001111101101101001100000
    acc = Fp.mul(acc, z21); // 0b111001111101101101001110101
    SquareEqNTimes(&acc, 7); // 0b1110011111011011010011101010000000
    acc = Fp.mul(acc, z25); // 0b1110011111011011010011101010011001
    SquareEqNTimes(&acc, 6); // 0b1110011111011011010011101010011001000000
    acc = Fp.mul(acc, z19); // 0b1110011111011011010011101010011001010011
    SquareEqNTimes(&acc, 5); // 0b111001111101101101001110101001100101001100000
    acc = Fp.mul(acc, z7); // 0b111001111101101101001110101001100101001100111
    SquareEqNTimes(&acc, 5); // 0b11100111110110110100111010100110010100110011100000
    acc = Fp.mul(acc, z11); // 0b11100111110110110100111010100110010100110011101011
    SquareEqNTimes(&acc, 5); // 0b1110011111011011010011101010011001010011001110101100000
    acc = Fp.mul(acc, z29); // 0b1110011111011011010011101010011001010011001110101111101
    SquareEqNTimes(&acc, 5); // 0b111001111101101101001110101001100101001100111010111110100000
    acc = Fp.mul(acc, z9); // 0b111001111101101101001110101001100101001100111010111110101001
    SquareEqNTimes(&acc, 7); // 0b1110011111011011010011101010011001010011001110101111101010010000000
    acc = Fp.mul(acc, z3); // 0b1110011111011011010011101010011001010011001110101111101010010000011
    SquareEqNTimes(&acc, 7); // 0b11100111110110110100111010100110010100110011101011111010100100000110000000
    acc = Fp.mul(acc, z25); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001
    SquareEqNTimes(&acc, 5); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100100000
    acc = Fp.mul(acc, z25); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001
    SquareEqNTimes(&acc, 5); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100100000
    acc = Fp.mul(acc, z27); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011
    SquareEqNTimes(&acc, 8); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000000
    acc = Fp.mul(acc, z); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001
    SquareEqNTimes(&acc, 8); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000000
    acc = Fp.mul(acc, z); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001
    SquareEqNTimes(&acc, 6); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001000000
    acc = Fp.mul(acc, z13); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101
    SquareEqNTimes(&acc, 7); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000000
    acc = Fp.mul(acc, z7); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111
    SquareEqNTimes(&acc, 3); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111000
    acc = Fp.mul(acc, z3); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011
    SquareEqNTimes(&acc, 13); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000000000
    acc = Fp.mul(acc, z21); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101
    SquareEqNTimes(&acc, 5); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010100000
    acc = Fp.mul(acc, z9); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001
    SquareEqNTimes(&acc, 5); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101000011101100000000101010100100000
    acc = Fp.mul(acc, z27); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101000011101100000000101010100111011
    SquareEqNTimes(&acc, 5); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101100000
    acc = Fp.mul(acc, z27); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011
    SquareEqNTimes(&acc, 5); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001110111101100000
    acc = Fp.mul(acc, z9); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001110111101101001
    SquareEqNTimes(&acc, 10); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000000
    acc = Fp.mul(acc, z); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000001
    SquareEqNTimes(&acc, 7); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101000011101100000000101010100111011110110100100000000010000000
    acc = Fp.mul(acc, z255); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101000011101100000000101010100111011110110100100000000101111111
    SquareEqNTimes(&acc, 8); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111100000000
    acc = Fp.mul(acc, z255); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111
    SquareEqNTimes(&acc, 6); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111000000
    acc = Fp.mul(acc, z11); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011
    SquareEqNTimes(&acc, 9); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011000000000
    acc = Fp.mul(acc, z255); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011011111111
    SquareEqNTimes(&acc, 2); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001110111101101001000000001011111111111111100101101111111100
    acc = Fp.mul(acc, z); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001110111101101001000000001011111111111111100101101111111101
    SquareEqNTimes(&acc, 7); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011011111111010000000
    acc = Fp.mul(acc, z255); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011011111111101111111
    SquareEqNTimes(&acc, 8); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001110111101101001000000001011111111111111100101101111111110111111100000000
    acc = Fp.mul(acc, z255); // 0b11100111110110110100111010100110010100110011101011111010100100000110011001110011101100000001000000010011010000111011000000001010101001110111101101001000000001011111111111111100101101111111110111111111111111
    SquareEqNTimes(&acc, 8); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101000011101100000000101010100111011110110100100000000101111111111111110010110111111111011111111111111100000000
    acc = Fp.mul(acc, z255); // 0b1110011111011011010011101010011001010011001110101111101010010000011001100111001110110000000100000001001101000011101100000000101010100111011110110100100000000101111111111111110010110111111111011111111111111111111111
    SquareEqNTimes(&acc, 8); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011011111111101111111111111111111111100000000
    acc = Fp.mul(acc, z255); // 0b111001111101101101001110101001100101001100111010111110101001000001100110011100111011000000010000000100110100001110110000000010101010011101111011010010000000010111111111111111001011011111111101111111111111111111111111111111
    // acc is now z^((BaseFieldMultiplicativeOddOrder - 1)/2)
    rootOfUnity.* = Fp.square(acc); // BaseFieldMultiplicativeOddOrder - 1
    rootOfUnity.* = Fp.mul(rootOfUnity.*, z); // BaseFieldMultiplicativeOddOrder
    squareRootCandidate.* = Fp.mul(acc, z); // (BaseFieldMultiplicativeOddOrder + 1)/2
}

test "correctness" {
    for (0..1_000) |i| {
        // Take a random fp.
        var a: Fp = Fp.fromInteger(i);

        const sqrt_fast = Fp.sqrt(a);
        if (sqrt_fast == null) {
            continue;
        }

        // Check the obvious: regenNew should be equal to the original element.
        var regen_new = Fp.mul(sqrt_fast.?, sqrt_fast.?);
        try std.testing.expect(regen_new.equal(a));
    }
}
