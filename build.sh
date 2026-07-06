#!/usr/bin/env bash
# build.sh <freq_mhz> — synthesize, place/route and FLASH a single-tone
# generator at <freq_mhz> onto the Alchitry Au, driving ball G1 (scope C1).
#
# Flow: yosys -> nextpnr-xilinx -> fasm2frames.py -> xc7frames2bit -> openFPGALoader
#
# Point $FPGA at your open Xilinx toolchain checkout (see README.md for what it
# must contain). Flashing the Au's SRAM may need root or a udev rule — set
# SUDO=sudo if your user can't reach the FT2232 JTAG directly.
set -e

FMHZ="${1:?usage: build.sh <freq_mhz>}"
FPGA="${FPGA:-$HOME/fpga}"                 # toolchain root (override: FPGA=/path ./build.sh ...)
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

# --- pick counter-divide or PLL, and compute the primitive parameters ---
read USE_PLL DIV PLL_MULT PLL_DIV0 ACTUAL <<EOF
$(python3 - "$FMHZ" <<'PY'
import sys
f = float(sys.argv[1])   # target output MHz; a toggle FF halves the clock,
                          # so we need a "fastclk" at 2*f.
fast = 2.0 * f
# Counter divide of 100 MHz: tog flips every DIV cycles -> out = 100/(2*DIV).
# Exact when 50/f is a positive integer (fast = 100/DIV).
if f <= 60 and abs(round(50/f) - 50/f) < 1e-9 and (50/f) == int(50/f):
    div = int(round(50/f))
    print(0, div, 8, 8, 100.0/(2*div))
    sys.exit(0)
# PLL path: CLKOUT0 = f = 100*MULT/DIV0 directly, VCO=100*MULT in [800,1600].
best = None
for mult in range(8, 17):
    vco = 100.0 * mult
    for div0 in range(1, 129):
        out = vco / div0
        err = abs(out - f)
        if best is None or err < best[0]:
            best = (err, mult, div0, out)
_, mult, div0, actual = best
print(1, 2, mult, div0, actual)
PY
)
EOF

echo ">>> $FMHZ MHz : USE_PLL=$USE_PLL DIV=$DIV MULT=$PLL_MULT DIV0=$PLL_DIV0 actual=$ACTUAL MHz"

# --- synth ---
yosys -q -p "
  read_verilog -DPLL_MULT=$PLL_MULT -DPLL_DIV0=$PLL_DIV0 $PROJ/sig.v;
  chparam -set FMHZ $FMHZ -set USE_PLL $USE_PLL -set DIV $DIV sig;
  synth_xilinx -flatten -abc9 -arch xc7 -top sig;
  write_json $OUT/sig.json
" 2> "$OUT/yosys.log" || { echo "YOSYS FAILED"; tail -20 "$OUT/yosys.log"; exit 1; }

# --- place & route ---
"$NPNR" --chipdb "$CHIPDB" --xdc "$PROJ/sig.xdc" \
        --json "$OUT/sig.json" --fasm "$OUT/sig.fasm" \
        > "$OUT/nextpnr.log" 2>&1 || { echo "NEXTPNR FAILED"; tail -25 "$OUT/nextpnr.log"; exit 1; }

# --- fasm -> frames -> bitstream ---
# Vivado freq-hint features the open prjxray-db lacks; the PLL still locks.
grep -vE "CLK_FREQ_BB|_CLK_FREQ_" "$OUT/sig.fasm" > "$OUT/sig.clean.fasm"
python3 "$FASM2FRAMES" --part "$PART" --db-root "$XRAY_DB/artix7" \
        "$OUT/sig.clean.fasm" > "$OUT/sig.frames" 2> "$OUT/fasm2frames.log" \
        || { echo "FASM2FRAMES FAILED"; tail -20 "$OUT/fasm2frames.log"; exit 1; }

"$XRAY_TOOLS/xc7frames2bit" --part_file "$XRAY_DB/artix7/$PART/part.yaml" \
        --part_name "$PART" --frm_file "$OUT/sig.frames" \
        --output_file "$OUT/sig.bit" > "$OUT/frames2bit.log" 2>&1 \
        || { echo "FRAMES2BIT FAILED"; tail -20 "$OUT/frames2bit.log"; exit 1; }

echo ">>> bitstream: $(stat -c%s "$OUT/sig.bit") bytes"

# --- flash (SRAM, volatile — fast; re-flash each sweep step) ---
$SUDO "$OFL" -b alchitry_au -m "$OUT/sig.bit" 2>&1 | tail -4
echo ">>> flashed $ACTUAL MHz"
