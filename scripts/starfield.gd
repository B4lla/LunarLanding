extends Node3D
## Sparse stars for a vacuum sky. Unlit geometry, never collisions or physics.
## Instanced once. Follows only the active camera position, without parallax.

const STAR_COUNT: int = 330
const SKY_RADIUS: float = 240.0

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        set_process(false)
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261018
    var quad := QuadMesh.new()
    quad.size = Vector2(0.34, 0.34)
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.vertex_color_use_as_albedo = true
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    quad.material = mat
    var batch := MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.use_colors = true
    batch.mesh = quad
    batch.instance_count = STAR_COUNT
    for index in range(STAR_COUNT):
        var longitude: float = rng.randf_range(-PI, PI)
        var latitude: float = rng.randf_range(-0.20, 1.0)
        var direction := Vector3(cos(longitude) * sqrt(1.0 - latitude * latitude),
            latitude, sin(longitude) * sqrt(1.0 - latitude * latitude))
        var brightness: float = rng.randf_range(0.28, 0.65)
        var size: float = rng.randf_range(0.36, 1.05)
        batch.set_instance_transform(index, Transform3D(
            Basis.IDENTITY.scaled(Vector3.ONE * size), direction * SKY_RADIUS))
        batch.set_instance_color(index, Color(brightness * 0.85,
            brightness * 0.92, brightness, 1.0))
    var points := MultiMeshInstance3D.new()
    points.name = "StarsNoCollision"
    points.multimesh = batch
    points.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(points)
    _follow_camera()


func _process(_delta: float) -> void:
    _follow_camera()


func _follow_camera() -> void:
    var camera := get_viewport().get_camera_3d()
    if camera != null:
        global_position = camera.global_position
