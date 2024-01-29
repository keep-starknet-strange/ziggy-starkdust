build:
	@zig build

build-optimize:
	@zig build -Doptimize=ReleaseFast

test:
	@zig build test --summary all

test-filter:
	@zig build test --summary all -Dtest-filter="$(FILTER)"

build-integration-test:
	@zig build integration_test

build-and-run-pedersen-table-gen:
	@zig build pedersen_table_gen
	> ./src/math/crypto/pedersen/gen/constants.zig
	./zig-out/bin/pedersen_table_gen
	@zig fmt ./src/math/crypto/pedersen/gen/constants.zig

build-and-run-poseidon-consts-gen:
	@zig build poseidon_consts_gen
	> ./src/math/crypto/poseidon/gen/constants.zig
	./zig-out/bin/poseidon_consts_gen
	@zig fmt ./src/math/crypto/poseidon/gen/constants.zig

clean:
	@rm -rf zig-cache
	@rm -rf zig-out