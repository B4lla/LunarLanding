"""F12 reproducible offline texture bake; no runtime dependencies on Python.

Run: python -m pip install numpy pillow
     python tools/generate_materials.py
All maps are original procedural outputs; no third-party assets, no network.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets' / 'procedural'
DEST.mkdir(parents=True, exist_ok=True)


def noise(n: int, cells: int, seed: int) -> np.ndarray:
    """Periodic smooth lattice noise, compatible with seamless UV tiling."""
    rng = np.random.default_rng(seed)
    lattice = rng.random((cells, cells), dtype=np.float32)
    t = np.arange(n, dtype=np.float32) * (cells / n)
    a = np.floor(t).astype(np.int32)
    f = t - np.floor(t)
    f = f*f*(3.0 - 2.0*f)
    lo = a % cells
    hi = (a + 1) % cells
    x0, x1 = lo[:, None], hi[:, None]
    z0, z1 = lo[None, :], hi[None, :]
    fx, fz = f[:, None], f[None, :]
    return ((lattice[x0, z0]*(1.0-fx)+lattice[x1,z0]*fx)*(1.0-fz)
           +(lattice[x0,z1]*(1.0-fx)+lattice[x1,z1]*fx)*fz) * 2.0 - 1.0


def tile_height(n: int, seed: int) -> np.ndarray:
    return (noise(n, 4, seed)*0.39 + noise(n, 15, seed+1)*0.23
            + noise(n, 59, seed+2)*0.23 + noise(n, 217, seed+3)*0.15)


def crater_field(n: int, seed: int, count: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    field = np.zeros((n, n), dtype=np.float32)
    for _ in range(count):
        x, y = rng.integers(0, n, size=2)
        radius = rng.uniform(n*0.007, n*0.036)
        rr = int(radius*2.3) + 1
        ax = np.arange(-rr, rr+1, dtype=np.float32)
        xx, yy = np.meshgrid(ax, ax, indexing='ij')
        d = np.sqrt(xx*xx + yy*yy) / radius
        depression = np.exp(-2.8*d*d) * -0.32
        rim = np.exp(-((d-1.0)*5.0)**2) * 0.21
        patch = depression + rim
        ii = (x + np.arange(-rr,rr+1)) % n
        jj = (y + np.arange(-rr,rr+1)) % n
        field[np.ix_(ii,jj)] += patch
    return field


def store(name: str, values: np.ndarray) -> None:
    out = DEST / name
    data = np.clip(np.rint(values), 0, 255).astype(np.uint8)
    Image.fromarray(data, 'RGB' if data.ndim == 3 else 'L').save(out, optimize=True)



def bake(name: str, n: int, height: np.ndarray, rgb: tuple[float,float,float],
         color_gain: float, rough_base: float, rough_gain: float,
         normal_strength: float, scratch: np.ndarray | None = None) -> None:
    grain = noise(n, 223, n+21)
    shade = height*color_gain + grain*3.5
    albedo = np.stack([np.clip(channel + shade*(1.0+(k*0.08)),0,255)
                       for k,channel in enumerate(rgb)],axis=-1)
    if scratch is not None:
        albedo += scratch[...,None] * 11.0
    store(name + '_albedo.png', albedo)
    dx = (np.roll(height, -1, axis=0)-np.roll(height,1,axis=0))*normal_strength
    dy = (np.roll(height, -1, axis=1)-np.roll(height,1,axis=1))*normal_strength
    nx = -dx
    ny = -dy
    nz = np.ones_like(height)
    magnitude = np.sqrt(nx*nx+ny*ny+nz*nz)
    normals = np.stack(((nx/magnitude+1.0)*127.5,
                        (ny/magnitude+1.0)*127.5,
                        (nz/magnitude+1.0)*127.5),axis=-1)
    store(name + '_normal.png', normals)
    rough = np.clip(rough_base*255.0 + rough_gain*height*255 + grain*6, 0, 255)
    store(name + '_roughness.png', rough)


def generate() -> None:
    n = 1024
    h = tile_height(n, 64061) + crater_field(n, 345612, 52)
    bake('regolith',n,h,(87,90,94),31.0,0.94,0.07,12.0)
    n = 512
    x = np.arange(n, dtype=np.float32)
    gx,gy = np.meshgrid(x,x,indexing='ij')
    crease = (np.sin(gx*0.37 + np.sin(gy*0.027)*3.4)*0.11
            +np.sin(gy*0.23 + np.sin(gx*0.034)*5.0)*0.11)
    gold = tile_height(n, 56202)*0.62 + crease + noise(n, 126, 1922)*0.17
    bake('gold_foil',n,gold,(184,143,76),54,0.41,0.16,18.0)
    ceramic = tile_height(n, 11441)*0.22 + noise(n, 126, 4455)*0.06
    bake('cabin_ceramic',n,ceramic,(190,199,199),20,0.68,0.08,5.0)
    # Repeatable square panels, worn edges and fine milling marks.
    edge = np.minimum(np.minimum(gx%n, (n-1-gx)%n),
                      np.minimum(gy%n, (n-1-gy)%n))
    seam = -(np.exp(-edge/3.5))*0.15
    milling = 0.05*np.sin(gx*0.63)
    deck = tile_height(n, 33567)*0.23 + seam + milling
    bake('deck',n,deck,(91,96,102),35,0.76,0.10,7.0)
    files = sorted(DEST.glob('*.png'))
    manifest = {p.name: {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'bytes':p.stat().st_size}
                for p in files}
    (DEST/'manifest.json').write_text(json.dumps({'generator':'tools/generate_materials.py',
        'seed_policy':'fixed integers; original algorithmic content', 'images':manifest},
        indent=2)+'\n',encoding='utf-8')
    print('Generated %d F12 PBR maps, %.2f MiB' %(len(files),sum(p.stat().st_size for p in files)/1048576))


if __name__ == '__main__':
    generate()
