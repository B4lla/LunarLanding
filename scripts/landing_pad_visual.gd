extends Node3D
## Render-only guidance decals and structural dressing above the existing 12 x 12 m platform top.
## No collision, areas or landing-criteria changes.
## F23 deepens the landing pad with perimeter structure, low beacons, equipment housings
## and deck service details while keeping the physical slab unchanged.

const RADIUS := 4.15
const SEGMENTS := 96
const MARKING_HEIGHT := 0.314
const PAD_HALF_EXTENT := 6.0

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _draw_ring()
    var light_mark: StandardMaterial3D = _material(Color(0.88, 0.82, 0.63), true)
    var guide: StandardMaterial3D = _material(Color(0.87, 0.71, 0.27), false)
    var dark: StandardMaterial3D = _material(Color(0.10, 0.12, 0.14), false)
    var metal: StandardMaterial3D = _metal_material(Color(0.30, 0.32, 0.35), 0.22, 0.72)
    var metal_dark: StandardMaterial3D = _metal_material(Color(0.18, 0.20, 0.22), 0.18, 0.80)
    var warning: StandardMaterial3D = _metal_material(Color(0.84, 0.58, 0.16), 0.08, 0.70)
    var beacon: StandardMaterial3D = _material(Color(0.68, 0.82, 1.0), true)
    # Four approaching directions; the center is kept clear of new obstacles.
    for index in range(4):
        var angle: float = TAU * float(index) / 4.0
        _strip("ApproachLine%d" % index, Vector3(cos(angle) * 3.25, MARKING_HEIGHT, sin(angle) * 3.25),
            Vector3(1.20, 0.008, 0.11), -angle, guide)
    # A large two-stroke touchdown cross can be read from steep camera angles.
    _strip("TargetX", Vector3(-0.55, MARKING_HEIGHT, 0), Vector3(1.1, 0.008, 0.10), 0.0, light_mark)
    _strip("TargetZ", Vector3(0.55, MARKING_HEIGHT, 0), Vector3(1.1, 0.008, 0.10), 0.0, light_mark)
    _strip("TargetBridge", Vector3(0.0, MARKING_HEIGHT, 0), Vector3(1.05, 0.008, 0.10), -PI/2.0, light_mark)
    # Corner high-contrast chevrons on the surface, not tall beacons.
    for xsign in [-1.0, 1.0]:
        for zsign in [-1.0, 1.0]:
            var base := Vector3(float(xsign) * 4.85, MARKING_HEIGHT, float(zsign) * 4.85)
            _strip("CornerX_%d_%d" % [int(xsign), int(zsign)], base + Vector3(-float(xsign) * 0.32, 0, 0),
                Vector3(0.62, 0.008, 0.13), 0, guide)
            _strip("CornerZ_%d_%d" % [int(xsign), int(zsign)], base + Vector3(0, 0, -float(zsign) * 0.32),
                Vector3(0.62, 0.008, 0.13), -PI/2.0, dark)
    for i in range(8):
        var angle: float = TAU * (float(i) + 0.5) / 8.0
        var at := Vector3(cos(angle) * 5.55, MARKING_HEIGHT, sin(angle) * 5.55)
        _strip("PerimeterReflector%d" % i, at, Vector3(0.30, 0.008, 0.14), -angle, light_mark)
    _detail_f10(light_mark, guide, dark)
    _detail_f23(metal, metal_dark, warning, beacon, light_mark, dark)
    _detail_f27(metal, metal_dark, warning, beacon, light_mark, dark)


