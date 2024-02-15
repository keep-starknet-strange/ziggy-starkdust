#!/bin/bash

set -e
source ../cairo-vm-env/bin/activate

CAIRO_VM_CLI=../cairo-vm/target/release/cairo-vm-cli
BENCH_DIR=../cairo_programs/benchmarks
export PATH=$PATH:$(pwd)/../zig-out/bin:$(pwd)/../cairo-vm/target/release/

for file in $(ls ${BENCH_DIR} | grep .cairo | sed -E 's/\.cairo//'); do
    echo "Compiling ${file} program..."
    cairo-compile --cairo_path="${BENCH_DIR}" ${BENCH_DIR}/${file}.cairo --output ${BENCH_DIR}/${file}.json --proof_mode
    echo "Running ${file} benchmark"
    hyperfine --show-output \
        -n "cairo-vm (Rust)" "${CAIRO_VM_CLI} ${BENCH_DIR}/${file}.json --proof_mode --memory_file /dev/null --trace_file /dev/null --layout "all_cairo""
done
