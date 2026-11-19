class_name RewardConfig
extends Resource
## F03 reference shaping only; not an RL policy or trained model.

@export var living_cost: float = -0.01
@export var horizontal_distance_cost: float = 0.002
@export var horizontal_speed_cost: float = 0.02
@export var vertical_speed_cost: float = 0.01
@export var tilt_cost: float = 0.0005
@export var landing_bonus: float = 100.0
@export_range(0.0, 100.0, 0.1, "or_greater") var landing_center_bonus: float = 20.0
@export_range(0.1, 20.0, 0.1, "or_greater") var landing_center_bonus_radius_m: float = 6.0
@export var crash_penalty: float = -100.0
@export var bounds_penalty: float = -50.0
@export var timeout_penalty: float = -20.0


func center_bonus(distance_m: float) -> float:
    return landing_center_bonus * maxf(0.0, 1.0 - distance_m / landing_center_bonus_radius_m)