func _detail_f10(light_mark: StandardMaterial3D, guide: StandardMaterial3D,
        dark: StandardMaterial3D) -> void:
    # Surface-only segmented deck plating, hazard bands and visible bolts.
    # The original 12 x 12 m colliding slab remains unchanged.
    for index in range(1, 6):
        var offset: float = -6.0 + float(index) * 2.0
        _strip("DeckSeamX_%d" % index, Vector3(offset, MARKING_HEIGHT, 0),
            Vector3(0.018, 0.006, 11.4), 0, dark)
        _strip("DeckSeamZ_%d" % index, Vector3(0, MARKING_HEIGHT, offset),
            Vector3(11.4, 0.006, 0.018), 0, dark)
    for side in [-1.0, 1.0]:
        for index in range(8):
            var offset: float = -4.6 + float(index) * 1.3
            _strip("SafetyStripeX_%d_%d" % [int(side), index],
                Vector3(float(side) * 5.77, MARKING_HEIGHT + 0.003, offset),
                Vector3(0.35, 0.008, 0.19), 0.65, guide)
            _strip("SafetyStripeZ_%d_%d" % [int(side), index],
                Vector3(offset, MARKING_HEIGHT + 0.003, float(side) * 5.77),
                Vector3(0.35, 0.008, 0.19), -0.65, guide)
    # One instanced mesh for all deck rivets: a single draw call instead of 100.
    var bolt := CylinderMesh.new()
    bolt.top_radius = 0.035
    bolt.bottom_radius = 0.035
    bolt.height = 0.009
    bolt.radial_segments = 8
    bolt.material = light_mark
    var grid := MultiMesh.new()
    grid.transform_format = MultiMesh.TRANSFORM_3D
    grid.mesh = bolt
    grid.instance_count = 100
    for x in range(10):
        for z in range(10):
            var location := Vector3(-5.4 + float(x) * 1.2,
                MARKING_HEIGHT + 0.003, -5.4 + float(z) * 1.2)
            grid.set_instance_transform(x * 10 + z, Transform3D(Basis.IDENTITY, location))
    var fasteners := MultiMeshInstance3D.new()
    fasteners.name = "DeckFastenersNoCollision"
    fasteners.multimesh = grid
    fasteners.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(fasteners)


func _detail_f23(metal: StandardMaterial3D, metal_dark: StandardMaterial3D,
        warning: StandardMaterial3D, beacon: StandardMaterial3D,
        light_mark: StandardMaterial3D, dark: StandardMaterial3D) -> void:
    _perimeter_frame(metal, metal_dark)
    _corner_braces(metal_dark)
    _service_housings(metal, warning, dark)
    _perimeter_beacons(metal_dark, beacon)
    _deck_access_plates(metal, dark, light_mark)
    _tie_down_array(metal_dark)


func _perimeter_frame(metal: StandardMaterial3D, metal_dark: StandardMaterial3D) -> void:
    # Raised frame and shallow chamfer skirt to stop the pad reading as a plain slab.
    for side in [-1.0, 1.0]:
        _strip("FrameNorthSouth_%d" % int(side), Vector3(0, 0.365, side * 5.88),
            Vector3(11.9, 0.10, 0.24), 0, metal)
        _strip("FrameEastWest_%d" % int(side), Vector3(side * 5.88, 0.365, 0),
            Vector3(0.24, 0.10, 11.9), 0, metal)
        _strip("SkirtNorthSouth_%d" % int(side), Vector3(0, 0.255, side * 6.06),
            Vector3(11.95, 0.16, 0.12), 0, metal_dark)
        _strip("SkirtEastWest_%d" % int(side), Vector3(side * 6.06, 0.255, 0),
            Vector3(0.12, 0.16, 11.95), 0, metal_dark)


func _corner_braces(metal_dark: StandardMaterial3D) -> void:
    for xsign in [-1.0, 1.0]:
        for zsign in [-1.0, 1.0]:
            var anchor := Vector3(float(xsign) * 5.62, 0.36, float(zsign) * 5.62)
            _strip("CornerBraceX_%d_%d" % [int(xsign), int(zsign)],
                anchor + Vector3(-float(xsign) * 0.44, 0.0, 0.0),
                Vector3(0.78, 0.08, 0.16), 0.0, metal_dark)
            _strip("CornerBraceZ_%d_%d" % [int(xsign), int(zsign)],
                anchor + Vector3(0.0, 0.0, -float(zsign) * 0.44),
                Vector3(0.16, 0.08, 0.78), 0.0, metal_dark)


