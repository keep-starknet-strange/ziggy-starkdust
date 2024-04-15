const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;

const helper = @import("helper.zig");
const tonelliShanks = helper.tonelliShanks;
const extendedGCD = helper.extendedGCD;

const fromBigInt = @import("starknet.zig").fromBigInt;

const Int = std.math.big.int.Managed;

pub const ModSqrtError = error{
    InvalidInput,
};

pub const STARKNET_PRIME: u256 = @import("../../math/fields/constants.zig").STARKNET_PRIME;
pub const SIGNED_FELT_MAX: u256 = STARKNET_PRIME >> @as(u32, 1);

/// Represents a finite field element.
pub fn Field(comptime F: type, comptime modulo: u256) type {
    return struct {
        const Self = @This();

        /// Number of bits needed to represent a field element with the given modulo.
        pub const BitSize = @bitSizeOf(u256) - @clz(modulo);
        /// Number of bytes required to store a field element.
        pub const BytesSize = @sizeOf(u256);
        /// The modulo value representing the finite field.
        pub const Modulo = modulo;
        /// Half of the modulo value (Modulo - 1) divided by 2.
        pub const QMinOneDiv2 = (Modulo - 1) / 2;
        /// The number of bits in each limb (typically 64 for u64).
        pub const Bits: usize = 64;
        /// Bit mask for the last limb.
        pub const Mask: u64 = mask(Bits);
        /// Number of limbs used to represent a field element.
        pub const Limbs: usize = 4;
        /// The smallest value that can be represented by this integer type.
        pub const Min = Self.zero();
        /// The largest value that can be represented by this integer type.
        pub const Max: Self = Self.fromInt(u256, modulo - 1);

        const base_zero = val: {
            var bz: F.MontgomeryDomainFieldElement = undefined;
            F.fromBytes(
                &bz,
                [_]u8{0} ** BytesSize,
            );
            break :val .{ .fe = bz };
        };

        const base_one = val: {
            break :val .{
                .fe = [4]u64{
                    18446744073709551585,
                    18446744073709551615,
                    18446744073709551615,
                    576460752303422960,
                },
            };
        };

        pub const base_two = val: {
            break :val .{
                .fe = [4]u64{
                    18446744073709551553,
                    18446744073709551615,
                    18446744073709551615,
                    576460752303422416,
                },
            };
        };

        pub const base_three = val: {
            break :val .{
                .fe = [4]u64{
                    18446744073709551521,
                    18446744073709551615,
                    18446744073709551615,
                    576460752303421872,
                },
            };
        };

        fe: F.MontgomeryDomainFieldElement,

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            return std.fmt.format(writer, "Felt({any})", .{self.toInteger()});
        }

        /// Mask to apply to the highest limb to get the correct number of bits.
        pub fn mask(bits: usize) u64 {
            return switch (bits) {
                0 => 0,
                else => switch (@mod(bits, 64)) {
                    0 => std.math.maxInt(u64),
                    else => |b| std.math.shl(u64, 1, b) - 1,
                },
            };
        }

        /// Creates a `Field` element from an integer of type `T`. The resulting field element is
        /// in Montgomery form. This function handles conversion for integers of various sizes,
        /// ensuring compatibility with the defined finite field (`Field`) and its modulo value.
        ///
        /// # Arguments:
        /// - `T`: The type of the integer value.
        /// - `num`: The integer value to create the `Field` element from.
        ///
        /// # Returns:
        /// A new `Field` element in Montgomery form representing the converted integer.
        pub fn fromInt(comptime T: type, num: T) Self {
            var mont: F.MontgomeryDomainFieldElement = undefined;
            std.debug.assert(num >= 0);
            switch (@typeInfo(T).Int.bits) {
                0...63 => F.toMontgomery(&mont, [_]u64{ @intCast(num), 0, 0, 0 }),
                64 => F.toMontgomery(&mont, [_]u64{ num, 0, 0, 0 }),
                65...128 => F.toMontgomery(
                    &mont,
                    [_]u64{
                        @truncate(
                            @mod(
                                num,
                                @as(u128, @intCast(std.math.maxInt(u64))) + 1,
                            ),
                        ),
                        @truncate(
                            @divTrunc(
                                num,
                                @as(u128, @intCast(std.math.maxInt(u64))) + 1,
                            ),
                        ),
                        0,
                        0,
                    },
                ),
                else => {
                    var lbe: [BytesSize]u8 = [_]u8{0} ** BytesSize;
                    std.mem.writeInt(
                        u256,
                        lbe[0..],
                        @as(u256, @intCast(num % Modulo)),
                        .little,
                    );
                    var nonMont: F.NonMontgomeryDomainFieldElement = undefined;
                    F.fromBytes(
                        &nonMont,
                        lbe,
                    );
                    F.toMontgomery(
                        &mont,
                        nonMont,
                    );
                },
            }

            return .{ .fe = mont };
        }

        /// Get the field element representing zero.
        ///
        /// Returns a field element with a value of zero.
        pub inline fn zero() Self {
            return base_zero;
        }

        /// Get the field element representing one.
        ///
        /// Returns a field element with a value of one.
        pub inline fn one() Self {
            return base_one;
        }

        /// Get the field element representing two.
        ///
        /// Returns a field element with a value of two.
        pub inline fn two() Self {
            return base_two;
        }

        /// Get the field element representing three.
        ///
        /// Returns a field element with a value of three.
        pub inline fn three() Self {
            return base_three;
        }

        /// Create a field element from a byte array.
        ///
        /// Converts a byte array into a field element in Montgomery representation.
        pub fn fromBytes(bytes: [BytesSize]u8) Self {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            inline for (0..4) |i| {
                non_mont[i] = std.mem.readInt(
                    u64,
                    bytes[i * 8 .. (i + 1) * 8],
                    .little,
                );
            }
            var ret: Self = undefined;
            F.toMontgomery(
                &ret.fe,
                non_mont,
            );

            return ret;
        }

        /// Create a field element from a byte array.
        ///
        /// Converts a byte array into a field element in Montgomery representation.
        pub fn fromBytesBe(bytes: [BytesSize]u8) Self {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            inline for (0..4) |i| {
                non_mont[3 - i] = std.mem.readInt(
                    u64,
                    bytes[i * 8 .. (i + 1) * 8],
                    .big,
                );
            }
            var ret: Self = undefined;
            F.toMontgomery(
                &ret.fe,
                non_mont,
            );

            return ret;
        }

        /// Convert the field element to a bits little endian array.
        ///
        /// This function converts the field element to a byte array for serialization.
        pub fn toBitsLe(self: Self) [@bitSizeOf(u256)]bool {
            var bits = [_]bool{false} ** @bitSizeOf(u256);
            const nmself = self.fromMontgomery();

            for (0..4) |ind_element| {
                for (0..64) |ind_bit| {
                    bits[ind_element * 64 + ind_bit] = (nmself[ind_element] >> @intCast(ind_bit)) & 1 == 1;
                }
            }

            return bits;
        }

        /// Convert the field element to a byte array.
        ///
        /// This function converts the field element to a byte array for serialization.
        pub fn toBytes(self: Self) [BytesSize]u8 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(
                &non_mont,
                self.fe,
            );
            var ret: [BytesSize]u8 = undefined;
            inline for (0..4) |i| {
                std.mem.writeInt(
                    u64,
                    ret[i * 8 .. (i + 1) * 8],
                    non_mont[i],
                    .little,
                );
            }

            return ret;
        }

        /// Convert `self`'s representative into an array of `u64` digits,
        /// least significant digits first.
        pub fn toLeDigits(self: Self) [4]u64 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(
                &non_mont,
                self.fe,
            );

            return non_mont;
        }

        /// Convert the field element to a big-endian byte array.
        ///
        /// This function converts the field element to a big-endian byte array for serialization.
        pub fn toBytesBe(self: Self) [BytesSize]u8 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(
                &non_mont,
                self.fe,
            );
            var ret: [BytesSize]u8 = undefined;
            inline for (0..4) |i| {
                std.mem.writeInt(
                    u64,
                    ret[i * 8 .. (i + 1) * 8],
                    non_mont[3 - i],
                    .big,
                );
            }

            return ret;
        }

        /// Get the min number of bits needed to field element.
        ///
        /// Returns number of bits needed.
        pub fn numBits(self: Self) u64 {
            const nmself = self.fromMontgomery();
            var num_bits: u64 = 0;
            for (0..4) |i| {
                if (nmself[3 - i] != 0) {
                    num_bits = (4 - i) * @bitSizeOf(u64) - @clz(nmself[3 - i]);
                    break;
                }
            }
            return num_bits;
        }

        /// Check if the field element is lexicographically largest.
        ///
        /// Determines whether the field element is larger than half of the field's modulus.
        pub fn lexographicallyLargest(self: Self) bool {
            return self.toInteger() > QMinOneDiv2;
        }

        /// Convert the field element to its non-Montgomery representation.
        ///
        /// Converts a field element from Montgomery form to non-Montgomery representation.
        pub fn fromMontgomery(self: Self) F.NonMontgomeryDomainFieldElement {
            var nonMont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(
                &nonMont,
                self.fe,
            );
            return nonMont;
        }

        /// Add two field elements.
        ///
        /// Adds the current field element to another field element.
        pub fn add(
            self: Self,
            other: Self,
        ) Self {
            var ret: F.NonMontgomeryDomainFieldElement = undefined;
            F.add(
                &ret,
                self.fe,
                other.fe,
            );
            return .{ .fe = ret };
        }

        /// Calculating mod sqrt
        /// TODO: add precomution?
        pub fn sqrt(
            elem: Self,
        ) ?Self {
            const a = elem.toInteger();

            const v = tonelliShanks(@intCast(a), @intCast(modulo));
            if (v[2]) {
                return Self.fromInt(u256, @intCast(v[0]));
            }

            return null;
        }

        /// Subtract one field element from another.
        ///
        /// Subtracts another field element from the current field element.
        pub fn sub(
            self: Self,
            other: Self,
        ) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.sub(
                &ret,
                self.fe,
                other.fe,
            );
            return .{ .fe = ret };
        }

        pub fn mod(
            self: Self,
            other: Self,
        ) Self {
            return Self.fromInt(u256, @mod(self.toInteger(), other.toInteger()));
        }

        // multiply two field elements and return the result modulo the modulus
        // support overflowed multiplication
        pub fn mulModFloor(
            self: Self,
            other: Self,
            modulus: Self,
        ) Self {
            const s: u512 = @intCast(self.toInteger());
            const o: u512 = @intCast(other.toInteger());
            const m: u512 = @intCast(modulus.toInteger());

            return Self.fromInt(u256, @intCast((s * o) % m));
        }

        /// Multiply two field elements.
        ///
        /// Multiplies the current field element by another field element.
        pub fn mul(
            self: Self,
            other: Self,
        ) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.mul(
                &ret,
                self.fe,
                other.fe,
            );
            return .{ .fe = ret };
        }

        /// Multiply a field element by 5.
        ///
        /// Multiplies the current field element by the constant 5.
        pub fn mulBy5(self: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.add(
                &ret,
                self.fe,
                self.fe,
            );
            F.add(
                &ret,
                ret,
                ret,
            );
            F.add(
                &ret,
                ret,
                self.fe,
            );
            return .{ .fe = ret };
        }

        /// Negate a field element.
        ///
        /// Negates the value of the current field element.
        pub fn neg(self: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.sub(
                &ret,
                base_zero.fe,
                self.fe,
            );
            return .{ .fe = ret };
        }

        /// Check if the field element is zero.
        ///
        /// Determines if the current field element is equal to zero.
        pub fn isZero(self: Self) bool {
            return self.equal(base_zero);
        }

        /// Check if the field element is one.
        ///
        /// Determines if the current field element is equal to one.
        pub fn isOne(self: Self) bool {
            return self.equal(one());
        }

        pub fn modInverse(operand: Self, modulus: Self) !Self {
            const ext = extendedGCD(i256, @bitCast(operand.toInteger()), @bitCast(modulus.toInteger()));

            if (ext.gcd != 1) {
                @panic("GCD must be one");
            }

            const result = if (ext.x < 0)
                ext.x + @as(i256, @bitCast(modulus.toInteger()))
            else
                ext.x;

            return Self.fromInt(u256, @bitCast(result));
        }

        /// Calculate the square of a field element.
        ///
        /// Computes the square of the current field element.
        pub fn square(self: Self) Self {
            return self.mul(self);
        }

        pub fn pow2Const(comptime exponent: u32) Self {
            var base = Self.one();

            inline for (exponent) |_| {
                base = base.mul(Self.two());
            }

            return base;
        }

        /// Raise a field element to a power of 2.
        ///
        /// Computes the current field element raised to the power of 2 to the `exponent` power.
        /// The result is equivalent to repeatedly squaring the field element.
        pub fn pow2(
            self: Self,
            comptime exponent: u8,
        ) Self {
            var ret = self;
            inline for (exponent) |_| {
                ret = ret.mul(ret);
            }
            return ret;
        }

        /// Raise a field element to a general power.
        ///
        /// Computes the field element raised to a general power specified by the `exponent`.
        pub fn pow(
            self: Self,
            exponent: u256,
        ) Self {
            var res = one();
            var exp = exponent;
            var base = self;

            while (exp > 0) : (exp = exp / 2) {
                if (exp & 1 == 1) {
                    res = res.mul(base);
                }
                base = base.mul(base);
            }
            return res;
        }

        /// Bitor operation
        pub fn bitOr(self: Self, other: Self) Self {
            return Self.fromInt(u256, self.toInteger() | other.toInteger());
        }

        /// Bitand operation
        pub fn bitAnd(self: Self, other: Self) Self {
            return Self.fromInt(u256, self.toInteger() & other.toInteger());
        }

        /// Batch inversion of multiple field elements.
        ///
        /// Performs batch inversion of a slice of field elements in place.
        pub fn batchInv(
            out: []Self,
            in: []const Self,
        ) !void {
            std.debug.assert(out.len == in.len);

            var acc = one();
            for (0..in.len) |i| {
                out[i] = acc;
                acc = mul(
                    acc,
                    in[i],
                );
            }
            acc = acc.inv() orelse return error.CantInvertZeroElement;
            for (0..in.len) |i| {
                out[in.len - i - 1] = mul(
                    out[in.len - i - 1],
                    acc,
                );
                acc = mul(
                    acc,
                    in[in.len - i - 1],
                );
            }
        }

        /// Calculate the multiplicative inverse of a field element.
        ///
        /// Computes the multiplicative inverse of the current field element.
        pub fn inv(self: Self) ?Self {
            var r: u256 = Modulo;
            var t: i512 = 0;

            var newr: u256 = self.toInteger();
            var newt: i512 = 1;

            while (newr != 0) {
                const quotient = r / newr;
                const tempt = t - quotient * newt;
                const tempr = r - quotient * newr;

                r = newr;
                t = newt;
                newr = tempr;
                newt = tempt;
            }

            // Not invertible
            if (r > 1) {
                return null;
            }

            if (t < 0) {
                t = t + Modulo;
            }

            return Self.fromInt(u256, @intCast(t));
        }

        /// Quotient and remainder between `self` and `rhs`.
        pub fn divRem(
            self: Self,
            rhs: Self,
        ) !struct { q: Self, r: Self } {
            const qr = try helper.divRem(u256, self.toInteger(), rhs.toInteger());

            return .{
                .q = Self.fromInt(u256, qr[0]),
                .r = Self.fromInt(u256, qr[1]),
            };
        }

        /// Divide one field element by another.
        ///
        /// Divides the current field element by another field element.
        pub fn div(
            self: Self,
            den: Self,
        ) !Self {
            const den_inv = den.inv() orelse return error.DivisionByZero;
            return self.mul(den_inv);
        }

        /// Check if two field elements are equal.
        ///
        /// Determines whether the current field element is equal to another field element.
        pub fn equal(
            self: Self,
            other: Self,
        ) bool {
            return std.mem.eql(
                u64,
                &self.fe,
                &other.fe,
            );
        }

        /// Convert int to Field type, without FIELD max check overflow
        pub fn fromSignedInt(value: anytype) Self {
            if (value > 0) {
                return Self.fromInt(u256, @intCast(value));
            }

            return Self.fromInt(u256, @intCast(-value)).neg();
        }

        pub fn toSignedBigInt(self: Self, allocator: std.mem.Allocator) !std.math.big.int.Managed {
            return std.math.big.int.Managed.initSet(allocator, self.toSignedInt());
        }

        // converting felt to abs value with sign, in (- FIELD / 2, FIELD / 2
        pub fn toSignedInt(self: Self) i256 {
            const val = self.toInteger();
            if (val > SIGNED_FELT_MAX) {
                return -@as(i256, @intCast(STARKNET_PRIME - val));
            }

            return @intCast(val);
        }
        /// Convert the field element to a u256 integer.
        ///
        /// Converts the field element to a u256 integer.
        pub fn toInteger(self: Self) u256 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(
                &non_mont,
                self.fe,
            );

            var bytes: [BytesSize]u8 = [_]u8{0} ** BytesSize;
            F.toBytes(
                &bytes,
                non_mont,
            );

            return std.mem.readInt(
                u256,
                &bytes,
                std.builtin.Endian.little,
            );
        }

        /// Try to convert the field element to a usize if its value is small enough.
        ///
        /// Attempts to convert the field element to a usize if its value is within the representable range.
        pub fn intoUsize(self: Self) !usize {
            const asU256 = self.toInteger();
            // Check if the value is small enough to fit into a usize
            if (asU256 > @as(
                u256,
                @intCast(std.math.maxInt(usize)),
            )) {
                return error.ValueTooLarge;
            }

            // Otherwise, it's safe to cast
            return @intCast(asU256);
        }

        /// Try to convert the field element to a u64 if its value is small enough.
        ///
        /// Attempts to convert the field element to a u64 if its value is within the representable range.
        pub fn intoU64(self: Self) !u64 {
            const asU256 = self.toInteger();
            // Check if the value is small enough to fit into a u64
            if (asU256 > @as(
                u256,
                @intCast(std.math.maxInt(u64)),
            )) {
                return error.ValueTooLarge;
            }

            // Otherwise, it's safe to cast
            return @as(
                u64,
                @intCast(asU256),
            );
        }

        /// Calculate the Legendre symbol of a field element.
        ///
        /// Computes the Legendre symbol of the field element using Euler's criterion.
        pub fn legendre(a: Self) i2 {
            // Compute the Legendre symbol a|p using
            // Euler's criterion. p is a prime, a is
            // relatively prime to p (if p divides
            // a, then a|p = 0)
            // Returns 1 if a has a square root modulo
            // p, -1 otherwise.
            const ls = a.pow((Modulo - 1) / 2);

            const modulo_minus_one = comptime fromInt(u256, Modulo - 1);
            if (ls.equal(modulo_minus_one)) {
                return -1;
            } else if (ls.isZero()) {
                return 0;
            }
            return 1;
        }

        /// Compare two field elements and return the ordering result.
        ///
        /// # Parameters
        /// - `self` - The first field element to compare.
        /// - `other` - The second field element to compare.
        ///
        /// # Returns
        /// A `std.math.Order` enum indicating the ordering relationship.
        pub fn cmp(self: Self, other: Self) std.math.Order {
            var a_non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            var b_non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(
                &a_non_mont,
                self.fe,
            );
            F.fromMontgomery(
                &b_non_mont,
                other.fe,
            );
            _ = std.mem.reverse(u64, a_non_mont[0..]);
            _ = std.mem.reverse(u64, b_non_mont[0..]);
            return std.mem.order(
                u64,
                &a_non_mont,
                &b_non_mont,
            );
        }

        /// Check if this field element is less than the other.
        ///
        /// # Parameters
        /// - `self` - The field element to check.
        /// - `other` - The field element to compare against.
        ///
        /// # Returns
        /// `true` if `self` is less than `other`, `false` otherwise.
        pub fn lt(self: Self, other: Self) bool {
            return switch (self.cmp(other)) {
                .lt => true,
                else => false,
            };
        }

        /// Check if this field element is less than or equal to the other.
        ///
        /// # Parameters
        /// - `self` - The field element to check.
        /// - `other` - The field element to compare against.
        ///
        /// # Returns
        /// `true` if `self` is less than or equal to `other`, `false` otherwise.
        pub fn le(self: Self, other: Self) bool {
            return switch (self.cmp(other)) {
                .lt, .eq => true,
                else => false,
            };
        }

        /// Check if this field element is greater than the other.
        ///
        /// # Parameters
        /// - `self` - The field element to check.
        /// - `other` - The field element to compare against.
        ///
        /// # Returns
        /// `true` if `self` is greater than `other`, `false` otherwise.
        pub fn gt(self: Self, other: Self) bool {
            return switch (self.cmp(other)) {
                .gt => true,
                else => false,
            };
        }

        /// Check if this field element is greater than or equal to the other.
        ///
        /// # Parameters
        /// - `self` - The field element to check.
        /// - `other` - The field element to compare against.
        ///
        /// # Returns
        /// `true` if `self` is greater than or equal to `other`, `false` otherwise.
        pub fn ge(self: Self, other: Self) bool {
            return switch (self.cmp(other)) {
                .gt, .eq => true,
                else => false,
            };
        }

        pub fn shl(self: Self, other: u8) Self {
            return Self.fromInt(u256, self.toInteger() << other);
        }

        /// Left shift by `rhs` bits with overflow detection.
        ///
        /// This function shifts the value left by `rhs` bits and detects overflow.
        /// It returns the result of the shift and a boolean indicating whether overflow occurred.
        ///
        /// If the product $\mod{\mathtt{value} ⋅ 2^{\mathtt{rhs}}}_{2^{\mathtt{BITS}}}$ is greater than or equal to 2^BITS, it returns true.
        /// In other words, it returns true if the bits shifted out are non-zero.
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift left.
        ///
        /// # Returns
        ///
        /// A tuple containing the shifted value and a boolean indicating overflow.
        pub fn overflowing_shl(
            self: Self,
            rhs: usize,
        ) std.meta.Tuple(&.{ Self, bool }) {
            const limbs = rhs / 64;
            const bits = @mod(rhs, 64);

            if (limbs >= Limbs) {
                return .{
                    Self.zero(),
                    !self.equal(Self.zero()),
                };
            }
            var res = self;
            if (bits == 0) {
                // Check for overflow
                var overflow = false;
                for (Limbs - limbs..Limbs) |i| {
                    overflow = overflow or (res.fe[i] != 0);
                }
                if (res.fe[Limbs - limbs - 1] > Self.Mask) {
                    overflow = true;
                }

                // Shift
                var idx = Limbs - 1;
                while (idx >= limbs) : (idx -= 1) {
                    res.fe[idx] = res.fe[idx - limbs];
                }
                for (0..limbs) |i| {
                    res.fe[i] = 0;
                }
                res.fe[Limbs - 1] &= Self.Mask;
                return .{ res, overflow };
            }

            // Check for overflow
            var overflow = false;
            for (Limbs - limbs..Limbs) |i| {
                overflow = overflow or (res.fe[i] != 0);
            }

            if (std.math.shr(
                u64,
                res.fe[Limbs - limbs - 1],
                64 - bits,
            ) != 0) {
                overflow = true;
            }
            if (std.math.shl(
                u64,
                res.fe[Limbs - limbs - 1],
                bits,
            ) > Self.Mask) {
                overflow = true;
            }

            // Shift
            var idx = Limbs - 1;
            while (idx > limbs) : (idx -= 1) {
                res.fe[idx] = std.math.shl(
                    u64,
                    res.fe[idx - limbs],
                    bits,
                ) | std.math.shr(
                    u64,
                    res.fe[idx - limbs - 1],
                    64 - bits,
                );
            }

            res.fe[limbs] = std.math.shl(
                u64,
                res.fe[0],
                bits,
            );
            for (0..limbs) |i| {
                res.fe[i] = 0;
            }
            res.fe[Limbs - 1] &= Self.Mask;
            return .{ res, overflow };
        }

        /// Left shift by `rhs` bits with wrapping behavior.
        ///
        /// This function shifts the value left by `rhs` bits, and it wraps around if an overflow occurs.
        /// It returns the result of the shift.
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift left.
        ///
        /// # Returns
        ///
        /// The shifted value with wrapping behavior.
        pub fn wrapping_shl(self: Self, rhs: usize) Self {
            return self.overflowing_shl(rhs)[0];
        }

        /// Left shift by `rhs` bits with saturation.
        ///
        /// This function shifts the value left by `rhs` bits with saturation behavior.
        /// If an overflow occurs, it returns `Self.Max`, otherwise, it returns the result of the shift.
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift left.
        ///
        /// # Returns
        ///
        /// The shifted value with saturation behavior, or `Self.Max` on overflow.
        pub fn saturating_shl(self: Self, rhs: usize) Self {
            const _shl = self.overflowing_shl(rhs);
            return switch (_shl[1]) {
                false => _shl[0],
                else => Self.Max,
            };
        }

        /// Checked left shift by `rhs` bits.
        ///
        /// This function performs a left shift of `self` by `rhs` bits. It returns `Some(value)` if the result is less than `2^BITS`, where `value` is the shifted result. If the result
        /// would be greater than or equal to `2^BITS`, it returns [`null`], indicating an overflow condition where the shifted-out bits would be non-zero.
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift left.
        ///
        /// # Returns
        ///
        /// - `Some(value)`: The shifted value if no overflow occurs.
        /// - [`null`]: If the bits shifted out would be non-zero.
        pub fn checked_shl(self: Self, rhs: usize) ?Self {
            const _shl = self.overflowing_shl(rhs);
            return switch (_shl[1]) {
                false => _shl[0],
                else => null,
            };
        }

        /// Right shift by `rhs` bits with underflow detection.
        ///
        /// This function performs a right shift of `self` by `rhs` bits. It returns the
        /// floor value of the division $\floor{\frac{\mathtt{self}}{2^{\mathtt{rhs}}}}$
        /// and a boolean indicating whether the division was exact (false) or rounded down (true).
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift right.
        ///
        /// # Returns
        ///
        /// A tuple containing the shifted value and a boolean indicating underflow.
        pub fn overflowing_shr(
            self: Self,
            rhs: usize,
        ) std.meta.Tuple(&.{ Self, bool }) {
            const limbs = rhs / 64;
            const bits = @mod(rhs, 64);

            if (limbs >= Limbs) {
                return .{
                    Self.zero(),
                    !self.equal(Self.zero()),
                };
            }

            var res = self;
            if (bits == 0) {
                // Check for overflow
                var overflow = false;
                for (0..limbs) |i| {
                    overflow = overflow or (res.fe[i] != 0);
                }

                // Shift
                for (0..Limbs - limbs) |i| {
                    res.fe[i] = res.fe[i + limbs];
                }
                for (Limbs - limbs..Limbs) |i| {
                    res.fe[i] = 0;
                }
                return .{ res, overflow };
            }

            // Check for overflow
            var overflow = false;
            for (0..limbs) |i| {
                overflow = overflow or (res.fe[i] != 0);
            }
            overflow = overflow or (std.math.shr(
                u64,
                res.fe[limbs],
                bits,
            ) != 0);

            // Shift
            for (0..Limbs - limbs - 1) |i| {
                res.fe[i] = std.math.shr(
                    u64,
                    res.fe[i + limbs],
                    bits,
                ) | std.math.shl(
                    u64,
                    res.fe[i + limbs + 1],
                    64 - bits,
                );
            }

            res.fe[Limbs - limbs - 1] = std.math.shr(
                u64,
                res.fe[Limbs - 1],
                bits,
            );
            for (Limbs - limbs..Limbs) |i| {
                res.fe[i] = 0;
            }
            return .{ res, overflow };
        }

        /// Right shift by `rhs` bits with checked underflow.
        ///
        /// This function performs a right shift of `self` by `rhs` bits. It returns `Some(value)` with the result of the shift if no underflow occurs. If underflow happens (bits are shifted out), it returns [`null`].
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift right.
        ///
        /// # Returns
        ///
        /// - `Some(value)`: The shifted value if no underflow occurs.
        /// - [`null`]: If the division is not exact.
        pub fn checked_shr(self: Self, rhs: usize) ?Self {
            const _shl = self.overflowing_shr(rhs);
            return switch (_shl[1]) {
                false => _shl[0],
                else => null,
            };
        }

        /// Right shift by `rhs` bits with wrapping behavior.
        ///
        /// This function performs a right shift of `self` by `rhs` bits, and it wraps around if an underflow occurs. It returns the result of the shift.
        ///
        /// # Parameters
        ///
        /// - `self`: The value to be shifted.
        /// - `rhs`: The number of bits to shift right.
        ///
        /// # Returns
        ///
        /// The shifted value with wrapping behavior.
        pub fn wrapping_shr(self: Self, rhs: usize) Self {
            return self.overflowing_shr(rhs)[0];
        }
    };
}
