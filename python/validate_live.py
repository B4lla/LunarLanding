"""F03 strict real-engine integration check. No training and no third-party imports.

Requires a RUNNING res://scenes/remote.tscn on localhost. The same tests may be
unit-tested with a fake client, but a PASS here is only real when Godot is live.
"""
from __future__ import annotations

import argparse
import math
import time
from typing import Callable

from console import execute
from rocket_landing_env import ProtocolError, RocketLandingClient

HZ = 60
OBS_TOL = 2e-3  # Jolt floats; do not require bitwise determinism.


def _counter(info: dict, key: str) -> int:
    value = info.get(key)
    if type(value) not in (int, float) or not math.isfinite(value) or int(value) != value:
        raise AssertionError(f"Missing or invalid {key}: {value!r}")
    return int(value)


def _near(a: list[float], b: list[float], label: str, tol: float = OBS_TOL) -> None:
    if len(a) != len(b) or not all(math.isfinite(x) and math.isfinite(y) and abs(x-y) <= tol
                                  for x, y in zip(a, b)):
        raise AssertionError(f"{label}: inconsistent states, expected {a!r}; got {b!r}")


def _step_fingerprint(client: RocketLandingClient, *, idle_seconds: float,
                      delay_between_steps: bool = False) -> tuple[list[float], list[float], list[float], list[int], list[float]]:
    """Return reset/step observations, integration deltas and elapsed simulation seconds."""
    reset_obs, reset_info = client.reset(seed=1007, random_start=False)
    if idle_seconds and not delay_between_steps:
        time.sleep(idle_seconds)
    first_obs, _, terminal, truncated, first_info = client.step([0.7, 0.0, 0.0])
    if terminal or truncated:
        raise AssertionError("Unexpected terminal state on first tick")
    if idle_seconds and delay_between_steps:
        time.sleep(idle_seconds)
    second_obs, _, terminal, truncated, second_info = client.step([0.7, 0.0, 0.0])
    if terminal or truncated:
        raise AssertionError("Unexpected terminal state on second tick")
    counters = [_counter(x, 'body_integration_serial') for x in (reset_info, first_info, second_info)]
    commits = [_counter(x, 'reset_commit_serial') for x in (reset_info, first_info, second_info)]
    if commits[0] < 1 or not (commits[0] == commits[1] == commits[2]):
        raise AssertionError(f"Unexpected reset commits during step(): {commits}")
    deltas = [counters[1]-counters[0], counters[2]-counters[1]]
    if deltas != [1, 1]:
        raise AssertionError(f"Expected exactly one Jolt integration per step, got {deltas}")
    elapsed = [float(x['elapsed_s']) for x in (reset_info, first_info, second_info)]
    if abs(elapsed[0]) > 1e-5 or any(abs(elapsed[i] - i/HZ) > 1e-4 for i in (1, 2)):
        raise AssertionError(f"Expected simulated episode time [0, 1/60, 2/60], got {elapsed}")
    fuel = [float(x['fuel_kg']) for x in (reset_info, first_info, second_info)]
    if not (fuel[0] > fuel[1] > fuel[2] >= 0):
        raise AssertionError(f"Fuel must decrease only when running positive throttle: {fuel}")
    return reset_obs, first_obs, second_obs, deltas, fuel


def verify_pause(client: RocketLandingClient, idle_seconds: float, write: Callable[[str], None]) -> None:
    """Compare matching seeded trajectories with idle before and between actions.

    This catches background motion/fuel use without adding an observe wire command.
    It does NOT prove that the engine consumes zero CPU while paused.
    """
    reference = _step_fingerprint(client, idle_seconds=0)
    for where in ('before', 'between'):
        delayed = _step_fingerprint(client, idle_seconds=idle_seconds,
                                    delay_between_steps=(where == 'between'))
        for index, label in enumerate(('reset', 'step1', 'step2')):
            _near(reference[index], delayed[index], f"Idle {where}: {label}")
        if reference[3] != delayed[3]:
            raise AssertionError(f"Idle {where} changed Jolt tick counts")
        _near(reference[4], delayed[4], f"Idle {where}: fuel", tol=1e-4)
    write(f"PASS: one Jolt integration per step, exact episode dt 1/60 s, "
          f"no state/fuel drift after {idle_seconds:.2f} s pauses (before/between steps)")