func _service_housings(metal: StandardMaterial3D, warning: StandardMaterial3D,
        dark: StandardMaterial3D) -> void:
    var positions := [
        Vector3(0.0, 0.44, -5.25), Vector3(0.0, 0.44, 5.25),
        Vector3(-5.25, 0.44, 0.0), Vector3(5.25, 0.44, 0.0)
    ]
    for idx in range(positions.size()):
        var pos: Vector3 = positions[idx]
        var long_side := absf(pos.x) < 0.1
        _solid("ServiceHousing_%d" % idx, pos,
            Vector3(1.55 if long_side else 0.62, 0.18, 0.62 if long_side else 1.55), metal)
        _solid("ServiceCap_%d" % idx, pos + Vector3(0, 0.12, 0),
            Vector3(1.22 if long_side else 0.44, 0.03, 0.44 if long_side else 1.22), warning)
        for slot in range(3):
            var offset: float = -0.22 + float(slot) * 0.22
            if long_side:
                _solid("ServiceVent_%d_%d" % [idx, slot], pos + Vector3(offset, 0.105, 0),
                    Vector3(0.07, 0.012, 0.48), dark)
            else:
                _solid("ServiceVent_%d_%d" % [idx, slot], pos + Vector3(0, 0.105, offset),
                    Vector3(0.48, 0.012, 0.07), dark)


func _perimeter_beacons(metal_dark: StandardMaterial3D, beacon: StandardMaterial3D) -> void:
    var beacon_positions := [
        Vector3(-4.2, 0.32, -5.65), Vector3(0.0, 0.32, -5.65), Vector3(4.2, 0.32, -5.65),
        Vector3(-4.2, 0.32, 5.65), Vector3(0.0, 0.32, 5.65), Vector3(4.2, 0.32, 5.65),
        Vector3(-5.65, 0.32, -4.2), Vector3(-5.65, 0.32, 0.0), Vector3(-5.65, 0.32, 4.2),
        Vector3(5.65, 0.32, -4.2), Vector3(5.65, 0.32, 0.0), Vector3(5.65, 0.32, 4.2)
    ]
    for idx in range(beacon_positions.size()):
        var pos: Vector3 = beacon_positions[idx]
        _cylinder("BeaconBase_%d" % idx, pos + Vector3(0, 0.05, 0), 0.07, 0.07, 0.10, metal_dark)
        _cylinder("BeaconLens_%d" % idx, pos + Vector3(0, 0.12, 0), 0.05, 0.05, 0.05, beacon)


func _deck_access_plates(metal: StandardMaterial3D, dark: StandardMaterial3D,
        light_mark: StandardMaterial3D) -> void:
    var plates := [
        Vector3(-2.65, MARKING_HEIGHT + 0.004, -2.65), Vector3(2.65, MARKING_HEIGHT + 0.004, -2.65),
        Vector3(-2.65, MARKING_HEIGHT + 0.004, 2.65), Vector3(2.65, MARKING_HEIGHT + 0.004, 2.65)
    ]
    for idx in range(plates.size()):
        var pos: Vector3 = plates[idx]
        _strip("AccessPlate_%d" % idx, pos, Vector3(1.15, 0.010, 1.15), 0, metal)
        _strip("AccessPlateInset_%d" % idx, pos + Vector3(0, 0.003, 0), Vector3(0.84, 0.006, 0.84), 0, dark)
        for bolt_idx in range(4):
            var sx := -1.0 if bolt_idx in [0, 2] else 1.0
            var sz := -1.0 if bolt_idx in [0, 1] else 1.0
            _cylinder("AccessBolt_%d_%d" % [idx, bolt_idx],
                pos + Vector3(0.34 * sx, 0.011, 0.34 * sz), 0.022, 0.022, 0.010, light_mark)


