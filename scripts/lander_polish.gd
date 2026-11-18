extends Node3D
## Additional handmade *visual-only* detail for the bundled fallback lunar lander.
## NASA model, if separately verified and selected, hides this whole node.
## F13: upgrades the craft silhouette, legs and materials while preserving physics.

const GOLD_ALBEDO := preload("res://assets/procedural/gold_foil_albedo.png")
const GOLD_NORMAL := preload("res://assets/procedural/gold_foil_normal.png")
const GOLD_ROUGHNESS := preload("res://assets/procedural/gold_foil_roughness.png")
const CERAMIC_ALBEDO := preload("res://assets/procedural/cabin_ceramic_albedo.png")
const CERAMIC_NORMAL := preload("res://assets/procedural/cabin_ceramic_normal.png")
const CERAMIC_ROUGHNESS := preload("res://assets/procedural/cabin_ceramic_roughness.png")


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _hide_placeholder_geometry()
    var titanium := _mat(Color(0.45, 0.50, 0.53), 0.80, 0.26)
    var dark := _mat(Color(0.07, 0.08, 0.10), 0.42, 0.40)
    var copper := _mat(Color(0.56, 0.33, 0.18), 0.70, 0.35)
    var foil := _pbr_mat("gold_foil", Color(0.93, 0.88, 0.74), 0.70, 0.42)
    var ceramic := _pbr_mat("cabin_ceramic", Color(0.90, 0.91, 0.88), 0.12, 0.61)
    var glass := _glass_mat()
    var panel := _panel_mat()
    _configure_f13_materials(foil, dark, ceramic, glass, titanium, panel, copper)
    _detail_f10(titanium, dark, copper, foil)
    _detail_f13_realism(titanium, dark, copper, foil, ceramic)
    # F33 must run after F13 creates its legacy meshes, so replacements
    # can be hidden deterministically without changing the scene physics.
    var hifi: Node3D = Node3D.new()
    hifi.name = "HighFidelityF33"
    hifi.set_script(preload("res://scripts/lander_hifi.gd"))
    add_child(hifi)
    hifi.call("build_visuals")
    # F37: bridge the previously exposed central gap with a sealed visual body.
    var midsection: Node3D = Node3D.new()
    midsection.name = "F37CenterBody"
    midsection.set_script(preload("res://scripts/lander_midsection.gd"))
    add_child(midsection)
    midsection.call("build_visuals")


func _hide_placeholder_geometry() -> void:
    var host := get_parent()
    if host == null:
        return
    for node_name in [
        "BodyMesh", "Nozzle",
        "LegPadMeshFL", "LegPadMeshFR", "LegPadMeshBL", "LegPadMeshBR",
        "StrutFL", "StrutFR", "StrutBL", "StrutBR"
    ]:
        var node := host.get_node_or_null(node_name)
        if node is MeshInstance3D:
            node.visible = false


func _configure_f13_materials(foil: StandardMaterial3D, dark: StandardMaterial3D,
        ceramic: StandardMaterial3D, glass: StandardMaterial3D,
        titanium: StandardMaterial3D, panel: StandardMaterial3D,
        copper: StandardMaterial3D) -> void:
    _apply_material([
        "DescentFoil", "FoilModule1", "FoilModule2", "FoilModule3", "FoilModule4"
    ], foil)
    _apply_material(["UpperCabin", "CabinCap"], ceramic)
    _apply_material(["LeftWindow", "RightWindow"], glass)
    _apply_material([
        "LeftWindowBorder", "RightWindowBorder", "AuxTankL", "AuxTankR",
        "BoomL", "BoomR", "LandingFootDisc0", "LandingFootDisc1",
        "LandingFootDisc2", "LandingFootDisc3", "AntennaMast",
        "UpperAntenna", "LowerAntennaL", "LowerAntennaR"
    ], titanium)
    _apply_material(["SolarPanelL", "SolarPanelR"], panel)
    _apply_material([
        "LegHydraulic0", "LegHydraulic1", "LegHydraulic2", "LegHydraulic3",
        "DescentNozzleLiner"
    ], copper)


func _apply_material(names: Array, material: Material) -> void:
    for node_name in names:
        var node := get_node_or_null(String(node_name))
        if node is MeshInstance3D:
            node.material_override = material


