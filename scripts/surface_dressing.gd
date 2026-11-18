extends Node3D
## F34: non-colliding macro regolith pigmentation, geological silhouettes and
## industrial wear. Never creates physical ground, landing contacts or RL zones.
## Building this node is skipped entirely for headless training.

const ROCK_MIN_RADIUS: float = 43.0
const ROCK_MAX_RADIUS: float = 73.0
const ROCK_INSTANCE_COUNT: int = 192
const RIDGE_COUNT: int = 8
const FRAME_MARK_COUNT: int = 48


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _add_regolith_macro_variation()
    _add_far_field_strata()
    _scatter_ejecta()
    _add_pad_wear()
    _add_edge_service_scuffs()


func _surface(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.metallic = metallic
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat


func _macro_patch_material() -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.vertex_color_use_as_albedo = true
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
    return material


func _add_regolith_macro_variation() -> void:
    # One batched low-poly overlay, beneath existing F10/F27 patina and F31
    # touchdown response. Alpha vanishes near base and the terrain perimeter.
    # This breaks visible texture repeats at 40–160 m without new shaders.
    var sheet: SurfaceTool = SurfaceTool.new()
    sheet.begin(Mesh.PRIMITIVE_TRIANGLES)
    var cells: int = 40
    var stride: float = 156.0 / float(cells)
    for iz in range(cells):
        for ix in range(cells):
            var x0: float = -78.0 + float(ix) * stride
            var z0: float = -78.0 + float(iz) * stride
            var x1: float = x0 + stride
            var z1: float = z0 + stride
            _macro_tri(sheet, Vector2(x0, z0), Vector2(x0, z1), Vector2(x1, z0))
            _macro_tri(sheet, Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1))
    var layer: MeshInstance3D = MeshInstance3D.new()
    layer.name = "F34GroundMacroPigment"
    layer.mesh = sheet.commit()
    layer.material_override = _macro_patch_material()
    layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    layer.visibility_range_end = 175.0
    add_child(layer)