func _tie_down_array(metal_dark: StandardMaterial3D) -> void:
    var ring := TorusMesh.new()
    ring.inner_radius = 0.022
    ring.outer_radius = 0.070
    ring.rings = 10
    ring.ring_segments = 12
    ring.material = metal_dark
    var mounts := MultiMesh.new()
    mounts.transform_format = MultiMesh.TRANSFORM_3D
    mounts.mesh = ring
    mounts.instance_count = 16
    var index := 0
    for side in [-1.0, 1.0]:
        for step in range(4):
            var offset: float = -3.3 + float(step) * 2.2
            mounts.set_instance_transform(index,
                Transform3D(Basis.IDENTITY, Vector3(offset, MARKING_HEIGHT + 0.018, side * 4.95)))
            index += 1
            mounts.set_instance_transform(index,
                Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(side * 4.95, MARKING_HEIGHT + 0.018, offset)))
            index += 1
    var tiedowns := MultiMeshInstance3D.new()
    tiedowns.name = "TieDownRingArray"
    tiedowns.multimesh = mounts
    tiedowns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(tiedowns)


func _detail_f27(metal: StandardMaterial3D, metal_dark: StandardMaterial3D,
        warning: StandardMaterial3D, beacon: StandardMaterial3D,
        light_mark: StandardMaterial3D, dark: StandardMaterial3D) -> void:
    var deck: StandardMaterial3D = _base_pbr_material()
    if deck == null:
        deck = metal
    _outer_base_apron(deck, metal_dark, warning)
    _apron_thresholds(metal_dark, warning)
    _base_connectors(metal_dark, warning)
    _base_modules(deck, metal_dark, warning, dark)
    _solar_arrays(metal_dark, beacon)
    _comm_masts(metal_dark, beacon, warning)
    _edge_light_array(beacon, light_mark)
    _base_cargo_and_ducts(metal, metal_dark, warning)


func _base_pbr_material() -> StandardMaterial3D:
    var f34_prefix: String = "res://assets/terrain_materials/service_deck_"
    var f34_valid: bool = true
    for channel in ["albedo", "normal", "roughness"]:
        if not ResourceLoader.exists(f34_prefix + channel + ".png"):
            f34_valid = false
    if f34_valid:
        var upgraded: StandardMaterial3D = StandardMaterial3D.new()
        upgraded.albedo_texture = load(f34_prefix + "albedo.png") as Texture2D
        upgraded.normal_texture = load(f34_prefix + "normal.png") as Texture2D
        upgraded.normal_enabled = true
        upgraded.normal_scale = 0.55
        upgraded.roughness_texture = load(f34_prefix + "roughness.png") as Texture2D
        upgraded.roughness = 0.87
        upgraded.metallic = 0.20
        upgraded.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        upgraded.uv1_scale = Vector3.ONE
        return upgraded
    var prefix: String = "res://assets/base_materials/base_deck_"
    for channel in ["albedo", "normal", "roughness"]:
        if not ResourceLoader.exists(prefix + channel + ".png"):
            return null
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = load(prefix + "albedo.png") as Texture2D
    mat.normal_texture = load(prefix + "normal.png") as Texture2D
    mat.normal_enabled = true
    mat.normal_scale = 0.55
    mat.roughness_texture = load(prefix + "roughness.png") as Texture2D
    mat.roughness = 0.89
    mat.metallic = 0.19
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
    return mat


