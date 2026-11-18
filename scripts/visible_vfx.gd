extends Node3D
## F22/F26: immediate, visible, shader-based exhaust with a particle backup layer.
## Works with the project's GL Compatibility renderer: no GPUParticles3D trails.
## Every beam is built from crossed procedural sheets with soft expansion and haze.
## Reads only the existing RocketPhysics input state; NEVER applies forces.

const BEAM_SHADER: Shader = preload("res://assets/materials/visible_exhaust.gdshader")
const F38_ENGINE_SHADER: Shader = preload("res://assets/materials/engine_exhaust.gdshader")
const F39_FIRE_SHADER: Shader = preload("res://assets/materials/fire_tongues.gdshader")
const F31_SURFACE_MATH: GDScript = preload("res://scripts/surface_math.gd")
const OFF_THRESHOLD := 0.035
const F35_ENABLE_FICTIONAL_GIMBAL_JETS: bool = false

@onready var rocket: RocketPhysics = get_node("../../Rocket")
@onready var episode: EpisodeController = get_node("../../EpisodeController")
@onready var legacy_fx: Node3D = get_parent()

var engine_core: Node3D
var engine_flames: Node3D
var engine_halo: Node3D
var engine_diffuse: Node3D
var yaw_beams: Array[Node3D] = []
var pitch_beams: Array[Node3D] = []
var lateral_beams: Array[Node3D] = []
var yaw_haze_beams: Array[Node3D] = []
var pitch_haze_beams: Array[Node3D] = []
var lateral_haze_beams: Array[Node3D] = []
# F29: short world-space release fade avoids instant on/off of vacuum jets.
var _beam_levels: Dictionary = {}
var _frame_delta: float = 0.016667

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        set_process(false)
        return
    engine_core = _create_beam("F22EngineCore", 0.42, 2.90, 3,
        Color(1.0, 0.98, 0.89), Color(1.0, 0.72, 0.30), 0.66, 0.75, false,
        0.48, 0.12, 0.18)
    # Independent irregular flame tongues: not a rigid cone or a smoke column.
    engine_flames = _create_beam("F39FireTongues", 0.74, 3.40, 4,
        Color(1.0, 0.98, 0.78), Color(1.0, 0.34, 0.075), 0.68, 0.91, false,
        0.61, 0.15, 0.38)
    engine_halo = _create_beam("F22EngineHalo", 1.25, 4.15, 3,
        Color(1.0, 0.87, 0.59), Color(0.63, 0.75, 0.96), 0.28, 0.92, false,
        0.94, 0.29, 0.32)
    engine_diffuse = _create_beam("F22EngineDiffuse", 1.77, 5.00, 3,
        Color(1.0, 0.83, 0.61), Color(0.51, 0.66, 0.96), 0.12, 1.00, false,
        1.26, 0.54, 0.43)
    for i in range(4):
        yaw_beams.append(_create_beam("F22Yaw%d" % i, 0.45, 1.52, 2,
            Color(0.96, 0.99, 1.0), Color(0.49, 0.78, 1.0), 0.84, 0.74, true,
            0.42, 0.28, 0.22))
        pitch_beams.append(_create_beam("F22Pitch%d" % i, 0.43, 1.56, 2,
            Color(0.96, 0.99, 1.0), Color(0.50, 0.80, 1.0), 0.80, 0.76, true,
            0.44, 0.30, 0.22))
        lateral_beams.append(_create_beam("F22Side%d" % i, 0.49, 1.70, 2,
            Color(0.97, 1.0, 1.0), Color(0.49, 0.81, 1.0), 0.90, 0.78, true,
            0.48, 0.32, 0.24))

        yaw_haze_beams.append(_create_beam("F22YawHaze%d" % i, 0.72, 2.10, 3,
            Color(0.92, 0.98, 1.0), Color(0.55, 0.82, 1.0), 0.22, 1.02, true,
            0.82, 0.72, 0.56))
        pitch_haze_beams.append(_create_beam("F22PitchHaze%d" % i, 0.72, 2.18, 3,
            Color(0.92, 0.98, 1.0), Color(0.55, 0.82, 1.0), 0.22, 1.02, true,
            0.82, 0.72, 0.56))
        lateral_haze_beams.append(_create_beam("F22SideHaze%d" % i, 0.80, 2.34, 3,
            Color(0.93, 0.99, 1.0), Color(0.55, 0.84, 1.0), 0.24, 1.04, true,
            0.88, 0.76, 0.58))

