#!/usr/bin/env python3
# measure.py <expected_mhz> [n_frames] [tdiv_s]
# Incoherent power-spectrum averaging of raw scope frames (500 MS/s band):
# FFT each frame with a Hann window, average |FFT|^2, then report the peak
# nearest the expected frequency, its amplitude in volts, the measured
# frequency, the noise floor and SNR. This is the spectrum-analyzer method
# (RMS averaging) — robust for pure frequency detection and independent of
# trigger phase, so it works right up to the raw Nyquist.
import os, sys, json, struct, time, urllib.request
import numpy as np

DEV = os.environ.get("SCOPE", "scope.local:8080")  # set SCOPE=<ip>:8080
EXP = float(sys.argv[1]) * 1e6 if len(sys.argv) > 1 else 25e6
NFR = int(sys.argv[2]) if len(sys.argv) > 2 else 40
TDIV = float(sys.argv[3]) if len(sys.argv) > 3 else 5e-9

def post(control, value):
    body = json.dumps({"control": control, "value": value}).encode()
    urllib.request.urlopen(f"http://{DEV}/api/set", body, timeout=5).read()

def raw_frame(since):
    b = urllib.request.urlopen(
        f"http://{DEV}/api/frame.bin?since={since}&raw=1", timeout=5).read()
    if len(b) < 8 or b[0] != 0xF5:
        return None
    h = struct.unpack("<I", b[4:8])[0]
    hdr = json.loads(b[8:8+h].decode())
    pay = b[8+h:]
    if hdr.get("unchanged") or "cols" not in hdr:
        return hdr, None
    n = hdr["cols"]
    c1 = np.frombuffer(pay[:n], dtype=np.uint8).astype(np.float64)
    return hdr, c1

post("memdepth", 20480)
post("tdiv", TDIV)
post("run", 1)
time.sleep(1.2)

# Collect N distinct frames.
frames = []
last = 0
hdr0 = None
t0 = time.time()
while len(frames) < NFR and time.time() - t0 < 40:
    r = raw_frame(last)
    if r is None:
        continue
    hdr, c1 = r
    seq = hdr.get("seq", 0)
    if c1 is None or seq == last:
        last = seq or last
        time.sleep(0.02)
        continue
    last = seq
    hdr0 = hdr
    frames.append(c1)

if not frames or hdr0 is None:
    print(json.dumps({"expMHz": EXP/1e6, "err": "no frames"}))
    sys.exit(0)

ss = hdr0["sample_s"]
vpc = hdr0.get("vpc1", 1/32)
N = min(len(f) for f in frames)
N = 1 << (int(np.log2(N)))          # power of two for the FFT
win = np.hanning(N)
cg = win.mean()                     # Hann coherent gain (~0.5)
fs = 1.0 / ss
freqs = np.fft.rfftfreq(N, ss)

# Incoherent (power) average.
psum = np.zeros(len(freqs))
for c1 in frames:
    x = c1[:N] - c1[:N].mean()
    X = np.fft.rfft(x * win)
    psum += np.abs(X)**2
pavg = psum / len(frames)
mag = np.sqrt(pavg)                 # RMS magnitude per bin

def amp_v(m):                       # windowed peak |X| -> sine amplitude (volts)
    return (2.0 * m / (N * cg)) * vpc

# Fold the expected frequency into the Nyquist band (aliasing): the real
# peak of an above-Nyquist tone lands at its alias, so search there.
def fold(f, fs):
    f = f % fs
    return fs - f if f > fs/2 else f
search_hz = fold(EXP, fs)
# Peak within +/-1% of the (folded) expected frequency.
kc = int(round(search_hz / (fs/2) * (len(freqs)-1)))
win_k = max(3, int(0.01 * kc))
lo, hi = max(1, kc-win_k), min(len(freqs)-1, kc+win_k)
kpk = lo + int(np.argmax(mag[lo:hi+1]))
# parabolic refine
if 0 < kpk < len(freqs)-1:
    a, b, c = mag[kpk-1], mag[kpk], mag[kpk+1]
    den = a - 2*b + c
    kref = kpk + (0.5*(a-c)/den if den < 0 else 0)
else:
    kref = kpk
f_meas = kref * (fs/2) / (len(freqs)-1)

# Noise floor: median magnitude away from DC, peak and its harmonics.
mask = np.ones(len(freqs), bool)
mask[:int(0.01*len(freqs))] = False
for h in range(1, 8):
    kh = int(round(h*EXP/(fs/2)*(len(freqs)-1)))
    if kh < len(freqs):
        mask[max(0,kh-4*win_k):kh+4*win_k] = False
noise = np.median(mag[mask]) if mask.any() else 1e-9

# Global peak below raw Nyquist (to catch aliases when driving > Nyquist).
kglob = 1 + int(np.argmax(mag[1:]))
out = {
    "expMHz": round(EXP/1e6, 3),
    "frames": len(frames),
    "fMeasMHz": round(f_meas/1e6, 4),
    "ampVpk": round(amp_v(mag[kpk]), 5),
    "snrDb": round(20*np.log10(mag[kpk]/noise), 2),
    "peakDbc": round(20*np.log10(mag[kpk]/mag.max()), 2),
    "noiseVpk": round(amp_v(noise), 6),
    "globalPeakMHz": round(freqs[kglob]/1e6, 4),
    "rawNyqMHz": round(fs/2/1e6, 1),
    "binMHz": round((fs/2)/(len(freqs)-1)/1e6, 4),
    "codeRange": [int(min(f.min() for f in frames)), int(max(f.max() for f in frames))],
}
# Alias flag: if the strongest in-band peak sits far from where we expected the
# tone AND the expected freq is above Nyquist, the scope is showing an alias.
alias_hz = None
if EXP > fs/2:
    alias_hz = abs(((EXP + fs/2) % fs) - fs/2)   # fold into [0, Nyquist]
    out["expectedAliasMHz"] = round(alias_hz/1e6, 3)
out["freqErrKHz"] = round((f_meas - search_hz)/1e3, 1)
out["searchMHz"] = round(search_hz/1e6, 3)
out["detected"] = bool(out["snrDb"] > 6.0)
print(json.dumps(out))
