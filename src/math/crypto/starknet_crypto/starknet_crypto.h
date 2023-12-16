#include <stdint.h>
#include <stdbool.h>

typedef uint8_t byte_t;

// A 252 bit prime field element (felt), represented as an array of 32 bytes.
typedef byte_t felt_t[32];

// Computes the poseidon hash permutation over a state of three felts
void poseidon_permute(felt_t, felt_t, felt_t);

void pedersen_hash(felt_t, felt_t, felt_t);

bool verify_signature(felt_t, felt_t, felt_t, felt_t);