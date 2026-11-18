"""Strict, dependency-free TCP protocol v1 client. All physics remains in Godot."""
from __future__ import annotations

import json
import math
import socket
from typing import Any, Sequence


class SimulatorUnavailable(ConnectionError):
    """Godot process not listening, disconnected or timed out."""


class ProtocolError(RuntimeError):
    """Godot rejected a command or returned an invalid packet."""


class RocketLandingClient:
    """Connect to a running scenes/remote.tscn Godot instance on loopback.

    Each `step()` requests one nominal 60 Hz physics tick. The strict
    frame-count/performance guarantee under load is deferred to F04.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 55423,
                 timeout: float = 10.0):
        if host not in ("127.0.0.1", "localhost"):
            raise ValueError("F03 allows only 127.0.0.1/localhost")
        if not 1024 <= port <= 65535:
            raise ValueError("Invalid port")
        self._socket: socket.socket | None = None
        self._next_id = 0
        self._buffer = b""
        self._timeout = timeout
        try:
            try:
                self._socket = socket.create_connection(("127.0.0.1", port), timeout=timeout)
            except OSError as exc:
                raise SimulatorUnavailable(f"No Godot TCP listener at 127.0.0.1:{port}: {exc}") from exc
            self._socket.settimeout(timeout)
            metadata = self._request("ping")
            if metadata.get("physics_hz") != 60 or metadata.get("observation_size") != 15 \
                    or metadata.get("action_size") != 3:
                raise ProtocolError(f"Unexpected simulator contract: {metadata}")
        except Exception:
            self.close()
            raise

    def _request(self, cmd: str, **kwargs: Any) -> dict[str, Any]:
        if self._socket is None:
            raise SimulatorUnavailable("Client is closed")
        request_id = self._next_id
        self._next_id += 1
        raw = json.dumps({"v": 1, "id": request_id, "cmd": cmd, **kwargs},
                         allow_nan=False, separators=(",", ":")).encode("utf-8") + b"\n"
        if len(raw) > 8192:
            raise ValueError("Request exceeds protocol limit")
        try:
            self._socket.sendall(raw)
            while b"\n" not in self._buffer:
                chunk = self._socket.recv(4096)
                if not chunk:
                    raise SimulatorUnavailable("Godot closed the connection")
                self._buffer += chunk
                if len(self._buffer) > 65536:
                    raise ProtocolError("Godot response is too large")
            line, self._buffer = self._buffer.split(b"\n", 1)
        except (TimeoutError, OSError) as exc:
            raise SimulatorUnavailable(f"TCP connection to Godot failed: {exc}") from exc
        try:
            payload = json.loads(line)
        except (UnicodeDecodeError, ValueError) as exc:
            raise ProtocolError("Godot returned invalid JSON") from exc
        if (not isinstance(payload, dict) or payload.get("v") != 1
                or type(payload.get("id")) not in (int, float)
                or not math.isfinite(payload["id"]) or payload["id"] != request_id):
            raise ProtocolError("Protocol version/request identifier mismatch")
        if payload.get("ok") is not True:
            raise ProtocolError(f"{payload.get('error', 'unknown')}: {payload.get('message', '')}")
        return payload

    def reset(self, *, seed: int = 12345, random_start: bool = False
              ) -> tuple[list[float], dict[str, Any]]:
        if type(seed) is not int or not 0 <= seed <= 2147483647:
            raise ValueError("seed must be an integer from 0 through 2147483647")
        if type(random_start) is not bool:
            raise ValueError("random_start must be a boolean")
        result = self._request("reset", seed=seed, random_start=random_start)
        return self._read_state(result)

    def step(self, action: Sequence[float]
             ) -> tuple[list[float], float, bool, bool, dict[str, Any]]:
        try:
            values = list(action)
        except (TypeError, ValueError) as exc:
            raise ValueError("action must be three numbers") from exc
        if len(values) != 3 or any(type(v) not in (float, int) for v in values):
            raise ValueError("action must be [throttle, gimbal_x, gimbal_z]")
        if not all(math.isfinite(v) for v in values):
            raise ValueError("NaN/Infinity actions are forbidden")
        if not (0 <= values[0] <= 1 and -1 <= values[1] <= 1 and -1 <= values[2] <= 1):
            raise ValueError("action out of bounds: [0..1, -1..1, -1..1]")
        result = self._request("step", action=values)
        observation, info = self._read_state(result)
        reward = result.get("reward")
        if type(reward) not in (int, float) or not math.isfinite(reward):
            raise ProtocolError("Invalid reward")
        if type(result.get("terminated")) is not bool or type(result.get("truncated")) is not bool:
            raise ProtocolError("Missing termination flags")
        return observation, float(reward), result["terminated"], result["truncated"], info

    @staticmethod
    def _read_state(packet: dict[str, Any]) -> tuple[list[float], dict[str, Any]]:
        observation = packet.get("observation")
        info = packet.get("info")
        if (not isinstance(observation, list) or len(observation) != 15
                or any(type(v) not in (float, int) or not math.isfinite(v) for v in observation)
                or not isinstance(info, dict)):
            raise ProtocolError("Invalid observation/info shape or nonfinite data")
        return [float(n) for n in observation], dict(info)

    def close(self) -> None:
        if self._socket is not None:
            try:
                self._socket.close()
            finally:
                self._socket = None

    def __enter__(self) -> "RocketLandingClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