func _create_beam(name: String, width: float, length: float, planes: int,
        warm: Color, cool: Color, alpha: float, breadth: float, gas: bool,
        tip_spread: float, diffuse_mix: float, flare_strength: float) -> Node3D:
    var stream := Node3D.new()
    stream.name = name
    stream.visible = false
    add_child(stream)
    # Real flared mesh: fixed-width quads clipped F26's diffuse tail. Retain a
    # QuadMesh fallback for malformed parameters / compatibility diagnostics.
    var sheet: Mesh = QuadMesh.new()
    if width > 0.0 and length > 0.0:
        sheet = _flared_sheet(width, length, tip_spread)
    var material := ShaderMaterial.new()
    material.shader = BEAM_SHADER if gas else F38_ENGINE_SHADER
    if name == "F39FireTongues":
        material.shader = F39_FIRE_SHADER
    material.set_shader_parameter("near_color", Vector3(warm.r, warm.g, warm.b))
    material.set_shader_parameter("far_color", Vector3(cool.r, cool.g, cool.b))
    material.set_shader_parameter("opacity", alpha)
    material.set_shader_parameter("edge_breadth", breadth)
    material.set_shader_parameter("softness", 1.45 if gas else 2.05)
    material.set_shader_parameter("flow_speed", 7.5 if gas else 4.2)
    material.set_shader_parameter("gas_mode", 1.0 if gas else 0.0)
    material.set_shader_parameter("tip_spread", tip_spread)
    material.set_shader_parameter("diffuse_mix", diffuse_mix)
    material.set_shader_parameter("flare_strength", flare_strength)
    material.set_shader_parameter("strength", 0.0)
    for index in range(planes):
        var plane := MeshInstance3D.new()
        plane.name = "SoftSheet%d" % index
        plane.mesh = sheet
        # Independent shader parameters: F26 used one shared noise seed across
        # all crossed planes, making the supposed volume look like flat sheets.
        var layer_material := material.duplicate() as ShaderMaterial
        layer_material.set_shader_parameter("layer_seed", float(index) * 9.173 + float(name.hash() & 127) * 0.11)
        plane.material_override = layer_material
        plane.rotation.y = TAU * float(index) / float(planes)
        plane.position.y = 0.0
        plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        plane.extra_cull_margin = 8.0
        stream.add_child(plane)
    return stream


func _flared_sheet(width: float, length: float, tip_spread: float) -> ArrayMesh:
    # Near nozzle = local origin, far end = -Y. UV 0 -> 1 follows exhaust.
    # Expansion is real geometry, not merely wider alpha inside a fixed quad.
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var divisions: int = 16
    var sections: Array[Vector2] = []
    for index in range(divisions + 1):
        var t: float = float(index) / float(divisions)
        var flaring: float = 0.13 + 0.87 * pow(t, 0.74)
        var tail_width: float = width * (1.0 + tip_spread * 0.66 * t) * flaring
        sections.append(Vector2(-tail_width * 0.5, -length * t))
        sections.append(Vector2(tail_width * 0.5, -length * t))
    for index in range(divisions):
        var t0: float = float(index) / float(divisions)
        var t1: float = float(index + 1) / float(divisions)
        var left0: Vector2 = sections[index * 2]
        var right0: Vector2 = sections[index * 2 + 1]
        var left1: Vector2 = sections[(index + 1) * 2]
        var right1: Vector2 = sections[(index + 1) * 2 + 1]
        for point in [
            [left0, Vector2(0.0, t0)], [right0, Vector2(1.0, t0)], [left1, Vector2(0.0, t1)],
            [right0, Vector2(1.0, t0)], [right1, Vector2(1.0, t1)], [left1, Vector2(0.0, t1)]]:
            var coords: Vector2 = point[0]
            var uv: Vector2 = point[1]
            surface.set_uv(uv)
            surface.add_vertex(Vector3(coords.x, coords.y, 0.0))
    return surface.commit()


