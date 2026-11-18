"""F04: benchmark and same-seed replay of the real Godot/Jolt TCP simulator.

No trainer, Gymnasium dependency, synthetic performance score or physics bypass.
With --godot, owns one headless Godot process. Otherwise attaches to an existing
scenes/remote.tscn instance. Writes a machine-readable report even on failure.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import ctypes
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import platform
import re
import socket
import statistics
import subprocess
import sys
import time
from typing import Any, Callable, Iterator

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'python'))
from rocket_landing_env.client import RocketLandingClient  # noqa: E402

DIAGNOSTIC_KEYS = frozenset({'physics_frame', 'body_integration_serial', 'reset_commit_serial'})
ACTIONS = (0.0, 0.0, 0.0)  # deterministic passive fall, never a training policy


def _episode_info(info: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in info.items() if k not in DIAGNOSTIC_KEYS}


def _close_number(a: Any, b: Any, tolerance: float) -> bool:
    if type(a) not in (int, float) or type(b) not in (int, float):
        return False
    return math.isclose(float(a), float(b), rel_tol=tolerance, abs_tol=tolerance)


def _compare_value(a: Any, b: Any, tolerance: float, name: str) -> None:
    """Check semantic episode values, not monotonic engine debugging counters."""
    if type(a) in (float, int) and type(b) in (float, int):
        if not _close_number(a, b, tolerance):
            raise AssertionError(f'{name}: numeric mismatch {a!r} != {b!r} (tol={tolerance})')
        return
    if isinstance(a, dict) and isinstance(b, dict):
        if a.keys() != b.keys():
            raise AssertionError(f'{name}: different info keys')
        for key in a:
            _compare_value(a[key], b[key], tolerance, f'{name}.{key}')
        return
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        if len(a) != len(b):
            raise AssertionError(f'{name}: different lengths')
        for idx, (left, right) in enumerate(zip(a, b)):
            _compare_value(left, right, tolerance, f'{name}[{idx}]')
        return
    if type(a) is not type(b) or a != b:
        raise AssertionError(f'{name}: {a!r} != {b!r}')


def _validate_tick(previous: dict[str, Any], current: dict[str, Any], tick: int) -> None:
    elapsed = current.get('elapsed_s')
    if not _close_number(elapsed, tick / 60.0, 1e-5):
        raise AssertionError(f'tick {tick}: elapsed_s={elapsed!r}, expected {tick}/60')
    before = previous.get('body_integration_serial')
    after = current.get('body_integration_serial')
    if (type(before) not in (float, int) or type(after) not in (float, int)
            or after - before != 1):
        raise AssertionError(f'tick {tick}: Jolt body integrations {before!r} -> {after!r}, expected +1')


def record_episode(client: Any, seed: int, max_steps: int, *,
                   clock: Callable[[], float] = time.perf_counter,
                   step_hook: Callable[[], None] | None = None) -> dict[str, Any]:
    started = clock()
    observation, info = client.reset(seed=seed, random_start=True)
    reset_s = clock() - started
    if not _close_number(info.get('elapsed_s'), 0.0, 1e-5):
        raise AssertionError(f'seed={seed}: reset did not clear episode clock')
    # Store only deterministic episode information (no global physics frame IDs).
    trace = [{'observation': observation, 'info': _episode_info(info), 'reward': None,
              'terminated': False, 'truncated': False}]
    timings = []
    for tick in range(1, max_steps + 1):
        began = clock()
        observation, reward, terminated, truncated, new_info = client.step(ACTIONS)
        timings.append(clock() - began)
        _validate_tick(info, new_info, tick)
        if step_hook is not None:
            step_hook()
        trace.append({'observation': observation, 'info': _episode_info(new_info),
                      'reward': reward, 'terminated': terminated, 'truncated': truncated})
        info = new_info
        if terminated or truncated:
            break
    if not (trace[-1]['terminated'] or trace[-1]['truncated']):
        raise AssertionError(f'seed={seed}: episode incomplete after {max_steps} steps; increase --max-steps')
    return {'seed': seed, 'steps': len(timings), 'simulated_seconds': len(timings) / 60.0,
            'reset_seconds': reset_s, 'step_seconds': timings, 'trace': trace,
            'terminal_result': info.get('result')}


def benchmark(client: Any, *, seeds: list[int], repeats: int, max_steps: int,
              tolerance: float, clock: Callable[[], float] = time.perf_counter,
              step_hook: Callable[[], None] | None = None) -> dict[str, Any]:
    if not seeds or repeats < 2 or max_steps < 1 or not (0 < tolerance <= 1e-2):
        raise ValueError('Require seeds, repeats >= 2, max_steps >= 1, 0 < tolerance <= 1e-2')
    episode_summaries = []
    step_samples = []
    reset_samples = []
    total_steps = 0
    total_simulated_s = 0.0
    start = clock()
    for seed in seeds:
        baseline = None
        for replay in range(repeats):
            sample = record_episode(client, seed, max_steps, clock=clock, step_hook=step_hook)
            if baseline is None:
                baseline = sample['trace']
            else:
                _compare_value(baseline, sample['trace'], tolerance,
                               f'seed={seed}/replay={replay}')
            episode_summaries.append({'seed': seed, 'replay': replay,
                                      'steps': sample['steps'],
                                      'terminal_result': sample['terminal_result']})
            step_samples.extend(sample['step_seconds'])
            reset_samples.append(sample['reset_seconds'])
            total_steps += sample['steps']
            total_simulated_s += sample['simulated_seconds']
    elapsed = clock() - start
    return {'status': 'PASS', 'episodes': len(episode_summaries), 'seeds': seeds,
            'replays_per_seed': repeats, 'total_steps': total_steps,
            'wall_seconds': elapsed, 'simulated_seconds': total_simulated_s,
            'steps_per_wall_second': total_steps / elapsed if elapsed else None,
            'simulation_speed_ratio': total_simulated_s / elapsed if elapsed else None,
            'reset_mean_ms': statistics.mean(reset_samples) * 1000,
            'reset_max_ms': max(reset_samples) * 1000,
            'step_mean_ms': statistics.mean(step_samples) * 1000,
            'step_p95_ms': sorted(step_samples)[min(len(step_samples) - 1, math.ceil(len(step_samples) * 0.95) - 1)] * 1000,
            'episode_summaries': episode_summaries,
            'determinism': {'status': 'PASS', 'absolute_and_relative_tolerance': tolerance,
                            'comparison': 'full observation, reward, termination and episode info',
                            'excluded_process_counters': sorted(DIAGNOSTIC_KEYS)}}


def _port_free(port: int) -> bool:
    with socket.socket() as listener:
        try:
            listener.bind(('127.0.0.1', port))
            return True
        except OSError:
            return False


def godot_runtime_command(exe: Path, port: int, frame_mode: str = 'realtime',
                          render_mode: str = 'headless') -> list[str]:
    """Keep physics at 60 Hz; only change *wall-clock frame pacing* when opted in.

    fixed_60 is an experiment. The engine must still pass the same per-step
    physics and deterministic replay checks on the target machine.
    """
    if frame_mode not in ('realtime', 'fixed_60'):
        raise ValueError(f'Unknown frame mode: {frame_mode}')
    if render_mode not in ('headless', 'windowed'):
        raise ValueError(f'Unknown render mode: {render_mode}')
    options = ['--headless'] if render_mode == 'headless' else []
    if frame_mode == 'fixed_60':
        options.extend(['--fixed-fps', '60'])
    return [str(exe), *options, '--path', str(ROOT),
            'res://scenes/remote.tscn', '--', f'--rl-port={port}']


def compare_benchmarks(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Compare matched workloads only; keep these results observational."""
    for label, report in (('baseline', baseline), ('candidate', candidate)):
        if report.get('status') != 'PASS' or report.get('mode') != 'headless':
            raise ValueError(f'{label}: requires a successful owned-headless benchmark')
        if report.get('physics_hz') != 60:
            raise ValueError(f'{label}: unexpected physics frequency')
        if report.get('godot_version') != '4.7.2.stable.official.ed1daf0bf':
            raise ValueError(f'{label}: Godot version does not match validated reference')
        if report.get('action') != [0.0, 0.0, 0.0] or report.get('random_start') is not True:
            raise ValueError(f'{label}: not the reference passive-action workload')
        if not isinstance(report.get('steps_per_wall_second'), (float, int)) or report['steps_per_wall_second'] <= 0:
            raise ValueError(f'{label}: missing throughput metric')
    base_conf, new_conf = baseline['configuration'], candidate['configuration']
    for field in ('seed', 'seeds', 'repeats', 'max_steps', 'tolerance'):
        if base_conf.get(field) != new_conf.get(field):
            raise ValueError(f'Cannot compare different workloads: {field}')
    if baseline.get('total_steps') != candidate.get('total_steps'):
        raise ValueError('Workload changed: different number of executed physics ticks')
    if baseline.get('episode_summaries') != candidate.get('episode_summaries'):
        raise ValueError('Workload changed: different episode terminal summaries')
    ratio = candidate['steps_per_wall_second'] / baseline['steps_per_wall_second']
    return {'baseline_steps_per_second': baseline['steps_per_wall_second'],
            'candidate_steps_per_second': candidate['steps_per_wall_second'],
            'relative_throughput': ratio, 'change_percent': (ratio - 1.0) * 100.0,
            'comparison_scope': 'same seeds/action/episode results; machine load may differ',
            'baseline_frame_mode': baseline.get('engine_frame_mode', 'realtime'),
            'candidate_frame_mode': candidate.get('engine_frame_mode', 'realtime')}