func _detail_f10(titanium: StandardMaterial3D, dark: StandardMaterial3D,
        copper: StandardMaterial3D, gold: StandardMaterial3D) -> void:
    # Structural belt between ascent cabin and gold descent stage.
    _cylinder("AscentCollar", Vector3(0, 0.48, 0), 0.77, 0.77, 0.09, titanium)
    _cylinder("DescentEquipmentBelt", Vector3(0, -0.32, 0), 0.82, 0.82, 0.13, dark)
    for index in range(8):
        var angle: float = TAU * float(index) / 8.0
        var pos := Vector3(cos(angle) * 0.69, -0.72, sin(angle) * 0.69)
        _box("FoilPanel%d" % index, pos, Vector3(0.31, 0.31, 0.045),
            -angle, gold if index % 2 == 0 else copper)
    # Cabin side thermal grid and small instrumentation enclosures.
    for sign in [-1.0, 1.0]:
        _box("InstrumentRack%d" % int(sign), Vector3(float(sign) * 0.56, 0.90, 0.26),
            Vector3(0.15, 0.35, 0.27), 0, dark)
        _box("SolarCellSpine%d" % int(sign), Vector3(float(sign) * 1.28, 0.72, 0),
            Vector3(0.065, 0.40, 0.040), 0, titanium)
        for stripe in range(3):
            _box("SolarTrace%d_%d" % [int(sign), stripe],
                Vector3(float(sign) * 1.28, 0.59 + 0.11 * stripe, 0.0),
                Vector3(0.29, 0.013, 0.035), 0, titanium)
    # Two visible RCS exhaust ports per lateral side. No new thrust forces.
    for side in [-1.0, 1.0]:
        for fore in [-0.22, 0.22]:
            _cylinder("RCSHousing%d_%d" % [int(side), int(fore * 100)],
                Vector3(float(side) * 0.735, 0.51, fore), 0.105, 0.082, 0.19, dark,
                Vector3(0, 0, 90))
            _cylinder("RCSRim%d_%d" % [int(side), int(fore * 100)],
                Vector3(float(side) * 0.845, 0.51, fore), 0.105, 0.105, 0.025, copper,
                Vector3(0, 0, 90))
    _cylinder("UpperDockRing", Vector3(0, 1.71, 0), 0.38, 0.38, 0.06, titanium)
    _box("WindowCenterColumn", Vector3(0, 1.12, -0.585), Vector3(0.045, 0.25, 0.05), 0, titanium)
    # Front access ladder below the cabin, recessed between the two feet.
    # Short rungs and rails are only visible geometry; no physical collision.
    for side in [-1.0, 1.0]:
        _box("AccessRail_%d" % int(side),
            Vector3(float(side) * 0.25, -0.53, -0.84),
            Vector3(0.028, 1.31, 0.035), 0.0, titanium)
    for rung in range(8):
        _box("AccessRung_%02d" % rung,
            Vector3(0.0, -1.08 + float(rung) * 0.155, -0.856),
            Vector3(0.53, 0.023, 0.048), 0.0, titanium)
    # Access hatch and reinforcement bars read clearly at typical camera range.
    _box("HatchOuter", Vector3(0.0, 0.66, -0.70),
        Vector3(0.43, 0.46, 0.035), 0.0, titanium)
    _box("HatchInner", Vector3(0.0, 0.66, -0.724),
        Vector3(0.33, 0.35, 0.018), 0.0, dark)
    _cylinder("HatchHandle", Vector3(0.11, 0.64, -0.755),
        0.028, 0.028, 0.045, copper, Vector3(90, 0, 0))
    # Equipment/cabling on the sides, below the RCS housings.
    for side in [-1.0, 1.0]:
        _box("ServiceTrunk_%d" % int(side),
            Vector3(float(side) * 0.70, 0.10, -0.10),
            Vector3(0.07, 0.55, 0.10), 0.0, dark)
        for joint in range(5):
            _box("ServiceClamp_%d_%02d" % [int(side), joint],
                Vector3(float(side) * 0.755, -0.11 + 0.108 * float(joint), -0.1),
                Vector3(0.025, 0.035, 0.135), 0.0, copper)
    # Segmented heat shielding: accents on the four faces, not random bright foil.
    for face in range(4):
        var angle: float = float(face) * PI * 0.5
        for row in range(3):
            var location := Vector3(sin(angle) * 0.82,
                -0.83 + float(row) * 0.22, cos(angle) * 0.82)
            _box("DescentSeam_%d_%d" % [face, row], location,
                Vector3(0.47, 0.015, 0.025), -angle, gold if row == 1 else dark)
    # Low-profile angular instrument packages; stays inside the old art envelope.
    for side in [-1.0, 1.0]:
        _box("AvionicsPlate_%d" % int(side),
            Vector3(float(side) * 0.45, 1.25, 0.39),
            Vector3(0.28, 0.18, 0.04), 0.0, dark)
        _box("AvionicsLabel_%d" % int(side),
            Vector3(float(side) * 0.45, 1.25, 0.414),
            Vector3(0.16, 0.03, 0.009), 0.0, titanium)


