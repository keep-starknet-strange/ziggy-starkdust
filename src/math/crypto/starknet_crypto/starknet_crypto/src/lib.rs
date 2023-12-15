use starknet_crypto::{
    pedersen_hash as starknet_crypto_pedersen_hash, poseidon_permute_comp, verify, FieldElement,
};
extern crate libc;

// C representation of a bit array: a raw pointer to a mutable unsigned 8 bits integer.
type Bytes = *mut u8;

fn field_element_from_bytes(bytes: Bytes) -> FieldElement {
    let array = unsafe {
        let slice: &mut [u8] = std::slice::from_raw_parts_mut(bytes, 32);
        let array: [u8; 32] = slice.try_into().unwrap();
        array
    };
    FieldElement::from_bytes_be(&array).unwrap()
}

fn bytes_from_field_element(felt: FieldElement, bytes: Bytes) {
    let byte_array = felt.to_bytes_be();
    for i in 0..32 {
        unsafe {
            *bytes.offset(i) = byte_array[i as usize];
        }
    }
}

#[no_mangle]
extern "C" fn poseidon_permute(
    first_state_felt: Bytes,
    second_state_felt: Bytes,
    third_state_felt: Bytes,
) {
    // Convert state from C representation to FieldElement
    let mut state_array: [FieldElement; 3] = [
        field_element_from_bytes(first_state_felt),
        field_element_from_bytes(second_state_felt),
        field_element_from_bytes(third_state_felt),
    ];
    // Call poseidon permute comp
    poseidon_permute_comp(&mut state_array);
    // Convert state from FieldElement back to C representation
    bytes_from_field_element(state_array[0], first_state_felt);
    bytes_from_field_element(state_array[1], second_state_felt);
    bytes_from_field_element(state_array[2], third_state_felt);
}

#[no_mangle]
extern "C" fn pedersen_hash(felt_1: Bytes, felt_2: Bytes, result: Bytes) {
    // Convert Felts from C representation to FieldElement
    let f1 = field_element_from_bytes(felt_1);
    let f2 = field_element_from_bytes(felt_2);

    // Call starknet_crypto::pedersen_hash
    let hash_in_felt = starknet_crypto_pedersen_hash(&f1, &f2);
    bytes_from_field_element(hash_in_felt, result);
}

#[no_mangle]
extern "C" fn verify_signature(
    public_key_bytes: Bytes,
    message_bytes: Bytes,
    r_bytes: Bytes,
    s_bytes: Bytes,
) -> bool {
    let public_key = field_element_from_bytes(public_key_bytes);
    let message = field_element_from_bytes(message_bytes);
    let r = field_element_from_bytes(r_bytes);
    let s = field_element_from_bytes(s_bytes);
    let verification_result = verify(&public_key, &message, &r, &s);

    // An error on the verification is an invalid signature
    // That shouldn't verify
    match verification_result {
        Ok(verifies) => verifies,
        Err(_) => false,
    }
}
