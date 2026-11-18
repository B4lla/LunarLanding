class_name PhysicsConfig
extends Resource
## SI units. F02 extends the existing F01 parameters without requiring RL code.

@export_range(1.0, 1000000.0, 1.0, "or_greater") var mass_kg: float = 1000.0 # wet mass at reset
@export_range(0.0, 10000000.0, 1.0, "or_greater") var max_thrust_newtons: float = 3500.0
@export_range(0.0, 100.0, 0.01) var lunar_gravity_m_s2: float = 1.62
@export_range(1.0, 1000.0, 0.1, "or_greater") var initial_center_altitude_m: float = 50.0
@export var initial_vertical_velocity_m_s: float = -5.0
@export var platform_top_y_m: float = 0.30
@export_range(0.1, 20.0, 0.1) var rocket_half_height_m: float = 1.5
@export_range(0.1, 2.0, 0.05) var throttle_change_per_second: float = 0.4

# F02. Wet mass = dry_mass_kg + initial_fuel_kg (1000 kg initially).
@export_range(1.0, 1000000.0, 1.0) var dry_mass_kg: float = 900.0
@export_range(0.0, 100000.0, 1.0) var initial_fuel_kg: float = 100.0
@export_range(0.01, 100.0, 0.01) var fuel_flow_at_full_kg_s: float = 1.43
@export_range(0.0, 25.0, 0.1) var max_gimbal_deg: float = 8.0
@export_range(0.0, 10000.0, 1.0) var max_yaw_rcs_torque_nm: float = 380.0
@export var engine_mount_y_m: float = -1.0
@export_range(0.0, 10.0, 0.1) var safe_vertical_impact_m_s: float = 2.5
@export_range(0.0, 10.0, 0.1) var safe_horizontal_impact_m_s: float = 1.2
@export_range(0.0, 45.0, 0.1) var safe_tilt_deg: float = 15.0
@export_range(0.0, 5.0, 0.01) var safe_angular_speed_rad_s: float = 0.4
@export_range(0.1, 10.0, 0.05) var stable_contact_seconds: float = 0.8
@export_range(1.0, 2000.0, 1.0) var max_episode_seconds: float = 120.0
@export_range(1.0, 1000.0, 1.0) var horizontal_world_limit_m: float = 80.0
@export_range(1.0, 1000.0, 1.0) var maximum_altitude_m: float = 200.0
@export_range(0.0, 20.0, 0.1) var spawn_spread_m: float = 4.0


func validate() -> bool:
    return mass_kg > 0.0 and is_finite(mass_kg) \
        and max_thrust_newtons >= 0.0 and is_finite(max_thrust_newtons) \
        and lunar_gravity_m_s2 >= 0.0 and is_finite(lunar_gravity_m_s2) \
        and initial_center_altitude_m > rocket_half_height_m \
        and is_finite(initial_center_altitude_m) \
        and is_finite(initial_vertical_velocity_m_s) \
        and is_finite(platform_top_y_m) \
        and rocket_half_height_m > 0.0 and is_finite(rocket_half_height_m) \
        and throttle_change_per_second > 0.0 and is_finite(throttle_change_per_second) \
        and dry_mass_kg > 0.0 and is_finite(dry_mass_kg) \
        and initial_fuel_kg >= 0.0 and is_finite(initial_fuel_kg) \
        and absf(mass_kg - (dry_mass_kg + initial_fuel_kg)) < 0.001 \
        and fuel_flow_at_full_kg_s > 0.0 and is_finite(fuel_flow_at_full_kg_s) \
        and max_gimbal_deg > 0.0 and max_gimbal_deg <= 25.0 \
        and max_yaw_rcs_torque_nm >= 0.0 and is_finite(max_yaw_rcs_torque_nm) \
        and engine_mount_y_m < 0.0 and is_finite(engine_mount_y_m) \
        and safe_vertical_impact_m_s > 0.0 and safe_horizontal_impact_m_s > 0.0 \
        and safe_tilt_deg > 0.0 and safe_angular_speed_rad_s > 0.0 \
        and stable_contact_seconds > 0.0 and max_episode_seconds > 0.0 \
        and horizontal_world_limit_m > 0.0 and maximum_altitude_m > initial_center_altitude_m \
        and spawn_spread_m >= 0.0 and is_finite(spawn_spread_m)