func _outer_base_apron(deck: StandardMaterial3D, metal_dark: StandardMaterial3D,
        warning: StandardMaterial3D) -> void:
    # The core landing top is y=0.30. The service apron is deliberately at
    # y=0.12: unmistakably *not* an extended touchdown surface.
    for side in [-1.0, 1.0]:
        _solid_deck("BaseApronNorthSouth_%d" % int(side), Vector3(0, 0.065, side * 8.65),
            Vector3(21.2, 0.11, 4.6), deck)
        _solid_deck("BaseApronEastWest_%d" % int(side), Vector3(side * 8.65, 0.065, 0),
            Vector3(4.6, 0.11, 21.2), deck)
        _solid("ApronRimNorthSouth_%d" % int(side), Vector3(0, 0.09, side * 11.14),
            Vector3(22.4, 0.18, 0.18), metal_dark)
        _solid("ApronRimEastWest_%d" % int(side), Vector3(side * 11.14, 0.09, 0),
            Vector3(0.18, 0.18, 22.4), metal_dark)
        # Clear raised separator only outside the original 12 x 12 center.
        _strip("SafetyBoundaryNS_%d" % int(side), Vector3(0, 0.126, side * 6.56),
            Vector3(11.9, 0.009, 0.20), 0.0, warning)
        _strip("SafetyBoundaryEW_%d" % int(side), Vector3(side * 6.56, 0.126, 0),
            Vector3(0.20, 0.009, 11.9), 0.0, warning)
    for xsign in [-1.0, 1.0]:
        for zsign in [-1.0, 1.0]:
            _solid_deck("ApronCorner_%d_%d" % [int(xsign), int(zsign)],
                Vector3(8.65 * xsign, 0.065, 8.65 * zsign),
                Vector3(4.6, 0.11, 4.6), deck)
            _strip("ApronCornerStripe_%d_%d" % [int(xsign), int(zsign)],
                Vector3(9.75 * xsign, 0.125, 9.75 * zsign),
                Vector3(1.50, 0.009, 0.22), 0.72 * xsign * zsign, warning)
    _apron_panel_seams(metal_dark)


func _apron_panel_seams(metal_dark: StandardMaterial3D) -> void:
    # F29: 32 identical-material marks in ONE draw call rather than 32 nodes.
    # All transforms remain in the same positions as F28.
    var seam_mesh := BoxMesh.new()
    seam_mesh.size = Vector3.ONE
    seam_mesh.material = metal_dark
    var instances := MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.mesh = seam_mesh
    instances.instance_count = 32
    var cursor: int = 0
    for index in range(1, 9):
        var offset: float = -10.0 + float(index) * 2.2
        for side in [-1.0, 1.0]:
            instances.set_instance_transform(cursor, Transform3D(
                Basis.IDENTITY.scaled(Vector3(0.025, 0.008, 3.5)),
                Vector3(offset, 0.124, side * 8.9)))
            cursor += 1
            instances.set_instance_transform(cursor, Transform3D(
                Basis.IDENTITY.scaled(Vector3(3.5, 0.008, 0.025)),
                Vector3(side * 8.9, 0.124, offset)))
            cursor += 1
    var seams := MultiMeshInstance3D.new()
    seams.name = "ApronPanelSeamsInstanced"
    seams.multimesh = instances
    seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(seams)


func _apron_thresholds(metal_dark: StandardMaterial3D,
        warning: StandardMaterial3D) -> void:
    # Close F28's 0.35 m gap: original service apron starts at +/-6.35 while
    # the physical pad ends at +/-6.00. The bridge stays BELOW the y=.30 pad.
    # It is only visual; never advertises a second touchdown area.
    for side in [-1.0, 1.0]:
        _solid("PadThresholdNS_%d" % int(side),
            Vector3(0.0, 0.06, side * 6.16), Vector3(11.8, 0.12, 0.50), metal_dark)
        _solid("PadThresholdEW_%d" % int(side),
            Vector3(side * 6.16, 0.06, 0.0), Vector3(0.50, 0.12, 11.8), metal_dark)
        _strip("ThresholdWarningNS_%d" % int(side),
            Vector3(0.0, 0.129, side * 6.16), Vector3(11.7, 0.007, 0.16), 0.0, warning)
        _strip("ThresholdWarningEW_%d" % int(side),
            Vector3(side * 6.16, 0.129, 0.0), Vector3(0.16, 0.007, 11.7), 0.0, warning)


