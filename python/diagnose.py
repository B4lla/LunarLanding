"""Live F03 TCP/reset diagnostic (no training); records errors in a local log."""
from __future__ import annotations

import argparse

from console import execute
from rocket_landing_env import RocketLandingClient


def diagnose(port: int, write) -> None:
    write(f"Connecting to 127.0.0.1:{port} ...")
    with RocketLandingClient(port=port) as env:
        write("TCP connected; v1 / 60 Hz contract verified.")
        obs, info = env.reset(seed=12345, random_start=False)
        write(f"reset: position_xyz={obs[:3]} velocity_xyz={obs[3:6]}")
        write(f"  integration_serial={info.get('body_integration_serial')} "
              f"reset_commit_serial={info.get('reset_commit_serial')} "
              f"physics_frame={info.get('physics_frame')}")
        write(f"  status={info.get('result')} fuel_kg={info.get('fuel_kg')}")
        if abs(obs[3]) > 1e-4 or abs(obs[4] + 5.0) > 1e-4 or abs(obs[5]) > 1e-4:
            raise AssertionError(f"reset returned velocity {obs[3:6]}; expected [0, -5, 0]")
        if info.get('body_integration_serial') is None or info.get('reset_commit_serial') is None:
            raise AssertionError("The server did not return integration counters; check its version")
        step_obs, _, terminated, truncated, step_info = env.step([0.0, 0.0, 0.0])
        write(f"step: position_xyz={step_obs[:3]} velocity_xyz={step_obs[3:6]}")
        write(f"  integration_serial={step_info.get('body_integration_serial')} "
              f"reset_commit_serial={step_info.get('reset_commit_serial')} "
              f"physics_frame={step_info.get('physics_frame')}")
        write(f"  terminated={terminated} truncated={truncated} status={step_info.get('result')}")
        if step_obs[4] >= obs[4]:
            raise AssertionError("A step without thrust did not produce downward gravitational acceleration")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=55423)
    args = parser.parse_args()
    return execute('diagnose', lambda write: diagnose(args.port, write))


if __name__ == '__main__':
    raise SystemExit(main())
