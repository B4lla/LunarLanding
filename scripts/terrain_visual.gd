extends Node3D
## F05/F27 render-only material selection and base-ground dressing. NEVER change
## StaticBody3D/colliders. The ground becomes more legible and the landing area
## blends into a larger space-base context without affecting physics.

const TEXTURE_ROOT := "res://assets/polyhaven/"
const TEXTURE_BASE := "rocks_ground_01_"
const RECEIPT_PATH := "res://assets/polyhaven/download_receipt.json"
const FALLBACK_SHADER: Shader = preload("res://assets/materials/regolith_fallback.gdshader")
const DECAL_Y := 0.012


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _configure_f12_platform()
    var mesh_node := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
    if mesh_node == null:
        push_error("F05: missing ground visual; unchanged collider preserved")
        return
    var diffuse := TEXTURE_ROOT + TEXTURE_BASE + "diff_1k.jpg"
    var normal := TEXTURE_ROOT + TEXTURE_BASE + "nor_gl_1k.png"
    var rough := TEXTURE_ROOT + TEXTURE_BASE + "rough_1k.jpg"
    var paths: Array[String] = [diffuse, normal, rough]
    if _are_downloads_verified(paths) and ResourceLoader.exists(diffuse) and ResourceLoader.exists(normal) and ResourceLoader.exists(rough):
        var color_map: Texture2D = load(diffuse) as Texture2D
        var normal_map: Texture2D = load(normal) as Texture2D
        var rough_map: Texture2D = load(rough) as Texture2D
        if color_map != null and normal_map != null and rough_map != null:
            var material := StandardMaterial3D.new()
            material.albedo_texture = color_map
            material.normal_enabled = true
            material.normal_texture = normal_map
            material.normal_scale = 1.08
            material.roughness_texture = rough_map
            material.roughness = 1.0
            material.metallic = 0.0
            # Preserve F14 desktop stability; mobile reduces UV frequency.
            material.uv1_scale = Vector3(48.0, 48.0, 1.0)
            if OS.has_feature("mobile"):
                material.uv1_scale = Vector3(34.0, 34.0, 1.0)
            material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
            mesh_node.material_override = material
            print("F05/F27 PBR PASS: SHA-256 verified CC0 terrain maps loaded")
        else:
            _use_fallback(mesh_node)
    else:
        _use_fallback(mesh_node)
    _add_compacted_regolith_apron()
    _add_service_paths()
    _add_base_zones()
    _add_distant_terrain_relief()


func _are_downloads_verified(paths: Array[String]) -> bool:
    if not FileAccess.file_exists(RECEIPT_PATH):
        return false
    var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH))
    if not receipt is Array or receipt.size() != paths.size():
        return false
    for path in paths:
        if not FileAccess.file_exists(path):
            return false
        var found := false
        for entry in receipt:
            if not entry is Dictionary:
                return false
            if entry.get("file") != path.trim_prefix("res://"):
                continue
            if found or entry.get("status") != "OK":
                return false
            var origin: String = str(entry.get("url", ""))
            if not origin.begins_with("https://dl.polyhaven.org/file/ph-assets/Textures/"):
                return false
            if not origin.ends_with("/" + path.get_file()):
                return false
            if typeof(entry.get("size_bytes")) != TYPE_INT:
                return false
            if FileAccess.get_file_as_bytes(path).size() != int(entry.get("size_bytes")):
                return false
            if FileAccess.get_sha256(path) != str(entry.get("sha256", "")):
                return false
            found = true
        if not found:
            return false
    return true


func _use_fallback(mesh_node: MeshInstance3D) -> void:
    # F12 locally baked, tileable and normal-mapped fallback ships inside the PCK.
    # The older shader remains the last resort if a source map is missing.
    var baked := _f34_ground_material()
    if baked != null:
        baked.uv1_scale = Vector3(18.0, 18.0, 1.0)
        mesh_node.material_override = baked
        return
    baked = _f28_ground_material()
    if baked != null:
        baked.uv1_scale = Vector3(18.0, 18.0, 1.0)
        mesh_node.material_override = baked
        return
    baked = _f12_baked_material("regolith", 0.0, 0.98, 1.10)
    if baked != null:
        baked.uv1_scale = Vector3(28.0, 28.0, 1.0)
        if not OS.has_feature("mobile"):
            baked.uv1_scale = Vector3(22.0, 22.0, 1.0)
        mesh_node.material_override = baked
        return
    var material := ShaderMaterial.new()
    material.shader = FALLBACK_SHADER
    mesh_node.material_override = material


