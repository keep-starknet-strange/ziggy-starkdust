%builtins ecdsa
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.cairo_builtins import SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature

func main{ecdsa_ptr: SignatureBuiltin*}() {
    verify_ecdsa_signature(
        2718,
        1735102664668487605176656616876767369909409133946409161569774794110049207117,
        3086480810278599376317923499561306189851900463386393948998357832163236918254,
        598673427589502599949712887611119751108407514580626464031881322743364689811,
    );
    return ();
}
