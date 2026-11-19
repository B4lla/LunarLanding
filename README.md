# Rocket Landing RL Simulator

**Land a lunar module, control the flight from Python, and train a reinforcement learning agent.**

This project combines a 3D Godot simulator with a local TCP bridge and a Gymnasium-compatible environment. Fly manually or let an agent control thrust and attitude.

## How the AI learns

The goal is to teach an agent to land safely through **reinforcement learning**. Instead of following a fixed list of landing instructions, the agent interacts with the simulator, receives a numerical reward for each step, and adjusts its policy to seek a higher cumulative reward over an episode. A policy is the model that chooses an action from the current observation.

The included training script uses **Soft Actor-Critic (SAC)** from Stable-Baselines3 with an `MlpPolicy` neural network. SAC is designed for continuous actions and balances learning from experience with exploration. Gymnasium connects the agent to the simulator; Godot calculates the actual flight physics and sends the resulting state and reward back through the local TCP bridge.

Each training episode follows the same loop:

1. **Observe:** the agent receives 15 values describing position relative to the landing platform, linear velocity, orientation as a quaternion, angular velocity, remaining fuel fraction, and whether the lander is touching the platform or ground.
2. **Act:** the agent chooses three continuous values: engine throttle (`0` to `1`) and two attitude inputs (`-1` to `1`). The remote agent does not control yaw.
3. **Simulate and score:** Godot advances one physics step and calculates a reward from the resulting state. The agent uses these experiences to update its policy during training.
4. **Finish or reset:** landing, crashing, or leaving the permitted area ends the episode; reaching the time limit truncates it. The environment is then reset for another attempt.

### Rewards and penalties

The reward combines a small cost on every step with penalties for horizontal distance from the pad, horizontal and vertical speed, and tilt. These terms encourage the agent to approach the pad, reduce its speed, and remain upright. A terminal outcome adds one of the following values to that step's shaped reward:

| Outcome | Additional reward |
| --- | ---: |
| Successful landing | `+100`, plus up to `+20` for landing near the center |
| Crash | `-100` |
| Out of bounds | `-50` |
| Time limit | `-20` |

The weights are defined in `config/reward.tres` and applied in `scripts/rl_bridge.gd`. The accuracy bonus decreases linearly from 20 points at the center to zero at 6 m, using the horizontal distance once the landing is stable. Each action advances one 60 Hz physics tick.

Each run starts with landing demonstrations recorded in Godot. The neural network first learns to imitate their throttle and steering actions. SAC then collects experience from randomized starts and trains on the replay buffer. Randomized starts vary X and Z by up to 4 m and place the rocket's center 46–54 m above the pad. An imitation loss keeps the actor close to demonstrated corrections while it learns from its own flights. The saved network takes the same 15 observations and produces the same three actions when used with `SAC.load()` and `predict()`.

The trainer evaluates the initial network, every 5,000 SAC steps, and at the end of the run. Each evaluation uses deterministic actions on one nominal start and twelve fixed randomized starts. It saves the checkpoint with the most successful landings, using smaller mean landing distance and then higher mean reward to break ties.

## Requirements

- Windows for the included `.bat` files.
- Godot **4.7.2**, using Jolt Physics and GL Compatibility.
- Python **3.10 or newer**, available as `py` or `python` on PATH.
- An internet connection to install Python dependencies and, optionally, download external assets.

The Python code also runs on other systems when commands and the Godot path are adapted.

## Getting started

1. Open `project.godot` in Godot 4.7.2. Wait for the initial import to finish, then press **F5** to run the project. A fresh checkout must be imported before training.
2. Run `install_dependencies.bat` from the project root. It creates `.venv` and installs the local package, Gymnasium, NumPy, and Stable-Baselines3. Run it again to update compatible dependencies.
3. Run `train.bat`. If Godot is not on PATH and `GODOT_EXE` is not set, enter the full path to the executable without quotes when prompted. By default, training runs for 100,000 steps without opening a window.

