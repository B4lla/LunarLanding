"""Deterministic offline PBR maps for F28 lunar terrain and industrial service decks.

No downloads, no changes to F12 textures or physics. Run with numpy + Pillow.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets' / 'base_materials'


def periodic_noise(n: int, cells: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    grid = rng.random((cells, cells), dtype=np.float32)
    ix = np.arange(n, dtype=np.float32) * (cells / n)
    base = np.floor(ix).astype(np.int32)
    mixv = ix - base
    mixv *= mixv * (3.0 - 2.0 * mixv)
    a = base % cells
    b = (base + 1) % cells
    aa, ab = grid[np.ix_(a, a)], grid[np.ix_(a, b)]
    ba, bb = grid[np.ix_(b, a)], grid[np.ix_(b, b)]
    fx = mixv[:, None]
    fy = mixv[None, :]
    return ((aa * (1 - fx) + ba * fx) * (1 - fy) + (ab * (1 - fx) + bb * fx) * fy) * 2.0 - 1.0


def store(name: str, array: np.ndarray) -> None:
    data = np.clip(np.rint(array), 0, 255).astype(np.uint8)
    Image.fromarray(data, 'RGB' if data.ndim == 3 else 'L').save(DEST / name, optimize=True)


def channels(prefix: str, height: np.ndarray, rgb: tuple[float, float, float],
             gain: float, roughness: float, bump: float) -> None:
    n = height.shape[0]
    fine = periodic_noise(n, 191, 22813)
    variations = (height * gain + fine * 3.6)
    albedo = np.stack([np.clip(v + variations * (1.0 + 0.07 * k), 0, 255)
                       for k, v in enumerate(rgb)], axis=-1)
    store(prefix + '_albedo.png', albedo)
    dx = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * bump
    dy = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * bump
    norm = np.sqrt(dx * dx + dy * dy + 1.0)
    normal_map = np.stack(((1.0 - dx / norm) * 127.5,
                           (1.0 - dy / norm) * 127.5,
                           (1.0 / norm + 1.0) * 127.5), axis=-1)
    store(prefix + '_normal.png', normal_map)
    store(prefix + '_roughness.png', roughness * 255.0 + height * 9.0 + fine * 3.0)


def generate() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    n = 1024
    macro = periodic_noise(n, 4, 4242) * 0.42 + periodic_noise(n, 17, 4243) * 0.27
    grains = periodic_noise(n, 81, 4244) * 0.20 + periodic_noise(n, 281, 4245) * 0.11
    lunar = macro + grains
    # Volcanic-gray compacted regolith, large-scale patterns plus fine pebble noise.
    channels('lunar_regolith', lunar, (84, 88, 94), 41.0, 0.93, 5.0)

    n = 512
    macro = periodic_noise(n, 7, 1101) * 0.25 + periodic_noise(n, 73, 1102) * 0.17
    i, j = np.meshgrid(np.arange(n, dtype=np.float32), np.arange(n, dtype=np.float32), indexing='ij')
    # Seam and countersunk-fastener impressions with exactly periodic boundaries.
    edge = np.minimum.reduce([i, j, n - i, n - j])
    seams = -0.30 * np.exp(-(edge / 3.5) ** 2)
    bolt_dist = np.sqrt((i - 26.0) ** 2 + (j - 26.0) ** 2)
    bolt = -0.10 * np.exp(-((bolt_dist - 7.5) / 1.6) ** 2)
    abrasion = 0.055 * np.sin(i * 0.43 + periodic_noise(n, 11, 1103) * 5.0)
    industrial = macro + seams + bolt + abrasion
    channels('base_deck', industrial, (83, 94, 105), 44.0, 0.80, 5.0)

    manifest = {}
    for path in sorted(DEST.glob('*.png')):
        blob = path.read_bytes()
        manifest[path.name] = {'sha256': hashlib.sha256(blob).hexdigest(), 'bytes': len(blob)}
    (DEST / 'manifest.json').write_text(json.dumps({
        'generator': 'tools/generate_base_materials.py',
        'license': 'Original procedurally generated artwork',
        'seed_policy': 'fixed integers / periodic lattice noise',
        'images': manifest,
    }, indent=2) + '\n', encoding='utf-8')
    print(f'F28: generated {len(manifest)} original PBR textures in {DEST}')


if __name__ == '__main__':
    generate()