def native_engine_for_memory(exe: Path) -> Path:
    """Avoid sampling Godot's Windows *_console.exe launcher instead of engine.

    Godot's console binary can start a separate GUI-subsystem engine process;
    its own nearly static working set is NOT representative of the simulation.
    Only RAM monitoring opts into this resolution, to preserve prior benchmarks.
    """
    if exe.name.lower().endswith('_console.exe'):
        direct = exe.with_name(exe.name[:-len('_console.exe')] + '.exe')
        if not direct.is_file():
            raise FileNotFoundError(
                f'Memory monitoring requires the main Godot executable, not '
                f'the console launcher. Expected sibling: {direct}'
            )
        return direct
    return exe


@contextmanager
def godot_session(executable: str | None, port: int, log_dir: Path,
                  frame_mode: str = 'realtime', *, render_mode: str = 'headless',
                  process_callback: Callable[[int], None] | None = None,
                  monitor_engine_memory: bool = False
                  ) -> Iterator[tuple[str, Callable[[], RocketLandingClient]]]:
    """Ownership is explicit: never terminate a user-owned Godot process."""
    if render_mode not in ('headless', 'windowed'):
        raise ValueError(f'Unknown render mode: {render_mode}')
    if not executable and render_mode != 'headless':
        raise ValueError('windowed mode requires --godot to launch an owned process')
    if not executable and frame_mode != 'realtime':
        raise ValueError('fixed_60 mode requires --godot to launch an owned Godot process')
    if not executable:
        yield 'external (version not verified)', lambda: RocketLandingClient(port=port, timeout=15)
        return
    # Avoid resolving malformed Windows drive paths as relative paths under ROOT.
    # Example observed in Windows F04 evidence: ':\\Local' (missing 'C').
    if re.match(r'^:[\\/]', executable):
        raise ValueError(
            'Invalid Godot path: missing Windows drive letter before ":\\". '
            'Use the full executable path, e.g. C:\\Local\\Godot.exe.'
        )
    exe = Path(executable).expanduser().resolve()
    if not exe.is_file():
        raise FileNotFoundError(f'Godot executable not found: {exe}')
    runtime_exe = native_engine_for_memory(exe) if monitor_engine_memory else exe
    # Validate the actual binary that Popen will own, not a lightweight console
    # wrapper which can create a second independent engine PID on Windows.
    info = subprocess.run([str(runtime_exe), '--version'], capture_output=True, text=True,
                          timeout=12, check=True)
    version = info.stdout.strip()
    if not version.startswith('4.7.2.'):
        raise RuntimeError(f'F04 reference is Godot 4.7.2; found {version!r}. Use a validated engine.')
    if not _port_free(port):
        raise RuntimeError(f'Port {port} is already in use; refusing to attach an owned process')
    log_dir.mkdir(parents=True, exist_ok=True)
    # A fresh ZIP has no .godot/ import cache; parse/import resources before runtime.
    # Preserve this log independently from the running simulation process.
    imported = subprocess.run([str(runtime_exe), '--headless', '--path', str(ROOT),
                               '--editor', '--import', '--quit'], cwd=ROOT,
                              capture_output=True, text=True, encoding='utf-8',
                              errors='replace', timeout=90, check=False)
    import_output = imported.stdout + imported.stderr
    (log_dir / 'godot_import.log').write_text(import_output, encoding='utf-8')
    if imported.returncode != 0 or re.search(
            r'SCRIPT ERROR|Parse Error|Parser Error|Failed to load script|Failed to parse script',
            import_output, re.I):
        raise RuntimeError('Godot import failed; see logs/f04/godot_import.log')
    with (log_dir / f'godot_{render_mode}.log').open('w', encoding='utf-8') as output:
        proc = subprocess.Popen(godot_runtime_command(runtime_exe, port, frame_mode, render_mode),
                                cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        try:
            if process_callback is not None:
                process_callback(proc.pid)
            deadline = time.monotonic() + 20.0
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError(f'Godot exited before TCP READY (exit={proc.returncode})')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.2)
            else:
                raise TimeoutError(f'Godot did not open TCP port {port} within 20 s')
            time.sleep(0.4)  # let the readiness probe disconnect
            yield version, lambda: RocketLandingClient(port=port, timeout=15)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=4)


