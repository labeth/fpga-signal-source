#!/usr/bin/env bash
# build-dac.sh [freq_hz] [wave] — synthesize, place/route and FLASH the
# TLC7524CN 8-bit DAC driver (dacgen.v) onto the Alchitry Au.
#   freq_hz : output frequency in Hz (default 1000)
#   wave    : 0 sawtooth (default), 1 triangle, 2 square
#
# Flow (same as build.sh): yosys -> nextpnr-xilinx -> fasm2frames.py ->
# xc7frames2bit -> openFPGALoader. Set SUDO=sudo if flashing needs root.
set -e

FHZ="${1:-1000}"
WAVE="${2:-0}"
FPGA="${FPGA:-$HOME/fpga}"
SUDO="${SUDO:-}"
NPNR="$FPGA/nextpnr-xilinx/nextpnr-xilinx"
CHIPDB="$FPGA/nextpnr-xilinx/xilinx/xc7a35t.bin"
XRAY_DB="$FPGA/prjxray-db"
XRAY_TOOLS="$FPGA/prjxray/build/tools"
FASM2FRAMES="$FPGA/prjxray/utils/fasm2frames.py"
PART=xc7a35tftg256-1
OFL="$FPGA/openFPGALoader/build/openFPGALoader"
PROJ="$(cd "$(dirname "$0")" && pwd)"
OUT="$PROJ/out"
mkdir -p "$OUT"
export PATH="$FPGA/oss-cad-suite/bin:$PATH"
export PYTHONPATH="$FPGA/prjxray:${PYTHONPATH:-}"

# phase increment: fout = 100e6 * INC / 2^32  ->  INC = round(fout * 2^32 / 1e8)
INC=$(python3 -c "print(int(round($FHZ * (2**32) / 100e6)))")
ACTUAL=$(python3 -c "print(100e6 * $INC / 2**32)")
echo ">>> DAC gen: ${FHZ} Hz (INC=$INC -> actual ${ACTUAL} Hz), wave=$WAVE"

# --- synth ---
yosys -q -p "
  read_verilog $PROJ/dacgen.v;
  chparam -set INC $INC -set WAVE $WAVE dacgen;
  synth_xilinx -flatten -abc9 -arch xc7 -top dacgen;
  write_json $OUT/dacgen.json
" 2> "$OUT/yosys.log" || { echo "YOSYS FAILED"; tail -25 "$OUT/yosys.log"; exit 1; }

# --- place & route ---
"$NPNR" --chipdb "$CHIPDB" --xdc "$PROJ/dacgen.xdc" \
        --json "$OUT/dacgen.json" --fasm "$OUT/dacgen.fasm" \
        > "$OUT/nextpnr.log" 2>&1 || { echo "NEXTPNR FAILED"; tail -30 "$OUT/nextpnr.log"; exit 1; }

# --- fasm -> frames -> bitstream ---
grep -vE "CLK_FREQ_BB|_CLK_FREQ_" "$OUT/dacgen.fasm" > "$OUT/dacgen.clean.fasm"
python3 "$FASM2FRAMES" --part "$PART" --db-root "$XRAY_DB/artix7" \
        "$OUT/dacgen.clean.fasm" > "$OUT/dacgen.frames" 2> "$OUT/fasm2frames.log" \
        || { echo "FASM2FRAMES FAILED"; tail -20 "$OUT/fasm2frames.log"; exit 1; }
"$XRAY_TOOLS/xc7frames2bit" --part_file "$XRAY_DB/artix7/$PART/part.yaml" \
        --part_name "$PART" --frm_file "$OUT/dacgen.frames" \
        --output_file "$OUT/dacgen.bit" > "$OUT/frames2bit.log" 2>&1 \
        || { echo "FRAMES2BIT FAILED"; tail -20 "$OUT/frames2bit.log"; exit 1; }
echo ">>> bitstream: $(stat -c%s "$OUT/dacgen.bit") bytes"

# --- flash (SRAM, volatile) — non-interactive sudo (FT2232 needs root here) ---
echo a | sudo -S -p "" "$OFL" -b alchitry_au -m "$OUT/dacgen.bit" 2>&1 | tail -4
echo ">>> flashed DAC gen ${ACTUAL} Hz wave=$WAVE"