func _activate(stream: Node3D, position_world: Vector3, world_direction: Vector3,
        brightness: float, length_factor: float, reduced: bool) -> void:
    # F29: the command has its old threshold, but the visible level has a
    # temporal envelope. This prevents a rigid beam vanishing in one frame.
    stream.visible = brightness > OFF_THRESHOLD
    var key: int = stream.get_instance_id()
    var previous: float = float(_beam_levels.get(key, 0.0))
    var target: float = clampf(brightness, 0.0, 1.0)
    var response: float = 15.0 if target > previous else 8.0
    var progress: float = 1.0 - exp(-response * _frame_delta)
    var level: float = lerpf(previous, target, progress)
    if level < 0.012 and target < OFF_THRESHOLD:
        level = 0.0
    _beam_levels[key] = level
    stream.visible = level > OFF_THRESHOLD
    if not stream.visible:
        return
    # RCS nozzle glow follows the nozzle even during its short extinction tail.
    # Otherwise the descending vehicle outruns its own bright gas sheet.
    var attached_rcs: bool = stream.name.begins_with("F22Yaw") or (
        stream.name.begins_with("F22Pitch") or stream.name.begins_with("F22Side"))
    if brightness > OFF_THRESHOLD:
        stream.global_transform = Transform3D(
            Basis(Quaternion(Vector3.DOWN, world_direction.normalized())), position_world)
        stream.scale = Vector3(0.70 + 0.54 * brightness,
            length_factor * (0.74 + 0.58 * brightness), 0.70 + 0.54 * brightness)
    elif attached_rcs:
        # On cutoff, main exhaust sheets can fade in world space; only RCS
        # glow keeps up with its nozzle during the fade-out envelope.
        stream.global_transform = Transform3D(
            Basis(Quaternion(Vector3.DOWN, world_direction.normalized())), position_world)
    var visual_strength: float = clampf(level * (0.66 if reduced else 1.0), 0.0, 1.0)
    for child in stream.get_children():
        var plane: MeshInstance3D = child as MeshInstance3D
        var material: ShaderMaterial = plane.material_override as ShaderMaterial
        material.set_shader_parameter("strength", visual_strength)

