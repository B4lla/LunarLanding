"""F04: real Godot windowed-vs-headless trajectory parity, without training.

Same remote.tscn, TCP v1, deterministic seeds and passive actions. Opens a Godot
window for the second run. No mock is counted as a runtime pass.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import sys
from typing import Any

from benchmark import ROOT, _compare_value, godot_session, record_episode


def run_parity(executable: str, *, seed: int, seeds: int, repeats: int,
               max_steps: int, tolerance: float, port: int, log_dir: Path,
               frame_mode: str = 'fixed_60') -> dict[str, Any]:
    if not (1 <= seeds <= 1000 and repeats >= 2 and max_steps >= 50 and
            0 < tolerance <= 1e-2 and 1024 <= port <= 65535):
        raise ValueError('Invalid parity arguments')
    traces: dict[int, list[dict[str, Any]]] = {}
    summary = []
    versions = []
    for render_mode in ('headless', 'windowed'):
        with godot_session(executable, port, log_dir / render_mode,
                           frame_mode=frame_mode, render_mode=render_mode) as (version, factory):
            versions.append(version)
            with factory() as client:
                for scenario_seed in range(seed, seed + seeds):
                    baseline = None
                    for repeat in range(repeats):
                        result = record_episode(client, scenario_seed, max_steps)
                        trace = result['trace']
                        if baseline is not None:
                            _compare_value(baseline, trace, tolerance,
                                           f'{render_mode}/seed={scenario_seed}/replay={repeat}')
                        else:
                            baseline = trace
                        if render_mode == 'headless':
                            if repeat == 0:
                                traces[scenario_seed] = trace
                        else:
                            _compare_value(traces[scenario_seed], trace, tolerance,
                                           f'graphics-vs-headless/seed={scenario_seed}/replay={repeat}')
                        summary.append({'render_mode': render_mode, 'seed': scenario_seed,
                                        'replay': repeat, 'steps': result['steps'],
                                        'result': result['terminal_result']})
    if len(set(versions)) != 1:
        raise AssertionError(f'Godot versions differ between render modes: {versions}')
    return {'status': 'PASS', 'engine_versions': versions,
            'render_modes': ['headless', 'windowed'],
            'frame_mode': frame_mode,
            'seeds': seeds, 'repeats_per_mode': repeats,
            'episodes': len(summary),
            'total_steps': sum(row['steps'] for row in summary),
            'tolerance': tolerance,
            'comparison': 'complete observation/reward/terminal/episode info per tick',
            'results': summary}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--seed', type=int, default=12345)
    parser.add_argument('--seeds', type=int, default=3)
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--max-steps', type=int, default=900)
    parser.add_argument('--tolerance', type=float, default=1e-5)
    parser.add_argument('--port', type=int, default=55425)
    parser.add_argument('--frame-mode', choices=('realtime', 'fixed_60'), default='fixed_60')
    parser.add_argument('--output', type=Path, default=ROOT / 'logs/f04' / 'parity.json')
    args = parser.parse_args(argv)
    if not (0 <= args.seed <= 2147483647 and args.seeds >= 1 and
            args.seed + args.seeds - 1 <= 2147483647):
        parser.error('Invalid seed range')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {'schema_version': 1,
                              'created_utc': datetime.now(timezone.utc).isoformat(),
                              'platform': platform.platform(),
                              'status': 'FAIL', 'mode': 'Godot physical trajectory parity'}
    try:
        report.update(run_parity(args.godot, seed=args.seed, seeds=args.seeds,
                                 repeats=args.repeats, max_steps=args.max_steps,
                                 tolerance=args.tolerance, port=args.port,
                                 log_dir=args.output.parent / 'parity_logs',
                                 frame_mode=args.frame_mode))
        result = 0
        print(f"F04 PARITY PASS: {report['episodes']} real episodes, "
              f"headless/windowed matched to tolerance {args.tolerance}")
    except Exception as exc:
        report.update(status='FAIL', error_type=type(exc).__name__, error=str(exc))
        result = 1
        print(f'F04 PARITY FAIL: {type(exc).__name__}: {exc}', file=sys.stderr)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + '\n',
                           encoding='utf-8')
    print(f'Report: {args.output}')
    return result


if __name__ == '__main__':
    raise SystemExit(main())
