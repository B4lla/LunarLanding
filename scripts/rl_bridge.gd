extends Node3D
## F03 localhost-only, newline-delimited JSON TCP bridge. One client and one
## outstanding command. No agent, training algorithm, threads or HTTP server.
## Run via scenes/remote.tscn. Main scene's original manual controls remain intact.

const VERSION: int = 1
const DEFAULT_PORT: int = 55423
const MAX_MESSAGE_BYTES: int = 8192
const MAX_COMMAND_WAIT_TICKS: int = 120
const REWARD: RewardConfig = preload("res://config/reward.tres")

@onready var simulation: Node3D = $Simulation
@onready var rocket: RocketPhysics = simulation.get_node("Rocket")
@onready var episode: EpisodeController = simulation.get_node("EpisodeController")

var _server: TCPServer = TCPServer.new()
var _client: StreamPeerTCP = null
var _buffer: PackedByteArray = PackedByteArray()
var _port: int = DEFAULT_PORT
var _pending_id: int = -1
var _pending_command: String = ""
var _physics_ticks_remaining: int = 0
var _integrations_at_command_start: int = -1
var _reset_commits_at_command_start: int = -1
var _waited_physics_ticks: int = 0
var _command_in_flight: bool = false
var _initialized: bool = false


func _enter_tree() -> void:
    # Pause before the inherited F02 simulation or its bodies can advance.
    # The bridge itself stays active while physics and its children are paused.
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().paused = true


func _ready() -> void:
    print("F03_BOOT: scene=remote.tscn bridge=ROOT")
    process_mode = Node.PROCESS_MODE_ALWAYS
    process_priority = 1000
    # This mode never alters or receives manual/PID control input.
    simulation.set("external_control", true)
    simulation.set("use_reference_pid", false)
    # Main is PROCESS_MODE_ALWAYS for its pause key. The two physical nodes
    # must explicitly be PAUSABLE or fuel/time may advance while TCP waits.
    rocket.process_mode = Node.PROCESS_MODE_PAUSABLE
    episode.process_mode = Node.PROCESS_MODE_PAUSABLE
    rocket.remote_step_mode = true
    episode.remote_step_mode = true
    get_tree().paused = true
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--rl-port="):
            var candidate: String = argument.trim_prefix("--rl-port=")
            if not candidate.is_valid_int():
                push_error("F03: invalid --rl-port")
                get_tree().quit(2)
                return
            _port = candidate.to_int()
    if _port < 1024 or _port > 65535:
        push_error("F03: TCP port must be 1024..65535")
        get_tree().quit(2)
        return
    var err: int = _server.listen(_port, "127.0.0.1")
    if err != OK:
        push_error("F03_LISTEN_ERROR: localhost port %d could not be opened: %s" % [_port, error_string(err)])
        get_tree().quit(2)
        return
    _initialized = true
    # F03 vs F02 must be visually unambiguous, even without a visible console.
    simulation.get_node("HUD/Panel/Margin/VBox/Title").text = "ROCKET LANDING  /  F03 TCP"
    print("ROCKET_RL_F03_READY port=%d protocol=%d" % [_port, VERSION])


func _exit_tree() -> void:
    if _client != null:
        _client.disconnect_from_host()
    _server.stop()
    get_tree().paused = false


func _process(_delta: float) -> void:
    if not _initialized:
        return
    # Main updates telemetry first (priority 0). This bridge (priority 1000)
    # replaces only the mode label, so a mistaken F5/manual run is obvious.
    var tcp_status: String = "NO CLIENT"
    if _client != null:
        tcp_status = "RUNNING" if _command_in_flight else "CONNECTED"
    simulation.get_node("HUD/Panel/Margin/VBox/Mode").text = "MODE: REMOTE TCP :%d | %s" % [_port, tcp_status]
    if _client == null and _server.is_connection_available():
        _client = _server.take_connection()
        _buffer.clear()
    if _client == null:
        return
    _client.poll()
    if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
        _disconnect()
        return
    var available: int = _client.get_available_bytes()
    if available <= 0:
        return
    if _buffer.size() + available > MAX_MESSAGE_BYTES:
        _send_error(-1, "message_too_large", "Maximum request size: 8192 bytes")
        _disconnect()
        return
    var response: Array = _client.get_data(available)
    if response[0] != OK:
        _disconnect()
        return
    _buffer.append_array(response[1])
    while true:
        var newline: int = _buffer.find(10)
        if newline < 0:
            break
        var line: PackedByteArray = _buffer.slice(0, newline)
        _buffer = _buffer.slice(newline + 1)
        if line.is_empty():
            continue
        _handle_request(line.get_string_from_utf8())
        if _client == null:
            return


