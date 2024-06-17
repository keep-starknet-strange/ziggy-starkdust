%builtins ec_op

from starkware.cairo.common.cairo_builtins import EcOpBuiltin
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.ec import ec_op

func main{ec_op_ptr: EcOpBuiltin*}() {
    let p = EcPoint(
        0x6a4beaef5a93425b973179cdba0c9d42f30e01a5f1e2db73da0884b8d6756fc,
        0x72565ec81bc09ff53fbfad99324a92aa5b39fb58267e395e8abe36290ebf24f,
    );
    let m = 34;
    let q = EcPoint(
        0x654fd7e67a123dd13868093b3b7777f1ffef596c2e324f25ceaf9146698482c,
        0x4fad269cbf860980e38768fe9cb6b0b9ab03ee3fe84cfde2eccce597c874fd8,
    );
    let (r) = ec_op(p, m, q);
    assert r.x = 108925483682366235368969256555281508851459278989259552980345066351008608800;
    assert r.y = 1592365885972480102953613056006596671718206128324372995731808913669237079419;
    return ();
}