func _macro_tri(sheet: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
    for vertex in [a, b, c]:
        var p: Vector2 = vertex
        var radius: float = p.length()
        # No tinting of physical pad, painted markings or immediate service yard.
        var fade_center: float = smoothstep(29.0, 41.0, radius)
        var fade_outer: float = 1.0 - smoothstep(68.0, 78.0, maxf(absf(p.x), absf(p.y)))
        var broad: float = (sin(p.x * 0.105) * cos(p.y * 0.073)
            + sin(p.x * 0.043 - p.y * 0.097) * 0.7) * 0.5
        var pigment: float = 0.28 if broad < 0.0 else 0.53
        var alpha: float = minf(0.13, absf(broad) * 0.17) * fade_center * fade_outer
        sheet.set_color(Color(pigment, pigment * 1.02, pigment * 1.055, alpha))
        sheet.add_vertex(Vector3(p.x, 0.007, p.y))


func _add_far_field_strata() -> void:
    # Asymmetric, broken crescent ridges rather than repeated sphere hills.
    # They are decorative silhouettes OUTSIDE the approach radius. Visual
    # height is NOT physical elevation; documented for manual QA.
    var stratum: SurfaceTool = SurfaceTool.new()
    stratum.begin(Mesh.PRIMITIVE_TRIANGLES)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 341190
    for ridge_index in range(RIDGE_COUNT):
        var heading: float = TAU * (float(ridge_index) + 0.15) / float(RIDGE_COUNT)
        var radial: float = rng.randf_range(52.0, 66.0)
        var width: float = rng.randf_range(5.0, 10.0)
        var length: float = rng.randf_range(8.0, 15.0)
        var height: float = rng.randf_range(0.29, 0.72)
        var origin: Vector2 = Vector2(cos(heading), sin(heading)) * radial
        var tangent: Vector2 = Vector2(-sin(heading), cos(heading))
        var normal: Vector2 = Vector2(cos(heading), sin(heading))
        var segments: int = 14
        for i in range(segments):
            var t0: float = float(i) / float(segments)
            var t1: float = float(i + 1) / float(segments)
            var left: Vector3 = _ridge_point(origin, tangent, normal, length, width, height, t0, -1.0)
            var crest0: Vector3 = _ridge_point(origin, tangent, normal, length, width, height, t0, 0.0)
            var right: Vector3 = _ridge_point(origin, tangent, normal, length, width, height, t0, 1.0)
            var left1: Vector3 = _ridge_point(origin, tangent, normal, length, width, height, t1, -1.0)
            var crest1: Vector3 = _ridge_point(origin, tangent, normal, length, width, height, t1, 0.0)
            var right1: Vector3 = _ridge_point(origin, tangent, normal, length, width, height, t1, 1.0)
            _ridge_triangle(stratum, left, crest0, left1)
            _ridge_triangle(stratum, left1, crest0, crest1)
            _ridge_triangle(stratum, crest0, right, crest1)
            _ridge_triangle(stratum, crest1, right, right1)
    stratum.generate_normals()
    var ridges: MeshInstance3D = MeshInstance3D.new()
    ridges.name = "F34FarFieldLunarStrata"
    ridges.mesh = stratum.commit()
    ridges.material_override = _regolith_rock_material()
    ridges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    ridges.visibility_range_end = 160.0
    add_child(ridges)


func _ridge_point(origin: Vector2, tangent: Vector2, normal: Vector2,
        span: float, width: float, height: float, t: float, across: float) -> Vector3:
    var arc: float = sin(t * PI)
    var along: float = (t - 0.5) * span
    var wobble: float = sin(t * 19.0) * 0.18 + sin(t * 47.0) * 0.07
    var lateral: float = across * width * 0.5 * arc + wobble
    var point: Vector2 = origin + tangent * along + normal * lateral
    var rise: float = height * arc * (1.0 - absf(across))
    return Vector3(point.x, 0.009 + rise, point.y)


func _ridge_triangle(surf: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    for point in [a, b, c]:
        surf.set_uv(Vector2(point.x * 0.16, point.z * 0.16))
        surf.add_vertex(point)


func _regolith_rock_material() -> StandardMaterial3D:
    var mat: StandardMaterial3D = _surface(Color(0.36, 0.37, 0.395), 0.0, 0.98)
    var prefix: String = "res://assets/terrain_materials/regolith_"
    if (ResourceLoader.exists(prefix + "albedo.png")
            and ResourceLoader.exists(prefix + "normal.png")
            and ResourceLoader.exists(prefix + "roughness.png")):
        mat.albedo_texture = load(prefix + "albedo.png") as Texture2D
        mat.normal_enabled = true
        mat.normal_texture = load(prefix + "normal.png") as Texture2D
        mat.normal_scale = 0.63
        mat.roughness_texture = load(prefix + "roughness.png") as Texture2D
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return mat


func _scatter_ejecta() -> void:
    var stone: SphereMesh = SphereMesh.new()
    stone.radius = 0.11
    stone.height = 0.20
    stone.radial_segments = 6
    stone.rings = 3
    stone.material = _regolith_rock_material()
    var batch: MultiMesh = MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.mesh = stone
    batch.instance_count = ROCK_INSTANCE_COUNT
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 341218
    for i in range(ROCK_INSTANCE_COUNT):
        var bearing: float = rng.randf_range(0.0, TAU)
        var distance: float = sqrt(rng.randf()) * (ROCK_MAX_RADIUS - ROCK_MIN_RADIUS) + ROCK_MIN_RADIUS
        var xx: float = cos(bearing) * distance
        var zz: float = sin(bearing) * distance
        var size: float = rng.randf_range(0.45, 2.8)
        var flatness: float = rng.randf_range(0.4, 1.0)
        var turn: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
        turn = turn.scaled(Vector3(size * 1.28, size * flatness, size))
        batch.set_instance_transform(i, Transform3D(turn, Vector3(xx, 0.012, zz)))
    var stones: MultiMeshInstance3D = MultiMeshInstance3D.new()
    stones.name = "F34RockEjectaInstanced"
    stones.multimesh = batch
    stones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    stones.visibility_range_end = 115.0
    add_child(stones)


func _add_pad_wear() -> void:
    # Muted thin scratch arcs ON TOP of the real landing slab (y=.30), below
    # existing F10 guidance at y=.314. Do not paint false scorch/impact zones.
    var surface: SurfaceTool = SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for band in range(3):
        var radius: float = 4.70 + float(band) * 0.20
        for segment in range(64):
            if (segment * 7 + band * 13) % 17 < 5:
                continue
            var a: float = TAU * float(segment) / 64.0
            var b: float = TAU * (float(segment) + 0.65) / 64.0
            _pad_mark_triangle(surface, radius, radius + 0.012, a, b)
    var scuffs: MeshInstance3D = MeshInstance3D.new()
    scuffs.name = "F34LandingDeckMicroScuffs"
    scuffs.mesh = surface.commit()
    scuffs.material_override = _macro_patch_material()
    scuffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    scuffs.visibility_range_end = 65.0
    add_child(scuffs)


func _pad_mark_triangle(surface: SurfaceTool, inner: float, outer: float,
        a: float, b: float) -> void:
    var x0: Vector3 = Vector3(cos(a) * inner, 0.308, sin(a) * inner)
    var x1: Vector3 = Vector3(cos(a) * outer, 0.308, sin(a) * outer)
    var y0: Vector3 = Vector3(cos(b) * inner, 0.308, sin(b) * inner)
    var y1: Vector3 = Vector3(cos(b) * outer, 0.308, sin(b) * outer)
    for vertex in [x0, y0, x1, x1, y0, y1]:
        surface.set_color(Color(0.10, 0.11, 0.12, 0.24))
        surface.add_vertex(vertex)


func _add_edge_service_scuffs() -> void:
    # Surface finish only on the F23 raised steel frame, not an artificial
    # physical lip. 48 sparse, dark scuffs, one instanced draw.
    var scratch: BoxMesh = BoxMesh.new()
    scratch.size = Vector3(0.025, 0.003, 0.23)
    scratch.material = _surface(Color(0.11, 0.12, 0.135), 0.12, 0.87)
    var batch: MultiMesh = MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.mesh = scratch
    batch.instance_count = FRAME_MARK_COUNT
    var index: int = 0
    for sign_side in [-1.0, 1.0]:
        for slot in range(12):
            var pos: float = -5.1 + float(slot) * (10.2 / 11.0)
            batch.set_instance_transform(index, Transform3D(Basis.IDENTITY,
                Vector3(pos, 0.419, 5.88 * sign_side)))
            index += 1
            batch.set_instance_transform(index, Transform3D(Basis(Vector3.UP, PI * 0.5),
                Vector3(5.88 * sign_side, 0.419, pos)))
            index += 1
    var marks: MultiMeshInstance3D = MultiMeshInstance3D.new()
    marks.name = "F34FrameWearMarkings"
    marks.multimesh = batch
    marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    marks.visibility_range_end = 75.0
    add_child(marks)
