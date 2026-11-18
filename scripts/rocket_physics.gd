class_name RocketPhysics
extends RigidBody3D
## F02: real six-degree-of-freedom RigidBody with gimbal and yaw RCS.
## No position animation, no agent, and no artificial altitude clamps.

@export var physics_config: PhysicsConfig

var throttle: float = 0.0
var gimbal_x: float = 0.0 # normalized [-1, +1]
var gimbal_z: float = 0.0 # normalized [-1, +1]
var yaw_rcs: float = 0.0 # normalized [-1, +1]
var fuel_kg: float = 0.0
var controls_enabled: bool = true
var contact_platform: bool = false
var contact_ground: bool = false
var initial_contact_velocity: Vector3 = Vector3.ZERO
var initial_contact_angular_velocity: Vector3 = Vector3.ZERO
var _had_contact: bool = false
var _previous_velocity: Vector3 = Vector3.ZERO
var _previous_angular_velocity: Vector3 = Vector3.ZERO
var _reset_requested: bool = true
# Increments only when Jolt calls _integrate_forces on this rigid body.
var physics_integration_serial: int = 0
var reset_commit_serial: int = 0
var _start_pose: Transform3D = Transform3D.IDENTITY
var _start_velocity: Vector3 = Vector3.ZERO
var _start_angular_velocity: Vector3 = Vector3.ZERO
# F03 only: the TCP bridge arms one force/fuel application per action. Godot
# can invoke _physics_process more than once while waiting for the Jolt body
# integration callback. Additional callbacks must not double-spend fuel or
# submit the same thrust twice. F01/F02 manual mode is unchanged.
var remote_step_mode: bool = false
var remote_step_pending: bool = false


func _ready() -> void:
    if physics_config == null or not physics_config.validate():
        push_error("F02: missing or invalid physics config")
        set_physics_process(false)
        return
    mass = physics_config.mass_kg
    fuel_kg = physics_config.initial_fuel_kg
    gravity_scale = 1.0
    linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
    angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
    linear_damp = 0.0
    angular_damp = 0.0
    can_sleep = false
    contact_monitor = true
    max_contacts_reported = 16
    configure_start(Transform3D(Basis.IDENTITY, Vector3(0.0,
        physics_config.platform_top_y_m + physics_config.initial_center_altitude_m, 0.0)),
        Vector3(0.0, physics_config.initial_vertical_velocity_m_s, 0.0), Vector3.ZERO)
    request_reset()


func set_throttle(value: float) -> bool:
    if not is_finite(value):
        push_warning("Rejected non-finite throttle")
        return false
    throttle = clampf(value, 0.0, 1.0) if fuel_kg > 0.0 else 0.0
    return true


func set_attitude_inputs(x: float, z: float, yaw: float) -> bool:
    if not is_finite(x) or not is_finite(z) or not is_finite(yaw):
        push_warning("Rejected non-finite orientation input")
        return false
    gimbal_x = clampf(x, -1.0, 1.0)
    gimbal_z = clampf(z, -1.0, 1.0)
    yaw_rcs = clampf(yaw, -1.0, 1.0)
    return true


func configure_start(pose: Transform3D, velocity: Vector3,
        angular_velocity_at_start: Vector3) -> bool:
    if not pose.is_finite() or not velocity.is_finite() or not angular_velocity_at_start.is_finite():
        push_warning("Rejected invalid reset pose/velocity")
        return false
    _start_pose = pose
    _start_velocity = velocity
    _start_angular_velocity = angular_velocity_at_start
    return true


func request_reset() -> void:
    remote_step_pending = false
    set_throttle(0.0)
    set_attitude_inputs(0.0, 0.0, 0.0)
    fuel_kg = physics_config.initial_fuel_kg
    mass = physics_config.mass_kg
    controls_enabled = true
    contact_platform = false
    contact_ground = false
    _had_contact = false
    initial_contact_velocity = Vector3.ZERO
    initial_contact_angular_velocity = Vector3.ZERO
    _previous_velocity = _start_velocity
    _previous_angular_velocity = _start_angular_velocity
    _reset_requested = true
    freeze = false
    sleeping = false


