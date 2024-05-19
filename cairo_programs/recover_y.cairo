%builtins ec_op

from starkware.cairo.common.cairo_builtins import EcOpBuiltin
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.ec import recover_y

func main{ec_op_ptr: EcOpBuiltin*}() {
    let x = 0x6a4beaef5a93425b973179cdba0c9d42f30e01a5f1e2db73da0884b8d6756fc;
    let r: EcPoint = recover_y(x);
    assert r.x = 0x6a4beaef5a93425b973179cdba0c9d42f30e01a5f1e2db73da0884b8d6756fc;
    assert r.y = 0xda9a137e43f611ac0405266cdb56d55a4c604a7d981c6a17541c9d6f140db2;
    return ();
}
