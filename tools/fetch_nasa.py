"""Opt-in download of NASA Apollo Lunar Module GLB into an unmodified asset folder.

Uses official NASA-3D-Resources GitHub source. Does not attach the model to
simulation, scale it, generate collision, or imply NASA endorses this project.
Usage: python tools/fetch_nasa.py (requires network)
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'assets' / 'nasa'
FILENAME = 'apollo_lunar_module.glb'
SOURCE = ('https://raw.githubusercontent.com/nasa/NASA-3D-Resources/master/'
          '3D%20Models/Apollo%20Lunar%20Module/Apollo%20Lunar%20Module.glb')
MAX_BYTES = 5 * 1024 * 1024


def inspect_glb(data: bytes) -> dict:
    """Reject HTML/partial/invalid GLBs before promoting the download to an asset."""
    if len(data) < 28 or len(data) > MAX_BYTES or data[:4] != b'glTF':
        raise ValueError('not a GLB 2.0 file or size exceeds limit')
    magic, version, declared_length = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF' or version != 2 or declared_length != len(data):
        raise ValueError('GLB version/declared length mismatch')
    chunk_len, chunk_type = struct.unpack_from('<I4s', data, 12)
    if chunk_type != b'JSON' or chunk_len < 2 or chunk_len % 4 or 20 + chunk_len > len(data):
        raise ValueError('GLB first chunk must be a valid aligned JSON chunk')
    payload = json.loads(data[20:20 + chunk_len].decode('utf-8').rstrip(' \t\r\n\x00'))
    if payload.get('asset', {}).get('version') != '2.0' or not payload.get('meshes'):
        raise ValueError('GLB has no glTF 2.0 meshes')
    # Validate second chunk length and type, if any.
    cursor = 20 + chunk_len
    while cursor < len(data):
        if cursor + 8 > len(data):
            raise ValueError('incomplete GLB chunk header')
        count, kind = struct.unpack_from('<I4s', data, cursor)
        cursor += 8
        if count % 4 or cursor + count > len(data) or kind not in (b'BIN\x00', b'JSON'):
            raise ValueError('invalid GLB chunk length or type')
        cursor += count
    return {'mesh_count': len(payload['meshes']), 'node_count': len(payload.get('nodes', [])),
            'scene_count': len(payload.get('scenes', [])), 'version': version}


def fetch() -> dict:
    TARGET.mkdir(parents=True, exist_ok=True)
    destination = TARGET / FILENAME
    receipt = {'source': SOURCE, 'source_page': 'https://science.nasa.gov/3d-resources/apollo-lunar-module/',
               'file': str(destination.relative_to(ROOT)).replace('\\', '/'),
               'author': 'NASA/Michael D. Carbajal',
               'policy': 'https://www.nasa.gov/nasa-brand-center/images-and-media/',
               'status': 'FAIL'}
    try:
        with urlopen(Request(SOURCE, headers={'User-Agent': 'RocketLandingRL-F05/0.5.9'}), timeout=30) as response:
            data = response.read(MAX_BYTES + 1)
        details = inspect_glb(data)
        # A failed download must never overwrite an earlier valid asset.
        partial = destination.with_suffix('.download')
        partial.write_bytes(data)
        partial.replace(destination)
        receipt.update({'status': 'OK', 'sha256': hashlib.sha256(data).hexdigest(),
                        'size_bytes': len(data), 'glb': details})
    except Exception as exc:
        receipt['error'] = str(exc)
    (TARGET / 'nasa_download_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return receipt


if __name__ == '__main__':
    result = fetch()
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['status'] == 'OK' else 1)
