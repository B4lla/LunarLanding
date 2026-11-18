extends Node3D
## F10 native lunar micro-detail. Visual-only, deterministic and headless-free.
## Crater pigmentation is FLAT: it deliberately cannot change the Jolt surface.
## All detail lives beyond the 12 x 12 m landing platform approach corridor.

const CRATER_COUNT: int = 16
const DEBRIS_COUNT: int = 180
const SAFE_RADIUS: float = 16.0
const MAX_RADIUS: float = 54.0
const CRATER_SEGMENTS: int = 40
const DECAL_Y: float = 0.012

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _make_crater_stains()
    _scatter_debris()


func _make_crater_stains() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 180317
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index in range(CRATER_COUNT):
        var angle: float = rng.randf_range(-PI, PI)
        var distance: float = rng.randf_range(SAFE_RADIUS + 5.0, MAX_RADIUS - 5.0)
        var origin := Vector2(cos(angle) * distance, sin(angle) * distance)
        var radius: float = rng.randf_range(1.1, 3.5)
        # Four concentric bands emulate discoloration, not a physical hole.
        # Alpha fades at the boundary and never obscures the approach target.
        var radii := [0.0, 0.53, 0.78, 1.02, 1.23]
        var opacity := [0.24, 0.26, 0.10, 0.17, 0.0]
        for band in range(radii.size() - 1):
            for slice in range(CRATER_SEGMENTS):
                var a: float = TAU * float(slice) / float(CRATER_SEGMENTS)
                var b: float = TAU * float(slice + 1) / float(CRATER_SEGMENTS)
                var inner_a := _stain_point(origin, radius * radii[band], a)
                var inner_b := _stain_point(origin, radius * radii[band], b)
                var outer_a := _stain_point(origin, radius * radii[band + 1], a)
                var outer_b := _stain_point(origin, radius * radii[band + 1], b)
                var shade: float = 0.17 if band < 2 else 0.36
                _decal_triangle(surface, inner_a, outer_a, inner_b, shade,
                    opacity[band], opacity[band + 1], opacity[band])
                _decal_triangle(surface, inner_b, outer_a, outer_b, shade,
                    opacity[band], opacity[band + 1], opacity[band + 1])
    var decals := MeshInstance3D.new()
    decals.name = "FlatCraterPatinaNoCollision"
    decals.mesh = surface.commit()
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
    mat.vertex_color_use_as_albedo = true
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
    decals.material_override = mat
    decals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    decals.visibility_range_end = 110.0
    add_child(decals)


func _stain_point(origin: Vector2, distance: float, angle: float) -> Vector3:
    return Vector3(origin.x + cos(angle) * distance, DECAL_Y,
        origin.y + sin(angle) * distance)


func _decal_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
        shade: float, alpha_a: float, alpha_b: float, alpha_c: float) -> void:
    surface.set_color(Color(shade, shade * 1.025, shade * 1.06, alpha_a))
    surface.add_vertex(a)
    surface.set_color(Color(shade, shade * 1.025, shade * 1.06, alpha_b))
    surface.add_vertex(b)
    surface.set_color(Color(shade, shade * 1.025, shade * 1.06, alpha_c))
    surface.add_vertex(c)


func _scatter_debris() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 840611
    var rock := SphereMesh.new()
    rock.radius = 0.10
    rock.height = 0.20
    rock.radial_segments = 7
    rock.rings = 3
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.32, 0.33, 0.35)
    mat.roughness = 1.0
    rock.material = mat
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = rock
    multimesh.instance_count = DEBRIS_COUNT
    for index in range(DEBRIS_COUNT):
        var angle: float = rng.randf_range(-PI, PI)
        var distance: float = sqrt(rng.randf_range(0.0, 1.0)) * (MAX_RADIUS - SAFE_RADIUS) + SAFE_RADIUS
        var width: float = rng.randf_range(0.45, 1.50)
        var height: float = rng.randf_range(0.30, 0.95)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
        basis = basis.scaled(Vector3(width, height, width * rng.randf_range(0.7, 1.2)))
        var location := Vector3(cos(angle) * distance, 0.018, sin(angle) * distance)
        multimesh.set_instance_transform(index, Transform3D(basis, location))
    var scatter := MultiMeshInstance3D.new()
    scatter.name = "SmallNonCollidingEjecta"
    scatter.multimesh = multimesh
    scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    scatter.visibility_range_end = 125.0
    add_child(scatter)