func _base_connectors(metal_dark: StandardMaterial3D, warning: StandardMaterial3D) -> void:
    # Four recessed access strips; flush with the actual ground. No landing
    # area outside the central pad is advertised as physically usable.
    for side in [-1.0, 1.0]:
        _solid("BaseConnector_NS_%d" % int(side), Vector3(0.0, 0.035, side * 13.7),
            Vector3(3.2, 0.07, 5.2), metal_dark)
        _solid("BaseConnector_EW_%d" % int(side), Vector3(side * 13.7, 0.035, 0.0),
            Vector3(5.2, 0.07, 3.2), metal_dark)
        for lane in range(4):
            var offset: float = -1.10 + float(lane) * 0.72
            _strip("ConnectorStripeNS_%d_%d" % [int(side), lane],
                Vector3(offset, 0.076, side * 13.7), Vector3(0.10, 0.006, 4.55), 0.0, warning)
            _strip("ConnectorStripeEW_%d_%d" % [int(side), lane],
                Vector3(side * 13.7, 0.076, offset), Vector3(4.55, 0.006, 0.10), 0.0, warning)


func _base_modules(deck: StandardMaterial3D, metal_dark: StandardMaterial3D,
        warning: StandardMaterial3D, dark: StandardMaterial3D) -> void:
    # Equipment and habitat shells rest on the ground; F27 floated above it.
    var origins: Array[Vector3] = [Vector3(0, 0, -18.2), Vector3(0, 0, 18.2),
        Vector3(-18.2, 0, 0), Vector3(18.2, 0, 0)]
    for index in range(origins.size()):
        var along_x: bool = index < 2
        var pos: Vector3 = origins[index]
        var label: String = ["North", "South", "West", "East"][index]
        var size: Vector3 = Vector3(7.0, 1.55, 3.8) if along_x else Vector3(3.8, 1.55, 7.0)
        var center: Vector3 = pos + Vector3(0, 0.795, 0)
        _solid("BaseModule_" + label, center, size, deck)
        _solid("BaseModuleCap_" + label, center + Vector3(0, 0.86, 0),
            Vector3(size.x + 0.30, 0.15, size.z + 0.30), metal_dark)
        _solid("BaseModuleRoof_" + label, center + Vector3(0, 0.97, 0),
            Vector3(size.x * 0.34, 0.06, size.z * 0.34), warning)
        for slot in range(5):
            var offset: float = -2.4 + float(slot) * 1.2
            if along_x:
                _solid("BaseWindow_" + label + "_%d" % slot,
                    center + Vector3(offset, 0.16, -size.z * 0.5 - 0.032),
                    Vector3(0.68, 0.35, 0.065), dark)
                _solid("BaseRearVent_" + label + "_%d" % slot,
                    center + Vector3(offset, 0.0, size.z * 0.5 + 0.034),
                    Vector3(0.76, 0.18, 0.068), metal_dark)
            else:
                _solid("BaseWindow_" + label + "_%d" % slot,
                    center + Vector3(-size.x * 0.5 - 0.032, 0.16, offset),
                    Vector3(0.065, 0.35, 0.68), dark)
                _solid("BaseRearVent_" + label + "_%d" % slot,
                    center + Vector3(size.x * 0.5 + 0.034, 0.0, offset),
                    Vector3(0.068, 0.18, 0.76), metal_dark)


