extends Node3D
## F20 — High-detail *visual-only* lunar lander pass.
## Child of VisualDetail: optional NASA preview hides the whole procedural model.
## All geometry is a passive MeshInstance3D / MultiMeshInstance3D; no collision,
## movement, thrust, or physics values are created or changed here.

var alloy: StandardMaterial3D
var gunmetal: StandardMaterial3D
var dark: StandardMaterial3D
var brass: StandardMaterial3D
var insulation: StandardMaterial3D
var ceramic: StandardMaterial3D
var glass: StandardMaterial3D
var marking: StandardMaterial3D


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    alloy = _material(Color(0.55, 0.61, 0.64), 0.82, 0.31)
    gunmetal = _material(Color(0.25, 0.29, 0.32), 0.78, 0.40)
    dark = _material(Color(0.065, 0.077, 0.086), 0.33, 0.58)
    brass = _material(Color(0.64, 0.43, 0.18), 0.81, 0.33)
    insulation = _material(Color(0.80, 0.58, 0.22), 0.62, 0.51)
    ceramic = _material(Color(0.77, 0.80, 0.78), 0.12, 0.66)
    glass = _material(Color(0.012, 0.028, 0.044), 0.12, 0.105)
    marking = _material(Color(0.90, 0.48, 0.11), 0.15, 0.54)
    _descent_frame()
    _precision_landing_gear()
    _ascent_cabin()
    _engine_and_feeds()
    _avionics_and_rcs()
    _antennae_and_sensors()
    _batch_fasteners()


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.metallic = metallic
    result.roughness = roughness
    return result


func _beam(tag: String, point_a: Vector3, point_b: Vector3, radius: float,
        mat: StandardMaterial3D, sides: int = 10) -> void:
    var direction := point_b - point_a
    if direction.length_squared() < 0.000001:
        return
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = direction.length()
    cylinder.radial_segments = sides
    var item := MeshInstance3D.new()
    item.name = tag
    item.mesh = cylinder
    item.material_override = mat
    item.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())),
        (point_a + point_b) * 0.5)
    add_child(item)


func _solid(tag: String, center: Vector3, size: Vector3,
        mat: StandardMaterial3D, yaw: float = 0.0) -> void:
    var shape := BoxMesh.new()
    shape.size = size
    var item := MeshInstance3D.new()
    item.name = tag
    item.mesh = shape
    item.position = center
    item.rotation.y = yaw
    item.material_override = mat
    add_child(item)


func _collar(tag: String, center: Vector3, radius: float, thickness: float,
        mat: StandardMaterial3D) -> void:
    var shape := TorusMesh.new()
    shape.inner_radius = maxf(0.001, radius - thickness)
    shape.outer_radius = radius
    shape.rings = 14
    shape.ring_segments = 20
    var item := MeshInstance3D.new()
    item.name = tag
    item.mesh = shape
    item.position = center
    item.material_override = mat
    add_child(item)


func _pipe(tag: String, waypoints: Array[Vector3], width: float,
        mat: StandardMaterial3D) -> void:
    for i in range(waypoints.size() - 1):
        _beam("%s_%02d" % [tag, i], waypoints[i], waypoints[i + 1], width, mat, 8)


func _front_polygon(tag: String, vertices: PackedVector3Array,
        mat: StandardMaterial3D) -> void:
    # Quadrilateral triangulated in front-face winding, facing -Z.
    var normal := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalized()
    var corners := PackedVector3Array([
        vertices[0], vertices[1], vertices[2],
        vertices[0], vertices[2], vertices[3]
    ])
    var normals := PackedVector3Array([normal, normal, normal, normal, normal, normal])
    var surface: Array = []
    surface.resize(Mesh.ARRAY_MAX)
    surface[Mesh.ARRAY_VERTEX] = corners
    surface[Mesh.ARRAY_NORMAL] = normals
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
    var item := MeshInstance3D.new()
    item.name = tag
    item.mesh = mesh
    item.material_override = mat
    add_child(item)