def process_image_path(pid: int) -> Path:
    """Return the actual Windows process image for a sampled PID (not a wrapper)."""
    if pid <= 0 or sys.platform != 'win32':
        raise ValueError('Process image verification requires Windows and a positive PID')
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
    kernel.QueryFullProcessImageNameW.argtypes = (
        wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)
    )
    kernel.QueryFullProcessImageNameW.restype = wintypes.BOOL
    handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        raise OSError(ctypes.get_last_error(), f'Cannot inspect Godot PID {pid}')
    try:
        buffer = ctypes.create_unicode_buffer(32768)
        length = wintypes.DWORD(len(buffer))
        if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(length)):
            raise OSError(ctypes.get_last_error(), 'QueryFullProcessImageNameW failed')
        return Path(buffer.value)
    finally:
        kernel.CloseHandle(handle)


def process_rss_bytes(pid: int) -> int:
    """RSS / working-set bytes of the *owned Godot process*, no extra pip deps.

    Linux uses /proc and Windows GetProcessMemoryInfo. An error is explicit,
    not a zero measurement. This is a trend indicator, not a leak proof.
    """
    if pid <= 0:
        raise ValueError('A positive owned Godot PID is required')
    if sys.platform == 'win32':
        from ctypes import wintypes

        class ProcessMemoryCounters(ctypes.Structure):
            _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD),
                        ('PeakWorkingSetSize', ctypes.c_size_t),
                        ('WorkingSetSize', ctypes.c_size_t),
                        ('QuotaPeakPagedPoolUsage', ctypes.c_size_t),
                        ('QuotaPagedPoolUsage', ctypes.c_size_t),
                        ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t),
                        ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                        ('PagefileUsage', ctypes.c_size_t),
                        ('PeakPagefileUsage', ctypes.c_size_t)]

        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        psapi = ctypes.WinDLL('psapi', use_last_error=True)
        kernel.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
        psapi.GetProcessMemoryInfo.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD)
        psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        handle = kernel.OpenProcess(0x0400 | 0x0010, False, pid)
        if not handle:
            raise OSError(ctypes.get_last_error(), f'Cannot open Godot PID {pid} for RSS')
        try:
            counters = ProcessMemoryCounters()
            counters.cb = ctypes.sizeof(counters)
            if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                raise OSError(ctypes.get_last_error(), 'GetProcessMemoryInfo failed')
            return int(counters.WorkingSetSize)
        finally:
            kernel.CloseHandle(handle)
    if sys.platform.startswith('linux'):
        for line in Path(f'/proc/{pid}/status').read_text(encoding='ascii').splitlines():
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) * 1024
        raise RuntimeError(f'No VmRSS in /proc/{pid}/status')
    raise RuntimeError('Memory RSS measurement supported on Windows/Linux only')


