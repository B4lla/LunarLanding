extends Node3D
## F33 — Passive high-fidelity art layer; does not affect RigidBody3D physics.
## Built after the parent F13 pass so obsolete meshes can be safely hidden.
## F05's verified NASA preview hides the parent VisualDetail, including this layer.

const SEGMENTS: int = 32
const HEAT_ALBEDO := preload("res://assets/lander_materials/bell_albedo.png")
const HEAT_NORMAL := preload("res://assets/lander_materials/bell_normal.png")
const HEAT_ROUGHNESS := preload("res://assets/lander_materials/bell_roughness.png")
const PANEL_ALBEDO := preload("res://assets/procedural/gold_foil_albedo.png")
const PANEL_NORMAL := preload("res://assets/procedural/gold_foil_normal.png")
const PANEL_ROUGHNESS := preload("res://assets/procedural/gold_foil_roughness.png")

var _built: bool = false


func build_visuals() -> void:
    if _built or DisplayServer.get_name() == "headless":
        return
    _built = true
    _retire_old_surfaces()
    var bell_exterior: StandardMaterial3D = _pbr(
        Color(0.83, 0.86, 0.87), 0.86, 0.43,
        HEAT_ALBEDO, HEAT_NORMAL, HEAT_ROUGHNESS, 0.52)
    var bell_interior: StandardMaterial3D = _plain(Color(0.078, 0.083, 0.088), 0.48, 0.85)
    var heat_alloy: StandardMaterial3D = _plain(Color(0.34, 0.39, 0.41), 0.80, 0.46)
    var joint: StandardMaterial3D = _plain(Color(0.15, 0.17, 0.18), 0.62, 0.57)
    var foil_light: StandardMaterial3D = _pbr(
        Color(0.84, 0.77, 0.58), 0.67, 0.54,
        PANEL_ALBEDO, PANEL_NORMAL, PANEL_ROUGHNESS, 0.58)
    var foil_dark: StandardMaterial3D = _pbr(
        Color(0.65, 0.57, 0.39), 0.63, 0.64,
        PANEL_ALBEDO, PANEL_NORMAL, PANEL_ROUGHNESS, 0.62)
    _hollow_bell(bell_exterior, bell_interior, heat_alloy)
    _segmented_thermal_blankets(foil_light, foil_dark, joint)
    _cabin_panel_joints(joint)
    _batch_rcs_insets(bell_interior)
    _batch_foot_grip(heat_alloy)


func _retire_old_surfaces() -> void:
    # F20 already supplies trapezoidal glazing. Earlier rectangular panes and
    # the F13 solid bell would otherwise overlap/z-fight with the F33 surfaces.
    var parent_visual: Node3D = get_parent() as Node3D
    if parent_visual == null:
        return
    for name in [
        "LeftWindow", "RightWindow", "LeftWindowBorder", "RightWindowBorder",
        "EngineBellOuter", "EngineBellLip", "DescentNozzleLiner"
    ]:
        var old: MeshInstance3D = parent_visual.get_node_or_null(name) as MeshInstance3D
        if old != null:
            old.visible = false
    var precision: Node3D = parent_visual.get_node_or_null("PrecisionDetailsF20") as Node3D
    if precision != null:
        for name in ["EngineCoolingRing_02", "EngineCoolingRing_03", "EngineExitHeatRim"]:
            var part: MeshInstance3D = precision.get_node_or_null(name) as MeshInstance3D
            if part != null:
                part.visible = false


func _plain(tint: Color, metal: float, rough: float) -> StandardMaterial3D:
    var result: StandardMaterial3D = StandardMaterial3D.new()
    result.albedo_color = tint
    result.metallic = metal
    result.roughness = rough
    return result


func _pbr(tint: Color, metal: float, rough: float, albedo: Texture2D,
        normal: Texture2D, rough_map: Texture2D, normal_power: float) -> StandardMaterial3D:
    var result: StandardMaterial3D = _plain(tint, metal, rough)
    result.albedo_texture = albedo
    result.normal_enabled = true
    result.normal_texture = normal
    result.normal_scale = normal_power
    result.roughness_texture = rough_map
    return result


func _add_vertex(tool: SurfaceTool, point: Vector3, uv: Vector2) -> void:
    tool.set_uv(uv)
    tool.add_vertex(point)


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
        ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, reverse: bool = false) -> void:
    # A-B-C and A-C-D wind outwards for the nozzle's exterior.
    if reverse:
        _add_vertex(tool, a, ua)
        _add_vertex(tool, c, uc)
        _add_vertex(tool, b, ub)
        _add_vertex(tool, a, ua)
        _add_vertex(tool, d, ud)
        _add_vertex(tool, c, uc)
    else:
        _add_vertex(tool, a, ua)
        _add_vertex(tool, b, ub)
        _add_vertex(tool, c, uc)
        _add_vertex(tool, a, ua)
        _add_vertex(tool, c, uc)
        _add_vertex(tool, d, ud)


