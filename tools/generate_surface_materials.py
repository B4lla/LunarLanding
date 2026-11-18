"""F34 offline, deterministic lunar regolith and industrial metal PBR.

No downloads. Only regeneration needs NumPy and Pillow; PNG assets are bundled.
All three materials tile seamlessly (periodic noise and periodic derivatives).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets' / 'terrain_materials'
SEED = 341018


def noise(size: int, cells: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    grid = rng.random((cells, cells), dtype=np.float32) * 2.0 - 1.0
    coordinate = np.arange(size, dtype=np.float32) * (cells / size)
    a = np.floor(coordinate).astype(np.int32)
    smooth = coordinate - a
    smooth = smooth * smooth * (3.0 - 2.0 * smooth)
    ax, bx = a % cells, (a + 1) % cells
    aa = grid[np.ix_(ax, ax)]
    ab = grid[np.ix_(ax, bx)]
    ba = grid[np.ix_(bx, ax)]
    bb = grid[np.ix_(bx, bx)]
    sx = smooth[:, None]
    sy = smooth[None, :]
    return ((aa * (1.0 - sx) + ba * sx) * (1.0 - sy)
            + (ab * (1.0 - sx) + bb * sx) * sy)


def save(name: str, array: np.ndarray) -> None:
    value = np.clip(np.rint(array), 0, 255).astype(np.uint8)
    Image.fromarray(value, 'RGB' if value.ndim == 3 else 'L').save(DEST / name, optimize=True)


def make_pbr(name: str, height: np.ndarray, rgb: tuple[int, int, int],
             color_gain: float, normal_gain: float, roughness: float,
             extra_color: np.ndarray | None = None) -> None:
    fine = noise(height.shape[0], 131, SEED + len(name))
    variation = height * color_gain + fine * 2.0
    if extra_color is not None:
        variation += extra_color
    albedo = np.stack([float(channel) + variation * (1.0 + 0.035 * index)
                       for index, channel in enumerate(rgb)], axis=-1)
    save(name + '_albedo.png', albedo)
    # Wraparound finite differences: no visible seam in the tile normal map.
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * normal_gain
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * normal_gain
    magnitude = np.sqrt(dx * dx + dy * dy + 1.0)
    normal = np.stack(((1.0 - dx / magnitude) * 127.5,
                       (1.0 - dy / magnitude) * 127.5,
                       (1.0 + 1.0 / magnitude) * 127.5), axis=-1)
    save(name + '_normal.png', normal)
    save(name + '_roughness.png', roughness * 255.0 + height * 16.0 + fine * 3.0)


def deck_grid(n: int, period: int, bolt_radius: float) -> np.ndarray:
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    # Texture tile contains a whole number of panel units and seam profile is
    # symmetric at repeat boundaries. Dents are bounded and subtly recessed.
    fx = np.mod(x, period)
    fy = np.mod(y, period)
    edge = np.minimum(np.minimum(fx, period - fx), np.minimum(fy, period - fy))
    seams = -0.34 * np.exp(-((edge - 1.9) / 2.0) ** 2)
    center_x = (fx - 16.0)
    center_y = (fy - 16.0)
    bolts = -0.16 * np.exp(-((np.sqrt(center_x * center_x + center_y * center_y) - bolt_radius) / 2.2) ** 2)
    return seams + bolts


def generate() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    n = 1024
    lunar = (0.49 * noise(n, 3, SEED + 11)
             + 0.26 * noise(n, 13, SEED + 12)
             + 0.16 * noise(n, 57, SEED + 13)
             + 0.09 * noise(n, 227, SEED + 14))
    # Sparse pale streaks approximate disturbed regolith; rock-grey rather than
    # terrestrial brown, with no atmospheric/wet effects.
    make_pbr('regolith', lunar, (79, 81, 85), 39.0, 4.2, 0.94)

    n = 512
    metallic_micro = (0.34 * noise(n, 9, SEED + 20)
                      + 0.18 * noise(n, 67, SEED + 21)
                      + 0.09 * noise(n, 181, SEED + 22))
    scratches = 0.12 * np.sin(np.arange(n, dtype=np.float32)[None, :] * 0.37
                             + noise(n, 11, SEED + 23) * 3.0)
    # Physically safe: baked detail only. Do not imply a physically extended pad.
    landing = metallic_micro + deck_grid(n, 128, 5.0) + scratches
    make_pbr('pad_deck', landing, (96, 102, 109), 35.0, 3.9, 0.71)

    service = (0.42 * noise(n, 7, SEED + 30)
               + 0.21 * noise(n, 47, SEED + 31)
               + 0.12 * noise(n, 157, SEED + 32)
               + deck_grid(n, 128, 4.0))
    make_pbr('service_deck', service, (75, 85, 93), 39.0, 3.7, 0.82)
    entries = {}
    for file in sorted(DEST.glob('*.png')):
        blob = file.read_bytes()
        entries[file.name] = {
            'sha256': hashlib.sha256(blob).hexdigest(),
            'bytes': len(blob),
            'width': Image.open(file).width,
            'height': Image.open(file).height,
        }
    manifest = {
        'phase': 'F34', 'seed': SEED,
        'generator': 'tools/generate_surface_materials.py',
        'license': 'Original offline procedurally generated assets',
        'tiling': 'periodic', 'files': entries,
    }
    (DEST / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('F34 generated', len(entries), 'PBR maps in', DEST)


if __name__ == '__main__':
    generate()
