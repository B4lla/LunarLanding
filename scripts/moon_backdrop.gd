extends Node3D
## F05 backdrop is entirely non-colliding, deterministic, and visual-only.
## Geometry is never used by RL state, rewards or landing contact logic.

const TERRAIN_RADIUS := 80.0
const GRID_SEGMENTS := 48
const ROCK_COUNT := 220

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _create_distant_terrain()
    _create_rocks()

func _height(x: float, z: float, detail_noise: FastNoiseLite) -> float:
    var radius := Vector2(x, z).length()
    # Flat physical touchdown corridor; only distant horizons are sculpted.
    var blend := smoothstep(26.0, 53.0, radius)
    var wave := 2.2 + 1.8 * sin(x * 0.07) * cos(z * 0.045)
    return -0.065 + maxf(0.0, wave + detail_noise.get_noise_2d(x, z) * 2.2) * blend

func _create_distant_terrain() -> void:
    var noise := FastNoiseLite.new()
    noise.seed = 45051
    noise.frequency = 0.053
    noise.fractal_octaves = 3
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for zi in range(GRID_SEGMENTS):
        for xi in range(GRID_SEGMENTS):
            var x0 := -TERRAIN_RADIUS + 2.0 * TERRAIN_RADIUS * xi / GRID_SEGMENTS
            var x1 := -TERRAIN_RADIUS + 2.0 * TERRAIN_RADIUS * (xi + 1) / GRID_SEGMENTS
            var z0 := -TERRAIN_RADIUS + 2.0 * TERRAIN_RADIUS * zi / GRID_SEGMENTS
            var z1 := -TERRAIN_RADIUS + 2.0 * TERRAIN_RADIUS * (zi + 1) / GRID_SEGMENTS
            var a := Vector3(x0, _height(x0, z0, noise), z0)
            var b := Vector3(x1, _height(x1, z0, noise), z0)
            var c := Vector3(x0, _height(x0, z1, noise), z1)
            var d := Vector3(x1, _height(x1, z1, noise), z1)
            # Triangle winding produces normals pointed up, away from ground.
            for p in [a, c, b, b, c, d]:
                # Project XZ to a 4m tile; no displacement of Jolt terrain.
                surface.set_uv(Vector2(p.x, p.z) * 0.25)
                surface.add_vertex(p)
    surface.generate_normals()
    var mesh := surface.commit()
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.33, 0.34, 0.36)
    material.roughness = 0.96
    var folder := "res://assets/procedural/regolith"
    if ResourceLoader.exists(folder + "_albedo.png") and ResourceLoader.exists(folder + "_normal.png"):
        material.albedo_texture = load(folder + "_albedo.png") as Texture2D
        material.normal_enabled = true
        material.normal_texture = load(folder + "_normal.png") as Texture2D
        material.normal_scale = 0.55
        material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    var distant := MeshInstance3D.new()
    distant.name = "DistantRegolithVisualOnly"
    distant.mesh = mesh
    distant.material_override = material
    distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(distant)

func _create_rocks() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 10505
    # A single faceted irregular basalt mesh replaces repeated smooth spheres.
    # Keeping it instanced avoids 220 separate draw calls.
    var rock_mesh := _f12_boulder_mesh()
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.34, 0.35, 0.37)
    material.roughness = 0.98
    material.vertex_color_use_as_albedo = true
    rock_mesh.surface_set_material(0, material)
    var placement_noise := FastNoiseLite.new()
    placement_noise.seed = 45051
    placement_noise.frequency = 0.053
    placement_noise.fractal_octaves = 3
    var instances := MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.mesh = rock_mesh
    instances.instance_count = ROCK_COUNT
    for index in range(ROCK_COUNT):
        var angle := rng.randf_range(-PI, PI)
        var radius := sqrt(rng.randf_range(0.0, 1.0)) * 58.0 + 20.0
        var x := cos(angle) * radius
        var z := sin(angle) * radius
        var size := rng.randf_range(0.16, 0.85)
        var rock_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
        rock_basis = rock_basis.scaled(Vector3(size * 1.35, size * 0.65, size))
        # Visual boulders are outside the pad; collision remains the flat ground.
        instances.set_instance_transform(index, Transform3D(rock_basis, Vector3(x, _height(x, z, placement_noise) - 0.14, z)))
    var scatter := MultiMeshInstance3D.new()
    scatter.name = "NonCollidingRockScatter"
    scatter.multimesh = instances
    scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(scatter)


func _f12_boulder_mesh() -> ArrayMesh:
    var rng := RandomNumberGenerator.new()
    rng.seed = 125001
    var mesh := SurfaceTool.new()
    mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
    var rings: Array[PackedVector3Array] = []
    for band in range(6):
        var points := PackedVector3Array()
        var theta: float = 0.08 + (PI * 0.47 - 0.08) * float(band) / 5.0
        for index in range(11):
            var angle: float = TAU * float(index % 10) / 10.0
            var variation: float = rng.randf_range(0.82, 1.17) if index < 10 else 1.0
            # End-of-ring vertex uses first angle; mesh does not need exact UVs.
            points.append(Vector3(cos(angle) * 0.55 * sin(theta) * variation,
                0.70 * cos(theta) * rng.randf_range(0.93, 1.07),
                sin(angle) * 0.47 * sin(theta) * variation))
        rings.append(points)
    for band in range(rings.size() - 1):
        for index in range(10):
            var high_a: Vector3 = rings[band][index]
            var high_b: Vector3 = rings[band][(index + 1) % 10]
            var low_a: Vector3 = rings[band + 1][index]
            var low_b: Vector3 = rings[band + 1][(index + 1) % 10]
            var color := Color(0.85, 0.88, 0.91).lerp(Color(1.0, 1.0, 1.0),
                rng.randf_range(0.0, 1.0))
            for point in [high_a, high_b, low_a, low_a, high_b, low_b]:
                mesh.set_color(color)
                mesh.add_vertex(point)
    mesh.generate_normals()
    return mesh.commit()