func _commit_surface(tag: String, tool: SurfaceTool, material: StandardMaterial3D,
        tiny_detail: bool = false) -> MeshInstance3D:
    tool.generate_normals()
    tool.generate_tangents()
    var mesh: ArrayMesh = tool.commit()
    var item: MeshInstance3D = MeshInstance3D.new()
    item.name = tag
    item.mesh = mesh
    item.material_override = material
    item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    if tiny_detail:
        item.visibility_range_end = 45.0
        item.visibility_range_end_margin = 5.0
    add_child(item)
    return item


func _bell_profile() -> Array[Vector2]:
    # x=Y height, y=radius. Geometry lies inside the existing F20 ring envelope.
    return [
        Vector2(-1.035, 0.172), Vector2(-1.085, 0.197),
        Vector2(-1.175, 0.228), Vector2(-1.270, 0.282),
        Vector2(-1.363, 0.344), Vector2(-1.435, 0.385)
    ]


func _revolve(tag: String, profile: Array[Vector2], material: StandardMaterial3D,
        inward: bool) -> void:
    var st: SurfaceTool = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for ring in range(profile.size() - 1):
        var upper: Vector2 = profile[ring]
        var lower: Vector2 = profile[ring + 1]
        for sector in range(SEGMENTS):
            var u0: float = float(sector) / float(SEGMENTS)
            var u1: float = float(sector + 1) / float(SEGMENTS)
            var a: float = TAU * u0
            var b: float = TAU * u1
            var p0: Vector3 = Vector3(cos(a) * upper.y, upper.x, sin(a) * upper.y)
            var p1: Vector3 = Vector3(cos(a) * lower.y, lower.x, sin(a) * lower.y)
            var p2: Vector3 = Vector3(cos(b) * lower.y, lower.x, sin(b) * lower.y)
            var p3: Vector3 = Vector3(cos(b) * upper.y, upper.x, sin(b) * upper.y)
            var v0: float = float(ring) / float(profile.size() - 1)
            var v1: float = float(ring + 1) / float(profile.size() - 1)
            # Order is reversed relative to ascending-Y rings. Correct outward
            # face: A -> next upper -> next lower -> lower.
            _quad(st, p0, p3, p2, p1,
                Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1),
                inward)
    _commit_surface(tag, st, material)


func _hollow_bell(outer: StandardMaterial3D, inner: StandardMaterial3D,
        edging: StandardMaterial3D) -> void:
    var profile: Array[Vector2] = _bell_profile()
    var inner_profile: Array[Vector2] = []
    for part in profile:
        inner_profile.append(Vector2(part.x + 0.001, part.y - 0.024))
    _revolve("F33EngineBellExterior", profile, outer, false)
    _revolve("F33EngineBellInterior", inner_profile, inner, true)
    # Continuous lip bridges the two shells at the exit, without capping the bell.
    var rim: SurfaceTool = SurfaceTool.new()
    rim.begin(Mesh.PRIMITIVE_TRIANGLES)
    var outside: Vector2 = profile[profile.size() - 1]
    var inside: Vector2 = inner_profile[inner_profile.size() - 1]
    for sector in range(SEGMENTS):
        var a0: float = TAU * float(sector) / float(SEGMENTS)
        var a1: float = TAU * float(sector + 1) / float(SEGMENTS)
        var a: Vector3 = Vector3(cos(a0) * outside.y, outside.x, sin(a0) * outside.y)
        var b: Vector3 = Vector3(cos(a1) * outside.y, outside.x, sin(a1) * outside.y)
        var c: Vector3 = Vector3(cos(a1) * inside.y, inside.x, sin(a1) * inside.y)
        var d: Vector3 = Vector3(cos(a0) * inside.y, inside.x, sin(a0) * inside.y)
        _quad(rim, a, b, c, d,
            Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
    _commit_surface("F33EngineExitLip", rim, edging)
    # No interior cap: the plume remains visible through the nozzle opening.


func _segmented_thermal_blankets(gold: StandardMaterial3D,
        weathered: StandardMaterial3D, joint: StandardMaterial3D) -> void:
    # A slightly protruding, faceted 8-panel thermal skirt follows the original
    # eight-sided descent mesh. Gaps between plates reveal the old foil beneath.
    for panel in range(8):
        var t0: float = TAU * (float(panel) + 0.07) / 8.0
        var t1: float = TAU * (float(panel) + 0.93) / 8.0
        var top_y: float = -0.388
        var bot_y: float = -0.778
        var radial: float = 0.815
        var upper_a: Vector3 = Vector3(radial * cos(t0), top_y, radial * sin(t0))
        var upper_b: Vector3 = Vector3(radial * cos(t1), top_y, radial * sin(t1))
        var lower_b: Vector3 = Vector3(radial * cos(t1), bot_y, radial * sin(t1))
        var lower_a: Vector3 = Vector3(radial * cos(t0), bot_y, radial * sin(t0))
        var st: SurfaceTool = SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        _quad(st, upper_a, upper_b, lower_b, lower_a,
            Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), false)
        _commit_surface("F33ThermalPanel_%02d" % panel,
            st, gold if panel % 3 != 0 else weathered)
        # 8 discrete seam retainers, not a continuous second cylinder.
        _beam("F33BlanketClip_%02d" % panel,
            upper_a.lerp(upper_b, 0.5), lower_a.lerp(lower_b, 0.5),
            0.006, joint)


