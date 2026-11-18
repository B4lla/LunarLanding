"""Real Godot F03 integration smoke. No RL training; log saved for support."""
from __future__ import annotations

import argparse

from console import execute
from rocket_landing_env import RocketLandingClient


def check(port: int, resets: int, write) -> None:
    write(f"Connecting to 127.0.0.1:{port} | resets={resets} ...")
    with RocketLandingClient(port=port) as env:
        write("TCP connected. Checking resets and physics ...")
        reference = None
        for i in range(resets):
            obs, info = env.reset(seed=12345, random_start=False)
            if reference is None:
                reference = obs
            if any(abs(x - y) > 1e-4 for x, y in zip(obs, reference)):
                raise AssertionError(f'Reset {i}: state residue versus original')
            if abs(obs[3]) > 1e-4 or abs(obs[4] + 5.0) > 1e-4:
                raise AssertionError(f'Reset {i}: velocity failed to reset: {obs[3:6]}')
            if info['fuel_kg'] != 100.0 or info['throttle'] != 0.0:
                raise AssertionError(f'Reset {i}: fuel or throttle residual')
            step_obs, reward, terminated, truncated, info = env.step([0.0, 0.0, 0.0])
            assert len(step_obs) == 15 and not (terminated or truncated)
            if i == 0:
                write(f'first step: {step_obs[:6]} reward: {reward}')
            if (i + 1) % 20 == 0 or i + 1 == resets:
                write(f"Resets verified: {i + 1}/{resets}")
        random_a, _ = env.reset(seed=777, random_start=True)
        random_b, _ = env.reset(seed=777, random_start=True)
        if any(abs(x - y) > 1e-4 for x, y in zip(random_a, random_b)):
            raise AssertionError('Repeated randomized seed produced different spawn states')

        env.reset(seed=12345)
        free_obs = None
        for _ in range(5):
            free_obs, *_ = env.step([0.0, 0.0, 0.0])
        env.reset(seed=12345)
        power_obs = None
        power_info = None
        for _ in range(5):
            power_obs, _, _, _, power_info = env.step([1.0, 0.0, 0.0])
        if power_obs[4] < free_obs[4] + 0.1:
            raise AssertionError(f'Engine did not accelerate the rocket: free={free_obs[4]} powered={power_obs[4]}')
        if power_info['fuel_kg'] >= 100.0:
            raise AssertionError('Main engine did not consume fuel')
        write(f'F03 PASS: {resets} real reset/step cycles, seeded starts and engine force')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=55423)
    parser.add_argument('--resets', type=int, default=100)
    args = parser.parse_args()
    if args.resets <= 0:
        parser.error('--resets must be greater than 0')
    return execute('smoke', lambda write: check(args.port, args.resets, write))


if __name__ == '__main__':
    raise SystemExit(main())