func _physics_process(delta: float) -> void:
    if physics_config == null or _reset_requested or not controls_enabled:
        return
    if remote_step_mode:
        if not remote_step_pending:
            return
        # An accepted TCP step authorizes exactly one application. The bridge
        # still waits for a separate, actual Jolt integration before replying.
        remote_step_pending = false
    # Throttle burns fuel. Scale the last tick to remaining fuel (no negative fuel).
    var effective_throttle: float = throttle
    if fuel_kg <= 0.0:
        effective_throttle = 0.0
    elif effective_throttle > 0.0:
        var demanded_kg: float = physics_config.fuel_flow_at_full_kg_s * effective_throttle * delta
        if demanded_kg > fuel_kg:
            effective_throttle *= fuel_kg / demanded_kg
            fuel_kg = 0.0
        else:
            fuel_kg -= demanded_kg
        mass = physics_config.dry_mass_kg + fuel_kg

    if effective_throttle > 0.0:
        var local_direction: Vector3 = (
            Basis(Vector3.RIGHT, deg_to_rad(gimbal_x * physics_config.max_gimbal_deg))
            * Basis(Vector3.BACK, deg_to_rad(gimbal_z * physics_config.max_gimbal_deg))
            * Vector3.UP
        ).normalized()
        var thrust_world: Vector3 = global_transform.basis * local_direction \
            * (physics_config.max_thrust_newtons * effective_throttle)
        var arm_world: Vector3 = global_transform.basis \
            * Vector3(0.0, physics_config.engine_mount_y_m, 0.0)
        # Equivalent wrench of the nozzle force at its physical offset.
        # Explicit cross product avoids offset semantics ambiguity between backends.
        apply_central_force(thrust_world)
        apply_torque(arm_world.cross(thrust_world))
    if yaw_rcs != 0.0:
        apply_torque(global_transform.basis.y * (yaw_rcs * physics_config.max_yaw_rcs_torque_nm))
    if fuel_kg <= 0.0:
        throttle = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    physics_integration_serial += 1
    if _reset_requested:
        state.transform = _start_pose
        state.linear_velocity = _start_velocity
        state.angular_velocity = _start_angular_velocity
        state.sleeping = false
        _reset_requested = false
        reset_commit_serial += 1
        return

    # Real contacts from Jolt, not inferred from center altitude.
    var on_platform: bool = false
    var on_ground: bool = false
    for i in range(state.get_contact_count()):
        var collider: Object = state.get_contact_collider_object(i)
        if collider is Node3D:
            if collider.is_in_group("landing_platform"):
                on_platform = true
            elif collider.is_in_group("lunar_ground"):
                on_ground = true
    contact_platform = on_platform
    contact_ground = on_ground
    var touching: bool = on_platform or on_ground
    if touching and not _had_contact:
        # A previous pre-solver tick is retained: post-solver velocity can understate impact.
        initial_contact_velocity = _previous_velocity
        initial_contact_angular_velocity = _previous_angular_velocity
    _had_contact = touching
    if not touching:
        _previous_velocity = state.linear_velocity
        _previous_angular_velocity = state.angular_velocity


func finalize_remote_reset() -> bool:
    # Invoked only after the real _integrate_forces reset has been acknowledged
    # and while SceneTree is paused. Set the exact initial conditions again
    # because the tick that commits the Jolt reset may also advance gravity
    # and position. This is a sporadic reset, never per-frame movement.
    if _reset_requested or reset_commit_serial <= 0:
        return false
    global_transform = _start_pose
    linear_velocity = _start_velocity
    angular_velocity = _start_angular_velocity
    sleeping = false
    return (global_transform.origin.distance_to(_start_pose.origin) < 0.0001
        and linear_velocity.distance_to(_start_velocity) < 0.0001
        and angular_velocity.distance_to(_start_angular_velocity) < 0.0001)


func tilt_degrees() -> float:
    var cos_tilt: float = clampf(global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)
    return rad_to_deg(acos(cos_tilt))


func center_altitude_m() -> float:
    return global_position.y - physics_config.platform_top_y_m


func collider_clearance_m() -> float:
    return center_altitude_m() - physics_config.rocket_half_height_m


func fuel_fraction() -> float:
    if physics_config.initial_fuel_kg <= 0.0:
        return 0.0
    return clampf(fuel_kg / physics_config.initial_fuel_kg, 0.0, 1.0)