You can double-click the batch files or run them from a terminal in the project folder. Use a terminal to read error messages if a window closes immediately.

### Training options

Pass arguments to the launcher from Command Prompt or PowerShell:

```powershell
.\train.bat --godot "C:\path\to\Godot.exe" --steps 100000
.\train.bat --steps 10000 --output python/user_algorithms/candidate.zip
.\train.bat --help
```

- `--godot`: path to the executable. Alternatively, set `GODOT_EXE` or add `godot.exe` or `godot4.exe` to PATH.
- `--steps`: positive number of SAC steps after collecting and learning from demonstrations.
- `--visual`: show the simulation; without it Godot runs headless.
- `--output`: save the model to a different path, preserving an existing model.
- `--seed`: seed for training, defaulting to `42`.
- `--port`: local Godot port, defaulting to `55423`. Use another port if it is occupied.

Headless training runs without wall-clock synchronization. Godot still advances one physics tick per action. The default model path is `python/user_algorithms/sac_rocket.zip`. A later run using the same path replaces the previous model. Generated models are excluded from Git.

To watch the saved model start from different positions, run `probar_modelo.bat --aleatorio`. The evaluator prints the starting X/Y/Z coordinates and the distance from the pad center for each successful landing.

### Manual installation

To set up the environment without the batch files, run from the project root:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e "./python[training]"
.\.venv\Scripts\python.exe python\user_algorithms\train.py --godot "C:\path\to\Godot.exe" --steps 100000
```

## Flight controls

| Action | Keys |
| --- | --- |
| Increase / decrease thrust | Up / Down arrow |
| Minimum / maximum thrust | `0` / `1` |
| Pitch | `W` / `S` |
| Roll | `A` / `D` |
| Yaw | `Q` / `E` |
| Pause / resume | `P` |
| Reset | `R` |
| Reset with randomized conditions | `N` |
| Toggle automatic controller | `T` |
| Toggle camera follow | `C` |

## Optional visual assets

The included assets are sufficient to run the simulator. To download the Poly Haven textures and NASA lunar module model, run:

```powershell
.\install_assets.bat
```

Open or restart Godot afterward to import the files. The assets and their download receipts are stored locally in `assets/polyhaven` and `assets/nasa` and are excluded from Git. The download scripts validate file formats and record hashes. Check [Poly Haven's license](https://polyhaven.com/license) and [NASA's media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/) before redistributing them.

The NASA model is an optional preview, disabled by default. After downloading and importing it, set `ROCKET_F05_NASA_PREVIEW=1` in the environment used to launch Godot. Poly Haven textures are used when available and verified.

## Python integration

`python/rocket_landing_env` contains a TCP client and `RocketLandingEnv`, the Gymnasium interface. `scenes/remote.tscn` hosts the remote bridge and is started automatically during training. The server listens only on the local machine, by default on port `55423`. Episode result and reason text is in English; integrations that matched the previous Spanish text must be updated.

To inspect training options without starting a run:

```powershell
.\.venv\Scripts\python.exe python\user_algorithms\train.py --help
```

## Project structure

```text
assets/                     Audio, materials, and visual assets
config/                     Physics and reward configuration
scenes/                     Simulator and remote bridge scenes
scripts/                    Godot logic
python/rocket_landing_env/  TCP client and Gymnasium environment
python/user_algorithms/     Training script
tools/                      Asset generators and optional downloads
```

## Troubleshooting

- **Python not found:** install Python 3.10 or newer, enable PATH access, and reopen the terminal.
- **Godot not found:** pass `--godot "C:\path\to\Godot.exe"` or set `GODOT_EXE`.
- **Missing resources or classes in a fresh checkout:** open the project in Godot and wait for import to finish before training.
- **Port already in use:** close the Godot instance or other process using local port `55423`.
- **Download failed:** check your connection and rerun the relevant batch file; external assets are optional.

`.gitignore` excludes virtual environments, caches such as `__pycache__` and `.godot`, logs, exports, trained models, and downloaded external assets.