func _descent_frame() -> void:
    # Visible bolted truss at the ascent/descent interface, instead of an
    # uninterrupted stack of cylinders. Front = -Z.
    for side in [-1.0, 1.0]:
        var x: float = float(side) * 0.76
        _beam("DeckFrontRail_%d" % int(side), Vector3(x, -0.25, -0.75),
            Vector3(x, -0.96, -0.75), 0.025, alloy)
        _beam("DeckRearRail_%d" % int(side), Vector3(x, -0.25, 0.75),
            Vector3(x, -0.96, 0.75), 0.025, alloy)
    for face in [-1.0, 1.0]:
        var z: float = float(face) * 0.77
        _beam("DeckTop_%d" % int(face), Vector3(-0.77, -0.26, z),
            Vector3(0.77, -0.26, z), 0.035, gunmetal)
        _beam("DeckSill_%d" % int(face), Vector3(-0.77, -0.93, z),
            Vector3(0.77, -0.93, z), 0.030, gunmetal)
        for side in [-1.0, 1.0]:
            var x: float = float(side) * 0.67
            _beam("DeckDiagonal_%d_%d" % [int(face), int(side)],
                Vector3(x, -0.27, z), Vector3(-x * 0.17, -0.93, z),
                0.016, gunmetal, 8)
    # Low-profile service bays and thermal blanket retainers on all four sides.
    for face in range(4):
        var yaw: float = float(face) * PI * 0.5
        var turn := Basis(Vector3.UP, yaw)
        for side in [-1.0, 1.0]:
            var local := Vector3(float(side) * 0.37, -0.57, -0.826)
            var point: Vector3 = turn * local
            _solid("EquipmentBay_%d_%d" % [face, int(side)], point,
                Vector3(0.28, 0.27, 0.055), dark, yaw)
            _solid("EquipmentBayCover_%d_%d" % [face, int(side)],
                point + turn * Vector3(0.0, 0.0, -0.031),
                Vector3(0.23, 0.22, 0.013),
                gunmetal if face % 2 == 0 else insulation, yaw)
            for vent in range(3):
                _solid("ServiceVent_%d_%d_%d" % [face, int(side), vent],
                    point + turn * Vector3(0.0, 0.045 - 0.045 * float(vent), -0.042),
                    Vector3(0.145, 0.011, 0.011), dark, yaw)
    _solid("FrontEquipmentMark", Vector3(0.0, -0.36, -0.834),
        Vector3(0.14, 0.055, 0.018), marking)


func _precision_landing_gear() -> void:
    # Exact endpoints give the visual supports a credible load path between
    # the attachment to the descent stage and the already-fixed foot positions.
    for corner in range(4):
        var sx: float = -1.0 if corner % 2 == 0 else 1.0
        var sz: float = -1.0 if corner < 2 else 1.0
        var mount := Vector3(sx * 0.69, -0.22, sz * 0.69)
        var knee := Vector3(sx * 0.91, -1.03, sz * 0.91)
        var ankle := Vector3(sx * 1.05, -1.46, sz * 1.05)
        _beam("LoadStrut_%d" % corner, mount, knee, 0.061, gunmetal, 12)
        _beam("ShockPiston_%d" % corner, knee, ankle, 0.039, alloy, 12)
        _beam("GoldThermalSleeve_%d" % corner,
            mount.lerp(knee, 0.20), mount.lerp(knee, 0.56), 0.069, insulation, 12)
        _beam("ActuatorCylinder_%d" % corner,
            mount.lerp(knee, 0.59), mount.lerp(knee, 0.79), 0.076, brass, 12)
        _beam("CompressionBrace_%d" % corner,
            Vector3(sx * 0.42, -0.85, sz * 0.45), knee,
            0.024, alloy, 10)
        _beam("DiagonalBrace_%d" % corner,
            Vector3(sx * 0.65, -0.22, sz * 0.12),
            mount.lerp(knee, 0.58), 0.018, gunmetal, 8)
        _collar("PivotMount_%d" % corner, mount, 0.106, 0.035, gunmetal)
        _collar("FootPadOuterLip_%d" % corner,
            Vector3(sx * 1.05, -1.491, sz * 1.05), 0.382, 0.024, gunmetal)
        _collar("FootPadRetainer_%d" % corner,
            Vector3(sx * 1.05, -1.472, sz * 1.05), 0.30, 0.018, brass)
        _solid("FootPadShockAnchor_%d" % corner,
            Vector3(sx * 1.05, -1.445, sz * 1.05),
            Vector3(0.15, 0.064, 0.15), dark)
        # These are decorative (not functional damping or new colliders).
        for band in range(3):
            var at: Vector3 = knee.lerp(ankle, 0.19 + float(band) * 0.18)
            _collar("PistonSeal_%d_%d" % [corner, band], at, 0.065, 0.014, gunmetal)


