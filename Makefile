.PHONY: deps deps-macos build build_cairo_vm_cli build-compare-benchmarks $(CAIRO_VM_CLI) \

CAIRO_VM_CLI:=cairo-vm/target/release/cairo-vm-cli

$(CAIRO_VM_CLI):
	git clone --depth 1 -b v0.9.1 https://github.com/lambdaclass/cairo-vm
	cd cairo-vm; cargo b --release --bin cairo-vm-cli

build_cairo_vm_cli: | $(CAIRO_VM_CLI)
BENCH_DIR=cairo_programs/benchmarks

# Creates a pyenv and installs cairo-lang
deps:
	pyenv install  -s 3.9.15
	PYENV_VERSION=3.9.15 python -m venv cairo-vm-env
	. cairo-vm-env/bin/activate ; \
	pip install -r requirements.txt ; \

# Creates a pyenv and installs cairo-lang
deps-macos:
	brew install gmp pyenv
	pyenv install -s 3.9.15
	PYENV_VERSION=3.9.15 /opt/homebrew/bin/python3.9 -m venv cairo-vm-env
	. cairo-vm-env/bin/activate ; \
	CFLAGS=-I/opt/homebrew/opt/gmp/include LDFLAGS=-L/opt/homebrew/opt/gmp/lib pip install -r requirements.txt ; \

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

build-compare-benchmarks: build_cairo_vm_cli build
	cd scripts; sh benchmarks.sh

clean:
	@rm -rf zig-cache
	@rm -rf zig-out
