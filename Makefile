.PHONY: deps deps-macos cargo-deps build_cairo_vm_cli build-compare-benchmarks $(CAIRO_VM_CLI) \

CAIRO_VM_CLI:=cairo-vm/target/release/cairo-vm-cli

$(CAIRO_VM_CLI):
	git clone --depth 1 -b v0.9.1 https://github.com/lambdaclass/cairo-vm
	cd cairo-vm; cargo b --release --bin cairo-vm-cli

build_cairo_vm_cli: | $(CAIRO_VM_CLI)
# TODO: change BENCH_DIR to cairo_programs/benchmarks
BENCH_DIR=cairo_programs/test_benchmarks

cargo-deps:
	cargo install --version 1.14.0 hyperfine

# Creates a pyenv and installs cairo-lang
deps: cargo-deps
	pyenv install  -s 3.9.15
	PYENV_VERSION=3.9.15 python -m venv cairo-vm-env
	. cairo-vm-env/bin/activate ; \
	pip install -r requirements.txt ; \

# Creates a pyenv and installs cairo-lang
deps-macos: cargo-deps
	brew install gmp pyenv
	pyenv install -s 3.9.15
	PYENV_VERSION=3.9.15 python -m venv cairo-vm-env
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

build-compare-benchmarks: build_cairo_vm_cli
	@for file in $$(ls $(BENCH_DIR) | grep .cairo | sed -E 's/\.cairo//'); do \
		echo "Compiling $$file program..." \
		cairo-compile --cairo_path="$(BENCH_DIR)" $(BENCH_DIR)/$$file.cairo --output $(BENCH_DIR)/$$file.json \
		echo "Running $$file benchmark"; \
		export PATH="$$(pyenv root)/shims:$$PATH"; \
		hyperfine \
			-n "cairo-vm (Rust)" "$(CAIRO_VM_CLI) $(BENCH_DIR)/$$file.json --proof_mode --memory_file /dev/null --trace_file /dev/null --layout all_cairo" \
			-n "cairo-vm (Zig)" "/Users/aniket.p/Blockchain/Development/starknet/ziggy-starkdust/zig-out/bin/ziggy-starkdust execute --filename $(BENCH_DIR)/$$file.json --enable-trace=true --output-memory=/dev/null --output-trace=/dev/null --layout all_cairo"; \
	done

clean:
	@rm -rf zig-cache
	@rm -rf zig-out