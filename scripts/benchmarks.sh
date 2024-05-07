#!/bin/bash

set -e
source ../cairo-vm-env/bin/activate

BENCH_DIR=../cairo_programs/benchmarks
CAIRO_DIR=../cairo_programs/
CAIRO_VM_CLI=../cairo-vm/target/release/cairo-vm-cli
ZIG_CLI=../zig-out/bin/ziggy-starkdust

for file in $(ls ${BENCH_DIR} | grep .cairo | sed -E 's/\.cairo//'); do
    echo "Compiling ${file} program..."
    cairo-compile --cairo_path="${CAIRO_DIR}" ${BENCH_DIR}/${file}.cairo --output ${BENCH_DIR}/${file}.json --proof_mode
    echo "Running ${file} benchmark"
    hyperfine --show-output --warmup 2 \
        -n "cairo-vm (Zig)" "${ZIG_CLI} execute --filename ${BENCH_DIR}/${file}.json  --layout all_cairo" \
        -n "cairo-vm (Rust)" "${CAIRO_VM_CLI} ${BENCH_DIR}/${file}.json --proof_mode --layout all_cairo" 
done
