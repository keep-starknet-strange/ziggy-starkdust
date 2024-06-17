
#!/usr/bin/env bash

set -e
. ../cairo-vm-env/bin/activate

cd ..
CAIRO_PROGRAMS_DIR=cairo_programs
CAIRO_PROGRAMS_BENCHMARK_DIR=cairo_programs/benchmarks
CAIRO_DIR=cairo_programs

echo "Compiling benchmark cairo programs"
for file in $(ls ${CAIRO_PROGRAMS_BENCHMARK_DIR} | grep .cairo | sed -E 's/\.cairo//'); do
    echo "Compiling ${file} program..."
    cairo-compile --cairo_path="${CAIRO_DIR}:../${CAIRO_DIR}" ${CAIRO_PROGRAMS_BENCHMARK_DIR}/${file}.cairo --output ${CAIRO_PROGRAMS_BENCHMARK_DIR}/${file}.json --proof_mode
done

echo "Compiling cairo programs"
for file in $(ls ${CAIRO_PROGRAMS_DIR} | grep .cairo | sed -E 's/\.cairo//'); do
    echo "Compiling ${file} program..."
    cairo-compile --cairo_path="${CAIRO_DIR}:../${CAIRO_DIR}" ${CAIRO_PROGRAMS_DIR}/${file}.cairo --output ${CAIRO_PROGRAMS_DIR}/${file}.json --proof_mode
done