func _f34_ground_material() -> StandardMaterial3D:
    var root: String = "res://assets/terrain_materials/regolith_"
    for channel in ["albedo", "normal", "roughness"]:
        if not ResourceLoader.exists(root + channel + ".png"):
            return null
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_texture = load(root + "albedo.png") as Texture2D
    mat.normal_enabled = true
    mat.normal_texture = load(root + "normal.png") as Texture2D
    mat.normal_scale = 0.80
    mat.roughness_texture = load(root + "roughness.png") as Texture2D
    mat.roughness = 0.98
    mat.metallic = 0.0
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return mat


func _f28_ground_material() -> StandardMaterial3D:
    var root: String = "res://assets/base_materials/lunar_regolith_"
    for channel in ["albedo", "normal", "roughness"]:
        if not ResourceLoader.exists(root + channel + ".png"):
            return null
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = load(root + "albedo.png") as Texture2D
    mat.normal_enabled = true
    mat.normal_texture = load(root + "normal.png") as Texture2D
    mat.normal_scale = 0.93
    mat.roughness_texture = load(root + "roughness.png") as Texture2D
    mat.roughness = 0.98
    mat.metallic = 0.0
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return mat


func _configure_f12_platform() -> void:
    var platform := get_node_or_null("LandingPlatform/MeshInstance3D") as MeshInstance3D
    if platform == null:
        return
    var baked: StandardMaterial3D = _f34_deck_material()
    if baked == null:
        baked = _f12_baked_material("deck", 0.18, 0.90, 0.54)
    if baked == null:
        return
    baked.uv1_scale = Vector3(2.35, 2.35, 1.0)  # Keep physical 12 x 12 m deck legible.
    platform.material_override = baked


func _f34_deck_material() -> StandardMaterial3D:
    var root: String = "res://assets/terrain_materials/pad_deck_"
    for channel in ["albedo", "normal", "roughness"]:
        if not ResourceLoader.exists(root + channel + ".png"):
            return null
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_texture = load(root + "albedo.png") as Texture2D
    mat.normal_texture = load(root + "normal.png") as Texture2D
    mat.normal_enabled = true
    mat.normal_scale = 0.59
    mat.roughness_texture = load(root + "roughness.png") as Texture2D
    mat.roughness = 0.79
    mat.metallic = 0.28
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return mat


func _f12_baked_material(key: String, metallic: float, roughness: float,
        normal_depth: float) -> StandardMaterial3D:
    var root := "res://assets/procedural/" + key
    var diffuse := root + "_albedo.png"
    var normal := root + "_normal.png"
    var rough := root + "_roughness.png"
    if not ResourceLoader.exists(diffuse) or not ResourceLoader.exists(normal) or not ResourceLoader.exists(rough):
        return null
    var result := StandardMaterial3D.new()
    result.albedo_texture = load(diffuse) as Texture2D
    result.normal_enabled = true
    result.normal_texture = load(normal) as Texture2D
    result.normal_scale = normal_depth
    result.roughness_texture = load(rough) as Texture2D
    result.metallic = metallic
    result.roughness = roughness
    result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    result.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
    return result


func _add_compacted_regolith_apron() -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var radii := [8.5, 12.0, 18.0, 26.0]
    var shades := [0.34, 0.31, 0.28, 0.25]
    var alphas := [0.00, 0.18, 0.12, 0.00]
    for band in range(radii.size() - 1):
        for slice in range(72):
            var a: float = TAU * float(slice) / 72.0
            var b: float = TAU * float(slice + 1) / 72.0
            var inner_a := Vector3(cos(a) * radii[band], DECAL_Y, sin(a) * radii[band])
            var inner_b := Vector3(cos(b) * radii[band], DECAL_Y, sin(b) * radii[band])
            var outer_a := Vector3(cos(a) * radii[band + 1], DECAL_Y, sin(a) * radii[band + 1])
            var outer_b := Vector3(cos(b) * radii[band + 1], DECAL_Y, sin(b) * radii[band + 1])
            _decal_triangle(surface, inner_a, outer_a, inner_b, shades[band], alphas[band], alphas[band + 1], alphas[band])
            _decal_triangle(surface, inner_b, outer_a, outer_b, shades[band], alphas[band], alphas[band + 1], alphas[band + 1])
    var apron := MeshInstance3D.new()
    apron.name = "CompactedRegolithApron"
    apron.mesh = surface.commit()
    apron.material_override = _decal_material()
    apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    apron.visibility_range_end = 150.0
    add_child(apron)


