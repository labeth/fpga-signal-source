# FPGA test-signal source

A crystal-accurate signal generator used to characterize and demo a clean-room
scope firmware — an **Alchitry Au** (Xilinx **XC7A35T-ftg256**) driving one
channel with exact, repeatable tones and bursts. This is bench test gear, wholly
independent of the firmware (see
[open-sds1000cml](https://github.com/labeth/open-sds1000cml)); it just lets us
feed the instrument a known signal (e.g. to validate the super-resolution
stacker, or to find the real detection ceiling).

## Wiring

| FPGA | Signal | To |
|---|---|---|
| ball **N14** | 100 MHz oscillator | (on-board) |
| ball **G1** (Alchitry `A20`, bank 35, 3.3 V LVCMOS) | `c1` output | scope **C1** |
| ball **M6** (Alchitry `A27`, `IO_L19P_T3`, 3.3 V LVCMOS) | `c2` output | scope **C2** |

Drive each channel with a 10× probe or a direct coax; keep the ground short. The
output is a 3.3 V logic square wave — its odd harmonics are real and useful (they
exercise higher frequencies than the fundamental). The single-tone `sig.v` drives
C1 only; the **protocol generators** below drive both C1 and C2 (a second channel
is required for the two-wire SPI/I2C decoders).

## Signals

- **`sig.v`** — single tone. Two mechanisms, picked automatically by `build.sh`:
  a counter/toggle divide of the 100 MHz clock for the clean low end (≤ ~50 MHz),
  or a `PLLE2` whose output clock is forwarded straight to the pin for the high
  end (up to ~460 MHz on the -1 part — above the scope's 250 MHz Nyquist).
- **`burst.v`** — a frequency-stepped burst: 5 cycles of 50 MHz, 15 of 150 MHz,
  25 of 250 MHz, each segment 100 ns, repeating at **3.33 MHz**. One `PLLE2`
  makes all three phase-locked; two cascaded `BUFGCTRL` clock-mux the selected
  tone to the pin. The low repetition rate triggers cleanly, and the distinctive
  three-burst shape gives the stacker an unambiguous alignment lock.
- **`sig.xdc`** — pin/clock constraints (shared by `sig.v` / `burst.v`).

### Protocol-decode ground truth

These feed the scope's serial-protocol decoder ([`app/internal/decode`](https://github.com/labeth/open-sds1000cml/tree/main/app/internal/decode)
on the instrument, `internal/web/decode.js` in the browser) a known byte stream.
All send the same 8-byte message `"Hi \x55\xAA\x0F\xF0\n"` — human-readable ASCII
plus alternating/edge bit patterns (`0x55 0xAA 0x0F 0xF0`) that catch bit-order
and sampling-phase bugs.

- **`uart.v`** — 8N1, LSB-first, 115200 baud, mirrored on **C1 and C2** (decode
  either). Repeats with an idle gap so the scope frames it.
- **`spi.v`** — SPI **Mode 0** (CPOL=0, CPHA=0), MSB-first, 200 kHz: **SCLK on C1**
  (G1), **MOSI on C2** (M6). Idle gap between repeats re-frames the CS-less decoder.
- **`i2c.v`** — one repeating **I2C** transaction (~200 kHz): START, addr `0x24`+W,
  ACK, data `0x55 0xAA 0x0F 0xF0` (each ACKed), STOP. **SCL on C1** (G1), **SDA on
  C2** (M6). Driven from a quarter-period (SCL,SDA) ROM so SDA only ever switches
  mid-SCL-low — never on an SCL edge, which would forge a START/STOP.
- **`proto.xdc`** — shared constraints (all three modules expose `clk`, `c1`, `c2`).

```sh
./build-proto.sh uart    # flash the UART generator (C1 = C2 = TX)
./build-proto.sh spi     # flash the SPI generator  (C1 = SCLK, C2 = MOSI)
./build-proto.sh i2c     # flash the I2C generator  (C1 = SCL,  C2 = SDA)
```

Verified on hardware (Alchitry driving both scope channels): for **all three**
protocols the on-device (Go) and browser (JS) decoders produce **byte-for-byte
identical** output on the same captured frame, and the instrument's on-trace
decode strip shows the same bytes — UART `"Hi \x55\xAA\x0F\xF0\n"`, SPI the same
8 bytes, I2C `S 24 W · 55 AA 0F F0 · P`. `app/internal/decode` also carries
round-trip unit tests for each.

## Toolchain

An all-open Xilinx flow — no Vivado. Point `$FPGA` at a directory containing
these (all built from source; see each project's README):

```
$FPGA/
  oss-cad-suite/        # yosys + friends on PATH
  nextpnr-xilinx/       # nextpnr-xilinx + xilinx/xc7a35t.bin chipdb
  prjxray/  prjxray-db/ # fasm2frames.py, xc7frames2bit, artix7 db
  openFPGALoader/       # build/openFPGALoader (FT2232 JTAG)
```

Then:

```sh
export FPGA=/path/to/toolchain          # default: $HOME/fpga
export SCOPE=192.168.1.50:8080          # your scope's web API (for measure.py)
# flashing the Au's SRAM may need root or a udev rule:
export SUDO=sudo                        # only if your user can't reach the JTAG

./build.sh 50            # synth + P&R + flash a 50 MHz tone
./build-burst.sh         # flash the 50/150/250 MHz burst
python3 measure.py 50    # incoherent power-spectrum measure of C1 @ 50 MHz
```

`build.sh` flashes volatile SRAM (fast, re-flash per sweep step); power-cycling
the Au clears it.

## Gotchas (that cost real time)

- **`LOC`, not `PACKAGE_PIN`** in the XDC, and only `IOSTANDARD` / `create_clock`
  — nextpnr-xilinx's XDC parser asserts on `SLEW`/`DRIVE`/`PACKAGE_PIN`.
- **Avoid `ODDR`** — it crashes nextpnr-xilinx (`!is_string` assertion). Forward a
  clock straight to the pin, or use a toggle FF, instead.
- **`BUFGMUX` won't place** ("no BELs remaining"); use the underlying `BUFGCTRL`
  as a 2:1 clock mux (`.S0(~sel) .S1(sel) .IGNORE0/1(1'b1) .CE0/1(1'b1)`).
- **PLL builds** emit `*_CLK_FREQ_BB*` fasm features the open prjxray-db lacks —
  `grep -vE "CLK_FREQ_BB|_CLK_FREQ_"` them out before `fasm2frames`; the PLL
  still locks (they're Vivado frequency hints only).
- GCC 15 needs `-DCMAKE_CXX_FLAGS="-include cstdint"` to build nextpnr-xilinx and
  prjxray.

## What we measured with it

The scope's **maximum detectable frequency ≈ 250 MHz** = the 500 MS/s ADC
Nyquist; above that, tones **alias** (300→200, 350→150, …). The limit is the
sample rate, not the analog bandwidth (which only attenuates) or noise. The burst
pattern also makes the super-resolution stacker's frequency-dependent gain
visible in one capture (large gain at 50 MHz, tapering near Nyquist where
alignment jitter — not noise — dominates).
