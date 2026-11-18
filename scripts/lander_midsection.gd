extends Node3D
## F37: closes the empty gap between the descent stage and the crew cabin.
## This is a passive art-only assembly underneath VisualDetail. Collision,
## center of mass, thrust and training observations are deliberately untouched.

const FOIL_ALBEDO: Texture2D = preload("res://assets/procedural/gold_foil_albedo.png")
const FOIL_NORMAL: Texture2D = preload("res://assets/procedural/gold_foil_normal.png")

func build_visuals() -> void:
    if DisplayServer.get_name() == "headless" or get_child_count() > 0:
        return
    var shell := StandardMaterial3D.new()
    shell.albedo_color = Color(0.42, 0.46, 0.45)
    shell.metallic = 0.54
    shell.roughness = 0.65
    var foil := StandardMaterial3D.new()
    foil.albedo_color = Color(0.73, 0.60, 0.38)
    foil.albedo_texture = FOIL_ALBEDO
    foil.normal_enabled = true
    foil.normal_texture = FOIL_NORMAL
    foil.normal_scale = 0.32
    foil.metallic = 0.55
    foil.roughness = 0.63
    var frame := StandardMaterial3D.new()
    frame.albedo_color = Color(0.20, 0.23, 0.25)
    frame.metallic = 0.65
    frame.roughness = 0.48

    # Upper cabin begins at Y 0.515; lower foil module ends at Y -0.320.
    # One continuous tapered octagonal center section is visible from all sides.
    var core := CylinderMesh.new()
    core.top_radius = 0.575
    core.bottom_radius = 0.755
    core.height = 0.79
    core.radial_segments = 8
    _mesh("F37SealedCenterBody", core, shell, Vector3(0, 0.065, 0))

    # Outer jackets must not overlap the thin F13 belts or obscure RCS ports.
    var jacket := CylinderMesh.new()
    jacket.top_radius = 0.664
    jacket.bottom_radius = 0.765
    jacket.height = 0.34
    jacket.radial_segments = 8
    _mesh("F37LowerThermalJacket", jacket, foil, Vector3(0, -0.115, 0))

    var ring_mesh := CylinderMesh.new()
    ring_mesh.top_radius = 0.70
    ring_mesh.bottom_radius = 0.70
    ring_mesh.height = 0.055
    ring_mesh.radial_segments = 12
    _mesh("F37UpperInterfaceRing", ring_mesh, frame, Vector3(0, 0.438, 0))

    # Four unobtrusive equipment bays on the outside, not a hollow frame.
    var bay_mesh := BoxMesh.new()
    bay_mesh.size = Vector3(0.27, 0.26, 0.07)
    for index in range(4):
        var angle: float = TAU * (float(index) + 0.5) / 4.0
        var bay := _mesh("F37EquipmentBay_%d" % index, bay_mesh, frame,
            Vector3(sin(angle) * 0.677, 0.116, cos(angle) * 0.677))
        bay.rotation.y = angle
        bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mesh(label: String, shape: Mesh, material: Material,
        location: Vector3) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    item.name = label
    item.mesh = shape
    item.material_override = material
    item.position = location
    add_child(item)
    return item
