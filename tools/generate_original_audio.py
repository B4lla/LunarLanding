"""Create deterministic, original synthesized sound effects (no third-party recordings).

These are craft/cockpit audio cues; lunar vacuum does not transmit external sound.
Run from any directory. The generated WAVs are committed to the project for offline use.
"""
from __future__ import annotations

from array import array
import math
from pathlib import Path
import random
import wave

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
RATE = 22050


def render(kind: str, duration: float, loop: bool) -> bytes:
    n = int(duration * RATE)
    noise = random.Random({'engine': 43, 'rcs': 71, 'touchdown': 92}[kind])
    values = array('h')
    lowpass = 0.0
    for i in range(n):
        t = i / RATE
        phase = i / n
        lowpass += 0.07 * (noise.uniform(-1, 1) - lowpass)
        if kind == 'engine':
            signal = (0.41 * math.sin(2 * math.pi * 53 * t) +
                      0.20 * math.sin(2 * math.pi * 106 * t) +
                      0.16 * math.sin(2 * math.pi * 159 * t) +
                      0.42 * lowpass)
        elif kind == 'rcs':
            signal = 0.23 * math.sin(2 * math.pi * 390 * t) + 0.45 * lowpass
        else:
            # Brief, damped onboard impact cue; low-volume by default.
            decay = (1 - phase) ** 3
            signal = decay * (0.48 * math.sin(2 * math.pi * 118 * t)
                              + 0.28 * math.sin(2 * math.pi * 225 * t) + 0.16 * lowpass)
        if loop:
            # Removes clicks at the loop boundary while retaining a steady bed.
            edge = min(1.0, i / (RATE * .09), (n - 1 - i) / (RATE * .09))
            signal *= max(0, edge)
        values.append(max(-32767, min(32767, round(signal * 18000))))
    return values.tobytes()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, duration, loop in [('engine', 2.0, True), ('rcs', 1.0, True), ('touchdown', 0.65, False)]:
        with wave.open(str(OUT / f'{name}.wav'), 'wb') as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(RATE)
            file.writeframes(render(name, duration, loop))
        print(f'{name}.wav created')


if __name__ == '__main__':
    main()
