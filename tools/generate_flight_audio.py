"""Original, reproducible on-board lunar lander sound design (stdlib only).

All sounds are synthetic, royalty-free original creations. The lunar environment
is a vacuum: these cues represent structural/onboard or instrument sound, not
sound propagated through air in space. F08 WAVs are never rewritten.
"""
from __future__ import annotations

from array import array
import math
from pathlib import Path
import random
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
ASSETS = {
    'engine_rumble': (2.0, True),
    'engine_turbine': (2.0, True),
    'engine_ignition': (0.88, False),
    'engine_cutoff': (0.72, False),
    'rcs_hiss': (0.8, True),
    'rcs_pulse': (0.34, False),
    'landing_gear': (0.80, False),
    'crash': (1.52, False),
    'landing_confirm': (1.15, False),
}


def render(name: str, seconds: float | None = None, loop: bool | None = None) -> bytes:
    if name not in ASSETS:
        raise ValueError('Unknown F19 clip: ' + name)
    original_seconds, is_loop = ASSETS[name]
    seconds = original_seconds if seconds is None else seconds
    loop = is_loop if loop is None else loop
    count = int(round(RATE * seconds))
    if count < 100:
        raise ValueError('Invalid clip duration')
    seed = sum((i + 1) * ord(char) for i, char in enumerate(name)) + 19192026
    rng = random.Random(seed)
    slow = 0.0
    fast = 0.0
    high = 0.0
    phase = 0.0
    pcm = array('h')
    for i in range(count):
        t = i / RATE
        u = i / count
        noise = rng.uniform(-1.0, 1.0)
        slow += 0.022 * (noise - slow)
        fast += 0.29 * (noise - fast)
        high = noise - fast
        breath = 0.87 + 0.13 * math.sin(2.0 * math.pi * (4.0 * t + 0.09 * math.sin(2 * math.pi * 1.5 * t)))
        if name == 'engine_rumble':
            # Deep, modulated vibration through hull + low-pass exhaust turbulence.
            signal = (0.31 * math.sin(2 * math.pi * 49 * t + 0.18 * math.sin(2 * math.pi * 7 * t))
                      + 0.17 * math.sin(2 * math.pi * 98 * t)
                      + 1.25 * slow + 0.17 * fast) * breath
        elif name == 'engine_turbine':
            signal = (0.16 * math.sin(2 * math.pi * (247 * t + 0.13 * math.sin(2 * math.pi * 3.0 * t)))
                      + 0.10 * math.sin(2 * math.pi * 492 * t)
                      + 0.48 * high + 0.42 * fast) * breath
        elif name == 'engine_ignition':
            env = min(1.0, t / 0.028) * (1.0 - u) ** 0.55
            signal = env * (0.80 * slow + 0.23 * high
                             + 0.26 * math.sin(2 * math.pi * (45 * t + 120 * t * t)))
        elif name == 'engine_cutoff':
            env = math.exp(-5.0 * u)
            signal = env * (0.58 * fast + 0.65 * slow
                            + 0.25 * math.sin(2 * math.pi * (310 * t - 125 * t * t)))
        elif name == 'rcs_hiss':
            signal = 0.42 * high + 0.86 * fast + 0.23 * math.sin(2 * math.pi * 760 * t)
        elif name == 'rcs_pulse':
            env = min(1.0, t / 0.008) * math.exp(-9.0 * u)
            signal = env * (0.55 * high + 0.95 * fast + 0.18 * math.sin(2 * math.pi * 900 * t))
        elif name == 'landing_gear':
            env = math.exp(-14.0 * u)
            secondary = math.exp(-max(0.0, t - 0.14) * 28.0) if t >= 0.14 else 0.0
            signal = (0.43 * math.sin(2 * math.pi * (80 * t + 0.3 * math.sin(2 * math.pi * 9 * t)))
                      + 0.80 * slow + 0.22 * high) * env + secondary * (0.15 * fast)
        elif name == 'crash':
            env = math.exp(-5.6 * u)
            transient = math.exp(-30.0 * u)
            signal = env * (0.25 * math.sin(2 * math.pi * 64 * t)
                            + 1.15 * slow + 0.44 * fast) + transient * (0.43 * high)
        elif name == 'landing_confirm':
            # Subtle avionics double acknowledgement, not an arcade fanfare.
            tone = 0.0
            for start, freq, duration in ((0.10, 640.0, 0.19), (0.42, 810.0, 0.27)):
                local_t = t - start
                if 0.0 <= local_t <= duration:
                    envelope = math.sin(math.pi * local_t / duration) ** 2
                    tone += 0.24 * envelope * math.sin(2 * math.pi * freq * local_t)
            signal = tone
        else:
            raise AssertionError(name)
        if loop:
            # Short symmetric edge guard; continuous bed layers overlap in mix.
            guard = min(1.0, i / (RATE * 0.024), (count - 1 - i) / (RATE * 0.024))
            signal *= max(0.0, guard)
        else:
            signal *= min(1.0, i / 120.0, (count - 1 - i) / 180.0)
        value = max(-32767, min(32767, int(round(signal * 18800.0))))
        pcm.append(value)
    return pcm.tobytes()


def main() -> None:
    OUT.mkdir(exist_ok=True, parents=True)
    for clip, (seconds, loop) in ASSETS.items():
        with wave.open(str(OUT / (clip + '.wav')), 'wb') as sound:
            sound.setnchannels(1)
            sound.setsampwidth(2)
            sound.setframerate(RATE)
            sound.writeframes(render(clip, seconds, loop))
        print(f'{clip}.wav: {seconds:.2f}s')


if __name__ == '__main__':
    main()
