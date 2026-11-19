class_name EpisodeController
extends Node
## F02 episode lifecycle; all contact flags come from the RigidBody physics state.
## No reward or Python step() interface (reserved for F03).

enum Result { FLIGHT, CONTACT, LANDED, CRASH, OUT_OF_BOUNDS, TIMEOUT }

const CONFIG: PhysicsConfig = preload("res://config/lunar.tres")
@onready var rocket: RocketPhysics = get_parent().get_node("Rocket")

var result: Result = Result.FLIGHT
var elapsed_s: float = 0.0
var contact_stable_s: float = 0.0
var episode_seed: int = 0
var impact_velocity: Vector3 = Vector3.ZERO
var impact_angular_velocity: Vector3 = Vector3.ZERO
var end_reason: String = ""
var _saw_platform: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# F03 only: step clock and terminal checks advance once on an acknowledged
# Jolt integration, not once per SceneTree callback. F02 remains unmodified.
var remote_step_mode: bool = false


func _ready() -> void:
    # Rocket _ready() already prepares the first deterministic start.
    reset_episode(12345)


func _physics_process(delta: float) -> void:
    if remote_step_mode:
        return
    _advance_episode(delta)


func advance_remote_step(delta: float) -> void:
    if not remote_step_mode:
        push_error("Remote episode tick requested outside F03")
        return
    _advance_episode(delta)


func _advance_episode(delta: float) -> void:
    if rocket._reset_requested or is_finished():
        return
    elapsed_s += delta
    var pos: Vector3 = rocket.global_position
    if absf(pos.x) > CONFIG.horizontal_world_limit_m \
            or absf(pos.z) > CONFIG.horizontal_world_limit_m \
            or rocket.center_altitude_m() > CONFIG.maximum_altitude_m \
            or rocket.center_altitude_m() < -5.0:
        _finish(Result.OUT_OF_BOUNDS, "Out of bounds")
        return
    if rocket.contact_ground:
        impact_velocity = rocket.initial_contact_velocity
        impact_angular_velocity = rocket.initial_contact_angular_velocity
        _finish(Result.CRASH, "Impact outside the landing pad")
        return
    if rocket.contact_platform:
        if not _saw_platform:
            _saw_platform = true
            impact_velocity = rocket.initial_contact_velocity
            impact_angular_velocity = rocket.initial_contact_angular_velocity
            if not _is_safe_touchdown(impact_velocity, impact_angular_velocity):
                _finish(Result.CRASH, "Excessive impact on landing pad")
                return
        result = Result.CONTACT
        if _stable_on_platform():
            contact_stable_s += delta
            if contact_stable_s >= CONFIG.stable_contact_seconds:
                _finish(Result.LANDED, "Stable landing")
                return
        else:
            contact_stable_s = 0.0
    else:
        # Require continuous actual contact for stable landing, even after bouncing.
        contact_stable_s = 0.0
        if result == Result.CONTACT:
            result = Result.FLIGHT
        _saw_platform = false
    if elapsed_s >= CONFIG.max_episode_seconds:
        _finish(Result.TIMEOUT, "Time limit reached")


func _is_safe_touchdown(v: Vector3, omega: Vector3) -> bool:
    return absf(v.y) <= CONFIG.safe_vertical_impact_m_s \
        and Vector2(v.x, v.z).length() <= CONFIG.safe_horizontal_impact_m_s \
        and rocket.tilt_degrees() <= CONFIG.safe_tilt_deg \
        and omega.length() <= CONFIG.safe_angular_speed_rad_s


func _stable_on_platform() -> bool:
    return _is_safe_touchdown(rocket.linear_velocity, rocket.angular_velocity) \
        and rocket.contact_platform and not rocket.contact_ground


func _finish(final_result: Result, reason: String) -> void:
    result = final_result
    end_reason = reason
    rocket.controls_enabled = false
    rocket.set_throttle(0.0)
    rocket.set_attitude_inputs(0.0, 0.0, 0.0)
    # Freeze the finished episode, but preserve impact metrics in EpisodeController.
    rocket.freeze = true
    rocket.linear_velocity = Vector3.ZERO
    rocket.angular_velocity = Vector3.ZERO


func is_finished() -> bool:
    return result == Result.LANDED or result == Result.CRASH \
        or result == Result.OUT_OF_BOUNDS or result == Result.TIMEOUT


func result_name() -> String:
    match result:
        Result.FLIGHT: return "IN FLIGHT"
        Result.CONTACT: return "CONTACT"
        Result.LANDED: return "SUCCESSFUL LANDING"
        Result.CRASH: return "CRASH"
        Result.OUT_OF_BOUNDS: return "OUT OF BOUNDS"
        Result.TIMEOUT: return "TIMEOUT"
    return "UNKNOWN"


func reset_episode(seed_value: int = 12345, random_start: bool = false) -> void:
    episode_seed = seed_value
    _rng.seed = seed_value
    var offset_x: float = 0.0
    var offset_y: float = 0.0
    var offset_z: float = 0.0
    var vel_x: float = 0.0
    var vel_z: float = 0.0
    var basis: Basis = Basis.IDENTITY
    var omega: Vector3 = Vector3.ZERO
    if random_start:
        offset_x = _rng.randf_range(-CONFIG.spawn_spread_m, CONFIG.spawn_spread_m)
        offset_z = _rng.randf_range(-CONFIG.spawn_spread_m, CONFIG.spawn_spread_m)
        vel_x = _rng.randf_range(-0.3, 0.3)
        vel_z = _rng.randf_range(-0.3, 0.3)
        basis = Basis.from_euler(Vector3(_rng.randf_range(-0.05, 0.05),
            _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.05, 0.05)))
        omega = Vector3(_rng.randf_range(-0.04, 0.04), 0.0, _rng.randf_range(-0.04, 0.04))
        offset_y = _rng.randf_range(-CONFIG.spawn_altitude_spread_m, CONFIG.spawn_altitude_spread_m)
    reset_with_state(Transform3D(basis, Vector3(offset_x,
        CONFIG.platform_top_y_m + CONFIG.initial_center_altitude_m + offset_y, offset_z)),
        Vector3(vel_x, CONFIG.initial_vertical_velocity_m_s, vel_z), omega)


func reset_with_state(pose: Transform3D, velocity: Vector3,
        angular_velocity_at_start: Vector3) -> bool:
    if not rocket.configure_start(pose, velocity, angular_velocity_at_start):
        return false
    elapsed_s = 0.0
    contact_stable_s = 0.0
    result = Result.FLIGHT
    end_reason = ""
    impact_velocity = Vector3.ZERO
    impact_angular_velocity = Vector3.ZERO
    _saw_platform = false
    rocket.request_reset()
    return true
