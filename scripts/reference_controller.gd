class_name ReferenceController
extends RefCounted
## Isolated vertical-only PID for validating controllability; NOT an RL agent.
## For non-upright / off-center starts this is deliberately not a landing solution.

const CONFIG: PhysicsConfig = preload("res://config/lunar.tres")
var _integral: float = 0.0
var _previous_error: float = 0.0
var _have_previous: bool = false


func reset() -> void:
    _integral = 0.0
    _previous_error = 0.0
    _have_previous = false


func calculate_throttle(rocket: RocketPhysics, dt: float) -> float:
    if dt <= 0.0 or not is_finite(dt):
        return 0.0
    var altitude: float = maxf(0.0, rocket.collider_clearance_m())
    var desired_velocity: float = -clampf(altitude * 0.12, 0.65, 5.0)
    var error: float = desired_velocity - rocket.linear_velocity.y
    var derivative: float = (error - _previous_error) / dt if _have_previous else 0.0
    _previous_error = error
    _have_previous = true
    _integral = clampf(_integral + error * dt, -4.0, 4.0)
    var requested_acceleration: float = CONFIG.lunar_gravity_m_s2 \
        + 0.9 * error + 0.08 * _integral + 0.06 * derivative
    return clampf(rocket.mass * requested_acceleration / CONFIG.max_thrust_newtons, 0.0, 1.0)
