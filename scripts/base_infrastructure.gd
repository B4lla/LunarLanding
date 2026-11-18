extends Node3D
## F30: independent, render-only spaceport infrastructure. No collision or gameplay.
## All raised hardware is beyond the central landing pad and approach apron.
## Headless/TCP training never instantiates these decorative render resources.

const BASE_SAFE_RADIUS: float = 14.0
const PAINT_Y: float = 0.024


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var housing: StandardMaterial3D = _surface(Color(0.38, 0.41, 0.43), 0.16, 0.74)
    var frame: StandardMaterial3D = _surface(Color(0.16, 0.20, 0.24), 0.42, 0.58)
    var pipe: StandardMaterial3D = _surface(Color(0.53, 0.56, 0.59), 0.62, 0.32)
    var hazard: StandardMaterial3D = _surface(Color(0.94, 0.62, 0.19), 0.08, 0.78)
    var markings: StandardMaterial3D = _surface(Color(0.75, 0.81, 0.82), 0.02, 0.91)
    var glass: StandardMaterial3D = _surface(Color(0.11, 0.21, 0.31), 0.19, 0.27)
    var lens: StandardMaterial3D = _emissive(Color(0.49, 0.77, 1.0), 0.92)
    _tank_farms(housing, frame, pipe, hazard)
    _utility_kiosks(housing, frame, glass, hazard)
    _pipe_manifolds(pipe, frame, hazard)
    _work_lights(frame, lens, hazard)
    _ground_guidance(markings, hazard)
    _service_drain_grates(frame)
    _base_labels(markings)


func _surface(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.metallic = metallic
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
    var mat := _surface(color, 0.02, 0.44)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = energy
    return mat


func _box(label: String, center: Vector3, dimensions: Vector3,
        material: StandardMaterial3D, shadow: bool = true) -> void:
    if not _outside_safe(center, label):
        return
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = center
    node.material_override = material
    node.visibility_range_end = 125.0
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)


func _cylinder(label: String, center: Vector3, radius: float, length: float,
        material: StandardMaterial3D, segments: int = 12) -> void:
    if not _outside_safe(center, label):
        return
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = length
    mesh.radial_segments = segments
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = center
    node.material_override = material
    node.visibility_range_end = 125.0
    add_child(node)


func _pipe_between(label: String, start: Vector3, finish: Vector3, radius: float,
        material: StandardMaterial3D) -> void:
    var displacement: Vector3 = finish - start
    var length: float = displacement.length()
    if length < 0.05:
        return
    var segment: Vector2 = Vector2(displacement.x, displacement.z)
    var planar_start: Vector2 = Vector2(start.x, start.z)
    var fraction: float = clampf(-planar_start.dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
    var closest: Vector2 = planar_start + segment * fraction
    if closest.length() < BASE_SAFE_RADIUS:
        push_error("F30 pipe would enter reserved landing footprint: " + label)
        return
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = length
    mesh.radial_segments = 10
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = (start + finish) * 0.5
    node.quaternion = Quaternion(Vector3.UP, displacement / length)
    node.material_override = material
    node.visibility_range_end = 125.0
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)


func _outside_safe(location: Vector3, label: String) -> bool:
    if Vector2(location.x, location.z).length() >= BASE_SAFE_RADIUS:
        return true
    push_error("F30 decoration would enter landing footprint: " + label)
    return false


func _tank_farms(housing: StandardMaterial3D, frame: StandardMaterial3D,
        pipe: StandardMaterial3D, hazard: StandardMaterial3D) -> void:
    # Service tanks in four side yards, never on the actual 12x12 touchdown slab.
    var yards: Array[Vector3] = [
        Vector3(-30.5, 0, -14.5), Vector3(30.5, 0, 14.5),
        Vector3(-14.5, 0, 30.5), Vector3(14.5, 0, -30.5),
    ]
    for yard_index in range(yards.size()):
        var origin: Vector3 = yards[yard_index]
        var along_x: bool = absf(origin.x) > absf(origin.z)
        _box("TankFoundation_%d" % yard_index, origin + Vector3(0, 0.08, 0),
            Vector3(5.3, 0.16, 4.8), frame)
        for tank_index in range(2):
            var offset: float = -1.35 + 2.70 * float(tank_index)
            var at: Vector3 = origin + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
            _cylinder("TankVessel_%d_%d" % [yard_index, tank_index],
                at + Vector3(0, 0.96, 0), 0.86, 1.75, housing, 20)
            _cylinder("TankTopBand_%d_%d" % [yard_index, tank_index],
                at + Vector3(0, 1.80, 0), 0.91, 0.09, frame, 20)
            _cylinder("TankFootBand_%d_%d" % [yard_index, tank_index],
                at + Vector3(0, 0.18, 0), 0.94, 0.13, frame, 20)
            _cylinder("TankTopValve_%d_%d" % [yard_index, tank_index],
                at + Vector3(0, 1.97, 0), 0.18, 0.21, hazard, 10)
            var tap: Vector3 = at + Vector3(0, 0.48, 0.93)
            _pipe_between("TankOutlet_%d_%d" % [yard_index, tank_index],
                tap, tap + Vector3(0, 0, 0.42), 0.075, pipe)
        # A low manifold joins the pair; no fake working pipes across the pad.
        var manifold_origin: Vector3 = origin + Vector3(0, 0.31, 2.35)
        var span: Vector3 = Vector3(2.15, 0, 0) if along_x else Vector3(0, 0, 2.15)
        _pipe_between("TankManifold_%d" % yard_index,
            manifold_origin - span, manifold_origin + span, 0.10, pipe)