def verify_spawn(client: RocketLandingClient, write: Callable[[str], None]) -> None:
    nominal, _ = client.reset(seed=101, random_start=False)
    _near(nominal[:3], [0.0, 50.0, 0.0], "Nominal spawn")
    starts = [client.reset(seed=seed, random_start=True)[0] for seed in (101, 102, 103, 104)]
    repeated, _ = client.reset(seed=101, random_start=True)
    _near(starts[0], repeated, "Repeated seed")
    for axis, label in enumerate(("X", "Y", "Z")):
        values = [obs[axis] for obs in starts]
        if any(abs(value - nominal[axis]) > 4.0 + OBS_TOL for value in values):
            raise AssertionError(f"Randomized {label} is more than 4 m from nominal: {values}")
        if max(values) - min(values) <= OBS_TOL:
            raise AssertionError(f"Randomized {label} does not vary: {values}")
    write("PASS: randomized X/Y/Z spawn within 4 m per axis, repeatable from the seed")


def verify_terminal(client: RocketLandingClient, max_steps: int, write: Callable[[str], None]) -> None:
    client.reset(seed=1234, random_start=False)
    for iteration in range(1, max_steps+1):
        _, _, terminated, truncated, info = client.step([0.0, 0.0, 0.0])
        if terminated or truncated:
            if terminated == truncated:
                raise AssertionError("Both terminated and truncated set simultaneously")
            write(f"PASS: complete episode {iteration} ticks: result={info.get('result')} "
                  f"reason={info.get('reason')!r} terminated={terminated} truncated={truncated}")
            break
    else:
        raise AssertionError(f"No episode ended within {max_steps} actual steps")
    try:
        client.step([0.0, 0.0, 0.0])
    except ProtocolError as exc:
        if 'episode_finished' not in str(exc):
            raise AssertionError(f"Unexpected post-terminal error: {exc}") from exc
    else:
        raise AssertionError("Step after terminal state was accepted")
    reset_obs, reset_info = client.reset(seed=1234, random_start=False)
    if not math.isclose(reset_obs[1], 50.0, abs_tol=1e-4):
        raise AssertionError("After terminated episode, reset altitude is not nominal")
    if not math.isclose(reset_obs[4], -5.0, abs_tol=1e-4):
        raise AssertionError("After terminated episode, reset vertical speed is not nominal")
    if reset_info.get('reason') or abs(float(reset_info['elapsed_s'])) > 1e-5:
        raise AssertionError("Episode flags/time survive reset")
    write("PASS: post-terminal step rejected; subsequent reset restores time, state and flags")


def live_check(port: int, idle_seconds: float, max_steps: int, write: Callable[[str], None]) -> None:
    write(f"Connected to Godot 127.0.0.1:{port}: testing F03 pause/ticks")
    with RocketLandingClient(port=port, timeout=15) as client:
        verify_pause(client, idle_seconds, write)
        verify_spawn(client, write)
        verify_terminal(client, max_steps, write)
    # Godot accepts only one socket at a time; give its process loop time to
    # observe a closed connection before attempting a fresh connection.
    time.sleep(0.2)
    with RocketLandingClient(port=port, timeout=15) as client:
        obs, _ = client.reset(seed=1234)
        if abs(obs[4] + 5.0) > 1e-4:
            raise AssertionError("Fresh connection reset failed")
    write("F03 LIVE EXTENDED PASS: pause, ticks, termination, reconnect")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=55423)
    parser.add_argument('--idle-seconds', type=float, default=0.5)
    parser.add_argument('--max-steps', type=int, default=900)
    args = parser.parse_args()
    if not 0.1 <= args.idle_seconds <= 5 or not 50 <= args.max_steps <= 10000:
        parser.error('idle-seconds must be 0.1..5 and max-steps 50..10000')
    return execute('validate_live', lambda write: live_check(args.port, args.idle_seconds, args.max_steps, write))


if __name__ == '__main__':
    raise SystemExit(main())
