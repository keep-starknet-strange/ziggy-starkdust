from starkware.cairo.common.alloc import alloc

func main{}() {
    let arr: felt* = alloc();

    assert arr[0] = 1;
    assert arr[5] = 2;

    let end = arr + 5;

    if (arr == end) {
        ret;
    }

    ret;
}
