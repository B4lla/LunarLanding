"""Live F03 Gymnasium check_env and process lifecycle; does not train a policy.

Install optional dependencies from the project root:
    python -m pip install -e './python[gymnasium]'
For a separately launched bridge (already listening):
    python python/check_gym.py --port 55423
For an independently owned Godot process on a free port:
    python python/check_gym.py --godot 'C:/path/to/Godot.exe' --port 55424
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import socket
import time

from console import execute

ROOT = Path(__file__).resolve().parents[1]


def direct_godot_binary(executable: str, *, windows: bool | None = None) -> str:
    """Test-runner-only workaround for Windows Godot console wrappers.

    The console wrapper launches another executable; preferring its sibling
    avoids parent/child teardown ambiguity. Never change the Env library or
    silently choose a guessed/nonexistent binary.
    """
    if windows is None:
        windows = os.name == 'nt'
    path = Path(executable)
    if windows and path.name.lower().endswith('_console.exe'):
        main = path.with_name(path.name[:-len('_console.exe')] + '.exe')
        if main.is_file():
            return str(main)
    return executable


def available(port: int) -> bool:
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=0.4):
            return True
    except OSError:
        return False


def wait_for_listener_release(port: int, *, timeout: float = 5.0,
                              probe=None, clock=None, pause=None) -> bool:
    """Wait for TCP listener shutdown after owned Godot exits.

    Windows may not expose the socket's removal immediately after the owner
    exits. A successful TCP connection after the deadline is a real failure.
    Probes connect (rather than bind) so a TIME_WAIT port is not mistaken for
    a live TCP server. Injectable dependencies keep this test offline.
    """
    probe = available if probe is None else probe
    clock = time.monotonic if clock is None else clock
    pause = time.sleep if pause is None else pause
    deadline = clock() + timeout
    while True:
        if not probe(port):
            return True
        remaining = deadline - clock()
        if remaining <= 0:
            return False
        pause(min(0.15, remaining))


def assert_owned_listener_released(port: int) -> None:
    if not wait_for_listener_release(port):
        raise AssertionError(
            f'Owned Godot TCP listener remained open after close() on port {port}. '
            f'Check another listener with: netstat -ano -p tcp | findstr :{port}')


def run_check(port: int, godot: str | None, write) -> None:
    try:
        from gymnasium.utils.env_checker import check_env
        from rocket_landing_env.gym_env import RocketLandingEnv
    except ImportError as exc:
        raise RuntimeError('Missing optional dependency: python -m pip install -e "./python[gymnasium]"') from exc
    if godot and available(port):
        raise RuntimeError(f'Owned-process mode requires a free port, but {port} is busy')
    kwargs = {'port': port, 'headless': True, 'timeout': 20.0}
    if godot:
        binary = direct_godot_binary(godot)
        if binary != godot:
            write(f'Windows console-wrapper test: owned Godot uses main executable {binary}')
        kwargs.update(godot_executable=binary, project_path=ROOT)
    env = RocketLandingEnv(**kwargs)
    proc = env._process
    log = env._log_path
    try:
        check_env(env, skip_render_check=True)
        observation, info = env.reset(seed=100, options={'random_start': True})
        if not env.observation_space.contains(observation):
            raise AssertionError('Gymnasium observation outside declared space')
        if int(info['seed']) != 100:
            raise AssertionError('Seed mismatch in Gymnasium reset')
        obs2, info2 = env.reset(seed=100, options={'random_start': True})
        if not (observation == obs2).all() or int(info2['seed']) != 100:
            raise AssertionError('Same seed must reproduce the same reset')
        step = env.step(env.action_space.sample())
        if len(step) != 5 or not env.observation_space.contains(step[0]):
            raise AssertionError('Invalid Gymnasium step tuple')
        write('PASS: real Gymnasium check_env; spaces; seeds; step(action)')
    finally:
        env.close()
    if godot:
        if proc is None or proc.poll() is None:
            raise AssertionError('Owned Godot process was not reaped on close()')
        assert_owned_listener_released(port)
        write(f'PASS: owned Godot exited on close(); detailed engine log: {log}')
        # Reopen and close with the same port to prove the previous process released it.
        new_env = RocketLandingEnv(**kwargs)
        try:
            o, _ = new_env.reset(seed=42)
            if not new_env.observation_space.contains(o):
                raise AssertionError('Reopened simulator returned invalid reset data')
        finally:
            new_env.close()
        assert_owned_listener_released(port)
        write('PASS: owned Godot opened and shut down a second time on the same port')
    write('F03 GYMNASIUM LIVE PASS')


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', type=int, default=55423)
    p.add_argument('--godot', default=None, help='Godot executable (owned process on a free port)')
    args = p.parse_args()
    if not 1024 <= args.port <= 65535:
        p.error('Port must be 1024..65535')
    return execute('check_gym', lambda write: run_check(args.port, args.godot, write))


if __name__ == '__main__':
    raise SystemExit(main())
