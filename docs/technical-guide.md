# Lunar Landing technical guide

[Back to the README](../README.md)

## Godot and flight physics

Lunar Landing uses a 3D lunar module to explore how a reinforcement learning agent learns a continuous control task. A person can fly the same simulator with the keyboard and see what the agent is learning to control. Godot's [main scene](../scenes/main.tscn) runs interactive flight, and the [remote scene](../scenes/remote.tscn) adds a bridge for Python.

[RocketPhysics](../scripts/rocket_physics.gd) controls a rigid body in Jolt. Lunar gravity is 1.62 m/s². The main engine applies thrust that can be tilted for pitch and roll, while the manual controls also allow yaw through a separate torque. Burning fuel reduces the lander's mass. The [physics configuration](../config/lunar.tres) sets the nominal start 50 m above the pad reference height and lets randomized starts vary by up to 10 m on each horizontal axis and 12 m in altitude.

The [episode controller](../scripts/episode_controller.gd) distinguishes pad contact from impact outside the pad. A safe touchdown requires vertical and horizontal speeds at or below 2.5 and 1.2 m/s, tilt at or below 15°, and angular speed at or below 0.4 rad/s. Contact must remain stable for 0.8 seconds. A crash, leaving the flight bounds or reaching the 20-second simulated limit ends the attempt.

Thrust, orientation and fuel interact during descent. Tilting the thrust vector helps correct horizontal drift while changing how much force acts vertically. As fuel burns, the same thrust produces more acceleration. The agent has to steer toward the pad and brake before contact, while keeping the lander upright.

## Local TCP and Gymnasium

The [Godot bridge](../scripts/rl_bridge.gd) listens on `127.0.0.1:55423` by default. It exchanges one JSON message per line with the [Python client](../python/rocket_landing_env/client.py). The remote simulation pauses between requests, so each action advances one 60 Hz physics tick. Headless training can run without waiting for wall-clock time.

[RocketLandingEnv](../python/rocket_landing_env/gym_env.py) wraps that connection as a Gymnasium environment:

| Method | What it does |
| --- | --- |
| `reset(seed=...)` | Starts a new flight and returns its observation and metadata. A seed reproduces a randomized start. |
| `step(action)` | Sends throttle (`0` to `1`) and two attitude inputs (`-1` to `1`). Returns the observation, reward, termination flag, truncation flag and metadata. |

The 15 observations describe position relative to the pad, linear velocity, orientation as a quaternion, angular velocity, remaining fuel fraction and contact. Landing, crashing and going out of bounds are terminations. The time limit is a truncation.

This split lets Python choose actions and train the policy while Godot remains responsible for physics and scoring. Pausing between requests makes a headless training action cover the same amount of simulated time as an action in a visible evaluation run.

## How the agent learns

1. [Collect demonstrations](../python/user_algorithms/landing_examples.py). A scripted controller flies the lander in Godot. Successful trajectories seed the replay buffer, and the neural network first learns to imitate their controls. Later demonstrations also include corrections from states reached by the model itself.
2. [Train with SAC](../python/user_algorithms/train.py). Stable-Baselines3 updates the policy from its own flights while an imitation loss helps retain the useful corrections. The [reward settings](../config/reward.tres) penalize distance, speed and tilt. Landing adds 100 points plus up to 20 for accuracy. A crash, leaving bounds and a timeout incur penalties of 100, 50 and 20 points, respectively.
3. Evaluate and save. The trainer checks the initial policy, every 5,000 SAC steps and the end of the run on one nominal and twelve fixed randomized starts. It saves the checkpoint with the most successful landings, breaking ties by smaller mean landing distance and then higher mean reward.

The replay buffer stores transitions from earlier flights so SAC can learn from them again. The actor chooses the controls, and the critics estimate the expected return. The trainer gives the critics a short warm-up with the actor frozen before updating the actor through SAC.

### Evaluate a saved policy

Run [`evaluate_model.bat`](../evaluate_model.bat) to watch the saved model in Godot. The [evaluation script](../evaluate_model.py) loads the checkpoint and selects actions deterministically. It reports each attempt's starting position, simulated duration, reward and distance from the center for successful landings. Use `--nominal` to repeat the centered start, or `--semilla 42` to reproduce a sequence of randomized starts. With the default settings, the evaluator loads `python/user_algorithms/sac_rocket.zip` and looks for `Godot_v4.7.2-stable_win64_console.exe` in the project root.

## AI-assisted development

An AI model assisted throughout development, from exploring approaches and implementing the simulator and training pipeline to reviewing changes and documenting the result. I supervised the process, set the goals, reviewed proposals and made the decisions about what to keep. This gave me practice breaking work into steps, reviewing changes and checking their behavior as I learned how reinforcement learning models train and improve.

The development assistant and the pilot have separate roles. The assistant helped build the project. During a flight, the trained SAC policy reads the simulator's numerical observations and chooses the controls locally.

## Where the assets come from

| Asset | Source |
| --- | --- |
| Lander, terrain and scene visuals | Godot [scenes](../scenes/) and procedural visual scripts. The [generation tools](../tools/) include offline scripts for material textures and details such as the engine nozzle. |
| Engine, thruster and landing sounds | Locally synthesized audio bundled in [assets](../assets/). The [flight audio generator](../tools/generate_flight_audio.py) is one example. |
| Optional ground textures | Poly Haven's CC0 `rocks_ground_01` material. The [download script](../tools/fetch_cc0.py) retrieves the color, normal and roughness maps. |
| Optional lunar module preview | NASA's Apollo Lunar Module GLB, credited to NASA/Michael D. Carbajal by the [download script](../tools/fetch_nasa.py). The preview is separate from the physics body. |
| README GIFs | Flight recordings and camera views in [docs/media](media/). |

Run `install_assets.bat` to download the optional assets, then reopen Godot to import them. The scripts save source and checksum receipts under `assets/polyhaven/` and `assets/nasa/`. Set `ROCKET_F05_NASA_PREVIEW=1` before launching Godot to enable the NASA preview. The download scripts record the sources for attribution and reuse.
