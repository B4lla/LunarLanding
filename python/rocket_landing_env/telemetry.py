"""F06 local, offline episode receipts and deterministic TCP replay.

This module never advances Godot except through the existing reset/step client.
No policy, RL trainer, physics code or protocol changes are introduced.
"""
from __future__ import annotations

import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
import platform
from pathlib import Path
import tempfile
from typing import Any, Callable

SCHEMA = 1
PHYSICS_HZ = 60
MAX_STEPS = 20000
PROCESS_COUNTERS = frozenset({'physics_frame', 'body_integration_serial', 'reset_commit_serial'})
OBS_NAMES = ('x_m', 'y_m', 'z_m', 'vx_m_s', 'vy_m_s', 'vz_m_s',
             'qw', 'qx', 'qy', 'qz', 'omega_x_rad_s', 'omega_y_rad_s', 'omega_z_rad_s',
             'fuel_fraction', 'contact')
CONFIG_PATHS = ('project.godot', 'config/lunar.tres', 'config/reward.tres',
                'scripts/rocket_physics.gd', 'scripts/episode_controller.gd',
                'scripts/rl_bridge.gd', 'scenes/rocket.tscn', 'scenes/terrain.tscn')


def canonical(data: Any) -> bytes:
    return (json.dumps(data, ensure_ascii=False, allow_nan=False, sort_keys=True,
                       separators=(',', ':')) + '\n').encode('utf-8')


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def configuration_fingerprint(root: Path) -> dict[str, str]:
    """Fingerprint the simulator contract, not display-only F05 resources."""
    return {name: sha256((root / name).read_bytes()) for name in CONFIG_PATHS}


def _numbers(values: Any, n: int, label: str) -> list[float]:
    if not isinstance(values, list) or len(values) != n:
        raise ValueError(f'{label} must be a list of {n} finite numbers')
    if any(type(x) not in (float, int) or not math.isfinite(x) for x in values):
        raise ValueError(f'{label} contains nonfinite or nonnumeric values')
    return [float(x) for x in values]


def validate_action(action: Any) -> list[float]:
    values = _numbers(action, 3, 'action')
    if not (0 <= values[0] <= 1 and -1 <= values[1] <= 1 and -1 <= values[2] <= 1):
        raise ValueError('action out of bounds')
    return values


def _valid_info(info: Any) -> dict[str, Any]:
    if not isinstance(info, dict) or not all(isinstance(k, str) for k in info):
        raise ValueError('info must be an object')
    try:
        canonical(info)  # reject non-finite nested values
    except (ValueError, TypeError) as exc:
        raise ValueError('info must contain finite JSON values') from exc
    return info


def validate_trace(trace: Any) -> dict[str, Any]:
    if not isinstance(trace, dict) or trace.get('schema_version') != SCHEMA:
        raise ValueError('Unsupported telemetry schema')
    if trace.get('source') != 'Godot TCP v1 RocketLandingClient':
        raise ValueError('Unexpected trace source')
    if trace.get('physics_hz') != PHYSICS_HZ:
        raise ValueError('Unexpected tick rate')
    for field in ('engine_version', 'python_version', 'host_platform'):
        if not isinstance(trace.get(field), str) or not trace[field].strip():
            raise ValueError(f'Missing runtime metadata: {field}')
    if type(trace.get('seed')) is not int or not 0 <= trace['seed'] <= 2147483647:
        raise ValueError('Invalid episode seed')
    if type(trace.get('random_start')) is not bool:
        raise ValueError('random_start must be boolean')
    if not isinstance(trace.get('created_utc'), str) or not trace['created_utc'].endswith('+00:00'):
        raise ValueError('Missing timestamp')
    if trace.get('pattern') not in ('passive', 'pulse'):
        raise ValueError('Unknown recorded action pattern')
    if not isinstance(trace.get('configuration_sha256'), dict) or set(trace['configuration_sha256']) != set(CONFIG_PATHS):
        raise ValueError('Missing configuration fingerprint')
    if any(not isinstance(s, str) or len(s) != 64 or any(c not in '0123456789abcdef' for c in s)
           for s in trace['configuration_sha256'].values()):
        raise ValueError('Malformed configuration fingerprint')
    reset = trace.get('reset')
    if not isinstance(reset, dict):
        raise ValueError('Missing reset observation')
    _numbers(reset.get('observation'), 15, 'reset.observation')
    _valid_info(reset.get('info'))
    steps = trace.get('steps')
    if not isinstance(steps, list) or not 1 <= len(steps) <= MAX_STEPS:
        raise ValueError('Invalid step count')
    finished = False
    for index, step in enumerate(steps, start=1):
        if not isinstance(step, dict) or step.get('tick') != index or type(step.get('tick')) is not int:
            raise ValueError(f'Invalid step ordinal at tick {index}')
        validate_action(step.get('action'))
        _numbers(step.get('observation'), 15, 'step.observation')
        if type(step.get('reward')) not in (float, int) or not math.isfinite(step['reward']):
            raise ValueError('Invalid reward')
        _valid_info(step.get('info'))
        if type(step.get('terminated')) is not bool or type(step.get('truncated')) is not bool:
            raise ValueError('Invalid terminal flags')
        if step['terminated'] and step['truncated']:
            raise ValueError('Both terminal flags set')
        if finished:
            raise ValueError('Steps after terminal event')
        finished = step['terminated'] or step['truncated']
    if trace.get('completion') != ('TERMINAL' if finished else 'STEP_LIMIT'):
        raise ValueError('Completion flag contradicts final step')
    return trace


