#!/usr/bin/env python3
"""gen_midi_song.py — write the MIDI song ROM for midi_song.v.

The song is the opening section of Beethoven's "Fuer Elise" (WoO 59, public
domain), entered by hand below: the A theme with its repeat (first and second
endings), the C major middle phrase, the E-D# bridge and the A theme again,
ending on A minor. Right hand on MIDI channel 1, left hand on channel 2 (both
Acoustic Grand Piano), a sustained string pad on channel 3 (String Ensemble 1).
Program changes go out only at the loop start. The loop is LOOP_MS long.

ROM word (24 bits, one per hex line):
  [23]    last entry: the sequencer wraps to entry 0 after it
  [22:8]  delay in ms, counted from the start of the previous byte
  [7:0]   the byte to send
The sequencer starts a byte once the delay has passed AND the previous byte has
left the UART (10 bits x 32 us = 320 us), so a delay of 0 sends back to back.
This script models that rule exactly when it rounds the delays, so timing errors
never accumulate; the loop is LOOP_MS to within half a millisecond.

Usage: gen_midi_song.py [out.hex [schedule.txt]]
out.hex defaults to midi_song.hex beside this script. schedule.txt, if given,
gets the planned byte schedule (start us from the first byte, byte), which a
simulation check compares the line against.
"""
import os
import sys

SIXTEENTH_MS = 135      # Poco moto: an eighth ~ 270 ms, a 3/8 bar 810 ms
LOOP_MS = 26000
BYTE_US = 320           # 10 bits at 31250 Bd
ROM_DEPTH = 2048

CH_RH, CH_LH, CH_PAD = 0, 1, 2          # MIDI channels 1, 2, 3
PROGRAMS = {CH_RH: 0, CH_LH: 0, CH_PAD: 48}  # GM: piano, piano, string ensemble 1

VEL_RH, VEL_RH_ACCENT, VEL_LH, VEL_PAD = 72, 86, 56, 42

# Pad chords (string voicing around middle C).
CHORDS = {
    "Am": ["A3", "C4", "E4"],
    "E":  ["G#3", "B3", "E4"],
    "C":  ["G3", "C4", "E4"],
    "G":  ["G3", "B3", "D4"],
}

# Bars: (right hand, left hand, pad chord). Right hand tokens are NOTE[:len] or
# r[:len] in sixteenths (len 1 if omitted). Left hand is the broken-chord figure
# in sixteenths from the downbeat, held (pedal) to the end of the bar.
UPBEAT = ("E5 D#5", "", None)
A1 = ("E5 D#5 E5 B4 D5 C5", "", "Am")
A2 = ("A4:2 r C4 E4 A4", "A2 E3 A3", "Am")
A3 = ("B4:2 r E4 G#4 B4", "E2 E3 G#3", "E")
A4 = ("C5:2 r E4 E5 D#5", "A2 E3 A3", "Am")
A7 = ("B4:2 r E4 C5 B4", "E2 E3 G#3", "E")
END1 = ("A4:2 r:2 E5 D#5", "A2 E3 A3", "Am")     # first ending, back to bar 1
END2 = ("A4:2 r B4 C5 D5", "A2 E3 A3", "Am")     # second ending, on to bar 9
THEME = [A1, A2, A3, A4, A1, A2, A7]
MIDDLE = [
    ("E5:3 G4 F5 E5", "C3 G3 C4", "C"),
    ("D5:3 F4 E5 D5", "G2 G3 B3", "G"),
    ("C5:3 E4 D5 C5", "A2 E3 A3", "Am"),
    ("B4:2 r E4 E5 r", "E2 E3", "E"),
    ("r E5 E6 r r D#5", "", "E"),
    ("E5 r r D#5 E5 D#5", "", "E"),
]
FINAL = ("A4:6", "A2 E3 A3", "Am")
SONG = [UPBEAT] + THEME + [END1] + THEME + [END2] + MIDDLE + THEME + [FINAL]
FINAL_HOLD_MS = 600     # the last chord rings this long past its bar

NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_note(name):
    """C4 = 60 (middle C), sharps with '#'."""
    pc = NAMES[name[0]]
    rest = name[1:]
    if rest.startswith("#"):
        pc += 1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + pc


