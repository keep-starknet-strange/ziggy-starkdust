%builtins range_check

from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    split_64,
    uint256_sqrt,
    uint256_signed_nn,
    uint256_unsigned_div_rem,
    uint256_mul,
    uint256_mul_div_mod
)
from starkware.cairo.common.alloc import alloc

func fill_array{range_check_ptr: felt}(
    array: Uint256*, base: Uint256, step: Uint256, array_length: felt, iterator: felt
) {
    if (iterator == array_length) {
        return ();
    }
    let (res, carry_high) = uint256_add(step, base);
    let (sqrt) = uint256_sqrt(res);

    assert array[iterator] = sqrt;
    return fill_array(array, base, array[iterator], array_length, iterator + 1);
}

func main{range_check_ptr: felt}() {
    let x: Uint256 = Uint256(5, 2);
    let y = Uint256(3, 7);
    let (res, carry_high) = uint256_add(x, y);
    assert res.low = 8;
    assert res.high = 9;
    assert carry_high = 0;

    let (low, high) = split_64(850981239023189021389081239089023);
    assert low = 7249717543555297151;
    assert high = 46131785404667;

    let (root) = uint256_sqrt(Uint256(17, 7));
    assert root = Uint256(48805497317890012913, 0);

    let (signed_nn) = uint256_signed_nn(Uint256(5, 2));
    assert signed_nn = 1;
    let (p) = uint256_signed_nn(Uint256(1, 170141183460469231731687303715884105728));
    assert p = 0;
    let (q) = uint256_signed_nn(Uint256(1, 170141183460469231731687303715884105727));
    assert q = 1;

    let (a_quotient, a_remainder) = uint256_unsigned_div_rem(Uint256(89, 72), Uint256(3, 7));
    assert a_quotient = Uint256(10, 0);
    assert a_remainder = Uint256(59, 2);

    let (b_quotient, b_remainder) = uint256_unsigned_div_rem(
        Uint256(-3618502788666131213697322783095070105282824848410658236509717448704103809099, 2),
        Uint256(5, 2),
    );
    assert b_quotient = Uint256(1, 0);
    assert b_remainder = Uint256(340282366920938463463374607431768211377, 0);

    let (c_quotient, c_remainder) = uint256_unsigned_div_rem(
        Uint256(340282366920938463463374607431768211455, 340282366920938463463374607431768211455),
        Uint256(1, 0),
    );

    assert c_quotient = Uint256(340282366920938463463374607431768211455, 340282366920938463463374607431768211455);
    assert c_remainder = Uint256(0, 0);

    let (a_quotient_low, a_quotient_high, a_remainder) = uint256_mul_div_mod(
        Uint256(89, 72),
        Uint256(3, 7),
        Uint256(107, 114),
    );
    assert a_quotient_low = Uint256(143276786071974089879315624181797141668, 4);
    assert a_quotient_high = Uint256(0, 0);
    assert a_remainder = Uint256(322372768661941702228460154409043568767, 101);

    let (b_quotient_low, b_quotient_high, b_remainder) = uint256_mul_div_mod(
        Uint256(-3618502788666131213697322783095070105282824848410658236509717448704103809099, 2),
        Uint256(1, 1),
        Uint256(5, 2),
    );
    assert b_quotient_low = Uint256(170141183460469231731687303715884105688, 1);
    assert b_quotient_high = Uint256(0, 0);
    assert b_remainder = Uint256(170141183460469231731687303715884105854, 1);

    let (c_quotient_low, c_quotient_high, c_remainder) = uint256_mul_div_mod(
        Uint256(340281070833283907490476236129005105807, 340282366920938463463374607431768211455),
        Uint256(2447157533618445569039502, 0),
        Uint256(0, 1),
    );

    assert c_quotient_low = Uint256(340282366920938463454053728725133866491, 2447157533618445569039501);
    assert c_quotient_high = Uint256(0, 0);
    assert c_remainder = Uint256(326588112914912836985603897252688572242, 0);

    let (mult_low_a, mult_high_a) = uint256_mul(Uint256(59, 2), Uint256(10, 0));
    assert mult_low_a = Uint256(590, 20);
    assert mult_high_a = Uint256(0, 0);

    let (mult_low_b: Uint256, mult_high_b: Uint256) = uint256_mul(
        Uint256(271442546951262198976322048597925888860, 0),
        Uint256(271442546951262198976322048597925888860, 0),
    );
    assert mult_low_b = Uint256(
        42047520920204780886066537579778623760, 216529163594619381764978757921136443390
    );
    assert mult_high_b = Uint256(0, 0);

    let array_length = 100;
    let (sum_array: Uint256*) = alloc();
    fill_array(sum_array, Uint256(57, 8), Uint256(17, 7), array_length, 0);

    return ();
}
