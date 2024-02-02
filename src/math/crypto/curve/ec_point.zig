// code ported from starknet-curve:
// https://github.com/xJonathanLEI/starknet-rs/blob/0857bd6cd3bd34cbb06708f0a185757044171d8d/starknet-curve/src/ec_point.rs
const Felt252 = @import("../../fields/starknet.zig").Felt252;
const ALPHA = @import("./curve_params.zig").ALPHA;
const BETA = @import("./curve_params.zig").BETA;

pub const ProjectivePoint = struct {
    const Self = @This();

    x: Felt252,
    y: Felt252,
    z: Felt252 = Felt252.one(),
    infinity: bool = false,

    pub fn fromAffinePoint(p: AffinePoint) Self {
        return .{
            .x = p.x,
            .y = p.y,
        };
    }

    fn identity() Self {
        return .{
            .x = Felt252.zero(),
            .y = Felt252.zero(),
            .z = Felt252.one(),
            .infinity = true,
        };
    }

    pub fn doubleAssign(self: *Self) void {
        if (self.infinity) {
            return;
        }

        // t=3x^2+az^2 with a=1 from stark curve
        const t = Felt252.three().mul(self.x).mul(self.x).add(self.z.mul(self.z));
        const u = Felt252.two().mul(self.y).mul(self.z);
        const v = Felt252.two().mul(u).mul(self.x).mul(self.y);
        const w = t.mul(t).sub(Felt252.two().mul(v));

        const uy = u.mul(self.y);

        self.* = .{
            .x = u.mul(w),
            .y = t.mul(v.sub(w)).sub(Felt252.two().mul(uy).mul(uy)),
            .z = u.mul(u).mul(u),
            .infinity = self.infinity,
        };
    }

    pub fn mulByBits(self: Self, rhs: [@bitSizeOf(u256)]bool) Self {
        var product = ProjectivePoint.identity();

        for (1..@bitSizeOf(u256)) |idx| {
            product.doubleAssign();
            if (rhs[@bitSizeOf(u256) - idx]) {
                product.addAssign(self);
            }
        }
        return product;
    }

    fn addAssign(self: *Self, rhs: ProjectivePoint) void {
        if (rhs.infinity) {
            return;
        }

        if (self.infinity) {
            self.* = rhs;
            return;
        }

        const u0 = self.x.mul(rhs.z);
        const u1 = rhs.x.mul(self.z);
        if (u0.equal(u1)) {
            self.doubleAssign();
            return;
        }

        const t0 = self.y.mul(rhs.z);
        const t1 = rhs.y.mul(self.z);
        const t = t0.sub(t1);

        const u = u0.sub(u1);
        const u2 = u.mul(u);

        const v = self.z.mul(rhs.z);

        // t * t * v - u2 * (u0 + u1);
        const w = t.mul(t.mul(v)).sub(u2.mul(u0.add(u1)));
        const u3 = u.mul(u2);

        const x = u.mul(w);
        const y = t.mul(u0.mul(u2).sub(w)).sub(t0.mul(u3));
        const z = u3.mul(v);

        self.* = .{
            .x = x,
            .y = y,
            .z = z,
            .infinity = self.infinity,
        };
    }

    pub fn addAssignAffinePoint(self: *Self, rhs: AffinePoint) void {
        if (rhs.infinity) {
            return;
        }

        if (self.infinity) {
            self.* = .{
                .x = rhs.x,
                .y = rhs.y,
                .z = Felt252.one(),
                .infinity = rhs.infinity,
            };
            return;
        }

        const u_0 = self.x;
        const u_1 = rhs.x.mul(self.z);
        const t0 = self.y;
        const t1 = rhs.y.mul(self.z);

        if (u_0.equal(u_1)) {
            if (!t0.equal(t1)) {
                self.infinity = true;
            } else {
                self.doubleAssign();
            }
            return;
        }

        const t = t0.sub(t1);
        const u = u_0.sub(u_1);
        const u_2 = u.mul(u);

        const v = self.z;
        const w = t.mul(t).mul(v).sub(u_2.mul(u_0.add(u_1)));
        const u_3 = u.mul(u_2);

        const x = u.mul(w);
        const y = t.mul(u_0.mul(u_2).sub(w)).sub(t0.mul(u_3));
        const z = u_3.mul(v);

        self.* = .{
            .x = x,
            .y = y,
            .z = z,
            .infinity = self.infinity,
        };
    }
};

pub const AffinePoint = struct {
    const Self = @This();
    x: Felt252,
    y: Felt252,
    infinity: bool,

    // TODO: think about from_x method, dont implemented right now, because need to implemented
    // sqrt method for Felt252

    pub fn addAssign(self: *Self, rhs: *AffinePoint) void {
        if (rhs.infinity) {
            return;
        }
        if (self.infinity) {
            self.x = rhs.x;
            self.y = rhs.y;
            self.infinity = rhs.infinity;
            return;
        }

        if (self.x.equal(rhs.x)) {
            if (self.y.equal(rhs.y.neg())) {
                self.x = Felt252.zero();
                self.y = Felt252.zero();
                self.infinity = true;
                return;
            }
            self.doubleAssign();
            return;
        }

        // l = (y2-y1)/(x2-x1)
        const lambda = rhs.y.sub(self.y).mul(rhs.x.sub(self.x).inv().?);

        const result_x = lambda.mul(lambda).sub(self.x).sub(rhs.x);
        self.y = lambda.mul(self.x.sub(result_x)).sub(self.y);
        self.x = result_x;
    }

    pub fn doubleAssign(self: *Self) void {
        if (self.infinity) {
            return;
        }

        // l = (3x^2+a)/2y with a=1 from stark curve
        const lambda = Felt252.three().mul(self.x.mul(self.x)).add(Felt252.one()).mul(Felt252.two().mul(self.y).inv().?);

        const result_x = lambda.mul(lambda).sub(self.x).sub(self.x);
        self.y = lambda.mul(self.x.sub(result_x)).sub(self.y);
        self.x = result_x;
    }

    pub fn fromProjectivePoint(p: *ProjectivePoint) Self {
        // always one, that is why we can unwrap, unreachable will not happen
        const zinv = if (p.z.inv()) |zinv| zinv else unreachable;

        return .{
            .x = p.x.mul(zinv),
            .y = p.y.mul(zinv),
            .infinity = false,
        };
    }
};
