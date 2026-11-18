extends RefCounted
## F31: deterministic, render-only ray-versus-ground approximation.
## The actual terrain and landing collider remain unchanged. We only read the
## existing physical deck height and ground plane, no physics-space queries.

const PAD_HALF_SIZE: float = 5.92
const PAD_TOP_Y: float = 0.30
const REGOLITH_Y: float = 0.0
const MAX_VISUAL_REACH: float = 13.0


static func solve(nozzle: Vector3, direction: Vector3) -> Dictionary:
    var down: Vector3 = direction.normalized()
    if down.y >= -0.22 or nozzle.y <= REGOLITH_Y:
        return {}
    # If the nozzle dips below the solid physical deck, its visible exhaust
    # must collapse rather than falsely appearing as regolith smoke below it.
    if nozzle.y <= PAD_TOP_Y and absf(nozzle.x) < PAD_HALF_SIZE and absf(nozzle.z) < PAD_HALF_SIZE:
        return {"point": Vector3(nozzle.x, PAD_TOP_Y, nozzle.z),
            "distance": 0.025, "deck": true, "proximity": 1.0}
    # Select the actual top surface using the projected intersection, not the
    # rocket center; tilted rockets may impact outside the pad footprint.
    var to_deck: float = (nozzle.y - PAD_TOP_Y) / -down.y
    if to_deck > 0.02:
        var deck_point: Vector3 = nozzle + down * to_deck
        if absf(deck_point.x) < PAD_HALF_SIZE and absf(deck_point.z) < PAD_HALF_SIZE:
            if to_deck <= MAX_VISUAL_REACH:
                return {"point": deck_point, "distance": to_deck, "deck": true,
                    "proximity": 1.0 - smoothstep(1.15, 11.0, to_deck)}
            return {}
    var to_ground: float = (nozzle.y - REGOLITH_Y) / -down.y
    if to_ground <= 0.02 or to_ground > MAX_VISUAL_REACH:
        return {}
    var ground_point: Vector3 = nozzle + down * to_ground
    if absf(ground_point.x) > 77.0 or absf(ground_point.z) > 77.0:
        return {}
    # Don't place fake regolith beneath the solid metal deck if an oblique ray
    # bypassed the top-plane test but later crosses under its footprint.
    if absf(ground_point.x) < PAD_HALF_SIZE and absf(ground_point.z) < PAD_HALF_SIZE:
        return {}
    return {"point": ground_point, "distance": to_ground, "deck": false,
        "proximity": 1.0 - smoothstep(1.15, 11.0, to_ground)}
