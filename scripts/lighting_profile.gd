extends Node3D
## F36 — localized, directed service illumination plus opt-in render measurements.
## Visual-only: no gameplay/physics nodes or control-policy writes.
## F31 lights remain in the scene for previous probes, but no longer emit
## physically implausible omnidirectional light from invisible sources.

const MAST_POSITIONS: Array[Vector3] = [
    Vector3(-29.0, 3.60, -25.0), Vector3(29.0, 3.60, 25.0),
    Vector3(25.0, 3.60, -29.0), Vector3(-25.0, 3.60, 29.0),
]
const PROFILE_BALANCED: String = "balanced"
const PROFILE_LOW: String = "low"
const WARMUP_FRAMES: int = 30
const RECORD_PERIOD: int = 2
const MAX_SAMPLES: int = 180

var spotlights: Array[SpotLight3D] = []
var quality_profile: String = PROFILE_BALANCED
var _f31: Node3D
var _fx: Node3D
var _frames: int = 0
var _recording: bool = false
var _write_path: String = ""
var _written: bool = false
var _frame_ms: Array[float] = []
var _draw_calls: Array[float] = []
var _render_objects: Array[float] = []
var _fps: Array[float] = []
var _fixture_check_elapsed: float = 0.0
var _last_spotlight_reduced: bool = false
var _last_spotlight_budget_known: bool = false
var _low_fps_frames: int = 0
var _recovery_frames: int = 0
var _adaptive_reduction: bool = false



func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        set_process(false)
        return
    _f31 = get_node_or_null("../F31LightingGroundResponse") as Node3D
    _fx = get_node_or_null("../VisualFX") as Node3D
    quality_profile = PROFILE_LOW if OS.get_environment("ROCKET_F36_QUALITY").to_lower() == "low" else PROFILE_BALANCED
    _write_path = OS.get_environment("ROCKET_F36_PROFILE_PATH")
    _recording = not _write_path.is_empty() or not OS.get_environment("F36_PROBE_PATH").is_empty()
    _disable_legacy_local_lights()
    _create_directed_fixture_lights()
    _tune_static_reflections()
    _apply_sun_shadow_bias()
    _update_spotlight_budget()
    set_process(true)


func _disable_legacy_local_lights() -> void:
    if _f31 == null:
        return
    # Existing F31 nodes are kept for historical F31 scene inspections.
    for fixture in _f31.get_children():
        if fixture is OmniLight3D and (
                fixture.name.begins_with("SpaceportAreaLight_") or
                fixture.name.begins_with("UtilityFloodlight_")):
            (fixture as OmniLight3D).light_energy = 0.0
            fixture.visible = false


func _create_directed_fixture_lights() -> void:
    # Each new spotlight originates at one real F30 floodlight mast, and points
    # towards the nearby utility yard. The landing slab stays sunlit: there are
    # no fictitious floodlights hovering above the touchdown zone.
    for index in range(MAST_POSITIONS.size()):
        var head: Vector3 = MAST_POSITIONS[index]
        var horizontal: Vector3 = Vector3(-head.x, 0.0, -head.z).normalized()
        var aim: Vector3 = head + horizontal * 5.0 + Vector3(0.0, -3.45, 0.0)
        var light: SpotLight3D = SpotLight3D.new()
        light.name = "F36PhysicalMastSpot_%02d" % index
        light.position = head
        light.spot_range = 14.5
        light.spot_angle = 51.0
        light.spot_attenuation = 1.25
        light.light_color = Color(0.70, 0.84, 1.0)
        light.light_energy = 0.92
        light.light_specular = 0.48
        light.shadow_enabled = false
        add_child(light)
        light.look_at_from_position(head, aim, Vector3.UP)
        spotlights.append(light)


func _tune_static_reflections() -> void:
    if _f31 == null:
        return
    var probe: ReflectionProbe = _f31.get_node_or_null("SpaceportStaticReflectionProbe") as ReflectionProbe
    if probe == null:
        return
    probe.update_mode = ReflectionProbe.UPDATE_ONCE
    probe.enable_shadows = false
    probe.intensity = 0.42
    probe.max_distance = 28.0
    probe.box_projection = false
    # Keep the probe stationary: never update its cubemap every frame.