func _ascent_cabin() -> void:
    # Large raked, dark cockpit windows replacing the toy-like rectangle look.
    # Slightly projected to prevent z-fighting with the legacy 8-facet cabin.
    for side in [-1.0, 1.0]:
        var s: float = float(side)
        var cx: float = s * 0.245
        var frame := PackedVector3Array([
            Vector3(cx - 0.131, 1.36, -0.615),
            Vector3(cx + 0.131, 1.36, -0.615),
            Vector3(cx + 0.195, 1.04, -0.687),
            Vector3(cx - 0.195, 1.04, -0.687)
        ])
        var inset := PackedVector3Array([
            Vector3(cx - 0.108, 1.328, -0.620),
            Vector3(cx + 0.108, 1.328, -0.620),
            Vector3(cx + 0.154, 1.068, -0.696),
            Vector3(cx - 0.154, 1.068, -0.696)
        ])
        _front_polygon("CockpitFrame_%d" % int(side), frame, gunmetal)
        _front_polygon("CockpitGlazing_%d" % int(side), inset, glass)
        _beam("WindowUpperSeal_%d" % int(side), frame[0], frame[1], 0.013, alloy, 8)
        _beam("WindowLowerSeal_%d" % int(side), frame[2], frame[3], 0.014, alloy, 8)
        _beam("WindowEdgeA_%d" % int(side), frame[0], frame[3], 0.012, alloy, 8)
        _beam("WindowEdgeB_%d" % int(side), frame[1], frame[2], 0.012, alloy, 8)
        _solid("WindowSunshade_%d" % int(side), Vector3(cx, 1.386, -0.62),
            Vector3(0.29, 0.028, 0.065), ceramic)
    # The crew access hatch stays fixed above the existing access ladder.
    for side in [-1.0, 1.0]:
        var x: float = float(side) * 0.24
        _beam("HatchReinforcedEdge_%d" % int(side),
            Vector3(x, 0.43, -0.754), Vector3(x, 0.83, -0.754),
            0.016, alloy, 8)
        _solid("HatchLatch_%d" % int(side),
            Vector3(x, 0.64, -0.785), Vector3(0.048, 0.07, 0.052), brass)
    _beam("HatchUpperLip", Vector3(-0.24, 0.845, -0.754),
        Vector3(0.24, 0.845, -0.754), 0.015, alloy, 8)
    _beam("HatchLowerLip", Vector3(-0.24, 0.43, -0.754),
        Vector3(0.24, 0.43, -0.754), 0.015, alloy, 8)
    for side in [-1.0, 1.0]:
        var sx: float = float(side)
        # Side mounted structural brackets and avionics with actual face clearance.
        _solid("CabinServicePanel_%d" % int(side),
            Vector3(sx * 0.70, 1.14, 0.11), Vector3(0.050, 0.28, 0.31), gunmetal)
        for rib in range(3):
            _solid("CabinServiceRib_%d_%d" % [int(side), rib],
                Vector3(sx * 0.737, 1.05 + 0.088 * float(rib), 0.11),
                Vector3(0.025, 0.021, 0.28), alloy)
    _collar("CabinDockMatingRing", Vector3(0.0, 1.735, 0.0), 0.405, 0.032, gunmetal)


func _engine_and_feeds() -> void:
    # Real concentric engine plumbing; keep the existing nozzle and plume intact.
    for i in range(4):
        _collar("EngineCoolingRing_%02d" % i,
            Vector3(0.0, -1.105 - float(i) * 0.077, 0.0),
            0.235 + float(i) * 0.040, 0.012, brass if i == 0 else alloy)
    _collar("EngineExitHeatRim", Vector3(0.0, -1.43, 0.0),
        0.395, 0.031, gunmetal)
    for s in [-1.0, 1.0]:
        var side: float = float(s)
        _pipe("OxidizerFeed_%d" % int(s), [
            Vector3(side * 0.76, -0.23, 0.45),
            Vector3(side * 0.76, -0.75, 0.45),
            Vector3(side * 0.39, -0.83, 0.30),
            Vector3(side * 0.24, -1.04, 0.20)
        ], 0.017, brass)
        _pipe("FuelFeed_%d" % int(s), [
            Vector3(side * 0.65, -0.38, -0.46),
            Vector3(side * 0.66, -0.87, -0.46),
            Vector3(side * 0.36, -0.97, -0.23),
            Vector3(side * 0.18, -1.06, -0.17)
        ], 0.014, alloy)
        _solid("FuelValve_%d" % int(s),
            Vector3(side * 0.66, -0.78, -0.46),
            Vector3(0.095, 0.12, 0.10), gunmetal)
    _solid("EngineController", Vector3(0.0, -0.91, 0.48),
        Vector3(0.31, 0.18, 0.16), dark)


