extends Node3D
## F05 optional NASA GLB preview. Purely presentational and disabled by default.
## Never changes the parent RigidBody3D, its collision, physics settings or actions.
## Enabled only via ROCKET_F05_NASA_PREVIEW=1 and a SHA-256-verified receipt.

const MODEL_PATH := "res://assets/nasa/apollo_lunar_module.glb"
const RECEIPT_PATH := "res://assets/nasa/nasa_download_receipt.json"
const OFFICIAL_SOURCE := "https://raw.githubusercontent.com/nasa/NASA-3D-Resources/master/3D%20Models/Apollo%20Lunar%20Module/Apollo%20Lunar%20Module.glb"
const MAX_FILE_BYTES := 5 * 1024 * 1024
const MAX_WIDTH_M := 2.60
const MAX_HEIGHT_M := 2.85
const MAX_DEPTH_M := 2.60


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    if OS.get_environment("ROCKET_F05_NASA_PREVIEW") != "1":
        return
    if not _receipt_is_authentic():
        push_warning("F05 NASA preview disabled: no valid model/receipt with matching SHA-256")
        return
    if not ResourceLoader.exists(MODEL_PATH):
        push_warning("F05 NASA preview disabled: GLB not imported; reopen Godot editor")
        return

    var packed: PackedScene = load(MODEL_PATH) as PackedScene
    if packed == null:
        push_warning("F05 NASA preview disabled: unable to load GLB scene")
        return
    var imported: Node = packed.instantiate()
    if not imported is Node3D or _contains_forbidden_nodes(imported):
        imported.free()
        push_warning("F05 NASA preview rejected: model must contain only passive visual nodes")
        return
    var imported_3d: Node3D = imported as Node3D
    add_child(imported_3d)
    var bounds: AABB = _mesh_bounds_in_preview_space(imported_3d)
    var extents: Vector3 = bounds.size
    if not extents.is_finite() or extents.x <= 0.0001 or extents.y <= 0.0001 or extents.z <= 0.0001:
        imported_3d.queue_free()
        push_warning("F05 NASA preview rejected: empty, flat or non-finite bounds")
        return
    # Fit the art inside the legacy physical envelope; no collider is rescaled.
    var factor: float = minf(MAX_WIDTH_M / extents.x,
                            minf(MAX_HEIGHT_M / extents.y, MAX_DEPTH_M / extents.z))
    if not is_finite(factor) or factor <= 0.0:
        imported_3d.queue_free()
        push_warning("F05 NASA preview rejected: invalid normalization scale")
        return
    imported_3d.scale = Vector3.ONE * factor
    imported_3d.position = -(bounds.position + extents * 0.5) * factor
    _hide_procedural_art()
    print("F05 NASA PREVIEW PASS: verified GLB displayed, visual fit=", factor,
          ", original Jolt collider untouched")


func _receipt_is_authentic() -> bool:
    if not FileAccess.file_exists(MODEL_PATH) or not FileAccess.file_exists(RECEIPT_PATH):
        return false
    var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH))
    if not receipt is Dictionary:
        return false
    if receipt.get("status") != "OK":
        return false
    if receipt.get("file") != "assets/nasa/apollo_lunar_module.glb":
        return false
    if receipt.get("source") != OFFICIAL_SOURCE:
        return false
    if typeof(receipt.get("size_bytes")) != TYPE_INT and typeof(receipt.get("size_bytes")) != TYPE_FLOAT:
        return false
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(MODEL_PATH)
    if bytes.size() < 28 or bytes.size() > MAX_FILE_BYTES:
        return false
    if bytes.size() != int(receipt.get("size_bytes")):
        return false
    var expected: String = str(receipt.get("sha256", ""))
    if expected.length() != 64:
        return false
    return FileAccess.get_sha256(MODEL_PATH) == expected


func _contains_forbidden_nodes(node: Node) -> bool:
    if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
        return true
    if node is Joint3D or node.get_script() != null:
        return true
    for child in node.get_children():
        if _contains_forbidden_nodes(child):
            return true
    return false


func _mesh_bounds_in_preview_space(root: Node3D) -> AABB:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var started := false
    var minimum := Vector3.ZERO
    var maximum := Vector3.ZERO
    for mesh in meshes:
        if mesh.mesh == null:
            continue
        var local_bounds: AABB = mesh.get_aabb()
        var to_preview: Transform3D = global_transform.affine_inverse() * mesh.global_transform
        for dx in [0.0, 1.0]:
            for dy in [0.0, 1.0]:
                for dz in [0.0, 1.0]:
                    var corner := local_bounds.position + local_bounds.size * Vector3(dx, dy, dz)
                    var point: Vector3 = to_preview * corner
                    if not point.is_finite():
                        return AABB()
                    if not started:
                        minimum = point
                        maximum = point
                        started = true
                    else:
                        minimum = minimum.min(point)
                        maximum = maximum.max(point)
    if not started:
        return AABB()
    return AABB(minimum, maximum - minimum)


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        meshes.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, meshes)


func _hide_procedural_art() -> void:
    var physical_rocket: Node = get_parent()
    for node_name in ["BodyMesh", "Nozzle", "LegPadMeshFL", "LegPadMeshFR",
                      "LegPadMeshBL", "LegPadMeshBR", "StrutFL", "StrutFR",
                      "StrutBL", "StrutBR", "VisualDetail"]:
        var art: Node3D = physical_rocket.get_node_or_null(node_name) as Node3D
        if art != null:
            art.visible = false