func _apply_sun_shadow_bias() -> void:
    var sun: DirectionalLight3D = get_node_or_null("../Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = true
        sun.shadow_bias = 0.055
        sun.shadow_normal_bias = 0.65


func _process(delta: float) -> void:
    # State/budget checks are 4 Hz, not 60/120 Hz. Never change engine
    # lighting or FX during opt-in F36 A/B evidence collection.
    _fixture_check_elapsed += maxf(delta, 0.0)
    if _fixture_check_elapsed >= 0.25:
        _fixture_check_elapsed = fmod(_fixture_check_elapsed, 0.25)
        _update_spotlight_budget()
    if not _recording:
        _adaptive_fx_quality(delta)
        return
    _frames += 1
    if _frames > WARMUP_FRAMES and _frames % RECORD_PERIOD == 0 and _frame_ms.size() < MAX_SAMPLES:
        if delta > 0.0 and delta < 1.0:
            _frame_ms.append(delta * 1000.0)
            _fps.append(float(Performance.get_monitor(Performance.TIME_FPS)))
            _draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
            _render_objects.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
    if not _written and not _write_path.is_empty() and _frames >= 250:
        _written = true
        var file: FileAccess = FileAccess.open(_write_path, FileAccess.WRITE)
        if file == null:
            push_error("F36: profiling output path cannot be opened: " + _write_path)
        else:
            file.store_string(JSON.stringify(get_metrics_receipt(), "  "))
            file.close()
            print("F36 render profile: " + _write_path)


func _update_spotlight_budget() -> void:
    var reduced: bool = _fx != null and bool(_fx.get("reduced_particles"))
    var budget_reduced: bool = quality_profile == PROFILE_LOW or reduced
    if _last_spotlight_budget_known and budget_reduced == _last_spotlight_reduced:
        return
    _last_spotlight_budget_known = true
    _last_spotlight_reduced = budget_reduced
    for index in range(spotlights.size()):
        # Two fewer overlapping lights when the camera is far or the optional
        # low profile is active. No runtime spawning or deleting GPU resources.
        var enable: bool = (index % 2 == 0) if quality_profile == PROFILE_LOW or reduced else true
        spotlights[index].visible = enable


func _adaptive_fx_quality(delta: float) -> void:
    # Only sustained drops trigger a reduction, never a single shader warmup
    # stall. A long stable period recovers full VFX with hysteresis.
    if _fx == null or delta <= 0.0 or delta > 0.25:
        return
    if quality_profile == PROFILE_LOW:
        return
    var user_settings: Node = get_node_or_null("../PresentationSettings")
    var user_reduced: bool = user_settings != null and bool(user_settings.get("reduced_fx"))
    if user_reduced:
        _adaptive_reduction = false
        _low_fps_frames = 0
        _recovery_frames = 0
        return
    if not _adaptive_reduction:
        _low_fps_frames = _low_fps_frames + 1 if delta > 0.029 else maxi(0, _low_fps_frames - 2)
        if _low_fps_frames >= 50:
            _adaptive_reduction = true
            _recovery_frames = 0
            _fx.call("set_quality_profile", true)
            print("F37: sustained frame-time pressure; temporary lower-cost VFX enabled")
    else:
        _recovery_frames = _recovery_frames + 1 if delta < 0.021 else maxi(0, _recovery_frames - 2)
        if _recovery_frames >= 500:
            _adaptive_reduction = false
            _low_fps_frames = 0
            _fx.call("set_quality_profile", false)
            print("F37: recovered frame-time; full VFX restored")


func _percentile(values: Array[float], quantile: float) -> float:
    if values.is_empty():
        return 0.0
    var sorted_values: Array[float] = values.duplicate()
    sorted_values.sort()
    var idx: int = clampi(ceili(float(sorted_values.size()) * quantile) - 1, 0, sorted_values.size() - 1)
    return snappedf(sorted_values[idx], 0.001)


func get_metrics_receipt() -> Dictionary:
    # These are OBSERVED engine samples, not a GPU benchmark or target FPS.
    return {
        "phase": "F36", "driver": DisplayServer.get_name(),
        "renderer": RenderingServer.get_current_rendering_method(),
        "quality_profile": quality_profile,
        "resolution": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
        "warmup_frames": WARMUP_FRAMES, "sample_interval_frames": RECORD_PERIOD,
        "sample_count": _frame_ms.size(),
        "frame_ms_p50": _percentile(_frame_ms, 0.50),
        "frame_ms_p95": _percentile(_frame_ms, 0.95),
        "frame_ms_p99": _percentile(_frame_ms, 0.99),
        "draw_calls_p50": _percentile(_draw_calls, 0.50),
        "draw_calls_p95": _percentile(_draw_calls, 0.95),
        "render_objects_p95": _percentile(_render_objects, 0.95),
        "reported_fps_p50": _percentile(_fps, 0.50),
        "note": "Frame delta includes CPU scheduling/presentation. No isolated GPU time or A/B comparison.",
    }
