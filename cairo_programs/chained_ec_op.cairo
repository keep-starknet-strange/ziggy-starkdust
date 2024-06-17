%builtins ec_op

from starkware.cairo.common.cairo_builtins import EcOpBuiltin
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.ec import chained_ec_op
from starkware.cairo.common.alloc import alloc

func main{ec_op_ptr: EcOpBuiltin*}() {
    let p = EcPoint(
        0x6a4beaef5a93425b973179cdba0c9d42f30e01a5f1e2db73da0884b8d6756fc,
        0x72565ec81bc09ff53fbfad99324a92aa5b39fb58267e395e8abe36290ebf24f,
    );
    let q1 = EcPoint(
        0x654fd7e67a123dd13868093b3b7777f1ffef596c2e324f25ceaf9146698482c,
        0x4fad269cbf860980e38768fe9cb6b0b9ab03ee3fe84cfde2eccce597c874fd8,
    );
    let q2 = EcPoint(
        0x654fd7e67a123dd13868093b3b7777f1ffef596c2e324f25ceaf9146698482c,
        0x4fad269cbf860980e38768fe9cb6b0b9ab03ee3fe84cfde2eccce597c874fd8,
    );
    let q3 = EcPoint(
        0x654fd7e67a123dd13868093b3b7777f1ffef596c2e324f25ceaf9146698482c,
        0x4fad269cbf860980e38768fe9cb6b0b9ab03ee3fe84cfde2eccce597c874fd8,
    );
    let q: EcPoint* = alloc();
    assert q[0] = q1;
    assert q[1] = q2;
    assert q[2] = q3;
    let m: felt* = alloc();
    assert m[0] = 34;
    assert m[1] = 34;
    assert m[2] = 34;
    let (r) = chained_ec_op(p, m, q, 3);
    assert r.x = 3384892298291437283292800194657711696590239153368187334668717989522828417221;
    assert r.y = 1522177177154723444905194991592642153940491339266976531102714535684279750063;
    return ();
}
