"""Train SAC: use --help to view available options."""
import argparse
import os
from pathlib import Path
import shutil


PROJECT = Path(__file__).resolve().parents[2]
def default_godot():
    """Prefer local configuration, then a Godot executable available on PATH."""
    return os.environ.get("GODOT_EXE") or shutil.which("godot") or shutil.which("godot4")


def positive_steps(value: str) -> int:
    try:
        steps = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Steps must be a positive integer") from exc
    if steps <= 0:
        raise argparse.ArgumentTypeError("Steps must be a positive integer")
    return steps


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Train a SAC agent to land the rocket.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--godot", type=Path, default=default_godot(),
        help="Path to Godot; defaults to GODOT_EXE or Godot on PATH",
    )
    parser.add_argument(
        "--steps", type=positive_steps, default=100_000,
        help="Number of training steps",
    )
    parser.add_argument(
        "--visual", action="store_true",
        help="Show the simulation; runs headless by default",
    )
    args = parser.parse_args(argv)
    if args.godot is None:
        parser.error("Godot not found. Use --godot, GODOT_EXE, or add Godot to PATH.")
    args.godot = args.godot.expanduser().resolve()
    if not args.godot.is_file():
        parser.error(
            f"Godot must be an executable file: {args.godot}. "
            "Provide the correct path with --godot."
        )
    return args


def main(argv=None):
    args = parse_args(argv)

    from stable_baselines3 import SAC
    from rocket_landing_env.gym_env import RocketLandingEnv

    env = RocketLandingEnv(
        godot_executable=str(args.godot),
        project_path=str(PROJECT),
        headless=not args.visual,
        random_start=False,
    )

    try:
        model = SAC(
            "MlpPolicy",
            env,
            verbose=1,
            learning_rate=3e-4,
            buffer_size=100_000,
        )
        model.learn(total_timesteps=args.steps)
        model.save(str(Path(__file__).with_name("sac_rocket")))
    finally:
        env.close()


if __name__ == "__main__":
    main()