func _physics_process(_delta: float) -> void:
    if not _command_in_flight:
        return
    _waited_physics_ticks += 1
    # The main thread physics tick can run before Jolt has actually integrated
    # the RigidBody. Do not report an uncommitted reset or an unexecuted step.
    if _physics_ticks_remaining > 0:
        _physics_ticks_remaining -= 1
    var integrated: bool = rocket.physics_integration_serial > _integrations_at_command_start
    var reset_committed: bool = rocket.reset_commit_serial > _reset_commits_at_command_start \
        and not rocket._reset_requested
    var ready: bool = _physics_ticks_remaining == 0 and integrated
    if _pending_command == "reset":
        ready = ready and reset_committed
    elif _pending_command == "step":
        ready = ready or (_physics_ticks_remaining == 0 and episode.is_finished())
    if ready:
        _command_in_flight = false
        # Pause before deferring the TCP reply. Deferring the pause as well can
        # admit an extra SceneTree tick (observed on Godot 4.7.2).
        get_tree().paused = true
        call_deferred("_complete_request")
    elif _waited_physics_ticks >= MAX_COMMAND_WAIT_TICKS:
        _command_in_flight = false
        get_tree().paused = true
        call_deferred("_fail_stalled_request")


func _to_wire_integer(value: Variant) -> int:
    # Godot JSON can decode a JSON integer as float; reject fractions/booleans.
    if not (value is int or value is float):
        return -1
    var number: float = float(value)
    if not is_finite(number) or number < 0.0 or number > 2147483647.0 or floorf(number) != number:
        return -1
    return int(number)


func _handle_request(raw_line: String) -> void:
    var request: Variant = JSON.parse_string(raw_line)
    if not request is Dictionary:
        _send_error(-1, "invalid_json", "Expected JSON object")
        return
    var id_value: Variant = request.get("id", null)
    var request_id: int = _to_wire_integer(id_value)
    if request_id < 0:
        _send_error(-1, "invalid_id", "id must be a nonnegative integer")
        return
    if request.get("v", null) != VERSION:
        _send_error(request_id, "version_mismatch", "Protocol version must be 1")
        return
    if _command_in_flight or _pending_command != "":
        _send_error(request_id, "busy", "Wait for the previous response")
        return
    var command: Variant = request.get("cmd", null)
    if command == "ping":
        _send({"v": VERSION, "id": request_id, "ok": true,
            "command": "ping", "physics_hz": Engine.physics_ticks_per_second,
            "observation_size": 15, "action_size": 3})
        return
    if command == "reset":
        var seed_value: Variant = request.get("seed", 12345)
        var random_value: Variant = request.get("random_start", false)
        var seed_integer: int = _to_wire_integer(seed_value)
        if seed_integer < 0 or seed_integer > 2147483647 or not (random_value is bool):
            _send_error(request_id, "invalid_reset", "seed must be 0..2147483647, random_start boolean")
            return
        episode.reset_episode(seed_integer, bool(random_value))
        if not rocket._reset_requested:
            _send_error(request_id, "reset_failed", "RigidBody reset was rejected")
            return
        # Integration of one Jolt tick is required to commit rigid-body reset.
        _begin_request(request_id, "reset", 1)
        return
    if command == "step":
        if episode.is_finished():
            _send_error(request_id, "episode_finished", "Call reset() before stepping again")
            return
        var action: Variant = request.get("action", null)
        if not (action is Array) or action.size() != 3:
            _send_error(request_id, "invalid_action", "Expected [throttle, gimbal_x, gimbal_z]")
            return
        var values: Array[float] = []
        for component in action:
            if not (component is float or component is int):
                _send_error(request_id, "invalid_action", "Action components must be numeric")
                return
            var value: float = float(component)
            if not is_finite(value):
                _send_error(request_id, "invalid_action", "NaN/Infinity forbidden")
                return
            values.append(value)
        if values[0] < 0.0 or values[0] > 1.0 or absf(values[1]) > 1.0 or absf(values[2]) > 1.0:
            _send_error(request_id, "action_out_of_range", "Ranges: [0..1, -1..1, -1..1]")
            return
        if not rocket.set_throttle(values[0]) or not rocket.set_attitude_inputs(values[1], values[2], 0.0):
            _send_error(request_id, "physics_rejected", "Invalid action rejected by RigidBody")
            return
        _begin_request(request_id, "step", 1)
        return
    _send_error(request_id, "unknown_command", "Supported commands: ping, reset, step")


func _begin_request(request_id: int, command: String, physics_ticks: int) -> void:
    _pending_id = request_id
    _pending_command = command
    _physics_ticks_remaining = physics_ticks
    _integrations_at_command_start = rocket.physics_integration_serial
    _reset_commits_at_command_start = rocket.reset_commit_serial
    _waited_physics_ticks = 0
    # A reset commits a Jolt state but is not an episode step and does not
    # consume propellant. Only step commands arm the physics force/fuel update.
    rocket.remote_step_pending = command == "step"
    _command_in_flight = true
    get_tree().paused = false


