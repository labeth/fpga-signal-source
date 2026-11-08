#!/usr/bin/env bash
# build-midi.sh — regenerate the MIDI song ROM, then synthesize and place/route
# midi_song.v into out/a11-midi-song/midi_song.bit (MIDI on A11/L2 = scope C1,
# A2/T8 = scope C2 held low). Builds only; LOAD=1 also loads the Au's SRAM
# (volatile) with openFPGALoader, which needs no root on this bench.
#
# Flow: gen_midi_song.py -> yosys -> nextpnr-xilinx -> fasm2frames.py ->
# xc7frames2bit [-> openFPGALoader]. $FPGA is the open toolchain (README.md).
set -euo pipefail

FPGA="${FPGA:-$HOME/fpga}"
NPNR="$FPGA/nextpnr-xilinx/nextpnr-xilinx"
CHIPDB="$FPGA/nextpnr-xilinx/xilinx/xc7a35t.bin"
XRAY_DB="$FPGA/prjxray-db"
XRAY_TOOLS="$FPGA/prjxray/build/tools"
FASM2FRAMES="$FPGA/prjxray/utils/fasm2frames.py"
PART=xc7a35tftg256-1
OFL="$FPGA/openFPGALoader/build/openFPGALoader"
PROJ="$(cd "$(dirname "$0")" && pwd)"
OUT="${MIDI_OUT:-$PROJ/out/a11-midi-song}"
mkdir -p "$OUT"
export PATH="$FPGA/oss-cad-suite/bin:$PATH"
export PYTHONPATH="$FPGA/prjxray:${PYTHONPATH:-}"

python3 "$PROJ/gen_midi_song.py" "$PROJ/midi_song.hex"

# $readmemh resolves midi_song.hex against the working directory.
cd "$PROJ"
yosys -q -p "
  read_verilog midi_song.v;
  synth_xilinx -flatten -abc9 -arch xc7 -top sig;
  write_json $OUT/midi_song.json
" 2> "$OUT/yosys.log" || { echo "YOSYS FAILED"; tail -20 "$OUT/yosys.log"; exit 1; }

"$NPNR" --router router2 --chipdb "$CHIPDB" --xdc "$PROJ/midi_song.xdc" \
        --json "$OUT/midi_song.json" --fasm "$OUT/midi_song.fasm" \
        > "$OUT/nextpnr.log" 2>&1 || { echo "NEXTPNR FAILED"; tail -25 "$OUT/nextpnr.log"; exit 1; }

grep -vE "CLK_FREQ_BB|_CLK_FREQ_" "$OUT/midi_song.fasm" > "$OUT/midi_song.clean.fasm"
python3 "$FASM2FRAMES" --part "$PART" --db-root "$XRAY_DB/artix7" \
        "$OUT/midi_song.clean.fasm" > "$OUT/midi_song.frames" 2> "$OUT/fasm2frames.log" \
        || { echo "FASM2FRAMES FAILED"; tail -20 "$OUT/fasm2frames.log"; exit 1; }

"$XRAY_TOOLS/xc7frames2bit" --part_file "$XRAY_DB/artix7/$PART/part.yaml" \
        --part_name "$PART" --frm_file "$OUT/midi_song.frames" \
        --output_file "$OUT/midi_song.bit" > "$OUT/frames2bit.log" 2>&1 \
        || { echo "FRAMES2BIT FAILED"; tail -20 "$OUT/frames2bit.log"; exit 1; }
echo ">>> bitstream: $OUT/midi_song.bit ($(stat -c%s "$OUT/midi_song.bit") bytes)"

if [ "${LOAD:-0}" = 1 ]; then
    "$OFL" -b alchitry_au -m "$OUT/midi_song.bit" 2>&1 | tail -4
    echo ">>> loaded the MIDI song (volatile SRAM)"
fi
