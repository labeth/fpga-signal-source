#!/usr/bin/env bash
# build-burst.sh — synth/pnr/flash burst.v (the fixed 50/150/250 MHz burst
# pattern, no params) onto the Alchitry Au, driving ball G1 (scope C1).
# Same toolchain + $FPGA / $SUDO conventions as build.sh.
set -e
FPGA="${FPGA:-$HOME/fpga}"
SUDO="${SUDO:-}"
PROJ="$(cd "$(dirname "$0")" && pwd)"
OUT="$PROJ/out"; mkdir -p "$OUT"
export PATH="$FPGA/oss-cad-suite/bin:$PATH"; export PYTHONPATH="$FPGA/prjxray:${PYTHONPATH:-}"
PART=xc7a35tftg256-1

yosys -q -p "read_verilog $PROJ/burst.v; synth_xilinx -flatten -abc9 -arch xc7 -top sig; write_json $OUT/burst.json" 2>"$OUT/y.log" || { echo YOSYS; tail -20 "$OUT/y.log"; exit 1; }
"$FPGA/nextpnr-xilinx/nextpnr-xilinx" --chipdb "$FPGA/nextpnr-xilinx/xilinx/xc7a35t.bin" --xdc "$PROJ/sig.xdc" --json "$OUT/burst.json" --fasm "$OUT/burst.fasm" >"$OUT/n.log" 2>&1 || { echo NEXTPNR; tail -25 "$OUT/n.log"; exit 1; }
grep -vE "CLK_FREQ_BB|_CLK_FREQ_" "$OUT/burst.fasm" > "$OUT/burst.clean.fasm"
python3 "$FPGA/prjxray/utils/fasm2frames.py" --part $PART --db-root "$FPGA/prjxray-db/artix7" "$OUT/burst.clean.fasm" > "$OUT/burst.frames" 2>"$OUT/f.log" || { echo FASM2FRAMES; tail -20 "$OUT/f.log"; exit 1; }
"$FPGA/prjxray/build/tools/xc7frames2bit" --part_file "$FPGA/prjxray-db/artix7/$PART/part.yaml" --part_name $PART --frm_file "$OUT/burst.frames" --output_file "$OUT/burst.bit" >"$OUT/b.log" 2>&1 || { echo FRAMES2BIT; tail -20 "$OUT/b.log"; exit 1; }
echo ">>> burst.bit $(stat -c%s "$OUT/burst.bit") bytes"
$SUDO "$FPGA/openFPGALoader/build/openFPGALoader" -b alchitry_au -m "$OUT/burst.bit" 2>&1 | tail -2
echo ">>> flashed burst pattern (50/150/250 MHz, 3.33 MHz repeat)"
