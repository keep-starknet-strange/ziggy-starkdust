%builtins poseidon
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.poseidon_state import PoseidonBuiltinState
from starkware.cairo.common.builtin_poseidon.poseidon import (
    poseidon_hash,
    poseidon_hash_single,
    poseidon_hash_many,
)
from starkware.cairo.common.alloc import alloc

func main{poseidon_ptr: PoseidonBuiltin*}() {
    // Hash one
    let (x) = poseidon_hash_single(
        218676008889449692916464780911713710628115973574242889792891157041292792362
    );
    assert x = 2835120893146788752888137145656423078969524407843035783270702964188823073934;
    // Hash two
    let (y) = poseidon_hash(1253795, 18540013156130945068);
    assert y = 37282360750367388068593128053386029947772104009544220786084510532118246655;
    // Hash five
    let felts: felt* = alloc();
    assert felts[0] = 84175983715088675913672849362079546;
    assert felts[1] = 9384720329467203286234076408512594689579283578028960384690;
    assert felts[2] = 291883989128409324823849293040390493094093;
    assert felts[3] = 5849589438543859348593485948598349584395839402940940290490324;
    assert felts[4] = 1836254780028456372728992049476335424263474849;
    let (z) = poseidon_hash_many(5, felts);
    assert z = 47102513329160951064697157194713013753695317629154835326726810042406974264;
    return ();
}
