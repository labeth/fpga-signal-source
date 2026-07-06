#!/usr/bin/env bash
# build-proto.sh <uart|spi|i2c> — synthesize, place/route and FLASH a serial-
# protocol generator onto the Alchitry Au. These are the ground truth for the
# scope's protocol decoder (app/internal/decode + the web decode.js):
#   uart : 8N1 115200 UART TX, mirrored on C1 and C2 ("Hi \x55\xAA\x0F\xF0\n").
#   spi  : SPI Mode-0 MSB-first, SCLK on C1 (G1), MOSI on C2 (M6).
#   i2c  : I2C transaction, SCL on C1 (G1), SDA on C2 (M6) — addr 0x24 W + payload.
#
# Flow: yosys -> nextpnr-xilinx -> fasm2frames.py -> xc7frames2bit -> openFPGALoader
# Point $FPGA at your open Xilinx toolchain checkout (see README.md). Flashing the
# Au's SRAM may need root — set SUDO=sudo if your user can't reach the FT2232 JTAG.
set -e

PROTO="${1:?usage: build-proto.sh <uart|spi|i2c>}"
case "$PROTO" in uart|spi|i2c) ;; *) echo "unknown proto: $PROTO (use uart|spi|i2c)"; exit 2;; esac

FPGA="${FPGA:-$HOME/fpga}"                 # toolchain root (override: FPGA=/path ./build-proto.sh ...)
SUDO="${SUDO:-}"                            # set SUDO=sudo if flashing needs root
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

# --- synth (top module is `sig` in both uart.v and spi.v) ---
yosys -q -p "
  read_verilog $PROJ/$PROTO.v;
  synth_xilinx -flatten -abc9 -arch xc7 -top sig;
  write_json $OUT/$PROTO.json
" 2> "$OUT/yosys.log" || { echo "YOSYS FAILED"; tail -20 "$OUT/yosys.log"; exit 1; }

# --- place & route ---
"$NPNR" --chipdb "$CHIPDB" --xdc "$PROJ/proto.xdc" \
        --json "$OUT/$PROTO.json" --fasm "$OUT/$PROTO.fasm" \
        > "$OUT/nextpnr.log" 2>&1 || { echo "NEXTPNR FAILED"; tail -25 "$OUT/nextpnr.log"; exit 1; }

# --- fasm -> frames -> bitstream (drop Vivado-only freq hints the open db lacks) ---
grep -vE "CLK_FREQ_BB|_CLK_FREQ_" "$OUT/$PROTO.fasm" > "$OUT/$PROTO.clean.fasm"
python3 "$FASM2FRAMES" --part "$PART" --db-root "$XRAY_DB/artix7" \
        "$OUT/$PROTO.clean.fasm" > "$OUT/$PROTO.frames" 2> "$OUT/fasm2frames.log" \
        || { echo "FASM2FRAMES FAILED"; tail -20 "$OUT/fasm2frames.log"; exit 1; }

"$XRAY_TOOLS/xc7frames2bit" --part_file "$XRAY_DB/artix7/$PART/part.yaml" \
        --part_name "$PART" --frm_file "$OUT/$PROTO.frames" \
        --output_file "$OUT/$PROTO.bit" > "$OUT/frames2bit.log" 2>&1 \
        || { echo "FRAMES2BIT FAILED"; tail -20 "$OUT/frames2bit.log"; exit 1; }

echo ">>> bitstream: $(stat -c%s "$OUT/$PROTO.bit") bytes"

# --- flash (SRAM, volatile) ---
$SUDO "$OFL" -b alchitry_au -m "$OUT/$PROTO.bit" 2>&1 | tail -4
echo ">>> flashed $PROTO generator on C1=G1 + C2=M6"