func _solar_arrays(metal_dark: StandardMaterial3D, beacon: StandardMaterial3D) -> void:
    var panel := _metal_material(Color(0.09, 0.16, 0.25), 0.25, 0.26)
    var grid_lines := _metal_material(Color(0.31, 0.38, 0.45), 0.30, 0.65)
    var origins: Array[Vector3] = [Vector3(-23.0, 0, -23.0), Vector3(23.0, 0, -23.0),
        Vector3(-23.0, 0, 23.0), Vector3(23.0, 0, 23.0)]
    for index in range(origins.size()):
        var pos: Vector3 = origins[index]
        _cylinder("SolarPost_%d" % index, pos + Vector3(0, 0.48, 0), 0.075, 0.11, 0.96, metal_dark)
        _solid("SolarSpine_%d" % index, pos + Vector3(0, 1.04, 0),
            Vector3(5.8, 0.065, 0.18), metal_dark)
        for side in [-1.0, 1.0]:
            var panel_pos := pos + Vector3(1.50 * side, 1.08, 0)
            _solid("SolarPanelL_%d_%d" % [index, int(side)], panel_pos,
                Vector3(2.65, 0.055, 2.4), panel)
            var pane: MeshInstance3D = get_node("SolarPanelL_%d_%d" % [index, int(side)]) as MeshInstance3D
            # Solar cell divider strips are separate flat geometry; keep them
            # coplanar with the pane instead of detaching when it is tilted.
            pane.rotation_degrees.z = 0.0
            for line in range(1, 4):
                var offset: float = -1.25 + float(line) * 0.62
                _strip("SolarCells_%d_%d_%d" % [index, int(side), line],
                    panel_pos + Vector3(0, 0.038, offset), Vector3(2.45, 0.012, 0.025), 0.0, grid_lines)
        _cylinder("SolarMarker_%d" % index, pos + Vector3(0, 1.23, 0),
            0.055, 0.055, 0.10, beacon)


func _comm_masts(metal_dark: StandardMaterial3D, beacon: StandardMaterial3D,
        warning: StandardMaterial3D) -> void:
    var corners: Array[Vector3] = [Vector3(-12.9, 0, -12.9), Vector3(12.9, 0, -12.9),
        Vector3(-12.9, 0, 12.9), Vector3(12.9, 0, 12.9)]
    for idx in range(corners.size()):
        var pos: Vector3 = corners[idx]
        _cylinder("CommsBase_%d" % idx, pos + Vector3(0, 0.14, 0), 0.22, 0.30, 0.28, metal_dark)
        _cylinder("CommsMast_%d" % idx, pos + Vector3(0, 1.43, 0), 0.052, 0.07, 2.55, metal_dark)
        _solid("CommsCross_%d" % idx, pos + Vector3(0, 2.18, 0),
            Vector3(1.12, 0.06, 0.12), warning)
        _cylinder("CommsBeacon_%d" % idx, pos + Vector3(0, 2.79, 0),
            0.07, 0.07, 0.13, beacon)


func _edge_light_array(beacon: StandardMaterial3D, light_mark: StandardMaterial3D) -> void:
    # 44 lights in one instanced draw instead of 48 separate cylinders.
    var lamp_mesh := CylinderMesh.new()
    lamp_mesh.top_radius = 0.055
    lamp_mesh.bottom_radius = 0.060
    lamp_mesh.height = 0.08
    lamp_mesh.radial_segments = 9
    lamp_mesh.material = beacon
    var lamps := MultiMesh.new()
    lamps.transform_format = MultiMesh.TRANSFORM_3D
    lamps.mesh = lamp_mesh
    lamps.instance_count = 44
    var k: int = 0
    for side in [-1.0, 1.0]:
        for idx in range(11):
            var offset: float = -9.30 + float(idx) * 1.86
            lamps.set_instance_transform(k, Transform3D(Basis.IDENTITY,
                Vector3(offset, 0.16, 10.20 * side)))
            k += 1
            lamps.set_instance_transform(k, Transform3D(Basis.IDENTITY,
                Vector3(10.20 * side, 0.16, offset)))
            k += 1
    var lights := MultiMeshInstance3D.new()
    lights.name = "ApronLightNorth_Array"
    lights.multimesh = lamps
    lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(lights)
    # Move guide strips onto the *lower* apron: preserve center target/RCS dust.
    _strip("ApronCenterGuideX", Vector3(0, 0.13, -8.65),
        Vector3(7.8, 0.006, 0.07), 0.0, light_mark)
    _strip("ApronCenterGuideZ", Vector3(8.65, 0.13, 0),
        Vector3(0.07, 0.006, 7.8), 0.0, light_mark)