func _utility_kiosks(housing: StandardMaterial3D, frame: StandardMaterial3D,
        glass: StandardMaterial3D, hazard: StandardMaterial3D) -> void:
    var kiosks: Array[Vector3] = [Vector3(-28.0, 0, 3.0), Vector3(28.0, 0, -3.0),
        Vector3(3.0, 0, 28.0), Vector3(-3.0, 0, -28.0)]
    for idx in range(kiosks.size()):
        var pos: Vector3 = kiosks[idx]
        var name: String = "PowerKiosk_%02d" % idx
        _box(name, pos + Vector3(0, 0.85, 0), Vector3(2.65, 1.66, 1.65), housing)
        _box(name + "_Cap", pos + Vector3(0, 1.72, 0), Vector3(2.82, 0.13, 1.81), frame)
        _box(name + "_Screen", pos + Vector3(0, 1.10, -0.849),
            Vector3(1.35, 0.54, 0.035), glass, false)
        _box(name + "_Alert", pos + Vector3(0, 0.46, -0.855),
            Vector3(1.56, 0.085, 0.04), hazard, false)
        for vent in range(3):
            _box(name + "_Vent%d" % vent,
                pos + Vector3(-0.75 + float(vent) * 0.75, 0.43, 0.84),
                Vector3(0.38, 0.22, 0.035), frame, false)


func _pipe_manifolds(pipe: StandardMaterial3D, frame: StandardMaterial3D,
        hazard: StandardMaterial3D) -> void:
    # Bends around the outer service lots; avoids creating bridges over landing.
    var routes: Array = [
        [Vector3(-29.0, 0.30, -8.0), Vector3(-27.0, 0.30, -8.0), Vector3(-27.0, 0.30, -3.2)],
        [Vector3(29.0, 0.30, 8.0), Vector3(27.0, 0.30, 8.0), Vector3(27.0, 0.30, 3.2)],
        [Vector3(-8.0, 0.30, 29.0), Vector3(-8.0, 0.30, 27.0), Vector3(-3.2, 0.30, 27.0)],
        [Vector3(8.0, 0.30, -29.0), Vector3(8.0, 0.30, -27.0), Vector3(3.2, 0.30, -27.0)],
    ]
    for idx in range(routes.size()):
        var route: Array = routes[idx]
        var a: Vector3 = route[0]
        var bend: Vector3 = route[1]
        var c: Vector3 = route[2]
        _pipe_between("UtilityPipeA_%d" % idx, a, bend, 0.092, pipe)
        _pipe_between("UtilityPipeB_%d" % idx, bend, c, 0.092, pipe)
        _cylinder("UtilityValve_%d" % idx, bend + Vector3(0, 0.12, 0), 0.18, 0.15, hazard, 10)
        _box("UtilityPipeStand_%d" % idx, (bend + c) * 0.5 - Vector3(0, 0.14, 0),
            Vector3(0.30, 0.28, 0.30), frame)


func _work_lights(frame: StandardMaterial3D, lens: StandardMaterial3D,
        hazard: StandardMaterial3D) -> void:
    # Explicitly emissive fixtures: NOT expensive shadow-casting dynamic lights.
    var lights: Array[Vector3] = [
        Vector3(-29, 0, -25), Vector3(29, 0, 25),
        Vector3(25, 0, -29), Vector3(-25, 0, 29),
    ]
    for idx in range(lights.size()):
        var pos: Vector3 = lights[idx]
        _cylinder("FloodlightMast_%d" % idx, pos + Vector3(0, 1.80, 0),
            0.075, 3.60, frame, 10)
        _box("FloodlightBar_%d" % idx, pos + Vector3(0, 3.64, 0),
            Vector3(1.55, 0.12, 0.18), frame)
        for side in [-1.0, 1.0]:
            var suffix: String = "%d_%d" % [idx, int(side)]
            _box("FloodlightLens_" + suffix,
                pos + Vector3(0.41 * side, 3.58, -0.13),
                Vector3(0.49, 0.25, 0.07), lens, false)
        _box("FloodlightHazard_%d" % idx, pos + Vector3(0, 0.34, -0.08),
            Vector3(0.21, 0.19, 0.16), hazard, false)


