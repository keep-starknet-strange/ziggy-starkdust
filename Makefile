libstarknet_crypto.a:
	@rm -f src/math/crypto/starknet_crypto/libstarknet_crypto.a
	@cd src/math/crypto/starknet_crypto/starknet_crypto && cargo build --release
	@mv src/math/crypto/starknet_crypto/starknet_crypto/target/release/libstarknet_crypto.a src/math/crypto/starknet_crypto

build: libstarknet_crypto.a
	@zig build

build-optimize: libstarknet_crypto.a
	@zig build -Doptimize=ReleaseFast

test: libstarknet_crypto.a
	@zig build test --summary all

test-filter: libstarknet_crypto.a
	@zig build test --summary all -Dtest-filter=$(FILTER)

clean:
	@cd src/math/crypto/starknet_crypto/starknet_crypto && cargo clean
	@rm -f src/math/crypto/starknet_crypto/libstarknet_crypto.a
	@rm -rf zig-cache
	@rm -rf zig-out