class MemoryTimeline:
    """Periodic samples; first/last/peak/delta, never claim zero leakage."""

    def __init__(self, interval: int = 60):
        if interval < 1:
            raise ValueError('RSS interval must be positive')
        self.interval = interval
        self.pid: int | None = None
        self.steps = 0
        self.samples: list[dict[str, int | float]] = []

    def attach(self, pid: int) -> None:
        self.pid = pid

    def sample(self) -> None:
        if self.pid is None:
            raise RuntimeError('Cannot sample memory before engine PID is known')
        self.samples.append({'step': self.steps,
                             'elapsed_wall_s': round(time.perf_counter() - self.started, 6),
                             'rss_bytes': process_rss_bytes(self.pid)})

    def begin(self) -> None:
        self.started = time.perf_counter()
        self.sample()

    def tick(self) -> None:
        self.steps += 1
        if self.steps % self.interval == 0:
            self.sample()

    def summary(self) -> dict[str, Any]:
        if not self.samples:
            raise RuntimeError('No RSS measurements recorded')
        values = [sample['rss_bytes'] for sample in self.samples]
        return {'measurement': 'Godot process working set / RSS',
                'interpretation': 'sampled trend only; cannot prove absence of memory leaks',
                'sample_interval_steps': self.interval,
                'pid': self.pid,
                'sample_count': len(values),
                'first_bytes': values[0], 'last_bytes': values[-1],
                'peak_bytes': max(values), 'min_bytes': min(values),
                'end_minus_start_bytes': values[-1] - values[0],
                'samples': self.samples}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE'),
                        help='Godot 4.7.2 executable; omitted means attach to an existing scene')
    parser.add_argument('--port', type=int, default=55425)
    parser.add_argument('--seeds', type=int, default=3, help='number of consecutive seeded scenarios')
    parser.add_argument('--seed', type=int, default=12345)
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--max-steps', type=int, default=900)
    parser.add_argument('--tolerance', type=float, default=1e-5)
    parser.add_argument('--frame-mode', choices=('realtime', 'fixed_60'), default='realtime',
                        help='fixed_60 is an opt-in uncapped timing experiment; physics remains 60 Hz')
    parser.add_argument('--compare-report', type=Path,
                        help='optional existing baseline JSON (same seeds/engine/workload)')
    parser.add_argument('--output', type=Path, default=ROOT / 'logs/f04' / 'benchmark.json')
    parser.add_argument('--monitor-memory', action='store_true',
                        help='Sample real Godot RSS/working set; owned process only')
    parser.add_argument('--rss-interval', type=int, default=60,
                        help='Steps between memory samples (default 60)')
    args = parser.parse_args(argv)
    if not (1024 <= args.port <= 65535 and 1 <= args.seeds <= 1000
            and args.repeats >= 2 and 50 <= args.max_steps <= 100000
            and 0 <= args.seed <= 2147483647
            and args.seed + args.seeds - 1 <= 2147483647
            and 0 < args.tolerance <= 1e-2 and 1 <= args.rss_interval <= 100000):
        parser.error('Invalid port/seeds/repeats/max-steps/seed/tolerance')
    if args.monitor_memory and not args.godot:
        parser.error('--monitor-memory requires an owned process (--godot)')
    if args.compare_report and args.output.resolve() == args.compare_report.resolve():
        parser.error('--output must be different from --compare-report (preserve baseline)')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {
        'schema_version': 1, 'created_utc': datetime.now(timezone.utc).isoformat(),
        'platform': platform.platform(), 'python': sys.version.split()[0],
        'cpu': platform.processor() or os.environ.get('PROCESSOR_IDENTIFIER', 'unknown'),
        'logical_cpus': os.cpu_count(), 'physics_hz': 60, 'mode': 'headless' if args.godot else 'external_unknown',
        'godot_version': 'unknown', 'engine_frame_mode': args.frame_mode,
        'action': list(ACTIONS), 'random_start': True,
        'configuration': {'seed': args.seed, 'seeds': args.seeds, 'repeats': args.repeats,
                          'max_steps': args.max_steps, 'tolerance': args.tolerance, 'port': args.port},
        'status': 'FAIL',
    }
    memory = MemoryTimeline(args.rss_interval) if args.monitor_memory else None
    try:
        if memory:
            # Recorded in evidence so a stable 6 MiB console launcher is never
            # misrepresented as the RSS of the physics process.
            requested_exe = Path(args.godot).expanduser().resolve()
            monitored_exe = native_engine_for_memory(requested_exe)
            report['memory_process_selection'] = {
                'requested_executable': str(requested_exe),
                'sampled_process_executable': str(monitored_exe),
                'console_wrapper_bypassed': monitored_exe != requested_exe,
            }
        with godot_session(args.godot, args.port, args.output.parent,
                           frame_mode=args.frame_mode,
                           process_callback=memory.attach if memory else None,
                           monitor_engine_memory=bool(memory)) as (version, client_factory):
            report['godot_version'] = version
            if memory and sys.platform == 'win32':
                actual = process_image_path(memory.pid)
                report['memory_process_selection']['observed_process_executable'] = str(actual)
                # A console launcher and its engine are distinct PIDs/images on
                # some Windows builds; reject samples from the wrong executable.
                if os.path.normcase(os.path.realpath(actual)) != os.path.normcase(os.path.realpath(monitored_exe)):
                    raise RuntimeError(
                        f'Memory PID {memory.pid} belongs to {actual}, expected {monitored_exe}'
                    )
                report['memory_process_selection']['process_image_verified'] = True
            with client_factory() as client:
                if memory:
                    memory.begin()
                report.update(benchmark(client,
                                        seeds=list(range(args.seed, args.seed + args.seeds)),
                                        repeats=args.repeats, max_steps=args.max_steps,
                                        tolerance=args.tolerance,
                                        step_hook=memory.tick if memory else None))
                if memory:
                    memory.sample()
                    report['process_memory'] = memory.summary()
        if args.compare_report:
            baseline = json.loads(args.compare_report.read_text(encoding='utf-8'))
            report['comparison'] = compare_benchmarks(baseline, report)
            print(f"F04 COMPARISON: {report['comparison']['relative_throughput']:.3f}x baseline throughput")
        print(f"F04 BENCHMARK PASS: {report['total_steps']} real steps, "
              f"{report['steps_per_wall_second']:.2f} steps/s, "
              f"same-seed replay PASS ({args.seeds} seeds x {args.repeats})")
        return_code = 0
    except Exception as exc:
        report['status'] = 'FAIL'
        report['error_type'] = type(exc).__name__
        report['error'] = str(exc)
        print(f'F04 BENCHMARK FAIL: {type(exc).__name__}: {exc}', file=sys.stderr)
        return_code = 1
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')
    print(f'Report: {args.output}')
    return return_code


if __name__ == '__main__':
    raise SystemExit(main())
