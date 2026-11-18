extends Node3D
## F31 lighting, reflections and surface-dependent impact rendering.
## Visual only. Zero areas, colliders, rigid bodies, force or policy writes.
## Godot GL Compatibility supports ReflectionProbe but not SSR.

const SURFACE_MATH: GDScript = preload("res://scripts/surface_math.gd")
const IMPACT_SHADER: Shader = preload("res://assets/materials/ground_impact.gdshader")

@onready var rocket: RocketPhysics = get_node("../Rocket")
@onready var episode: EpisodeController = get_node("../EpisodeController")
@onready var visual_fx: Node3D = get_node("../VisualFX")

var deck_impact: MeshInstance3D
var dust_impact: MeshInstance3D
var deck_mat: ShaderMaterial
var dust_mat: ShaderMaterial
var impact_light: OmniLight3D
var base_lights: Array[OmniLight3D] = []
var outer_lights: Array[OmniLight3D] = []
var reflection_probe: ReflectionProbe
var _impact_level: float = 0.0


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        set_process(false)
        return
    _refine_scene_lighting()
    _create_base_lights()
    _create_reflections()
    _create_surface_response()


func _refine_scene_lighting() -> void:
    # The existing sky-free lunar scene otherwise looks uniformly flat because
    # of its strong ambient + unshadowed second directional light.
    var environment_node := get_node_or_null("../WorldEnvironment") as WorldEnvironment
    if environment_node != null and environment_node.environment != null:
        var local_environment: Environment = environment_node.environment.duplicate() as Environment
        local_environment.ambient_light_energy = 0.32
        environment_node.environment = local_environment
    var bounce := get_node_or_null("../BounceLight") as DirectionalLight3D
    if bounce != null:
        bounce.light_energy = 0.15
    # Darker shadows, but retain a weak fill for readability on the unlit side.
    var sun := get_node_or_null("../Sun") as DirectionalLight3D
    if sun != null:
        sun.light_energy = 2.1


func _create_base_lights() -> void:
    # Exactly four local area guides instead of one OmniLight per luminous lens.
    var spots: Array[Vector3] = [
        Vector3(-10.8, 3.4, 0.0), Vector3(10.8, 3.4, 0.0),
        Vector3(0.0, 3.4, -10.8), Vector3(0.0, 3.4, 10.8)
    ]
    for index in range(spots.size()):
        var point: OmniLight3D = OmniLight3D.new()
        point.name = "SpaceportAreaLight_%d" % index
        point.position = spots[index]
        point.light_color = Color(0.69, 0.81, 1.0)
        point.light_energy = 0.44
        point.light_specular = 0.68
        point.omni_range = 9.5
        point.shadow_enabled = false
        add_child(point)
        base_lights.append(point)
    # These match real F30 light poles but do not produce extra shadows.
    var outskirts: Array[Vector3] = [
        Vector3(-29.0, 3.65, -25.0), Vector3(29.0, 3.65, 25.0),
        Vector3(25.0, 3.65, -29.0), Vector3(-25.0, 3.65, 29.0)
    ]
    for index in range(outskirts.size()):
        var flood: OmniLight3D = OmniLight3D.new()
        flood.name = "UtilityFloodlight_%d" % index
        flood.position = outskirts[index]
        flood.light_color = Color(0.68, 0.83, 1.0)
        flood.light_energy = 0.55
        flood.omni_range = 11.0
        flood.shadow_enabled = false
        add_child(flood)
        outer_lights.append(flood)