def demo_action(tick: int, pattern: str) -> list[float]:
    """Scripted actuator smoke stimulus, NOT an agent/controller/trainer."""
    if type(tick) is not int or tick < 1:
        raise ValueError('Invalid tick')
    if pattern == 'passive':
        return [0.0, 0.0, 0.0]
    if pattern == 'pulse':
        return [0.65 if 30 <= tick < 90 else 0.0, 0.0, 0.0]
    raise ValueError('Unknown pattern')


def record(client: Any, root: Path, *, seed: int = 12345,
           random_start: bool = True, max_steps: int = 900, pattern: str = 'passive',
           actions: Callable[[int], list[float]] | None = None,
           engine_version: str = 'unverified (caller supplied client)') -> dict[str, Any]:
    if type(seed) is not int or not 0 <= seed <= 2147483647:
        raise ValueError('Invalid seed')
    if type(random_start) is not bool or type(max_steps) is not int or not 1 <= max_steps <= MAX_STEPS:
        raise ValueError('Invalid episode options')
    if pattern not in ('passive', 'pulse') or not isinstance(engine_version, str) or not engine_version:
        raise ValueError('Unknown action pattern or engine version')
    observation, info = client.reset(seed=seed, random_start=random_start)
    trace = {'schema_version': SCHEMA,
             'source': 'Godot TCP v1 RocketLandingClient',
             'created_utc': datetime.now(timezone.utc).isoformat(),
             'physics_hz': PHYSICS_HZ, 'engine_version': engine_version,
             'python_version': platform.python_version(), 'host_platform': platform.platform(),
             'seed': seed, 'random_start': random_start,
             'pattern': pattern, 'configuration_sha256': configuration_fingerprint(root),
             'reset': {'observation': list(observation), 'info': dict(info)}, 'steps': [],
             'completion': 'STEP_LIMIT'}
    for tick in range(1, max_steps + 1):
        action = validate_action(actions(tick) if actions is not None else demo_action(tick, pattern))
        obs, reward, terminated, truncated, new_info = client.step(action)
        trace['steps'].append({'tick': tick, 'action': action,
                               'observation': list(obs), 'reward': reward,
                               'terminated': terminated, 'truncated': truncated,
                               'info': dict(new_info)})
        if terminated or truncated:
            trace['completion'] = 'TERMINAL'
            break
    return validate_trace(trace)


def _compare(expected: Any, actual: Any, tolerance: float, context: str) -> None:
    if type(expected) in (int, float) and type(actual) in (int, float):
        if not math.isclose(float(expected), float(actual), rel_tol=tolerance, abs_tol=tolerance):
            raise AssertionError(f'{context}: {expected!r} != {actual!r}')
    elif isinstance(expected, list) and isinstance(actual, (list, tuple)):
        if len(expected) != len(actual):
            raise AssertionError(f'{context}: length mismatch')
        for i, (a, b) in enumerate(zip(expected, actual)):
            _compare(a, b, tolerance, f'{context}[{i}]')
    elif isinstance(expected, dict) and isinstance(actual, dict):
        if expected.keys() != actual.keys():
            raise AssertionError(f'{context}: key mismatch')
        for key in expected:
            _compare(expected[key], actual[key], tolerance, f'{context}.{key}')
    elif type(expected) is not type(actual) or expected != actual:
        raise AssertionError(f'{context}: {expected!r} != {actual!r}')


def _episode_info(info: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in info.items() if k not in PROCESS_COUNTERS}