func _detail_f13_realism(titanium: StandardMaterial3D, dark: StandardMaterial3D,
        copper: StandardMaterial3D, gold: StandardMaterial3D,
        ceramic: StandardMaterial3D) -> void:
    # More pronounced descent engine housing.
    _cylinder("EngineBellOuter", Vector3(0.0, -1.19, 0.0), 0.18, 0.36, 0.54, dark)
    _cylinder("EngineBellLip", Vector3(0.0, -1.43, 0.0), 0.39, 0.39, 0.035, titanium)
    _cylinder("EngineGimbalCollar", Vector3(0.0, -0.97, 0.0), 0.25, 0.25, 0.11, titanium)
    _cylinder("EngineInjectorRing", Vector3(0.0, -1.03, 0.0), 0.14, 0.14, 0.04, copper)

    # Upper cabin belt and faceted payload deck to give the craft more structure.
    _cylinder("CabinBelt", Vector3(0.0, 0.83, 0.0), 0.70, 0.72, 0.08, titanium)
    for face in range(8):
        var angle: float = TAU * float(face) / 8.0
        var pos := Vector3(sin(angle) * 0.52, 1.33, cos(angle) * 0.52)
        _box("CabinFacet_%d" % face, pos, Vector3(0.17, 0.20, 0.03), -angle, ceramic)

    # Larger footpads and secondary support geometry for a more believable landing gear.
    var leg_data := [
        {"sx": -1.0, "sz": -1.0, "idx": 0},
        {"sx": 1.0, "sz": -1.0, "idx": 1},
        {"sx": -1.0, "sz": 1.0, "idx": 2},
        {"sx": 1.0, "sz": 1.0, "idx": 3}
    ]
    for entry in leg_data:
        var sx: float = float(entry["sx"])
        var sz: float = float(entry["sz"])
        var idx: int = int(entry["idx"])
        var xrot: float = 18.0 * sz
        var zrot: float = -18.0 * sx
        _box("LegShoulder_%d" % idx,
            Vector3(sx * 0.67, -0.12, sz * 0.67),
            Vector3(0.18, 0.12, 0.22), 0.0, titanium)
        _cylinder("LegMainTube_%d" % idx,
            Vector3(sx * 0.84, -0.78, sz * 0.84),
            0.040, 0.040, 1.30, titanium, Vector3(xrot, 0.0, zrot))
        _cylinder("LegSecondaryTube_%d" % idx,
            Vector3(sx * 0.68, -0.92, sz * 0.68),
            0.028, 0.028, 0.95, dark, Vector3(xrot * 1.7, 0.0, zrot * 1.7))
        _cylinder("LegActuatorSleeve_%d" % idx,
            Vector3(sx * 0.93, -0.98, sz * 0.93),
            0.052, 0.052, 0.38, copper, Vector3(xrot, 0.0, zrot))
        _cylinder("FootRim_%d" % idx,
            Vector3(sx * 1.05, -1.53, sz * 1.05),
            0.43, 0.39, 0.055, titanium)
        _cylinder("FootPadInner_%d" % idx,
            Vector3(sx * 1.05, -1.50, sz * 1.05),
            0.28, 0.33, 0.03, gold)
        _box("FootHinge_%d" % idx,
            Vector3(sx * 0.98, -1.36, sz * 0.98),
            Vector3(0.10, 0.07, 0.12), 0.0, dark)

    # RCS pods for visible side manoeuvring; visual only.
    var thruster_faces := [
        {"name": "Fore", "pos": Vector3(0.0, 0.96, -0.72), "spin": 0.0},
        {"name": "Aft", "pos": Vector3(0.0, 0.96, 0.72), "spin": PI},
        {"name": "Port", "pos": Vector3(-0.72, 0.96, 0.0), "spin": PI * 0.5},
        {"name": "Starboard", "pos": Vector3(0.72, 0.96, 0.0), "spin": -PI * 0.5}
    ]
    for thruster_face in thruster_faces:
        var tag := String(thruster_face["name"])
        var center: Vector3 = thruster_face["pos"]
        var spin: float = float(thruster_face["spin"])
        _box("RCSPod_%s" % tag, center, Vector3(0.24, 0.16, 0.24), spin, dark)
        _box("RCSPodPanel_%s" % tag, center + Vector3(0.0, 0.0, 0.02), Vector3(0.17, 0.09, 0.04), spin, titanium)
        for nozzle_index in range(2):
            var offset_y: float = -0.04 + 0.08 * float(nozzle_index)
            var nozzle_pos := center + Basis(Vector3.UP, spin) * Vector3(0.0, offset_y, -0.16)
            _cylinder("RCSNozzle_%s_%d" % [tag, nozzle_index], nozzle_pos,
                0.032, 0.046, 0.09, copper, Vector3(90.0, rad_to_deg(spin), 0.0))

    # Small sensors and a radar pack on the forward face.
    _box("RadarPack", Vector3(0.0, 0.35, -0.78), Vector3(0.33, 0.18, 0.10), 0.0, dark)
    _box("RadarLensL", Vector3(-0.09, 0.35, -0.84), Vector3(0.06, 0.06, 0.02), 0.0, titanium)
    _box("RadarLensR", Vector3(0.09, 0.35, -0.84), Vector3(0.06, 0.06, 0.02), 0.0, titanium)
    _cylinder("TopBeaconBase", Vector3(0.0, 1.92, -0.02), 0.06, 0.06, 0.12, titanium)
    _cylinder("TopBeaconRod", Vector3(0.0, 2.06, -0.02), 0.015, 0.015, 0.19, copper)


