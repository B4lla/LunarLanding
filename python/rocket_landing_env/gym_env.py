"""Optional Gymnasium-compatible environment. No trainer or RL policy."""
from __future__ import annotations

import os
import socket
from pathlib import Path
import subprocess
import tempfile
import time
from typing import Any

try:
    import gymnasium as gym
    from gymnasium import spaces
    import numpy as np
except ImportError as exc:
    raise ImportError('Install optional environment dependencies: pip install -e "./python[gymnasium]"') from exc

from .client import RocketLandingClient, SimulatorUnavailable


class RocketLandingEnv(gym.Env):
    """Gymnasium Env wrapper, with optional Godot process lifecycle management.

    Launch Godot with a remote scene but do not pass an external trainer path.
    Uses real physics and pauses Godot between requests. No accelerated mode.
    """

    metadata = {"render_modes": ["human"], "render_fps": 60}

    # These are process-wide debugging counters from the Godot/Jolt bridge.
    # They cannot be reproduced by seeding an *episode*, so exposing them in
    # Gymnasium info makes check_step_determinism fail despite a deterministic
    # observation/reward. Keep them intact in RocketLandingClient's TCP info.
    _PROCESS_DIAGNOSTIC_INFO_KEYS = frozenset({
        "physics_frame", "body_integration_serial", "reset_commit_serial",
    })

    @classmethod
    def _episode_info(cls, wire_info: dict[str, Any]) -> dict[str, Any]:
        """Return an independent Gymnasium info dict with episode data only.

        Do not alter tolerance, physical quantities or termination diagnostics;
        the low-level client is deliberately unfiltered for engine debugging.
        """
        return {key: value for key, value in wire_info.items()
                if key not in cls._PROCESS_DIAGNOSTIC_INFO_KEYS}

    def __init__(self, *, godot_executable: str | None = None,
                 project_path: str | os.PathLike[str] | None = None,
                 headless: bool = False, host: str = "127.0.0.1",
                 port: int = 55423, timeout: float = 10.0,
                 random_start: bool = False):
        super().__init__()
        # Validate before spawning anything; a busy port must not allow an
        # accidentally owned adapter to connect to an unrelated old Godot.
        if host not in ('127.0.0.1', 'localhost'):
            raise ValueError('Only localhost is supported')
        if type(port) is not int or not 1024 <= port <= 65535:
            raise ValueError('port must be an integer in 1024..65535')
        if not isinstance(timeout, (int, float)) or not 0 < timeout <= 300:
            raise ValueError('timeout must be in (0, 300] seconds')
        if type(random_start) is not bool or type(headless) is not bool:
            raise ValueError('random_start and headless must be booleans')
        self.render_mode = None if headless else "human"
        self._random_start = random_start
        self._needs_reset = True
        self._process: subprocess.Popen[bytes] | None = None
        self._log = None
        self._log_path: str | None = None
        self._client: RocketLandingClient | None = None
        self.action_space = spaces.Box(
            low=np.array([0.0, -1.0, -1.0], dtype=np.float32),
            high=np.array([1.0, 1.0, 1.0], dtype=np.float32), dtype=np.float32)
        self.observation_space = spaces.Box(
            low=np.array([-np.inf] * 13 + [0.0, 0.0], dtype=np.float32),
            high=np.array([np.inf] * 13 + [1.0, 1.0], dtype=np.float32),
            dtype=np.float32)
        if godot_executable is not None:
            executable = Path(godot_executable).expanduser().resolve()
            if not executable.is_file():
                raise FileNotFoundError(f'Godot executable must be a file: {executable}')
            # bind(), unlike connect(), does not briefly take the single
            # client slot of an already-running remote.tscn bridge.
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                try:
                    probe.bind(('127.0.0.1', port))
                except OSError as exc:
                    raise SimulatorUnavailable(f'Port {port} is already in use; cannot own Godot process') from exc
            if project_path is None:
                raise ValueError("project_path is required when starting Godot")
            project = Path(project_path).resolve()
            if not (project / "project.godot").is_file():
                raise FileNotFoundError(f"No project.godot in {project}")
            logfile = tempfile.NamedTemporaryFile(prefix="rocket-rl-f03-", suffix=".log", delete=False)
            self._log = logfile
            self._log_path = logfile.name
            args = [str(executable)]
            if headless:
                args.append("--headless")
            args += ["--path", str(project), "res://scenes/remote.tscn", "--", f"--rl-port={port}"]
            try:
                self._process = subprocess.Popen(args, stdout=logfile, stderr=subprocess.STDOUT)
            except Exception:
                self.close()
                raise
        try:
            deadline = time.monotonic() + timeout
            while True:
                try:
                    self._client = RocketLandingClient(host=host, port=port,
                                                       timeout=max(0.3, min(3.0, timeout)))
                    if self._process is not None and self._process.poll() is not None:
                        raise SimulatorUnavailable(
                            f'Owned Godot exited before successful connection. Log: {self._log_path}')
                    break
                except (ConnectionError, TimeoutError, OSError) as exc:
                    if self._process is None:
                        raise SimulatorUnavailable(f"No Godot listener at {host}:{port}; start scenes/remote.tscn") from exc
                    if self._process.poll() is not None or time.monotonic() >= deadline:
                        raise SimulatorUnavailable(
                            f"Godot failed to start F03 bridge. See log: {self._log_path}") from exc
                    time.sleep(0.1)
        except Exception:
            self.close()
            raise

    def reset(self, *, seed: int | None = None,
              options: dict[str, Any] | None = None) -> tuple[np.ndarray, dict[str, Any]]:
        super().reset(seed=seed)
        if options is not None and set(options) - {"random_start"}:
            raise ValueError("Only reset option 'random_start' is supported")
        random_start = self._random_start if options is None else options.get("random_start", self._random_start)
        if type(random_start) is not bool:
            raise ValueError("random_start must be boolean")
        if seed is None:
            seed = int(self.np_random.integers(0, 2**31 - 1))
        assert self._client is not None
        obs, info = self._client.reset(seed=seed, random_start=random_start)
        self._needs_reset = False
        return np.asarray(obs, dtype=np.float32), self._episode_info(info)

    def step(self, action: np.ndarray) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        if self._needs_reset:
            raise RuntimeError("Call reset() before step() or after episode termination")
        assert self._client is not None
        obs, reward, terminated, truncated, info = self._client.step([float(x) for x in action])
        self._needs_reset = terminated or truncated
        return np.asarray(obs, dtype=np.float32), reward, terminated, truncated, self._episode_info(info)

    def render(self) -> None:
        # Godot renders its own native window when headless=False.
        return None

    def close(self) -> None:
        if self._client is not None:
            self._client.close()
            self._client = None
        if self._process is not None:
            if self._process.poll() is None:
                self._process.terminate()
                try:
                    self._process.wait(timeout=4.0)
                except subprocess.TimeoutExpired:
                    self._process.kill()
                    self._process.wait(timeout=4.0)
            self._process = None
        if self._log is not None:
            self._log.close()
            self._log = None
        super().close()
