"""Generate successful flight demonstrations and warm-start the SAC actor."""
from configparser import ConfigParser
from math import atan2

import numpy as np
import torch


LANDED = "SUCCESSFUL LANDING"


class LandingReference:
    """Generate training labels from a descent profile and tilt feedback."""

    def __init__(self, project):
        config = ConfigParser()
        config.read(project / "config" / "lunar.tres", encoding="utf-8")
        self.gravity = config.getfloat("resource", "lunar_gravity_m_s2")
        self.max_thrust = config.getfloat("resource", "max_thrust_newtons")
        self.half_height = config.getfloat("resource", "rocket_half_height_m")

    def action(self, obs, info):
        x, y, z, vx, vy, vz, qw, qx, qy, qz, wx, _, wz, _, contact = obs
        if contact:
            return np.zeros(3, dtype=np.float32)

        pitch = atan2(2 * (qw * qx + qy * qz), 1 - 2 * (qx * qx + qz * qz))
        roll = atan2(2 * (qw * qz + qx * qy), 1 - 2 * (qx * qx + qz * qz))
        target_pitch = np.clip((-0.17 * z - 0.62 * vz) / self.gravity, -0.14, 0.14)
        target_roll = np.clip((0.17 * x + 0.62 * vx) / self.gravity, -0.14, 0.14)
        descent_speed = -np.clip((y - self.half_height) * 0.22, 0.8, 5.0)
        throttle = info["mass_kg"] * (self.gravity + 1.8 * (descent_speed - vy)) / self.max_thrust
        return np.array([
            np.clip(throttle, 0.12, 1.0),
            np.clip(4.0 * (pitch - target_pitch) + 3.8 * wx, -1.0, 1.0),
            np.clip(4.0 * (roll - target_roll) + 3.8 * wz, -1.0, 1.0),
        ], dtype=np.float32)


def collect_examples(model, env, reference, rng, examples, count, actor_fraction):
    successful_episodes = 0
    for episode in range(count):
        # Include the nominal start and perturbations so the actor sees
        # corrective steering as well as a straight descent.
        obs, info = env.reset(seed=int(rng.integers(0, 2**31 - 1)),
                              options={"random_start": episode != 0 and episode % 4 != 0})
        trajectory = []
        while True:
            target = reference.action(obs, info)
            action = target
            if actor_fraction:
                predicted, _ = model.predict(obs, deterministic=True)
                action = (1.0 - actor_fraction) * target + actor_fraction * predicted
            if episode or actor_fraction:
                action = np.clip(action + rng.normal(0, [0.04, 0.14, 0.14]),
                                 env.action_space.low, env.action_space.high)
            next_obs, reward, terminated, truncated, info = env.step(action)
            done = terminated or truncated
            trajectory.append((obs, next_obs, action, target, reward, done, info))
            obs = next_obs
            if done:
                break

        if info["result"] != LANDED:
            continue
        successful_episodes += 1
        for obs, next_obs, action, target, reward, done, info in trajectory:
            examples.append((obs, model.policy.scale_action(target)))
            model.replay_buffer.add(obs[None], next_obs[None],
                                    model.policy.scale_action(action)[None],
                                    np.array([reward]), np.array([done]), [info])

    print(f"Demonstration landings: {successful_episodes}/{count} ({len(examples)} transitions total)",
          flush=True)


def fit_actor(model, examples, rng, optimizer, updates):
    observations, actions = zip(*examples)
    inputs = torch.as_tensor(np.asarray(observations), device=model.device)
    targets = torch.as_tensor(np.asarray(actions), device=model.device)
    for _ in range(updates):
        indices = rng.integers(0, len(inputs), size=256)
        predicted = model.actor(inputs[indices], deterministic=True)
        loss = torch.nn.functional.mse_loss(predicted, targets[indices])
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
    return inputs, targets


def warm_start(model, env, reference, seed):
    rng = np.random.default_rng(seed)
    examples = []
    optimizer = torch.optim.Adam(model.actor.parameters(), lr=1e-3)
    for count, actor_fraction, updates in [(16, 0.0, 3500), (8, 0.45, 2000), (8, 0.7, 2000)]:
        # Later demonstrations add reference corrections on states resulting
        # from the actor's own small errors.
        collect_examples(model, env, reference, rng, examples, count, actor_fraction)
        if not examples:
            raise RuntimeError("No reference landings were collected. Check the Godot physics configuration.")
        inputs, targets = fit_actor(model, examples, rng, optimizer, updates)

    # SAC explores around the demonstrated control rather than replacing it
    # with a random action during replay-buffer warm-up.
    with torch.no_grad():
        model.actor.log_std.weight.zero_()
        model.actor.log_std.bias.fill_(-4.0)
    return inputs, targets


def keep_reference_behavior(actor, demonstrations, seed):
    """Add an imitation gradient to SAC's actor update using a separate batch."""
    inputs, targets = demonstrations
    rng = np.random.default_rng(seed)

    def add_imitation_gradient(_optimizer, _args, _kwargs):
        indices = rng.integers(0, len(inputs), size=256)
        with torch.enable_grad():
            predicted = actor(inputs[indices], deterministic=True)
            loss = 200.0 * torch.nn.functional.mse_loss(predicted, targets[indices])
            loss.backward()

    return actor.optimizer.register_step_pre_hook(add_imitation_gradient)
