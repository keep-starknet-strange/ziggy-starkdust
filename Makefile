build: libstarknet_crypto.a
	@zig build

build-optimize: libstarknet_crypto.a
	@zig build -Doptimize=ReleaseFast

test: libstarknet_crypto.a
	@zig build test --summary all

test-filter: libstarknet_crypto.a
	@zig build test --summary all -Dtest-filter="$(FILTER)"

build-integration-test:
	@zig build integration_test

<<<<<<< HEAD
build-and-run-pedersen-table-gen:
	@zig build pedersen_table_gen
	> ./src/math/crypto/pedersen/gen/constants.zig
	./zig-out/bin/pedersen_table_gen
	@zig fmt ./src/math/crypto/pedersen/gen/constants.zig

=======
>>>>>>> 9c7f6665cf60d1fa3748c64f11c144c353117da2
build-and-run-poseidon-consts-gen:
	@zig build poseidon_consts_gen
	> ./src/math/crypto/poseidon/gen/constants.zig
	./zig-out/bin/poseidon_consts_gen
	@zig fmt ./src/math/crypto/poseidon/gen/constants.zig

libstarknet_crypto.a:
	@rm -f src/math/crypto/starknet_crypto/libstarknet_crypto.a
	@cd src/math/crypto/starknet_crypto/starknet_crypto && cargo build --release
	@mv src/math/crypto/starknet_crypto/starknet_crypto/target/release/libstarknet_crypto.a src/math/crypto/starknet_crypto

clean:
	@cd src/math/crypto/starknet_crypto/starknet_crypto && cargo clean
	@rm -f src/math/crypto/starknet_crypto/libstarknet_crypto.a
	@rm -rf zig-cache
	@rm -rf zig-out