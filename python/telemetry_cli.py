"""F06: capture/inspect/replay real Godot/Jolt TCP episodes (no RL training).

Records JSON + CSV + adjacent SHA-256, and verifies a replay on the same
physics/configuration using recorded commands, not forced transforms.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
from benchmark import godot_session, native_engine_for_memory
from rocket_landing_env.telemetry import (read_trace, record, replay, summarize,
                                         write_csv, write_trace)


def _session(args: argparse.Namespace, path: Path):
    if not args.godot and not args.attach:
        raise ValueError('Use --godot PATH to own a Godot 4.7.2 process or --attach explicitly')
    if args.godot and args.attach:
        raise ValueError('Choose either --godot or --attach, not both')
    if args.attach and args.mode != 'headless':
        raise ValueError('Attach mode does not manage a graphical window')
    executable = args.godot
    if executable and Path(executable).name.lower().endswith('_console.exe'):
        # The Windows console launcher may spawn a second engine process.
        executable = str(native_engine_for_memory(Path(executable)))
    return godot_session(executable, args.port, path, frame_mode='realtime' if args.attach
                         else args.frame_mode, render_mode=args.mode)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for verb in ('record', 'replay'):
        p = sub.add_parser(verb, help=f'{verb} an episode using Godot TCP v1')
        p.add_argument('--godot', help='Godot 4.7.2 executable; launches and owns the process')
        p.add_argument('--attach', action='store_true', help='Explicitly use an already running remote.tscn')
        p.add_argument('--port', type=int, default=55436)
        p.add_argument('--mode', choices=('headless', 'windowed'), default='headless')
        p.add_argument('--frame-mode', choices=('realtime', 'fixed_60'), default='fixed_60')
        p.add_argument('--trace', type=Path, default=ROOT / 'logs/f06' / 'episode.json')
        p.add_argument('--log-dir', type=Path, default=ROOT / 'logs/f06' / verb)
        if verb == 'record':
            p.add_argument('--seed', type=int, default=12345)
            p.add_argument('--steps', type=int, default=900)
            p.add_argument('--pattern', choices=('passive', 'pulse'), default='pulse')
            p.add_argument('--random-start', action=argparse.BooleanOptionalAction, default=True)
            p.add_argument('--csv', type=Path)
        else:
            p.add_argument('--tolerance', type=float, default=1e-5)
            p.add_argument('--report', type=Path)
    inspect = sub.add_parser('inspect', help='Verify receipt and summarize a saved JSON episode offline')
    inspect.add_argument('--trace', type=Path, required=True)
    inspect.add_argument('--csv', type=Path, help='Optionally export verified episode CSV')
    args = parser.parse_args(argv)
    try:
        if args.command == 'inspect':
            trace = read_trace(args.trace)
            if args.csv:
                write_csv(args.csv, trace)
            report = {'status': 'PASS', 'mode': 'offline receipt/trace inspection',
                      'summary': summarize(trace), 'physical_replay_executed': False}
        elif args.command == 'record':
            with _session(args, args.log_dir) as (version, factory):
                with factory() as client:
                    trace = record(client, ROOT, seed=args.seed,
                                   random_start=args.random_start,
                                   max_steps=args.steps, pattern=args.pattern,
                                   engine_version=version)
            digest = write_trace(args.trace, trace)
            csv_path = args.csv or args.trace.with_suffix('.csv')
            write_csv(csv_path, trace)
            report = {'status': 'PASS', 'mode': 'live TCP trace capture',
                      'godot_version': version, 'trace_sha256': digest,
                      'trace': str(args.trace), 'csv': str(csv_path),
                      'summary': summarize(trace), 'physical_replay_executed': False}
        else:
            trace = read_trace(args.trace)
            with _session(args, args.log_dir) as (version, factory):
                with factory() as client:
                    replay_report = replay(client, trace, ROOT, tolerance=args.tolerance,
                                           engine_version=version)
            report = {'status': 'PASS', 'godot_version': version,
                      'trace': str(args.trace), 'physical_replay_executed': True,
                      **replay_report}
        print(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False))
        if args.command == 'replay':
            report_path = args.report or args.trace.with_suffix('.replay.json')
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps({**report,
                'created_utc': datetime.now(timezone.utc).isoformat()}, indent=2,
                ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')
        return 0
    except Exception as exc:
        print(f'F06 {args.command.upper()} FAIL: {type(exc).__name__}: {exc}', file=sys.stderr)
        if args.command == 'replay':
            output = args.report or args.trace.with_suffix('.replay.json')
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps({'status': 'FAIL', 'mode': 'live TCP physical replay',
                                          'physical_replay_executed': False,
                                          'error_type': type(exc).__name__, 'error': str(exc)},
                                         indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
