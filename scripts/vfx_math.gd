extends RefCounted
## F35 rendering-only response curves; zero randomness, forces or simulation state.
## All helpers deterministic; testable without requiring a GPU context.


static func regolith_intensity(hit: Dictionary, throttle: float) -> float:
    if hit.is_empty() or bool(hit.get("deck", false)) or not is_finite(throttle):
        return 0.0
    var near: float = clampf(float(hit.get("proximity", 0.0)), 0.0, 1.0)
    var commanded: float = clampf(throttle, 0.0, 1.0)
    return commanded * pow(near, 1.35)


static func fan_direction(index: int, count: int) -> Vector3:
    if count <= 0:
        return Vector3.RIGHT
    var angle: float = TAU * float(posmod(index, count)) / float(count)
    return Vector3(cos(angle), 0.16, sin(angle)).normalized()


static func visibility_tier(distance: float, previous: int) -> int:
    # A hysteretic three-band LOD prevents re-allocating CPU particle buffers
    # while the camera crosses the same threshold at frame frequency.
    if not is_finite(distance):
        return clampi(previous, 0, 2)
    var tier: int = clampi(previous, 0, 2)
    if tier == 0:
        return 1 if distance > 36.0 else 0
    if tier == 1:
        if distance < 30.0:
            return 0
        return 2 if distance > 85.0 else 1
    return 1 if distance < 72.0 else 2