func _glass_mat() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.03, 0.06, 0.09, 1.0)
    material.metallic = 0.04
    material.roughness = 0.06
    material.emission_enabled = true
    material.emission = Color(0.03, 0.09, 0.14)
    material.emission_energy_multiplier = 0.25
    return material


func _panel_mat() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.09, 0.14, 0.19, 1.0)
    material.metallic = 0.45
    material.roughness = 0.26
    material.emission_enabled = true
    material.emission = Color(0.10, 0.17, 0.21)
    material.emission_energy_multiplier = 0.14
    return material


func _pbr_mat(family: String, tint: Color, metal: float, rough: float) -> StandardMaterial3D:
    var material := _mat(tint, metal, rough)
    match family:
        "gold_foil":
            material.albedo_texture = GOLD_ALBEDO
            material.normal_enabled = true
            material.normal_texture = GOLD_NORMAL
            material.normal_scale = 0.70
            material.roughness_texture = GOLD_ROUGHNESS
        "cabin_ceramic":
            material.albedo_texture = CERAMIC_ALBEDO
            material.normal_enabled = true
            material.normal_texture = CERAMIC_NORMAL
            material.normal_scale = 0.46
            material.roughness_texture = CERAMIC_ROUGHNESS
        _:
            pass
    return material


func _mat(tint: Color, metal: float, rough: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    material.metallic = metal
    material.roughness = rough
    return material


func _box(label: String, at: Vector3, size: Vector3, spin: float,
        material: StandardMaterial3D) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    var item := MeshInstance3D.new()
    item.name = label
    item.mesh = mesh
    item.position = at
    item.rotation.y = spin
    item.material_override = material
    add_child(item)


func _cylinder(label: String, at: Vector3, upper: float, lower: float, height: float,
        material: StandardMaterial3D, angles: Vector3 = Vector3.ZERO) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = upper
    mesh.bottom_radius = lower
    mesh.height = height
    mesh.radial_segments = 16
    var item := MeshInstance3D.new()
    item.name = label
    item.mesh = mesh
    item.position = at
    item.rotation_degrees = angles
    item.material_override = material
    add_child(item)
