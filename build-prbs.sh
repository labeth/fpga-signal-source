#!/usr/bin/env bash
# build-prbs.sh <mbps> [JA_cycles] [JP_bits] — PRBS7 eye/jitter source.
#   mbps: bit rate; 100/mbps must be an even integer (2,4,5,10,20,25,50 Mbps ok)
#   JA:   jitter amplitude in 10ns sysclk cycles (square-wave PM; 0 = clean)
#   JP:   jitter period in bits (power of two, default 32) -> f_j = bitrate/JP
# TIE: square wave pp = 2*JA*10ns, fundamental (4/pi)*JA*10ns at f_j.
set -e
MBPS="${1:?usage: build-prbs.sh <mbps> [JA] [JP]}"; JA="${2:-0}"; JP="${3:-32}"
DIV=$((100 / MBPS))
[ $((DIV * MBPS)) -eq 100 ] || { echo "100/$MBPS not integer"; exit 1; }
[ $((DIV % 2)) -eq 0 ] || { echo "DIV=$DIV must be even (bit clock)"; exit 1; }
[ $((2 * JA)) -lt $DIV ] || { echo "2*JA must be < DIV=$DIV"; exit 1; }
FPGA=/home/labeth/ws/fpga; PROJ=$FPGA/proj; OUT=$PROJ/out; mkdir -p "$OUT"
export PATH="$FPGA/oss-cad-suite/bin:$PATH"; export PYTHONPATH="$FPGA/prjxray:${PYTHONPATH:-}"
PART=xc7a35tftg256-1
echo ">>> PRBS7 ${MBPS} Mbps (DIV=$DIV) JA=$JA JP=$JP  f_j=$((MBPS * 1000 / JP)) kHz  TIEpp=$((2 * JA * 10)) ns"
yosys -q -p "read_verilog $PROJ/prbs.v; chparam -set DIV $DIV -set JA $JA -set JP $JP sig; synth_xilinx -flatten -abc9 -arch xc7 -top sig; write_json $OUT/prbs.json" 2>"$OUT/y.log" || { echo YOSYS; tail -20 "$OUT/y.log"; exit 1; }
$FPGA/nextpnr-xilinx/nextpnr-xilinx --chipdb $FPGA/nextpnr-xilinx/xilinx/xc7a35t.bin --xdc $PROJ/prbs.xdc --json $OUT/prbs.json --fasm $OUT/prbs.fasm >"$OUT/n.log" 2>&1 || { echo NEXTPNR; tail -25 "$OUT/n.log"; exit 1; }
grep -vE "CLK_FREQ_BB|_CLK_FREQ_" "$OUT/prbs.fasm" > "$OUT/prbs.clean.fasm"
python3 $FPGA/prjxray/utils/fasm2frames.py --part $PART --db-root $FPGA/prjxray-db/artix7 "$OUT/prbs.clean.fasm" > "$OUT/prbs.frames" 2>"$OUT/f.log" || { echo FASM2FRAMES; tail -20 "$OUT/f.log"; exit 1; }
$FPGA/prjxray/build/tools/xc7frames2bit --part_file $FPGA/prjxray-db/artix7/$PART/part.yaml --part_name $PART --frm_file "$OUT/prbs.frames" --output_file "$OUT/prbs.bit" >"$OUT/b.log" 2>&1 || { echo FRAMES2BIT; tail -20 "$OUT/b.log"; exit 1; }
echo ">>> prbs.bit $(stat -c%s $OUT/prbs.bit) bytes"
echo a | sudo -S -p "" $FPGA/openFPGALoader/build/openFPGALoader -b alchitry_au -m "$OUT/prbs.bit" 2>&1 | tail -2
echo ">>> flashed PRBS7 ${MBPS}Mbps JA=$JA JP=$JP on C1=G1 (data) + C2=M6 (ideal clock)"
