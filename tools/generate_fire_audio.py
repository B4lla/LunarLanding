"""F39: reproducible royalty-free synthesized onboard rocket/valve recordings.

No sound propagates through lunar vacuum: these represent vibration and conducted
mechanical pressure heard *inside* a vehicle/simulation, not an outside mic.
Run: python tools/generate_fire_audio.py
Requires: numpy, scipy, soundfile (generation only; Godot needs only bundled WAV).
"""
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfiltfilt
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio_fire'
ROOT.mkdir(parents=True, exist_ok=True)
SR = 44100
RNG = np.random.default_rng(391128)


def periodic_band(seconds: float, low: float, high: float, slope: float = 0.0) -> np.ndarray:
    """Smooth colored noise with exactly periodic 1-cycle boundary for clean loops."""
    length = int(SR * seconds)
    freqs = np.fft.rfftfreq(length, 1.0 / SR)
    # Smooth shoulders avoid audible ringing / brickwall filtered noise.
    bottom = 1.0 / (1.0 + np.exp(np.clip((low - freqs) / max(low * .15, 2.0), -80, 80)))
    top = 1.0 / (1.0 + np.exp(np.clip((freqs - high) / max(high * .17, 2.0), -80, 80)))
    amplitude = bottom * top * np.maximum(freqs, 8.0) ** slope
    phases = RNG.uniform(0.0, 2 * np.pi, len(freqs))
    spectrum = amplitude * (np.cos(phases) + 1j * np.sin(phases))
    spectrum[0] = 0.0
    result = np.fft.irfft(spectrum, n=length).astype(np.float32)
    return result / max(1e-6, np.std(result))


def noise(seconds: float, low: float, high: float, slope: float = 0.0) -> np.ndarray:
    n = round(seconds * SR)
    x = RNG.standard_normal(n).astype(np.float32)
    if low > 0:
        x = sosfiltfilt(butter(4, low, btype='highpass', fs=SR, output='sos'), x)
    if high < SR / 2 - 10:
        x = sosfiltfilt(butter(4, high, btype='lowpass', fs=SR, output='sos'), x)
    return x / max(1e-6, np.std(x))


def stereo(x: np.ndarray, side: np.ndarray | None = None, width: float = .09) -> np.ndarray:
    if side is None:
        side = np.roll(x, 37)
    return np.stack([x + width * side, x - width * side], axis=1)


def save(name: str, arr: np.ndarray, target_peak: float = .78) -> None:
    arr = np.asarray(arr, dtype=np.float32)
    arr -= np.mean(arr, axis=0, keepdims=True)
    # Soft saturation mimics diaphragm/body transfer without clipping.
    arr = np.tanh(1.12 * arr)
    peak = float(np.max(np.abs(arr)))
    arr *= target_peak / max(peak, 1e-8)
    sf.write(ROOT / name, arr, SR, subtype='PCM_16')
    print(f'{name}: {len(arr)/SR:.2f}s, {arr.shape[1]} channels, peak {np.max(abs(arr)):.2f}')


# Sustained main engine: deep chamber rumble + broadband exhaust pressure.
# Non-constant periodic flutter prevents a static, videogame-like single-pitch drone.
DURATION = 8.0
n = round(DURATION * SR)
t = np.arange(n, dtype=np.float32) / SR
flutter = (1.0 + .075 * np.sin(2*np.pi*7*t) + .045 * np.sin(2*np.pi*13*t + 1.0)
           + .035 * np.sin(2*np.pi*19*t + .7))
rumble = (0.42*periodic_band(DURATION, 17, 75, -.35)
          + .38*periodic_band(DURATION, 60, 310, -.16)
          + .32*periodic_band(DURATION, 250, 1650, -.25)
          + .12*periodic_band(DURATION, 1300, 4300, -.15))
# Low structure-born vibration with slightly irregular combustion rhythm.
rumble += .10 * (np.sin(2*np.pi*53*t) + .5*np.sin(2*np.pi*107*t + .8))
rumble *= flutter
save('engine_rumble.wav', stereo(rumble, periodic_band(DURATION, 180, 3500), .10), .59)

# Brighter ignition-system / plumbing roar, mixed gently under rumble.
turbulence = (.48*periodic_band(DURATION, 260, 2000, -.05)
              + .40*periodic_band(DURATION, 1500, 6500, -.13)
              + .18*periodic_band(DURATION, 75, 330))
# Weak, slightly moving metal-band resonance, not a smooth sci-fi oscillator.
whine = .10 * np.sin(2*np.pi*370*t + 0.12 * np.sin(2*np.pi*3*t))
whine += .052 * np.sin(2*np.pi*742*t + .2*np.sin(2*np.pi*5*t))
turbulence = (turbulence + whine) * (1 + .045*np.sin(2*np.pi*11*t))
save('engine_turbine.wav', stereo(turbulence, periodic_band(DURATION, 600, 9000), .14), .47)

# Startup: pressure valve click, igniter crackle, fast pump ramp and chamber catches.
D = 2.8
n = round(D*SR)
t = np.arange(n) / SR
base = (.42*noise(D, 22, 210) + .38*noise(D, 190, 1750) + .23*noise(D, 900, 6800))
ramp = (1 - np.exp(-np.maximum(0, t-.10)*3.6))
settle = np.minimum(1.0, np.maximum(0.0, (D - t) / .28))
startup = base * ramp * settle
startup += (.22 * np.exp(-((t-.095)/.026)**2) * noise(D, 120, 4000)
            + .15 * np.exp(-((t-.29)/.06)**2) * noise(D, 700, 7000))
save('engine_ignition.wav', stereo(startup, noise(D, 100, 4000), .02), .83)

# Cutoff: valve closure followed by quickly collapsing pressure/vibrations.
D = 1.7
n = round(D*SR)
t = np.arange(n) / SR
falloff = np.exp(-t*4.0)
cutoff = (.46*noise(D, 25, 340) + .30*noise(D, 200, 1900)
          + .12*noise(D, 900, 6500)) * falloff
cutoff += .12 * np.exp(-((t-.07)/.025)**2) * noise(D, 180, 3800)
save('engine_cutoff.wav', stereo(cutoff, noise(D, 200, 5000), .04), .75)

# Attitude jets: shorter, broadband pressure with very little bass.
DURATION = 4.0
n = round(DURATION*SR)
t = np.arange(n) / SR
rcs = (.55*periodic_band(DURATION, 500, 5300, -.09)
       + .32*periodic_band(DURATION, 160, 1800)
       + .11*periodic_band(DURATION, 4200, 10500))
rcs *= 1 + .04*np.sin(2*np.pi*9*t)
save('rcs.wav', stereo(rcs, periodic_band(DURATION, 700, 9000), .14), .64)
rcs_hiss = (.60*periodic_band(DURATION, 1100, 9000, -.12)
            + .33*periodic_band(DURATION, 350, 2200))
save('rcs_hiss.wav', stereo(rcs_hiss, periodic_band(DURATION, 1600, 10000), .17), .56)
D = .46
n = round(D*SR)
t = np.arange(n) / SR
pulse_env = (1-np.exp(-t*125)) * np.exp(-t*15)
pulse = (noise(D, 300, 6200)*.70 + noise(D, 80, 660)*.25) * pulse_env
save('rcs_pulse.wav', stereo(pulse, noise(D, 400, 8000), .02), .70)
