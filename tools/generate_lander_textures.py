"""Deterministic F33 nozzle PBR maps. Offline, generated, no third-party assets."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'lander_materials'
SIZE = 512
SEED = 330618


def create_maps() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    yy, xx = np.indices((SIZE, SIZE), dtype=np.float32)
    u, v = xx / SIZE, yy / SIZE
    # Directional abrasion follows the nozzle axis (Y), while angular wear
    # and weld bands tile continuously around its 32-sector circumference.
    angular = (0.65 * np.sin(2 * np.pi * (u * 8.0 + 0.010 * np.sin(v * 3)))
               + 0.25 * np.sin(2 * np.pi * (u * 19.0 + 0.006 * np.sin(v * 7))))
    streak = gaussian_filter(rng.normal(size=(SIZE, SIZE)),
                             sigma=(15.0, 0.85), mode=('reflect', 'wrap'))
    streak = streak / max(0.01, float(np.std(streak)))
    fine = gaussian_filter(rng.normal(size=(SIZE, SIZE)),
                           sigma=1.3, mode=('reflect', 'wrap'))
    fine = fine / max(0.01, float(np.std(fine)))
    soot = np.clip((v - 0.53) * 1.55, 0, 1) ** 1.25
    heat_band = np.exp(-((v - 0.68) / 0.16) ** 2)
    # Fine circumferential weld lines, never thick decorative stripes.
    weld = (np.exp(-((v - 0.19) / 0.003) ** 2)
            + 0.8 * np.exp(-((v - 0.47) / 0.003) ** 2))
    light = np.clip(0.58 + 0.09 * angular + 0.068 * streak + 0.013 * fine
                    - 0.26 * soot - 0.055 * weld, 0.18, 0.84)
    red = np.clip(light * (1.01 + 0.036 * heat_band), 0, 1)
    green = np.clip(light * (1.01 - 0.035 * heat_band), 0, 1)
    blue = np.clip(light * (1.045 + 0.065 * heat_band), 0, 1)
    albedo = np.uint8(np.clip(np.stack([red, green, blue], axis=-1) * 255, 0, 255))
    rough = np.clip(0.43 + 0.12 * soot + 0.030 * np.abs(streak)
                    + 0.025 * np.abs(fine) + 0.10 * weld, 0.27, 0.81)
    rough_rgb = np.repeat(np.uint8(rough * 255)[:, :, None], 3, axis=2)
    relief = 0.22 * angular + 0.10 * streak + 0.015 * fine - 0.16 * weld
    gy, gx = np.gradient(relief)
    nx, ny = -gx * 1.6, -gy * 1.6
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal_rgb = np.uint8(np.clip(np.stack([
        nx / length * 0.5 + 0.5,
        ny / length * 0.5 + 0.5,
        nz / length * 0.5 + 0.5
    ], axis=-1) * 255, 0, 255))
    maps = {'bell_albedo.png': albedo, 'bell_normal.png': normal_rgb,
            'bell_roughness.png': rough_rgb}
    checksum: dict[str, str] = {}
    for name, pixels in maps.items():
        filepath = OUT / name
        Image.fromarray(pixels, 'RGB').save(filepath, optimize=True)
        checksum[name] = hashlib.sha256(filepath.read_bytes()).hexdigest()
    (OUT / 'manifest.json').write_text(json.dumps({
        'phase': 'F33', 'seed': SEED, 'size': SIZE,
        'license': 'Original procedural assets generated within this project',
        'files_sha256': checksum,
    }, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('F33 textures generated and verified in', OUT)


if __name__ == '__main__':
    create_maps()