func _base_cargo_and_ducts(metal: StandardMaterial3D,
        metal_dark: StandardMaterial3D, warning: StandardMaterial3D) -> void:
    # Low industrial details keep the working pad unobstructed.
    for side in [-1.0, 1.0]:
        _solid("ServiceDuctNS_%d" % int(side), Vector3(5.9 * side, 0.075, 12.8),
            Vector3(0.20, 0.15, 5.8), metal_dark)
        _solid("ServiceDuctEW_%d" % int(side), Vector3(12.8, 0.075, 5.9 * side),
            Vector3(5.8, 0.15, 0.20), metal_dark)
        for index in range(3):
            var offset: float = -2.0 + float(index) * 1.85
            var at := Vector3(12.5 * side, 0.45, 18.6 + offset)
            _solid("CargoPod_%d_%d" % [int(side), index], at,
                Vector3(1.4, 0.90, 1.0), metal)
            _strip("CargoMark_%d_%d" % [int(side), index],
                at + Vector3(0, 0.47, 0), Vector3(0.9, 0.008, 0.13), 0.0, warning)


func _material(color: Color, luminous: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.83
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    if luminous:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 0.7
    return material


func _metal_material(color: Color, metalness: float, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = metalness
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _solid_deck(label: String, at: Vector3, dimensions: Vector3,
        surface: StandardMaterial3D) -> void:
    # F29: industrial texels are ~2.6 m, not stretched once over a 21 m box.
    # Overrides are cloned per panel dimension, leaving the shared F28 material intact.
    var tiled: StandardMaterial3D = surface.duplicate() as StandardMaterial3D
    tiled.uv1_scale = Vector3(maxf(1.0, dimensions.x / 2.6),
        maxf(1.0, dimensions.z / 2.6), maxf(1.0, dimensions.z / 2.6))
    _solid(label, at, dimensions, tiled)


func _solid(label: String, at: Vector3, dimensions: Vector3, surface: StandardMaterial3D) -> void:
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = at
    node.material_override = surface
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(node)


func _cylinder(label: String, at: Vector3, upper: float, lower: float, height: float,
        surface: StandardMaterial3D, angles: Vector3 = Vector3.ZERO) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = upper
    mesh.bottom_radius = lower
    mesh.height = height
    mesh.radial_segments = 14
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = at
    node.rotation_degrees = angles
    node.material_override = surface
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(node)


func _strip(label: String, at: Vector3, dimensions: Vector3, spin: float, surface: StandardMaterial3D) -> void:
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    var node := MeshInstance3D.new()
    node.name = label
    node.mesh = mesh
    node.position = at
    node.rotation.y = spin
    node.material_override = surface
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)


func _draw_ring() -> void:
    var ring := SurfaceTool.new()
    ring.begin(Mesh.PRIMITIVE_TRIANGLES)
    for segment in range(SEGMENTS):
        if segment % 12 == 11:
            continue
        var a: float = TAU * float(segment) / float(SEGMENTS)
        var b: float = TAU * float(segment + 1) / float(SEGMENTS)
        var v0 := Vector3(cos(a) * (RADIUS - 0.13), MARKING_HEIGHT, sin(a) * (RADIUS - 0.13))
        var v1 := Vector3(cos(a) * RADIUS, MARKING_HEIGHT, sin(a) * RADIUS)
        var v2 := Vector3(cos(b) * (RADIUS - 0.13), MARKING_HEIGHT, sin(b) * (RADIUS - 0.13))
        var v3 := Vector3(cos(b) * RADIUS, MARKING_HEIGHT, sin(b) * RADIUS)
        for vertex in [v0, v2, v1, v1, v2, v3]:
            ring.add_vertex(vertex)
    ring.generate_normals()
    var markings := MeshInstance3D.new()
    markings.name = "LandingRingVisualOnly"
    markings.mesh = ring.commit()
    markings.material_override = _material(Color(0.86, 0.71, 0.32), true)
    markings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(markings)
