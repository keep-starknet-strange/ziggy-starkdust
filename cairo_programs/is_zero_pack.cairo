%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.field import unreduced_mul, verify_zero

func is_zero_pack{range_check_ptr}(x: BigInt3) -> (res: felt) {
    // just to import SECP_P
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        value = pack(ids.x, PRIME) % SECP_P
    %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack

        x = pack(ids.x, PRIME) % SECP_P
    %}
    if (nondet %{ x == 0 %} != 0) {
        return (res=1);
    }
    return (res=0);
}

func is_zero_pack_v2{range_check_ptr}(x: BigInt3) -> (res: felt) {
    // just to import SECP_P
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        value = pack(ids.x, PRIME) % SECP_P
    %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        x = pack(ids.x, PRIME) % SECP_P
    %}
    if (nondet %{ x == 0 %} != 0) {
        return (res=1);
    }
    return (res=0);
}

func is_zero_pack_ed25519{range_check_ptr}(x: BigInt3) -> (res: felt) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P=2**255-19

        x = pack(ids.x, PRIME) % SECP_P
    %}
    if (nondet %{ x == 0 %} != 0) {
        return (res=1);
    }
    return (res=0);
}

func test_is_zero_pack{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero_pack(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero_pack(one);
    assert res = 0;

    let secp256k1_prime = BigInt3(
        77371252455336262886226991, 77371252455336267181195263, 19342813113834066795298815
    );

    let (res: felt) = is_zero_pack(secp256k1_prime);
    assert res = 1;

    return ();
}

func test_is_zero_pack_v2{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero_pack(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero_pack(one);
    assert res = 0;

    let secp256k1_prime = BigInt3(
        77371252455336262886226991, 77371252455336267181195263, 19342813113834066795298815
    );

    let (res: felt) = is_zero_pack_v2(secp256k1_prime);
    assert res = 1;

    return ();
}

func test_is_zero_pack_ed25519{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero_pack_ed25519(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero_pack_ed25519(one);
    assert res = 0;

    let ed25519_prime = BigInt3(
        77371252455336267181195245, 77371252455336267181195263, 9671406556917033397649407
    );

    let (res: felt) = is_zero_pack_ed25519(ed25519_prime);
    assert res = 1;

    return ();
}

func main{range_check_ptr}() -> () {
    test_is_zero_pack();
    test_is_zero_pack_v2();
    test_is_zero_pack_ed25519();

    return ();
}
