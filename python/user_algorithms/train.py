"""Train SAC: use --help to view available options."""
import argparse
import os
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory


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


def valid_seed(value: str) -> int:
    seed = int(value)
    if not 0 <= seed < 2**31:
        raise argparse.ArgumentTypeError("Seed must be in 0..2147483647")
    return seed


def valid_port(value: str) -> int:
    port = int(value)
    if not 1024 <= port <= 65535:
        raise argparse.ArgumentTypeError("Port must be in 1024..65535")
    return port


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
        help="Number of SAC steps after learning from demonstrations",
    )
    parser.add_argument(
        "--visual", action="store_true",
        help="Show the simulation; runs headless by default",
    )
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).with_name("sac_rocket.zip"),
        help="Destination for the trained model",
    )
    parser.add_argument(
        "--seed", type=valid_seed, default=42,
        help="Seed for demonstrations and SAC exploration",
    )
    parser.add_argument(
        "--port", type=valid_port, default=55423,
        help="Loopback TCP port for the Godot instance",
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


def evaluate(model, env, landed_result):
    landings = 0
    returns = []
    # Compare every checkpoint on identical starts outside the demo seeds.
    for seed, random_start in [(0, False), (101, True), (102, True), (103, True), (104, True)]:
        obs, _ = env.reset(seed=seed, options={"random_start": random_start})
        total = 0.0
        while True:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, info = env.step(action)
            total += reward
            if terminated or truncated:
                landings += info["result"] == landed_result
                returns.append(total)
                break
    mean_return = sum(returns) / len(returns)
    print(f"Evaluation at {model.num_timesteps:,} SAC steps: "
          f"{landings}/{len(returns)} landings, mean return {mean_return:.2f}", flush=True)
    return landings, mean_return


def train_and_save(model, env, args, demonstrations):
    from landing_examples import LANDED, keep_reference_behavior

    output = args.output if args.output.suffix else args.output.with_suffix(".zip")
    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=output.parent) as directory:
        checkpoint = Path(directory) / "best.zip"
        best_score = evaluate(model, env, LANDED)
        best_step = 0
        model.save(checkpoint)

        # Fit the critics to replay before letting their initial Q estimates
        # update the actor. Collect these transitions with the learned policy.
        warmup_steps = min(2_000, args.steps // 2)
        if warmup_steps:
            model.actor.requires_grad_(False)
            try:
                model.learn(total_timesteps=warmup_steps, reset_num_timesteps=False)
            finally:
                model.actor.requires_grad_(True)

        hook = keep_reference_behavior(model.actor, demonstrations, args.seed)
        try:
            while model.num_timesteps < args.steps:
                steps = min(5_000 - model.num_timesteps % 5_000, args.steps - model.num_timesteps)
                model.learn(total_timesteps=steps, reset_num_timesteps=False)
                score = evaluate(model, env, LANDED)
                if score > best_score:
                    best_score = score
                    best_step = model.num_timesteps
                    model.save(checkpoint)
                # Evaluation reused Godot. Reset before collecting more experience.
                model.set_env(model.get_env(), force_reset=True)
        finally:
            hook.remove()

        checkpoint.replace(output)
    print(f"Saved best evaluated policy (SAC step {best_step:,}) to {output}", flush=True)


def main(argv=None):
    args = parse_args(argv)

    import torch
    from stable_baselines3 import SAC
    from rocket_landing_env.gym_env import RocketLandingEnv
    from rocket_landing_env.policy import LandingFeatures
    from landing_examples import LandingReference, warm_start

    # Small batches and networks run faster without CPU thread-pool overhead.
    torch.set_num_threads(1)
    env = RocketLandingEnv(
        godot_executable=str(args.godot),
        project_path=str(PROJECT),
        headless=not args.visual,
        unpaced=not args.visual,
        random_start=True,
        port=args.port,
    )

    try:
        model = SAC(
            "MlpPolicy",
            env,
            verbose=1,
            seed=args.seed,
            device="cpu",
            learning_rate=1e-5,
            gamma=0.999,
            buffer_size=200_000,
            learning_starts=0,  # The replay buffer is seeded with real flights below.
            ent_coef="auto_0.01",
            target_entropy=-9.0,
            policy_kwargs={"features_extractor_class": LandingFeatures, "net_arch": [128, 128]},
        )
        demonstrations = warm_start(model, env, LandingReference(PROJECT), args.seed)
        train_and_save(model, env, args, demonstrations)
    finally:
        env.close()


if __name__ == "__main__":
    main()