func _add_service_paths() -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var path_width := 2.4
    var path_length := 28.0
    for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
        var dir := Vector2(cos(angle), sin(angle))
        var right := Vector2(-dir.y, dir.x)
        var start := dir * 6.4
        var finish := dir * path_length
        var v0 := Vector3(start.x + right.x * path_width * 0.5, DECAL_Y + 0.001, start.y + right.y * path_width * 0.5)
        var v1 := Vector3(start.x - right.x * path_width * 0.5, DECAL_Y + 0.001, start.y - right.y * path_width * 0.5)
        var v2 := Vector3(finish.x + right.x * path_width * 0.7, DECAL_Y + 0.001, finish.y + right.y * path_width * 0.7)
        var v3 := Vector3(finish.x - right.x * path_width * 0.7, DECAL_Y + 0.001, finish.y - right.y * path_width * 0.7)
        _decal_triangle(surface, v0, v2, v1, 0.22, 0.18, 0.0, 0.18)
        _decal_triangle(surface, v1, v2, v3, 0.22, 0.18, 0.0, 0.0)
    var lanes := MeshInstance3D.new()
    lanes.name = "BaseServicePaths"
    lanes.mesh = surface.commit()
    lanes.material_override = _decal_material()
    lanes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    lanes.visibility_range_end = 170.0
    add_child(lanes)


func _add_base_zones() -> void:
    var guide := _zone_material(Color(0.34, 0.37, 0.40), 0.94)
    var accent := _zone_material(Color(0.56, 0.48, 0.22), 0.85)
    _zone_strip("BaseZoneNorth", Vector3(0, DECAL_Y + 0.002, -20.0), Vector3(18.0, 0.008, 4.0), 0.0, guide)
    _zone_strip("BaseZoneSouth", Vector3(0, DECAL_Y + 0.002, 20.0), Vector3(18.0, 0.008, 4.0), 0.0, guide)
    _zone_strip("BaseZoneWest", Vector3(-20.0, DECAL_Y + 0.002, 0), Vector3(4.0, 0.008, 18.0), 0.0, guide)
    _zone_strip("BaseZoneEast", Vector3(20.0, DECAL_Y + 0.002, 0), Vector3(4.0, 0.008, 18.0), 0.0, guide)
    for side in [-1.0, 1.0]:
        _zone_strip("HazardNorth_%d" % int(side), Vector3(3.8 * side, DECAL_Y + 0.003, -20.0), Vector3(1.9, 0.008, 0.20), 0.65, accent)
        _zone_strip("HazardSouth_%d" % int(side), Vector3(3.8 * side, DECAL_Y + 0.003, 20.0), Vector3(1.9, 0.008, 0.20), -0.65, accent)
        _zone_strip("HazardWest_%d" % int(side), Vector3(-20.0, DECAL_Y + 0.003, 3.8 * side), Vector3(0.20, 0.008, 1.9), 0.65, accent)
        _zone_strip("HazardEast_%d" % int(side), Vector3(20.0, DECAL_Y + 0.003, 3.8 * side), Vector3(0.20, 0.008, 1.9), -0.65, accent)


func _decal_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
        shade: float, alpha_a: float, alpha_b: float, alpha_c: float) -> void:
    surface.set_color(Color(shade, shade * 1.02, shade * 1.05, alpha_a))
    surface.add_vertex(a)
    surface.set_color(Color(shade, shade * 1.02, shade * 1.05, alpha_b))
    surface.add_vertex(b)
    surface.set_color(Color(shade, shade * 1.02, shade * 1.05, alpha_c))
    surface.add_vertex(c)


func _decal_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
    mat.vertex_color_use_as_albedo = true
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
    return mat


func _zone_material(color: Color, roughness: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat


func _zone_strip(label: String, at: Vector3, dimensions: Vector3, spin: float,
        material: StandardMaterial3D) -> void:
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = at
    node.rotation.y = spin
    node.material_override = material
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)


func _add_distant_terrain_relief() -> void:
    # Instanced silhouette berms beyond service radius. Visual only, no physical
    # craters or obstructing geometry near the autopilot touchdown footprint.
    var boulder := SphereMesh.new()
    boulder.radius = 1.0
    boulder.height = 2.0
    boulder.radial_segments = 7
    boulder.rings = 4
    var lunar := _f28_ground_material()
    if lunar != null:
        lunar.uv1_scale = Vector3(0.48, 0.48, 1.0)
        boulder.material = lunar
    else:
        boulder.material = _zone_material(Color(0.27, 0.28, 0.30), 0.99)
    var rng := RandomNumberGenerator.new()
    rng.seed = 280910
    var instances := MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.mesh = boulder
    instances.instance_count = 68
    for index in range(instances.instance_count):
        var angle: float = rng.randf_range(0.0, TAU)
        var radius: float = rng.randf_range(38.0, 74.0)
        var sx: float = rng.randf_range(0.65, 2.8)
        var sy: float = rng.randf_range(0.12, 0.55)
        var sz: float = rng.randf_range(0.7, 3.4)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
        basis = basis.scaled(Vector3(sx, sy, sz))
        var location := Vector3(cos(angle) * radius, -0.12, sin(angle) * radius)
        instances.set_instance_transform(index, Transform3D(basis, location))
    var relief := MultiMeshInstance3D.new()
    relief.name = "DistantRegolithReliefInstanced"
    relief.multimesh = instances
    relief.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    relief.visibility_range_end = 165.0
    add_child(relief)