def tokens(s):
    for tok in s.split():
        name, _, ln = tok.partition(":")
        yield name, int(ln or 1)


def events():
    """(t_ms, order, bytes): order 0 offs, 1 program changes, 2 ons."""
    ev = []
    for ch, prog in PROGRAMS.items():
        ev.append((0, 1, [0xC0 | ch, prog]))
    t16 = 0                   # running time in sixteenths
    pad_on, pad_name = [], None
    for bi, (rh, lh, chord) in enumerate(SONG):
        bar_len = sum(n for _, n in tokens(rh))
        bar_t = t16 * SIXTEENTH_MS
        bar_end = (t16 + bar_len) * SIXTEENTH_MS
        last = bi == len(SONG) - 1
        # right hand
        p = t16
        for name, n in tokens(rh):
            if name != "r":
                k = midi_note(name)
                vel = VEL_RH_ACCENT if p == t16 and bar_len == 6 else VEL_RH
                on = p * SIXTEENTH_MS
                off = (p + n) * SIXTEENTH_MS - 15 + (FINAL_HOLD_MS if last else 0)
                ev.append((on, 2, [0x90 | CH_RH, k, vel]))
                ev.append((off, 0, [0x80 | CH_RH, k, 64]))
            p += n
        # left hand: broken chord, held with the pedal to the bar end
        for i, name in enumerate(lh.split()):
            k = midi_note(name)
            ev.append((bar_t + i * SIXTEENTH_MS, 2, [0x90 | CH_LH, k, VEL_LH]))
            ev.append((bar_end - 20 + (FINAL_HOLD_MS if last else 0), 0, [0x80 | CH_LH, k, 64]))
        # pad: change only when the chord changes
        if chord and chord != pad_name:
            for k in pad_on:
                ev.append((bar_t - 30, 0, [0x80 | CH_PAD, k, 64]))
            pad_on = [midi_note(n) for n in CHORDS[chord]]
            pad_name = chord
            for k in pad_on:
                ev.append((bar_t, 2, [0x90 | CH_PAD, k, VEL_PAD]))
        t16 += bar_len
    end = t16 * SIXTEENTH_MS + FINAL_HOLD_MS
    for k in pad_on:
        ev.append((end, 0, [0x80 | CH_PAD, k, 64]))
    assert end < LOOP_MS - 300, f"song {end} ms does not fit the {LOOP_MS} ms loop"
    ev.sort(key=lambda e: (e[0], e[1]))
    return ev


def schedule(ev):
    """ROM entries [(delay_ms, byte)] and the modelled byte starts (us)."""
    rom, starts = [], []
    prev = None               # start of the previous byte, us
    for t_ms, _, msg in ev:
        for j, b in enumerate(msg):
            if prev is None:
                d = 0             # entry 0's delay is the loop wrap, set below
                start = 0
            else:
                want = t_ms * 1000 - prev if j == 0 else 0
                d = max(0, round(want / 1000))
                start = prev + max(d * 1000, BYTE_US)
            rom.append([d, b])
            starts.append(start)
            prev = start
    wrap = round((LOOP_MS * 1000 - prev) / 1000)
    assert wrap >= 1
    rom[0][0] = wrap
    return rom, starts, prev + wrap * 1000


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "midi_song.hex")
    ev = events()
    rom, starts, loop_us = schedule(ev)
    assert len(rom) <= ROM_DEPTH, f"{len(rom)} entries > ROM depth {ROM_DEPTH}"
    with open(out, "w") as f:
        for i, (d, b) in enumerate(rom):
            assert 0 <= d < 1 << 15
            last = 1 if i == len(rom) - 1 else 0
            f.write(f"{(last << 23) | (d << 8) | b:06x}\n")
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as f:
            f.write(f"# loop_us {loop_us} entries {len(rom)} (first byte waits entry 0's delay {rom[0][0]} ms)\n")
            for s, (d, b) in zip(starts, rom):
                f.write(f"{s} {b:02x}\n")
    notes = sum(1 for e in ev if e[2][0] & 0xF0 == 0x90)
    print(f"{out}: {len(rom)} entries, {len(ev)} messages ({notes} notes), "
          f"loop {loop_us} us, song ends at {max(e[0] for e in ev)} ms")


if __name__ == "__main__":
    main()
