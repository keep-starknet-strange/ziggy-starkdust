from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.registers import get_fp_and_pc

func main() {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    local numbers: (felt, felt, felt) = (1, 2, 3);

    let dest: felt* = alloc();

    memcpy(dst=dest, src=&numbers, len=3);

    assert numbers[0] = dest[0];
    assert numbers[1] = dest[1];
    assert numbers[2] = dest[2];

    return ();
}
