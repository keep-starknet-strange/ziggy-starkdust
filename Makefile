.PHONY: deps deps-macos build build_cairo_vm_cli build-compare-benchmarks $(CAIRO_VM_CLI) \

CAIRO_VM_CLI:=cairo-vm/target/release/cairo-vm-cli

$(CAIRO_VM_CLI):
	git clone --depth 1 -b v0.9.2 https://github.com/lambdaclass/cairo-vm
	cd cairo-vm; cargo b --release --bin cairo-vm-cli

build_cairo_vm_cli: | $(CAIRO_VM_CLI)
BENCH_DIR=cairo_programs/benchmarks


check:

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
	@zig build -Doptimize=ReleaseFast integration_test

run-integration-test:
	@zig build -Doptimize=ReleaseFast integration_test
	./zig-out/bin/integration_test

run-integration-test-filter:
	@zig build integration_test
	./zig-out/bin/integration_test $(FILTER)

build-compare-benchmarks: build_cairo_vm_cli build-optimize
	cd scripts; sh benchmarks.sh

build-compare-output: build_cairo_vm_cli build-optimize
	cd scripts; sh test_compare_output.sh

clean:
	@rm -rf ./zig-cache
	@rm -rf zig-out