func _complete_request() -> void:
    if _pending_command == "":
        return
    get_tree().paused = true
    var command: String = _pending_command
    # Restore the exact nominal spawn snapshot after the Jolt callback. The
    # commit tick can have applied gravity even though reset is not a step().
    if command == "reset" and not rocket.finalize_remote_reset():
        var failed_id: int = _pending_id
        _pending_command = ""
        _pending_id = -1
        _send_error(failed_id, "reset_state_mismatch", "Jolt did not accept the starting state")
        return
    if command == "step":
        # An integration was confirmed by the ready barrier. In F03, count
        # exactly one simulation dt and inspect contacts AFTER that integration.
        # SceneTree callbacks while waiting are deliberately not episode ticks.
        episode.advance_remote_step(1.0 / float(Engine.physics_ticks_per_second))
    var command_id: int = _pending_id
    _pending_command = ""
    _pending_id = -1
    if _client == null:
        return
    var terminated: bool = episode.result == EpisodeController.Result.LANDED \
        or episode.result == EpisodeController.Result.CRASH \
        or episode.result == EpisodeController.Result.OUT_OF_BOUNDS
    var truncated: bool = episode.result == EpisodeController.Result.TIMEOUT
    var response: Dictionary = {
        "v": VERSION, "id": command_id, "ok": true, "command": command,
        "observation": _observation(), "info": _info(),
    }
    if command == "step":
        response["reward"] = _reward()
        response["terminated"] = terminated
        response["truncated"] = truncated
    _send(response)


func _fail_stalled_request() -> void:
    if _pending_command == "":
        return
    get_tree().paused = true
    var failed_id: int = _pending_id
    var failed_command: String = _pending_command
    _pending_command = ""
    _pending_id = -1
    rocket.remote_step_pending = false
    _send_error(failed_id, "physics_not_advanced",
        "%s: no confirmed Jolt body integration within %d ticks" % [
            failed_command, MAX_COMMAND_WAIT_TICKS])


func _observation() -> Array:
    var p: Vector3 = rocket.global_position - Vector3(0.0, rocket.physics_config.platform_top_y_m, 0.0)
    var v: Vector3 = rocket.linear_velocity
    var q: Quaternion = rocket.global_transform.basis.get_rotation_quaternion()
    var omega: Vector3 = rocket.angular_velocity
    return [p.x, p.y, p.z, v.x, v.y, v.z,
        q.w, q.x, q.y, q.z, omega.x, omega.y, omega.z,
        rocket.fuel_fraction(), 1.0 if rocket.contact_platform or rocket.contact_ground else 0.0]


func _info() -> Dictionary:
    return {
        "seed": episode.episode_seed,
        "elapsed_s": episode.elapsed_s,
        "reason": episode.end_reason,
        "result": episode.result_name(),
        "fuel_kg": rocket.fuel_kg,
        "mass_kg": rocket.mass,
        "throttle": rocket.throttle,
        "impact_vertical_speed_m_s": episode.impact_velocity.y,
        "impact_horizontal_speed_m_s": Vector2(episode.impact_velocity.x,
            episode.impact_velocity.z).length(),
        "contact_platform": rocket.contact_platform,
        "contact_ground": rocket.contact_ground,
        "physics_frame": Engine.get_physics_frames(),
        "body_integration_serial": rocket.physics_integration_serial,
        "reset_commit_serial": rocket.reset_commit_serial,
    }


func _reward() -> float:
    var v: Vector3 = rocket.linear_velocity
    var p: Vector3 = rocket.global_position
    var distance_m: float = Vector2(p.x, p.z).length()
    var result: float = REWARD.living_cost \
        - REWARD.horizontal_distance_cost * distance_m \
        - REWARD.horizontal_speed_cost * Vector2(v.x, v.z).length() \
        - REWARD.vertical_speed_cost * absf(v.y) \
        - REWARD.tilt_cost * rocket.tilt_degrees()
    match episode.result:
        EpisodeController.Result.LANDED:
            result += REWARD.landing_bonus + REWARD.center_bonus(distance_m)
        EpisodeController.Result.CRASH: result += REWARD.crash_penalty
        EpisodeController.Result.OUT_OF_BOUNDS: result += REWARD.bounds_penalty
        EpisodeController.Result.TIMEOUT: result += REWARD.timeout_penalty
    return result


func _send_error(request_id: int, code: String, message: String) -> void:
    _send({"v": VERSION, "id": request_id, "ok": false,
        "error": code, "message": message})


func _send(payload: Dictionary) -> void:
    if _client == null:
        return
    var bytes: PackedByteArray = (JSON.stringify(payload) + "\n").to_utf8_buffer()
    var status: int = _client.put_data(bytes)
    if status != OK:
        _disconnect()


func _disconnect() -> void:
    get_tree().paused = true
    rocket.remote_step_pending = false
    _pending_id = -1
    _pending_command = ""
    _command_in_flight = false
    _buffer.clear()
    if _client != null:
        _client.disconnect_from_host()
    _client = null