func _ground_guidance(markings: StandardMaterial3D,
        hazard: StandardMaterial3D) -> void:
    # Directional approach/service paint, all below the actual landing top.
    var strip := BoxMesh.new()
    strip.size = Vector3(0.13, 0.006, 0.76)
    strip.material = markings
    var dashes := MultiMesh.new()
    dashes.transform_format = MultiMesh.TRANSFORM_3D
    dashes.mesh = strip
    dashes.instance_count = 32
    var write: int = 0
    for side in [-1.0, 1.0]:
        for segment in range(8):
            var distance: float = 22.0 + float(segment) * 1.68
            for axis in range(2):
                var position: Vector3 = (Vector3(0, PAINT_Y, distance * side)
                    if axis == 0 else Vector3(distance * side, PAINT_Y, 0))
                var turn: float = 0.0 if axis == 0 else PI * 0.5
                dashes.set_instance_transform(write, Transform3D(Basis(Vector3.UP, turn), position))
                write += 1
    _instances("ServiceLaneDashes", dashes)
    var band := BoxMesh.new()
    band.size = Vector3(0.45, 0.008, 1.60)
    band.material = hazard
    var markers := MultiMesh.new()
    markers.transform_format = MultiMesh.TRANSFORM_3D
    markers.mesh = band
    markers.instance_count = 16
    write = 0
    for side in [-1.0, 1.0]:
        for offset_idx in range(4):
            var at: float = 22.0 + float(offset_idx) * 3.6
            for axis in range(2):
                var position: Vector3 = (Vector3(1.65 * side, PAINT_Y, at * side)
                    if axis == 0 else Vector3(at * side, PAINT_Y, -1.65 * side))
                var turn: float = 0.0 if axis == 0 else PI * 0.5
                markers.set_instance_transform(write, Transform3D(Basis(Vector3.UP, turn), position))
                write += 1
    _instances("ServiceSafetyBands", markers)


func _service_drain_grates(frame: StandardMaterial3D) -> void:
    # 56 cast-iron panels share a single Mesh resource and draw submission.
    var grate := BoxMesh.new()
    grate.size = Vector3(0.54, 0.022, 0.10)
    grate.material = frame
    var drains := MultiMesh.new()
    drains.transform_format = MultiMesh.TRANSFORM_3D
    drains.mesh = grate
    drains.instance_count = 56
    var write: int = 0
    for side in [-1.0, 1.0]:
        for idx in range(7):
            var length: float = 15.0 + float(idx) * 2.1
            for parallel in [-1.0, 1.0]:
                drains.set_instance_transform(write, Transform3D(Basis.IDENTITY,
                    Vector3(5.2 * parallel, PAINT_Y, length * side)))
                write += 1
                drains.set_instance_transform(write, Transform3D(Basis(Vector3.UP, PI * 0.5),
                    Vector3(length * side, PAINT_Y, 5.2 * parallel)))
                write += 1
    _instances("ServiceDrainGrates", drains)


func _base_labels(material: StandardMaterial3D) -> void:
    # Flat, physically occluded 3D lettering on hab roofs; never a HUD overlay.
    var labels: Array = [
        ["HAB - 01", Vector3(0, 1.91, -18.2)],
        ["HAB - 02", Vector3(0, 1.91, 18.2)],
        ["POWER", Vector3(-18.2, 1.91, 0)],
        ["COMMS", Vector3(18.2, 1.91, 0)],
    ]
    for idx in range(labels.size()):
        var item: Array = labels[idx]
        var tag := Label3D.new()
        tag.name = "RoofIdentifier_%d" % idx
        tag.text = str(item[0])
        tag.font_size = 36
        tag.pixel_size = 0.008
        tag.modulate = material.albedo_color
        tag.position = item[1]
        tag.rotation_degrees = Vector3(-90, 0, 0)
        tag.no_depth_test = false
        if _outside_safe(tag.position, str(tag.name)):
            add_child(tag)


func _instances(label: String, group: MultiMesh) -> void:
    for index in range(group.instance_count):
        var location: Vector3 = group.get_instance_transform(index).origin
        if not _outside_safe(location, label):
            return
    var node := MultiMeshInstance3D.new()
    node.name = label
    node.multimesh = group
    node.visibility_range_end = 135.0
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)
