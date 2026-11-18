extends Camera3D
## Visual-only framing; never writes rocket state or steps physics.
## C toggles landing-context and a tight chase camera; both keep user zoom.
## F18 crop is closer at default zoom; framing still protects pad visibility.

const CONTEXT_FOV_DEG := 49.0
const FOLLOW_FOV_DEG := 45.0
const CONTEXT_DISTANCE_SCALE := 0.70
const FOLLOW_DISTANCE_SCALE := 0.70
const MAX_CONTEXT_SPAN_DEG := 85.0
const CAMERA_RESPONSE := 4.7
const MAX_PRESENTATION_HEIGHT_M := 90.0
var _initialized := false
var zoom_factor: float = 1.0

func set_zoom_factor(value: float) -> void:
	zoom_factor = clampf(value, 0.80, 1.35)


func invalidate_framing() -> void:
	_initialized = false

func update_visual_framing(delta: float, craft_position: Vector3, close_follow: bool) -> void:
	if DisplayServer.get_name() == "headless" or not current or not craft_position.is_finite():
		return
	var altitude: float = clampf(craft_position.y, 0.0, MAX_PRESENTATION_HEIGHT_M)
	var destination: Vector3
	var point_of_interest: Vector3
	if close_follow:
		destination = craft_position + Vector3(6.5, 4.0, 12.0) * FOLLOW_DISTANCE_SCALE
		point_of_interest = craft_position + Vector3(0.0, 0.25, 0.0)
		fov = FOLLOW_FOV_DEG
	else:
		# Tighter at high altitude than F05, but still shows the pad below.
		var previous_height: float = 17.0 + 0.43 * altitude
		var previous_depth: float = 22.0 + 0.67 * altitude
		destination = Vector3(craft_position.x + 7.2,
				previous_height + 0.08 * altitude - 1.0,
				craft_position.z + previous_depth * 0.64 * CONTEXT_DISTANCE_SCALE)
		point_of_interest = Vector3(craft_position.x * 0.62,
				0.60 * altitude, craft_position.z * 0.62)
		fov = CONTEXT_FOV_DEG
	# Zoom affects only the eye-to-focus offset. Keep the landing target unchanged.
	destination = point_of_interest + (destination - point_of_interest) / zoom_factor
	if not close_follow:
		destination = _fit_two_targets(destination, point_of_interest, craft_position)
	if not _initialized:
		global_position = destination
		_initialized = true
	else:
		var weight: float = 1.0 - exp(-CAMERA_RESPONSE * maxf(delta, 0.0))
		global_position = global_position.lerp(destination, weight)
	if close_follow:
		look_at(point_of_interest, Vector3.UP)
	else:
		# Two-point composition: midpoint in viewing angles (not world space),
		# so the craft and landing pad remain inside the viewport at altitude.
		# Automatically opens the vertical FOV when a close zoom cannot contain
		# both points. The context mode does not hide one to magnify the other.
		var craft_target: Vector3 = craft_position + Vector3(0.0, 1.25, 0.0)
		var pad_target: Vector3 = Vector3(0.0, 0.32, 0.0)
		var craft_ray: Vector3 = (craft_target - global_position).normalized()
		var pad_ray: Vector3 = (pad_target - global_position).normalized()
		var aim: Vector3 = (craft_ray + pad_ray).normalized()
		if aim.length_squared() < 0.01:
			aim = (point_of_interest - global_position).normalized()
		look_at(global_position + aim, Vector3.UP)
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.75)
		var required_half_fov: float = 0.0
		for ray in [craft_ray, pad_ray]:
			var depth: float = maxf(ray.dot(-global_transform.basis.z), 0.01)
			var vertical_angle: float = absf(atan2(ray.dot(global_transform.basis.y), depth))
			var horizontal_angle: float = absf(atan2(ray.dot(global_transform.basis.x), depth))
			required_half_fov = maxf(required_half_fov, vertical_angle)
			required_half_fov = maxf(required_half_fov, atan(tan(horizontal_angle) / aspect))
		fov = clampf(2.0 * rad_to_deg(required_half_fov) + 11.0, CONTEXT_FOV_DEG, 105.0)


func _fit_two_targets(wanted: Vector3, focal_point: Vector3, craft_position: Vector3) -> Vector3:
	# Dolly out only when the requested closer camera would lose the landing pad.
	# This is especially important with user PageUp zoom at high altitude.
	var craft_target: Vector3 = craft_position + Vector3(0.0, 1.25, 0.0)
	var pad_target := Vector3(0.0, 0.32, 0.0)
	for _attempt in range(10):
		var to_craft: Vector3 = (craft_target - wanted).normalized()
		var to_pad: Vector3 = (pad_target - wanted).normalized()
		var angular_span: float = rad_to_deg(acos(clampf(to_craft.dot(to_pad), -1.0, 1.0)))
		if angular_span <= MAX_CONTEXT_SPAN_DEG:
			break
		wanted = focal_point + (wanted - focal_point) * 1.15
	return wanted
