"""Original offline onboard rocket/RCS loops. No external downloads or clips.

Deterministic 44.1kHz PCM, band-shaped continuous noise with non-periodic
macro-modulation (realistic combustion texture, not sinusoidal ticks). Source
and generated files ship together; keep earlier F19/F37 assets untouched.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import wave
import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio_enhanced'
DURATION = {'engine_rumble': 9.0, 'engine_turbine': 9.0, 'rcs': 6.0,
            'rcs_hiss': 6.0, 'engine_ignition': 2.6,
            'engine_cutoff': 2.0, 'rcs_pulse': 0.85}
CLIPS = DURATION


def band(noise: np.ndarray, low: float, high: float) -> np.ndarray:
    """Raised cosine spectral rolls, retaining frequencies usable by laptops."""
    n = len(noise)
    f = np.fft.rfftfreq(n, 1 / RATE)
    low_edge = np.clip((f - low * .5) / max(low * .85, 2), 0, 1)
    high_edge = np.clip((high * 1.6 - f) / max(high * .85, 2), 0, 1)
    shape = np.sin(low_edge * np.pi / 2)**2 * np.sin(high_edge * np.pi / 2)**2
    y = np.fft.irfft(np.fft.rfft(noise) * shape, n=n)
    return y / max(float(np.std(y)), 1e-8)


def smooth_control(rng: np.random.Generator, n: int, step: int) -> np.ndarray:
    """Gently irregular macro-motion rather than a clocked/ticking gate."""
    at = np.arange(0, n+step, step)
    src = rng.uniform(-1, 1, size=len(at))
    x = np.interp(np.arange(n), at, src)
    # zero/low amplitude corner at loop seam is avoided by crossfading later.
    return x


def render(name: str) -> np.ndarray:
    if name not in DURATION:
        raise ValueError(name)
    n = int(DURATION[name] * RATE)
    t = np.arange(n, dtype=np.float64) / RATE
    rng = np.random.default_rng(int.from_bytes(hashlib.sha256(('f38_'+name).encode()).digest()[:8], 'little'))
    a = rng.standard_normal(n)
    b = rng.standard_normal(n)
    c = rng.standard_normal(n)
    deep = band(a, 24, 180)
    combustion = band(b, 85, 850)
    turbine = band(c, 300, 2900)
    hiss = band(a, 1400, 8200)
    grit = band(b, 1200, 5100)
    slow = smooth_control(rng, n, RATE//3)
    fast = smooth_control(rng, n, RATE//21)
    if name == 'engine_rumble':
        # Heavy LF chamber pressure + gritty propulsion resonance.
        envelope = 0.88 + .13*slow + .045*fast
        y = envelope*(.48*deep + .43*combustion + .35*turbine + .10*grit)
    elif name == 'engine_turbine':
        envelope = 0.91 + .12*slow + .06*fast
        y = envelope*(.16*deep + .26*combustion + .57*turbine + .32*hiss)
    elif name in ('rcs', 'rcs_hiss'):
        envelope = 0.90 + .09*slow + .05*fast
        y = envelope*(.10*combustion + .39*turbine + .53*hiss + .22*grit)
    elif name == 'engine_ignition':
        attack = np.clip(t/.24,0,1)**1.3
        release = np.clip((DURATION[name]-t)/.36,0,1)
        envelope = attack * release * (0.60 + .40*np.clip(t/1.8,0,1))
        y = envelope*(.40*deep + .43*combustion + .45*turbine + .12*hiss)
    elif name == 'engine_cutoff':
        envelope = np.exp(-2.8*t) * np.clip((DURATION[name]-t)/.30,0,1)
        y = envelope*(.40*deep + .38*combustion + .32*turbine + .18*hiss)
    else:  # long cold-gas spool, deliberately NOT a valve click
        envelope = np.clip(t/.09,0,1) * np.clip((DURATION[name]-t)/.33,0,1)
        y = envelope*(.16*combustion + .42*turbine + .52*hiss)
    # Warm saturation compresses transients; prevents sharp digital peaks.
    y = np.tanh(y*.72)
    if name in ('engine_rumble','engine_turbine','rcs','rcs_hiss'):
        # Seamless loop: overlap-add a true source region. Avoid fade-to-zero.
        k = int(RATE * 0.24)
        common = .5*(y[:k] + y[-k:])
        blend = np.linspace(0,1,k,endpoint=True)
        y[:k] = common*(1-blend) + y[:k]*blend
        y[-k:] = y[-k:]*(1-blend) + common*blend
        boundary = .5*(y[0]+y[-1])
        y[0] = boundary
        y[-1] = boundary
    max_val = max(float(np.max(np.abs(y))),1e-8)
    y = y * min(.91/max_val, 2.8)
    return np.clip(np.round(y*32767), -32767, 32767).astype('<i2')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in DURATION:
        pcm = render(name)
        with wave.open(str(OUT/f'{name}.wav'), 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        print(f'{name}: {len(pcm)/RATE:.2f}s SHA256={hashlib.sha256(pcm.tobytes()).hexdigest()}')

if __name__ == '__main__':
    main()
