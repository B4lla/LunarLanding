"""F37 original synthetic sound beds, deterministic, no downloaded audio.

Layered *broadband* rocket rumble and compressed-gas RCS noise. Loops use
periodic spectral noise instead of abrupt gated tails/short repeating ticks.
Usage: python tools/generate_legacy_audio.py
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import wave
import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio_legacy'
# Preserve old F08/F19 WAVs for regression and fallback.
CLIPS = {
    'engine_rumble': 6.0,
    'engine_turbine': 6.0,
    'engine_ignition': 1.55,
    'engine_cutoff': 1.35,
    'rcs_hiss': 4.0,
    'rcs': 4.0,
    'rcs_pulse': 0.62,
}


def _band(noise: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """Smooth zero-phase spectral band: no recursive/filter edge clicks."""
    n = len(noise)
    freq = np.fft.rfftfreq(n, 1 / RATE)
    low_roll = np.clip((freq - lo * 0.62) / max(1, lo * 0.60), 0, 1)
    high_roll = np.clip((hi * 1.4 - freq) / max(1, hi * 0.5), 0, 1)
    spectrum = np.fft.rfft(noise) * low_roll * high_roll
    filtered = np.fft.irfft(spectrum, n=n)
    return filtered / max(np.std(filtered), 1e-8)


def render(name: str) -> np.ndarray:
    if name not in CLIPS:
        raise ValueError(name)
    n = int(CLIPS[name] * RATE)
    rng = np.random.default_rng(int.from_bytes(hashlib.sha256(name.encode()).digest()[:8], 'little'))
    raw = rng.standard_normal(n)
    t = np.arange(n) / RATE
    p = t / CLIPS[name]  # periodic envelopes for looping beds
    low = _band(raw, 42, 340)
    mid = _band(raw, 190, 2200)
    air = _band(raw, 850, 6800)
    sub = _band(raw, 24, 115)

    if name == 'engine_rumble':
        slow = 0.94 + 0.06 * np.sin(2 * np.pi * 3 * p)
        signal = slow * (0.39 * sub + 0.34 * low + 0.21 * mid + 0.085 * air)
    elif name == 'engine_turbine':
        # An airframe-transmitted, steady roar; avoid whines/synthetic pitch ticks.
        mod = 0.92 + 0.08 * np.sin(2 * np.pi * 7 * p)
        signal = mod * (0.21 * low + 0.41 * mid + 0.31 * air)
    elif name in ('rcs_hiss', 'rcs'):
        # Sustained high-pressure cold-gas release: open nozzle turbulence.
        signal = (0.12 * low + 0.28 * mid + 0.50 * air) * (
            0.93 + 0.07 * np.sin(2 * np.pi * 5 * p))
    elif name == 'rcs_pulse':
        # Long air jet with a soft valve onset, not a dry electrical click.
        envelope = np.minimum(1, t / 0.055) * np.minimum(1, (CLIPS[name] - t) / 0.24)
        signal = envelope * (0.08 * low + 0.30 * mid + 0.50 * air)
    elif name == 'engine_ignition':
        envelope = np.minimum(1, t / 0.14) * np.minimum(1, (CLIPS[name] - t) / 0.43)
        signal = envelope * (0.42 * sub + 0.39 * low + 0.25 * mid + 0.14 * air)
    else:
        envelope = np.minimum(1, t / 0.03) * np.exp(-3.3 * t / CLIPS[name])
        envelope *= np.minimum(1, (CLIPS[name] - t) / 0.16)
        signal = envelope * (0.30 * sub + 0.27 * low + 0.27 * mid + 0.16 * air)

    if name in ('engine_rumble', 'engine_turbine', 'rcs_hiss', 'rcs'):
        # Blend both ends into a common boundary amplitude. This does not
        # silence the loop for 24 ms as the old assets did.
        edge = int(RATE * 0.012)
        boundary = 0.5 * (signal[0] + signal[-1])
        fade = np.arange(edge) / edge
        signal[:edge] = boundary * (1 - fade) + signal[:edge] * fade
        signal[-edge:] = signal[-edge:] * (1 - fade) + boundary * fade
    peak = np.max(np.abs(signal))
    return np.asarray(np.clip(signal * (0.77 / max(peak, 1e-8)) * 32767, -32767, 32767), dtype='<i2')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in CLIPS:
        data = render(name)
        with wave.open(str(OUT / f'{name}.wav'), 'wb') as sound:
            sound.setnchannels(1)
            sound.setsampwidth(2)
            sound.setframerate(RATE)
            sound.writeframes(data.tobytes())
        print(name, len(data) / RATE, hashlib.sha256(data.tobytes()).hexdigest())


if __name__ == '__main__':
    main()
