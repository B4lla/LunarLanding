extends Node
## Optional visual demo only; normal gameplay and remote/TCP never run this code.
## Launch Godot with: --path . -- --rl-vfx-showcase
@onready var rocket: RocketPhysics = get_parent().get_node("Rocket")
@onready var main: Node3D = get_parent()

var demo_enabled := false
var elapsed := 0.0
var stage := -1

func _ready() -> void:
    demo_enabled = OS.get_cmdline_user_args().has("--rl-vfx-showcase")
    if not demo_enabled or DisplayServer.get_name() == "headless":
        set_process(false)
        return
    call_deferred("_activate_demo")

func _activate_demo() -> void:
    # Freeze only this explicitly selected test mode; physics / RL stay unchanged.
    rocket.freeze = true
    rocket._reset_requested = false
    rocket.controls_enabled = false
    rocket.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 6.5, 0.0))
    rocket.linear_velocity = Vector3.ZERO
    rocket.angular_velocity = Vector3.ZERO
    main.set("camera_follow", true)
    main.get_node("Camera3D").call("set_zoom_factor", 1.30)
    print("F22 SHOWCASE READY: frozen lander at 6.5 m, chase camera. 1=engine, W/A/S/D/Q/E=RCS.")

func _process(delta: float) -> void:
    if not demo_enabled or not rocket.freeze:
        return
    elapsed += delta
    var next_stage := int(elapsed / 2.4) % 6
    if next_stage == stage:
        return
    stage = next_stage
    rocket.set_throttle(0.88)
    match stage:
        0:
            rocket.set_attitude_inputs(0.0, 0.0, 0.0)
            print("F22 SHOWCASE: engine plume")
        1:
            rocket.set_attitude_inputs(0.0, 1.0, 0.0)
            print("F22 SHOWCASE: side jet port")
        2:
            rocket.set_attitude_inputs(0.0, -1.0, 0.0)
            print("F22 SHOWCASE: side jet starboard")
        3:
            rocket.set_attitude_inputs(1.0, 0.0, 0.0)
            print("F22 SHOWCASE: pitch jet aft")
        4:
            rocket.set_attitude_inputs(-1.0, 0.0, 0.0)
            print("F22 SHOWCASE: pitch jet fore")
        5:
            rocket.set_attitude_inputs(0.0, 0.0, 1.0)
            print("F22 SHOWCASE: yaw RCS")