func _cabin_panel_joints(joint: StandardMaterial3D) -> void:
    # Quiet, structural seams instead of more bright equipment floating on top.
    for index in range(8):
        var theta: float = TAU * (float(index) + 0.5) / 8.0
        var axis: Vector3 = Vector3(cos(theta), 0.0, sin(theta))
        _beam("F33CabinSeam_%02d" % index,
            axis * 0.649 + Vector3(0, 0.875, 0),
            axis * 0.568 + Vector3(0, 1.398, 0),
            0.006, joint)


func _beam(label: String, start: Vector3, finish: Vector3, radius: float,
        material: StandardMaterial3D) -> void:
    var delta: Vector3 = finish - start
    if delta.length_squared() <= 0.000001:
        return
    var shape: CylinderMesh = CylinderMesh.new()
    shape.top_radius = radius
    shape.bottom_radius = radius
    shape.height = delta.length()
    shape.radial_segments = 6
    var item: MeshInstance3D = MeshInstance3D.new()
    item.name = label
    item.mesh = shape
    item.material_override = material
    item.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())),
        (start + finish) * 0.5)
    item.visibility_range_end = 35.0
    item.visibility_range_end_margin = 5.0
    add_child(item)


func _batch_rcs_insets(dark: StandardMaterial3D) -> void:
    # Four F20 pods x four outlets; recessed black circular apertures replace
    # the toy-like flat solid rectangles, without redirecting or firing gas.
    var mouth: CylinderMesh = CylinderMesh.new()
    mouth.top_radius = 0.026
    mouth.bottom_radius = 0.026
    mouth.height = 0.004
    mouth.radial_segments = 12
    var batch: MultiMesh = MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.mesh = mouth
    batch.instance_count = 16
    var n: int = 0
    for face in range(4):
        var theta: float = float(face) * PI * 0.5
        var turn: Basis = Basis(Vector3.UP, theta)
        var pointing: Basis = turn * Basis(Vector3.RIGHT, PI * 0.5)
        for nozzle in range(4):
            var x: float = -0.072 if nozzle % 2 == 0 else 0.072
            var y: float = -0.058 if nozzle < 2 else 0.058
            var center: Vector3 = turn * Vector3(x, y + 0.95, -0.945)
            batch.set_instance_transform(n, Transform3D(pointing, center))
            n += 1
    var group: MultiMeshInstance3D = MultiMeshInstance3D.new()
    group.name = "F33RecessedRCSPorts"
    group.multimesh = batch
    group.material_override = dark
    group.visibility_range_end = 38.0
    group.visibility_range_end_margin = 5.0
    add_child(group)
    # Metal rim exists in F20; an extra annulus would overlap it.


func _batch_foot_grip(alloy: StandardMaterial3D) -> void:
    # Non-physical shallow top-side ribs on each original fixed-position foot.
    var rib: BoxMesh = BoxMesh.new()
    rib.size = Vector3(0.08, 0.018, 0.025)
    var instances: MultiMesh = MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.mesh = rib
    instances.instance_count = 32
    var n: int = 0
    for corner in range(4):
        var sx: float = -1.0 if corner % 2 == 0 else 1.0
        var sz: float = -1.0 if corner < 2 else 1.0
        var foot: Vector3 = Vector3(sx * 1.05, -1.475, sz * 1.05)
        for spoke in range(8):
            var theta: float = TAU * float(spoke) / 8.0
            var local: Vector3 = Vector3(cos(theta) * 0.33, 0.0, sin(theta) * 0.33)
            instances.set_instance_transform(n, Transform3D(
                Basis(Vector3.UP, -theta), foot + local))
            n += 1
    var details: MultiMeshInstance3D = MultiMeshInstance3D.new()
    details.name = "F33FootpadRadialGrips"
    details.multimesh = instances
    details.material_override = alloy
    details.visibility_range_end = 35.0
    details.visibility_range_end_margin = 5.0
    add_child(details)
