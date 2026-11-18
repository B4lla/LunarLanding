extends Camera3D
## Third visual-only observer, independent of manual/follow C and TCP/Jolt.

@onready var rocket: RocketPhysics = get_node("../Rocket")
@onready var baseline: Camera3D = get_node("../Camera3D")
@onready var simulation: Node3D = get_parent()
const OBSERVER_DISTANCE_SCALE := 0.72
var zoom_factor: float = 1.0

func set_zoom_factor(value: float) -> void:
    zoom_factor = clampf(value, 0.80, 1.35)


func _ready() -> void:
    current = false
    if DisplayServer.get_name() == "headless":
        set_process(false)
        set_process_unhandled_key_input(false)

func _process(delta: float) -> void:
    if not current:
        return
    var wanted := rocket.global_position + Vector3(8.0, 4.0, 12.5) * OBSERVER_DISTANCE_SCALE / zoom_factor
    global_position = global_position.lerp(wanted, 1.0 - exp(-4.0 * delta))
    look_at(rocket.global_position + Vector3(0.0, 0.35, 0.0), Vector3.UP)

func _unhandled_key_input(event: InputEvent) -> void:
    if simulation.get("external_control") or not event is InputEventKey:
        return
    if event.pressed and not event.echo and event.keycode == KEY_V:
        if current:
            baseline.make_current()
            baseline.call("invalidate_framing")
        else:
            global_position = rocket.global_position + Vector3(8.0, 4.0, 12.5) * OBSERVER_DISTANCE_SCALE / zoom_factor
            look_at(rocket.global_position, Vector3.UP)
            make_current()
        get_viewport().set_input_as_handled()