func _create_reflections() -> void:
    # Compatibility accepts ReflectionProbe (max two per mesh), not SSR.
    # Static capture is intentionally UPDATE_ONCE: no per-frame GPU cubemap.
    reflection_probe = ReflectionProbe.new()
    reflection_probe.name = "SpaceportStaticReflectionProbe"
    reflection_probe.position = Vector3(0.0, 4.0, 0.0)
    reflection_probe.size = Vector3(25.5, 11.0, 25.5)
    reflection_probe.intensity = 0.52
    reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
    reflection_probe.enable_shadows = false
    reflection_probe.box_projection = false
    add_child(reflection_probe)
    # Preserve dusty regolith as very rough and nonmetallic. Modify only the
    # physical deck's render material, not its MeshInstance transform/collider.
    var deck := get_node_or_null("../Terrain/LandingPlatform/MeshInstance3D") as MeshInstance3D
    if deck != null and deck.material_override is StandardMaterial3D:
        var copy: StandardMaterial3D = (deck.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
        copy.metallic = 0.32
        copy.roughness = 0.69
        deck.material_override = copy


func _create_surface_response() -> void:
    var circle: ArrayMesh = _make_ground_disc()
    deck_mat = ShaderMaterial.new()
    deck_mat.shader = IMPACT_SHADER
    deck_mat.set_shader_parameter("is_deck", 1.0)
    deck_mat.set_shader_parameter("intensity", 0.0)
    dust_mat = ShaderMaterial.new()
    dust_mat.shader = IMPACT_SHADER
    dust_mat.set_shader_parameter("is_deck", 0.0)
    dust_mat.set_shader_parameter("intensity", 0.0)
    dust_mat.set_shader_parameter("seed", 2.4)
    deck_impact = _disc_node("MetalDeckExhaustReflection", circle, deck_mat)
    dust_impact = _disc_node("LunarRegolithRadialScour", circle, dust_mat)
    impact_light = OmniLight3D.new()
    impact_light.name = "ExhaustSurfaceBounce"
    impact_light.light_color = Color(1.0, 0.71, 0.42)
    impact_light.light_energy = 0.0
    impact_light.omni_range = 7.0
    impact_light.shadow_enabled = false
    add_child(impact_light)


func _make_ground_disc() -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for segment in range(64):
        var a: float = TAU * float(segment) / 64.0
        var b: float = TAU * float(segment + 1) / 64.0
        for data in [
            [Vector3.ZERO, Vector2(0.5, 0.5)],
            [Vector3(cos(a), 0.0, sin(a)), Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5)],
            [Vector3(cos(b), 0.0, sin(b)), Vector2(0.5 + cos(b) * 0.5, 0.5 + sin(b) * 0.5)]]:
            var point: Vector3 = data[0]
            var uv: Vector2 = data[1]
            surface.set_uv(uv)
            surface.add_vertex(point)
    return surface.commit()


func _disc_node(label: String, mesh: ArrayMesh, surface: ShaderMaterial) -> MeshInstance3D:
    var node: MeshInstance3D = MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.material_override = surface
    node.visible = false
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)
    return node


func _process(delta: float) -> void:
    var reduced: bool = bool(visual_fx.get("reduced_particles"))
    for flood in outer_lights:
        # F36 mutes legacy floodlights; do not re-enable their GPU influence.
        flood.visible = not reduced and flood.light_energy > 0.001
    var active: bool = not get_tree().paused and not episode.is_finished()
    var thrust: float = rocket.throttle if active else 0.0
    var direction: Vector3 = rocket.global_transform.basis * (
        Basis(Vector3.RIGHT, deg_to_rad(rocket.gimbal_x * rocket.physics_config.max_gimbal_deg))
        * Basis(Vector3.BACK, deg_to_rad(rocket.gimbal_z * rocket.physics_config.max_gimbal_deg))) * Vector3.DOWN
    var origin: Vector3 = rocket.to_global(Vector3(0.0, -1.30, 0.0))
    var impact: Dictionary = SURFACE_MATH.solve(origin, direction)
    var target: float = 0.0
    if not impact.is_empty():
        target = thrust * float(impact["proximity"])
    var rate: float = 12.0 if target > _impact_level else 8.0
    _impact_level = lerpf(_impact_level, target, 1.0 - exp(-rate * clampf(delta, 0.0, 0.10)))
    if _impact_level < 0.008 or impact.is_empty():
        deck_impact.visible = false
        dust_impact.visible = false
        impact_light.light_energy = 0.0
        return
    var point: Vector3 = impact["point"]
    var on_deck: bool = bool(impact["deck"])
    var width: float = (0.65 + 2.9 * sqrt(_impact_level)) * (0.8 if reduced else 1.0)
    deck_impact.visible = on_deck
    dust_impact.visible = not on_deck
    var disc: MeshInstance3D = deck_impact if on_deck else dust_impact
    disc.global_position = point + Vector3(0.0, 0.024 if on_deck else 0.017, 0.0)
    disc.scale = Vector3(width, 1.0, width)
    deck_mat.set_shader_parameter("intensity", _impact_level if on_deck else 0.0)
    dust_mat.set_shader_parameter("intensity", _impact_level if not on_deck else 0.0)
    impact_light.global_position = point + Vector3(0.0, 0.6, 0.0)
    impact_light.light_energy = _impact_level * (0.68 if on_deck else 0.24)
    impact_light.omni_range = 3.5 + 4.0 * _impact_level