func _process(delta: float) -> void:
    _frame_delta = clampf(delta, 0.0, 0.10)
    var active: bool = not get_tree().paused and not episode.is_finished()
    var reduced: bool = bool(legacy_fx.get("reduced_particles"))
    var f35_far: bool = int(legacy_fx.get("_f35_budget_tier")) >= 2
    var f35_medium: bool = int(legacy_fx.get("_f35_budget_tier")) >= 1
    var thrust: float = rocket.throttle if active else 0.0
    var nozzle_basis: Basis = rocket.global_transform.basis * (
        Basis(Vector3.RIGHT, deg_to_rad(rocket.gimbal_x * rocket.physics_config.max_gimbal_deg))
        * Basis(Vector3.BACK, deg_to_rad(rocket.gimbal_z * rocket.physics_config.max_gimbal_deg)))
    var position_world := rocket.to_global(Vector3(0.0, -1.34, 0.0))
    var plume_dir := nozzle_basis * Vector3.DOWN
    # F31: visual sheets must not pass through the physical deck or regolith.
    # Only the world-space nozzle ray is used; physics/landing policy unchanged.
    var surface_hit: Dictionary = F31_SURFACE_MATH.solve(position_world, plume_dir)
    var reach: float = float(surface_hit.get("distance", 999.0))
    var core_limit: float = minf(1.0, reach / (2.40 * 1.36))
    var halo_limit: float = minf(1.12, reach / (4.15 * 1.36))
    var diffuse_limit: float = minf(1.28, reach / (5.00 * 1.36))
    _activate(engine_core, position_world, plume_dir, thrust, maxf(core_limit, 0.025), reduced)
    # The new flame shares throttle, gimbal and ground clipping with the core.
    var fire_limit: float = minf(1.0, reach / (3.40 * 1.36))
    _activate(engine_flames, position_world, plume_dir, thrust, maxf(fire_limit, 0.025), reduced)
    _activate(engine_halo, position_world, plume_dir, thrust * (0.55 if f35_far else 0.80), maxf(halo_limit, 0.025), reduced)
    var diffuse_thrust: float = 0.0 if reduced else thrust * 0.68
    if f35_medium:
        diffuse_thrust = 0.0
    _activate(engine_diffuse, position_world, plume_dir, diffuse_thrust,
        maxf(diffuse_limit, 0.025), reduced)

    var yaw: float = rocket.yaw_rcs if active else 0.0
    var yaw_offsets := [Vector3(0.73, 0.51, 0.0), Vector3(-0.73, 0.51, 0.0),
        Vector3(0.73, 0.51, 0.0), Vector3(-0.73, 0.51, 0.0)]
    var yaw_dirs := [Vector3.BACK, Vector3.FORWARD, Vector3.FORWARD, Vector3.BACK]
    for index in range(4):
        var enabled: bool = (yaw > 0.08 and index < 2) or (yaw < -0.08 and index >= 2)
        var intensity := absf(yaw) if enabled else 0.0
        _activate(yaw_beams[index], rocket.to_global(yaw_offsets[index]),
            rocket.global_transform.basis * yaw_dirs[index], intensity, 1.0, reduced)
        var haze_strength: float = 0.0 if reduced else intensity * 0.72
        if f35_far:
            haze_strength = 0.0
        _activate(yaw_haze_beams[index], rocket.to_global(yaw_offsets[index]),
            rocket.global_transform.basis * yaw_dirs[index], haze_strength, 1.20, reduced)

    # F32: these are illustrative gimbal-assist VFX, not simulated lateral
    # thruster forces. They may only illuminate during an actual main burn.
    var pitch: float = rocket.gimbal_x if active and thrust > 0.025 else 0.0
    var side: float = rocket.gimbal_z if active and thrust > 0.025 else 0.0
    if not F35_ENABLE_FICTIONAL_GIMBAL_JETS:
        pitch = 0.0
        side = 0.0
    var pitch_offsets := [Vector3(-0.21, 0.98, -0.72), Vector3(0.21, 0.98, -0.72),
        Vector3(-0.21, 0.98, 0.72), Vector3(0.21, 0.98, 0.72)]
    var pitch_dirs := [Vector3.FORWARD, Vector3.FORWARD, Vector3.BACK, Vector3.BACK]
    for index in range(4):
        var enabled: bool = (pitch < -0.12 and index < 2) or (pitch > 0.12 and index >= 2)
        var intensity := absf(pitch) if enabled else 0.0
        _activate(pitch_beams[index], rocket.to_global(pitch_offsets[index]),
            rocket.global_transform.basis * pitch_dirs[index], intensity, 1.0, reduced)
        var haze_strength: float = 0.0 if reduced else intensity * 0.72
        if f35_far:
            haze_strength = 0.0
        _activate(pitch_haze_beams[index], rocket.to_global(pitch_offsets[index]),
            rocket.global_transform.basis * pitch_dirs[index], haze_strength, 1.18, reduced)
    var side_offsets := [Vector3(-0.84, 1.02, -0.24), Vector3(-0.84, 1.02, 0.24),
        Vector3(0.84, 1.02, -0.24), Vector3(0.84, 1.02, 0.24)]
    var side_dirs := [Vector3.LEFT, Vector3.LEFT, Vector3.RIGHT, Vector3.RIGHT]
    for index in range(4):
        var enabled: bool = (side > 0.12 and index < 2) or (side < -0.12 and index >= 2)
        var intensity := absf(side) if enabled else 0.0
        _activate(lateral_beams[index], rocket.to_global(side_offsets[index]),
            rocket.global_transform.basis * side_dirs[index], intensity, 1.0, reduced)
        var haze_strength: float = 0.0 if reduced else intensity * 0.74
        if f35_far:
            haze_strength = 0.0
        _activate(lateral_haze_beams[index], rocket.to_global(side_offsets[index]),
            rocket.global_transform.basis * side_dirs[index], haze_strength, 1.24, reduced)