func _avionics_and_rcs() -> void:
    # RCS cross-shaped nozzle clusters and wiring on each cardinal face.
    # Existing VFX emitters remain the sole source of visible gas jets.
    for face in range(4):
        var theta: float = float(face) * PI * 0.5
        var turn := Basis(Vector3.UP, theta)
        var pivot: Vector3 = turn * Vector3(0.0, 0.95, -0.84)
        _solid("RCSClusterBacking_%d" % face, pivot,
            Vector3(0.25, 0.24, 0.11), gunmetal, theta)
        for nozzle in range(4):
            var x: float = -0.072 if nozzle % 2 == 0 else 0.072
            var y: float = -0.058 if nozzle < 2 else 0.058
            var p: Vector3 = pivot + turn * Vector3(x, y, -0.065)
            _solid("RCSNozzleLiner_%d_%d" % [face, nozzle], p,
                Vector3(0.051, 0.051, 0.018), dark, theta)
            _solid("RCSNozzleLip_%d_%d" % [face, nozzle],
                p + turn * Vector3(0.0, 0.0, -0.016),
                Vector3(0.059, 0.059, 0.012), brass, theta)
        _pipe("RCSPiping_%d" % face, [
            pivot + turn * Vector3(0.15, -0.11, 0.08),
            pivot + turn * Vector3(0.26, -0.11, 0.08),
            pivot + turn * Vector3(0.26, -0.32, 0.08)
        ], 0.012, alloy)
    # Exterior sensor/enclosure front right, with separate glass optics.
    _solid("ForwardNavigationBox", Vector3(0.52, 0.24, -0.60),
        Vector3(0.22, 0.14, 0.13), gunmetal)
    for i in range(2):
        _solid("NavigationOptic_%d" % i,
            Vector3(0.45 + 0.12 * float(i), 0.24, -0.680),
            Vector3(0.057, 0.066, 0.021), glass)
    _solid("ForwardWarningPlate", Vector3(0.43, -0.91, -0.825),
        Vector3(0.11, 0.039, 0.012), marking)


func _antennae_and_sensors() -> void:
    # Compact communications array that does not alter the craft's envelope
    # radically; the original central mast remains visible.
    _beam("DishSupport", Vector3(-0.51, 1.57, 0.18),
        Vector3(-0.57, 2.07, 0.18), 0.016, alloy, 8)
    _collar("DishConcentricRim", Vector3(-0.57, 2.078, 0.18),
        0.165, 0.022, brass)
    _collar("DishConcentricInset", Vector3(-0.57, 2.081, 0.18),
        0.108, 0.02, gunmetal)
    _beam("DishFeed", Vector3(-0.57, 2.075, 0.18),
        Vector3(-0.57, 2.205, 0.18), 0.012, alloy, 8)
    for i in range(4):
        var angle: float = TAU * float(i) / 4.0
        _beam("DishBracing_%d" % i,
            Vector3(-0.57, 2.07, 0.18),
            Vector3(-0.57 + 0.135 * cos(angle), 2.083,
                0.18 + 0.135 * sin(angle)), 0.008, gunmetal, 6)
    _solid("TelemetryTransceiver", Vector3(0.46, 1.70, 0.25),
        Vector3(0.15, 0.13, 0.16), gunmetal)
    _beam("TelemetryAntenna", Vector3(0.46, 1.76, 0.25),
        Vector3(0.47, 2.18, 0.25), 0.009, brass, 6)
    _solid("TelemetryTip", Vector3(0.47, 2.19, 0.25),
        Vector3(0.04, 0.04, 0.04), marking)


func _batch_fasteners() -> void:
    # A single MultiMesh keeps many small bolts inexpensive to draw.
    var anchors: Array[Vector3] = []
    for face in range(4):
        var turn := Basis(Vector3.UP, float(face) * PI * 0.5)
        for side in [-1.0, 1.0]:
            for y in [-0.70, -0.47]:
                for x in [-0.11, 0.11]:
                    anchors.append(turn * Vector3(float(side) * 0.37 + float(x),
                        float(y), -0.876))
    for side in [-1.0, 1.0]:
        for y in [0.95, 1.32]:
            for x in [-0.12, 0.12]:
                anchors.append(Vector3(float(side) * 0.245 + float(x),
                    float(y), -0.705))
    var head := SphereMesh.new()
    head.radius = 0.012
    head.height = 0.024
    head.radial_segments = 6
    head.rings = 3
    var instances := MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.mesh = head
    instances.instance_count = anchors.size()
    for index in range(anchors.size()):
        instances.set_instance_transform(index,
            Transform3D(Basis.IDENTITY, anchors[index]))
    var batch := MultiMeshInstance3D.new()
    batch.name = "FastenersBatched"
    batch.multimesh = instances
    batch.material_override = alloy
    add_child(batch)
