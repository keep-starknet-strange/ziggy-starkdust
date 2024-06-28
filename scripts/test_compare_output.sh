
#!/usr/bin/env bash

set -e
. ../cairo-vm-env/bin/activate


cd ..
CAIRO_PROGRAMS_DIR=cairo_programs
CAIRO_DIR=cairo_programs
CAIRO_VM_CLI=cairo-vm/target/release/cairo-vm-cli
ZIG_CLI=zig-out/bin/ziggy-starkdust


# func to check that two files is same
sameContents() {
    echo "$(sha256sum "$1" | sed 's/ .*//') $2" | sha256sum --check 1>/dev/null 2>&1
}

RUST_MEMORY_OUTPUT="./tmp/rust_memory.tmp"
ZIG_MEMORY_OUTPUT="./tmp/zig_memory.tmp"
RUST_TRACE_OUTPUT="./tmp/rust_trace.tmp"
ZIG_TRACE_OUTPUT="./tmp/zig_trace.tmp"

trap ctrl_c INT

ctrl_c() {
    rm -rf tmp
}

# creating tmp directory for output fiels
mkdir tmp

for file in $(ls ${CAIRO_PROGRAMS_DIR} | grep .cairo | sed -E 's/\.cairo//'); do
    echo "Compiling ${file} program..."
    cairo-compile --cairo_path="${CAIRO_DIR}:" ${CAIRO_PROGRAMS_DIR}/${file}.cairo --output ${CAIRO_PROGRAMS_DIR}/${file}.json --proof_mode
    echo "Running ${file}"

    ${CAIRO_VM_CLI} ${CAIRO_PROGRAMS_DIR}/${file}.json --memory_file $RUST_MEMORY_OUTPUT --trace_file $RUST_TRACE_OUTPUT --proof_mode --layout all_cairo

    ${ZIG_CLI} execute --filename ${CAIRO_PROGRAMS_DIR}/${file}.json --enable-trace=true --output-memory=$ZIG_MEMORY_OUTPUT --output-trace=$ZIG_TRACE_OUTPUT --proof-mode=true --layout all_cairo
        
    if sameContents $RUST_TRACE_OUTPUT $ZIG_TRACE_OUTPUT; then 
        echo "Rust & Zig output trace is same"
    else
        echo "Zig have different output trace"
   fi

    if sameContents $RUST_MEMORY_OUTPUT $ZIG_MEMORY_OUTPUT; then 
        echo "Rust & Zig memory output is same"
    else
        echo "Zig have different output memory"
    fi
done

rm -rf tmp