def replay(client: Any, trace: dict[str, Any], root: Path, *, tolerance: float = 1e-5,
           engine_version: str | None = None) -> dict[str, Any]:
    """Run recorded actions through the same real TCP endpoint; never set positions."""
    validate_trace(trace)
    if not (type(tolerance) in (float, int) and math.isfinite(tolerance) and 0 < tolerance <= 1e-2):
        raise ValueError('Invalid numeric tolerance')
    if trace['configuration_sha256'] != configuration_fingerprint(root):
        raise ValueError('Physics/configuration fingerprint changed; replay rejected')
    if (engine_version is not None and trace['engine_version'].startswith('4.')
            and engine_version != trace['engine_version']):
        raise ValueError('Godot engine version differs from recorded trajectory')
    obs, info = client.reset(seed=trace['seed'], random_start=trace['random_start'])
    _compare(trace['reset']['observation'], list(obs), tolerance, 'reset.observation')
    _compare(_episode_info(trace['reset']['info']), _episode_info(info), tolerance, 'reset.info')
    for item in trace['steps']:
        obs, reward, terminated, truncated, new_info = client.step(item['action'])
        context = f"tick={item['tick']}"
        _compare(item['observation'], list(obs), tolerance, context + '.observation')
        _compare(item['reward'], reward, tolerance, context + '.reward')
        _compare(item['terminated'], terminated, tolerance, context + '.terminated')
        _compare(item['truncated'], truncated, tolerance, context + '.truncated')
        _compare(_episode_info(item['info']), _episode_info(new_info), tolerance, context + '.info')
    return {'status': 'PASS', 'mode': 'live TCP physical replay',
            'verified_steps': len(trace['steps']), 'tolerance': tolerance,
            'seed': trace['seed'], 'completion': trace['completion'],
            'excluded_process_counters': sorted(PROCESS_COUNTERS)}


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp: str | None = None
    try:
        with tempfile.NamedTemporaryFile(mode='wb', dir=path.parent, prefix='.f06-', delete=False) as handle:
            tmp = handle.name
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        if tmp is not None and os.path.exists(tmp):
            os.unlink(tmp)


def write_trace(path: Path, trace: dict[str, Any]) -> str:
    validate_trace(trace)
    data = canonical(trace)
    digest = sha256(data)
    _atomic_write(path, data)
    _atomic_write(Path(str(path) + '.sha256'), (digest + '  ' + path.name + '\n').encode('ascii'))
    return digest


def read_trace(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size > 40_000_000:
        raise ValueError('Missing or oversized trace (40 MB limit)')
    raw = path.read_bytes()
    receipt = Path(str(path) + '.sha256')
    if not receipt.is_file():
        raise ValueError('Missing adjacent SHA-256 receipt')
    expected = receipt.read_text(encoding='ascii').split()
    if len(expected) != 2 or expected[1] != path.name or sha256(raw) != expected[0]:
        raise ValueError('Trace receipt mismatch')
    try:
        data = json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ValueError('Invalid trace JSON') from exc
    return validate_trace(data)


def write_csv(path: Path, trace: dict[str, Any]) -> None:
    """Flatten trace into one row per physical tick; no diagnostic fields dropped."""
    import io
    validate_trace(trace)
    out = io.StringIO(newline='')
    writer = csv.writer(out, lineterminator='\n')
    writer.writerow(['tick', 'elapsed_s', 'throttle_action', 'gimbal_x_action',
                     'gimbal_z_action', *OBS_NAMES, 'reward', 'terminated',
                     'truncated', 'result', 'reason', 'info_json'])
    for step in trace['steps']:
        info = step['info']
        writer.writerow([step['tick'], info.get('elapsed_s', step['tick'] / PHYSICS_HZ),
                         *step['action'], *step['observation'], step['reward'],
                         step['terminated'], step['truncated'], info.get('result', ''),
                         info.get('reason', ''), json.dumps(info, sort_keys=True,
                                                         ensure_ascii=False, allow_nan=False)])
    _atomic_write(path, out.getvalue().encode('utf-8'))


def summarize(trace: dict[str, Any]) -> dict[str, Any]:
    validate_trace(trace)
    steps = trace['steps']
    last = steps[-1]
    return {'seed': trace['seed'], 'steps': len(steps),
            'simulated_seconds': len(steps) / PHYSICS_HZ,
            'completion': trace['completion'], 'terminal_result': last['info'].get('result'),
            'terminal_reason': last['info'].get('reason'),
            'cumulative_reward': sum(float(tick['reward']) for tick in steps),
            'minimum_center_altitude_m': min([trace['reset']['observation'][1]] + [tick['observation'][1] for tick in steps]),
            'final_vertical_velocity_m_s': last['observation'][4],
            'final_horizontal_speed_m_s': math.hypot(last['observation'][3], last['observation'][5]),
            'fuel_remaining_fraction': last['observation'][13]}
