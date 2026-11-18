extends Node3D
## Manual controls retained; optional F03 remote scene disables keyboard/PID writes.

const PHYSICS_CONFIG: PhysicsConfig = preload("res://config/lunar.tres")

@onready var rocket: RocketPhysics = $Rocket
@onready var episode: EpisodeController = $EpisodeController
@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera3D = $Camera3D

var external_control: bool = false
var use_reference_pid: bool = false
var camera_follow: bool = false
var remote_hosted: bool = false
var _pid: ReferenceController = ReferenceController.new()
# F02: only release attitude inputs previously owned by keyboard controls.
# External GDScript callers (e.g., the physical integration tests) must not
# be overridden by a headless/manual scene with no keys pressed.
var _keyboard_attitude_active: bool = false
var _hud_update_elapsed: float = 0.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # Fail closed if the remote bridge script does not parse or start: never
    # let the F02 manual descent masquerade as a running TCP server.
    remote_hosted = get_parent().name == "RemoteServer"
    if remote_hosted:
        external_control = true
        rocket.process_mode = Node.PROCESS_MODE_PAUSABLE
        episode.process_mode = Node.PROCESS_MODE_PAUSABLE
        get_tree().paused = true
        $HUD/Panel/Margin/VBox/Title.text = "ROCKET LANDING / REMOTE"
    camera.look_at(Vector3(0.0, 25.0, 0.0), Vector3.UP)
    var configured_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
    if not is_equal_approx(configured_gravity, PHYSICS_CONFIG.lunar_gravity_m_s2):
        push_error("F02: project gravity differs from config/lunar.tres")
    if ProjectSettings.get_setting("physics/3d/physics_engine") != "Jolt Physics":
        push_error("F02 requires Jolt Physics")


func _physics_process(delta: float) -> void:
    if external_control or get_tree().paused or episode.is_finished():
        return
    if use_reference_pid:
        rocket.set_throttle(_pid.calculate_throttle(rocket, delta))
        rocket.set_attitude_inputs(0.0, 0.0, 0.0)
    else:
        var adjust: float = 0.0
        if Input.is_key_pressed(KEY_UP):
            adjust += PHYSICS_CONFIG.throttle_change_per_second * delta
        if Input.is_key_pressed(KEY_DOWN):
            adjust -= PHYSICS_CONFIG.throttle_change_per_second * delta
        if adjust != 0.0:
            rocket.set_throttle(rocket.throttle + adjust)
        var key_pitch: float = float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
        var key_roll: float = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
        var key_yaw: float = float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
        if key_pitch != 0.0 or key_roll != 0.0 or key_yaw != 0.0:
            rocket.set_attitude_inputs(key_pitch, key_roll, key_yaw)
            _keyboard_attitude_active = true
        elif _keyboard_attitude_active:
            # Releasing a manual command neutralizes the keyboard's prior
            # command, without erasing values set programmatically by tests.
            rocket.set_attitude_inputs(0.0, 0.0, 0.0)
            _keyboard_attitude_active = false


func _process(_delta: float) -> void:
    # Camera is display-only; no physics, input or TCP state is written here.
    camera.call("update_visual_framing", _delta, rocket.global_position, camera_follow)
    # 10 Hz is ample for numerical cockpit telemetry and prevents F25-era
    # Control._draw geometry from invalidating every render frame.
    _hud_update_elapsed += maxf(_delta, 0.0)
    if _hud_update_elapsed >= 0.1:
        _hud_update_elapsed = fmod(_hud_update_elapsed, 0.1)
        hud.call("set_telemetry", rocket, episode, get_tree().paused,
            use_reference_pid, camera_follow)
    if remote_hosted and get_parent().get_script() == null:
        $HUD/Panel/Margin/VBox/Mode.text = "ERROR: TCP BRIDGE NOT LOADED; check debugger"


func _unhandled_key_input(event: InputEvent) -> void:
    if external_control or not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_R:
            reset_simulation()
            get_viewport().set_input_as_handled()
        KEY_P:
            toggle_pause()
            get_viewport().set_input_as_handled()
        KEY_0:
            if not get_tree().paused and not episode.is_finished() and not use_reference_pid:
                rocket.set_throttle(0.0)
            get_viewport().set_input_as_handled()
        KEY_1:
            if not get_tree().paused and not episode.is_finished() and not use_reference_pid:
                rocket.set_throttle(1.0)
            get_viewport().set_input_as_handled()
        KEY_T:
            if not get_tree().paused and not episode.is_finished():
                use_reference_pid = not use_reference_pid
                _pid.reset()
                _keyboard_attitude_active = false
                rocket.set_attitude_inputs(0.0, 0.0, 0.0)
            get_viewport().set_input_as_handled()
        KEY_C:
            camera_follow = not camera_follow
            camera.call("invalidate_framing")
            get_viewport().set_input_as_handled()
        KEY_N:
            reset_simulation(true)
            get_viewport().set_input_as_handled()


func reset_simulation(random_start: bool = false) -> void:
    get_tree().paused = false
    use_reference_pid = false
    _pid.reset()
    _keyboard_attitude_active = false
    episode.reset_episode(episode.episode_seed + 1 if random_start else 12345, random_start)


func toggle_pause() -> void:
    get_tree().paused = not get_tree().paused
