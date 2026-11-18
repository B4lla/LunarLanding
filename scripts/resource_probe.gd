extends Node
## F11 exported-release resource proof. Active ONLY with --rl-verify-assets.
## Reads Godot's installed PCK through ResourceLoader, not the source folder.
## No physics, observation, TCP, or normal-scene behavior is changed.

const CORE: Dictionary = {
    "scenes/main.tscn": "PackedScene",
    "scenes/remote.tscn": "PackedScene",
    "scenes/rocket.tscn": "PackedScene",
    "scenes/terrain.tscn": "PackedScene",
    "assets/materials/regolith_fallback.gdshader": "Shader",
    "assets/audio/engine.wav": "AudioStreamWAV",
    "assets/audio/rcs.wav": "AudioStreamWAV",
    "assets/audio/touchdown.wav": "AudioStreamWAV",
}
const F34_PBR_FILES: Array[String] = [
    "assets/terrain_materials/regolith_albedo.png",
    "assets/terrain_materials/regolith_normal.png",
    "assets/terrain_materials/regolith_roughness.png",
    "assets/terrain_materials/pad_deck_albedo.png",
    "assets/terrain_materials/pad_deck_normal.png",
    "assets/terrain_materials/pad_deck_roughness.png",
    "assets/terrain_materials/service_deck_albedo.png",
    "assets/terrain_materials/service_deck_normal.png",
    "assets/terrain_materials/service_deck_roughness.png",
]
const NASA_FILE: String = "assets/nasa/apollo_lunar_module.glb"
const NASA_RECEIPT: String = "assets/nasa/nasa_download_receipt.json"
const PBR_FILES: Array[String] = [
    "assets/polyhaven/rocks_ground_01_diff_1k.jpg",
    "assets/polyhaven/rocks_ground_01_nor_gl_1k.png",
    "assets/polyhaven/rocks_ground_01_rough_1k.jpg",
]
const PBR_RECEIPT: String = "assets/polyhaven/download_receipt.json"


func _ready() -> void:
    if not OS.get_cmdline_user_args().has("--rl-verify-assets"):
        return
    var checks: Dictionary = {}
    var errors: Array[String] = []
    for relative_path in CORE:
        var res: Resource = ResourceLoader.load("res://" + str(relative_path))
        var kind: String = str(CORE[relative_path])
        var ok: bool = false
        if kind == "PackedScene":
            ok = res is PackedScene
        elif kind == "AudioStreamWAV":
            ok = res is AudioStreamWAV
        elif kind == "Shader":
            ok = res is Shader
        checks[relative_path] = ok
        if not ok:
            errors.append("Missing/unloadable core resource: " + relative_path)

    # F34 resources are mandatory. Unlike optional NASA/Poly Haven assets,
    # every packaged build must import all nine texture channels correctly.
    var f34_checks: Dictionary = {}
    for relative_path in F34_PBR_FILES:
        var f34_tex: Texture2D = ResourceLoader.load("res://" + relative_path) as Texture2D
        var available: bool = f34_tex != null
        f34_checks[relative_path] = available
        if not available:
            errors.append("F34 texture not imported in exported PCK: " + relative_path)

    var nasa_present: bool = _raw_present(NASA_FILE) or _raw_present(NASA_RECEIPT)
    if nasa_present:
        if not _raw_present(NASA_FILE) or not _raw_present(NASA_RECEIPT):
            errors.append("Incomplete NASA model/receipt in exported PCK")
        else:
            var nasa_receipt: Variant = JSON.parse_string(
                FileAccess.get_file_as_string("res://" + NASA_RECEIPT))
            if not (nasa_receipt is Dictionary) or str(nasa_receipt.get("file", "")) != NASA_FILE:
                errors.append("NASA receipt has an unexpected schema/path")
            elif not _matches_receipt_hash(NASA_FILE, nasa_receipt):
                errors.append("NASA bytes in PCK do not match acquisition receipt")
            if not (ResourceLoader.load("res://" + NASA_FILE) is PackedScene):
                errors.append("NASA model is not an imported PackedScene")
    var pbr_present: bool = _raw_present(PBR_RECEIPT)
    for file in PBR_FILES:
        pbr_present = pbr_present or _raw_present(file)
    if pbr_present:
        if not _raw_present(PBR_RECEIPT):
            errors.append("Missing Poly Haven PBR receipt in exported PCK")
        var pbr_receipt: Variant = null
        if _raw_present(PBR_RECEIPT):
            pbr_receipt = JSON.parse_string(
                FileAccess.get_file_as_string("res://" + PBR_RECEIPT))
        if not (pbr_receipt is Array) or pbr_receipt.size() != PBR_FILES.size():
            errors.append("PBR receipt must contain exactly three maps")
        for file in PBR_FILES:
            if not _raw_present(file):
                errors.append("Missing PBR raw texture: " + file)
                continue
            if not (ResourceLoader.load("res://" + file) is Texture2D):
                errors.append("PBR texture did not import: " + file)
            var found: int = 0
            if pbr_receipt is Array:
                for entry in pbr_receipt:
                    if entry is Dictionary and str(entry.get("file", "")) == file:
                        found += 1
                        if not _matches_receipt_hash(file, entry):
                            errors.append("PBR bytes in PCK disagree with receipt: " + file)
            if found != 1:
                errors.append("Missing or duplicate PBR acquisition entry: " + file)

    var report: Dictionary = {
        "schema_version": 1,
        "probe": "F11_EXPORTED_RESOURCE_PROBE",
        "status": "PASS" if errors.is_empty() else "FAIL",
        "core_resources": checks,
        "f34_texture_resources": f34_checks,
        "nasa_present": nasa_present,
        "polyhaven_present": pbr_present,
        "errors": errors,
    }
    var serialized: String = JSON.stringify(report) + "\n"
    print("F11_RESOURCE_AUDIT:" + JSON.stringify(report))
    var output_path: String = OS.get_environment("ROCKET_F11_AUDIT_PATH")
    if output_path.is_empty():
        push_error("F11 resource probe requires ROCKET_F11_AUDIT_PATH")
        get_tree().quit(3)
        return
    var destination: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
    if destination == null:
        push_error("F11 resource probe unable to write verification receipt")
        get_tree().quit(3)
        return
    destination.store_string(serialized)
    destination.flush()
    destination.close()
    get_tree().quit(0 if errors.is_empty() else 3)


func _raw_present(path: String) -> bool:
    return FileAccess.file_exists("res://" + path)


func _matches_receipt_hash(relative_path: String, entry: Dictionary) -> bool:
    var raw: String = "res://" + relative_path
    if not _raw_present(relative_path):
        return false
    var sha: String = str(entry.get("sha256", ""))
    if sha.length() != 64 or str(entry.get("status", "")) != "OK":
        return false
    return (FileAccess.get_file_as_bytes(raw).size() == int(entry.get("size_bytes", -1))
        and FileAccess.get_sha256(raw) == sha)
