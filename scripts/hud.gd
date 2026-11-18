extends CanvasLayer
## F25 perimeter HUD with a flight-sim inspired edge layout.
## Presentation only; physics, input and TCP remain untouched.
## Stable F05/F18 node paths are retained for native/remote compatibility.

const HudCompassDisplayScript = preload("res://scripts/hud_compass_display.gd")
const HudTapeGaugeScript = preload("res://scripts/hud_tape_gauge.gd")
const HudArcGaugeScript = preload("res://scripts/hud_arc_gauge.gd")

const TEXT_PRIMARY := Color(0.93, 0.97, 0.99)
const TEXT_SECONDARY := Color(0.58, 0.72, 0.78)
const COLOR_NORMAL := Color(0.40, 0.89, 0.88)
const COLOR_CAUTION := Color(1.0, 0.76, 0.39)
const COLOR_DANGER := Color(1.0, 0.40, 0.40)
const PANEL_BG := Color(0.08, 0.10, 0.13, 0.92)
const PANEL_BORDER := Color(0.25, 0.29, 0.34, 1.0)

@onready var altitude_label: Label = $Panel/Margin/VBox/Altitude
@onready var speed_label: Label = $Panel/Margin/VBox/VerticalSpeed
@onready var position_label: Label = $Panel/Margin/VBox/Horizontal
@onready var attitude_label: Label = $Panel/Margin/VBox/Attitude
@onready var fuel_label: Label = $Panel/Margin/VBox/Fuel
@onready var fuel_bar: ProgressBar = $Panel/Margin/VBox/FuelBar
@onready var throttle_label: Label = $Panel/Margin/VBox/Throttle
@onready var throttle_bar: ProgressBar = $Panel/Margin/VBox/ThrottleBar
@onready var status_label: Label = $Panel/Margin/VBox/Status
@onready var mode_label: Label = $Panel/Margin/VBox/Mode
@onready var controls_label: Label = $Panel/Margin/VBox/Controls

# F37 compact flight HUD. Legacy F24/F25 widgets remain available but are not
# instantiated at runtime: they obscured the landing trajectory and cost draws.
var compact_altitude: Label
var compact_motion: Label
var compact_engine: Label
var compact_fuel: Label
var compact_status: Label
var compact_controls: Label
var compact_hint: Label
var compact_nav: Control
var compact_controls_panel: PanelContainer

var top_title: Label
var top_mode: Label
var bottom_status: Label
var bottom_controls: Label
var left_compass: Control
var hspeed_tape: Control
var altitude_tape: Control
var vs_tape: Control
var engine_gauge: Control
var twr_gauge: Control
var fuel_gauge: Control
var tilt_gauge: Control
var gimbal_gauge: Control
var rcs_gauge: Control
var burn_info: Label
var fuel_info: Label
var altitude_box: Label
var vs_box: Label
var caution_box: Label


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    _hide_legacy_panel()
    $Panel/Margin/VBox/Title.text = "LM-01 DESCENT HUD / FLIGHT COMPUTER"
    $Panel/Margin/VBox/Mode.text = "MANUAL | WIDE VIEW"
    _build_compact_hud()
    get_viewport().size_changed.connect(_layout_compact)


func _hide_legacy_panel() -> void:
    var panel: PanelContainer = $Panel
    panel.visible = false
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_compact_hud() -> void:
    # F38: minimal instrument clusters with information hierarchy. No floating
    # compass, center stack, tape gauges, or overlay on the rocket trajectory.
    # Keep all flight information accessible via the stable legacy node paths.
    var flight: PanelContainer = _compact_panel("FlightData", false, false, 242.0, 109.0)
    var flight_rows: VBoxContainer = _compact_rows(flight)
    _compact_text(flight_rows, "ALTITUDE / GROUND", true)
    compact_altitude = _compact_text(flight_rows, "50.0 m", false, 28)
    compact_motion = _compact_text(flight_rows, "V/S  -0.0   •   H/S  0.0", false, 12)

    var propulsion: PanelContainer = _compact_panel("PropulsionData", true, false, 232.0, 109.0)
    var engine_rows: VBoxContainer = _compact_rows(propulsion)
    _compact_text(engine_rows, "ENGINE / THROTTLE", true)
    compact_engine = _compact_text(engine_rows, "OFF", false, 27)
    compact_fuel = _compact_text(engine_rows, "FUEL  100%   •   TWR  0.0", false, 12)

    var status: PanelContainer = _compact_panel("StatusData", false, true, 310.0, 30.0)
    var status_rows: VBoxContainer = _compact_rows(status)
    compact_status = _compact_text(status_rows, "DESCENT / STABLE", false, 12)

    # Controls are secondary: small, peripheral, and removed on smaller views.
    compact_controls_panel = _compact_panel("ControlHint", true, true, 342.0, 30.0)
    var controls_rows: VBoxContainer = _compact_rows(compact_controls_panel)
    compact_controls = _compact_text(controls_rows,
        "1 ENGINE   |   WASD/QE   |   F1 SETTINGS", false, 11)
    _layout_compact()


func _compact_panel(tag: String, right: bool, bottom: bool,
        width: float, height: float) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.name = tag
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.anchor_left = 1.0 if right else 0.0
    panel.anchor_right = panel.anchor_left
    panel.anchor_top = 1.0 if bottom else 0.0
    panel.anchor_bottom = panel.anchor_top
    panel.offset_left = -width - 16.0 if right else 16.0
    panel.offset_right = -16.0 if right else width + 16.0
    panel.offset_top = -height - 14.0 if bottom else 14.0
    panel.offset_bottom = -14.0 if bottom else height + 14.0
    var styling := StyleBoxFlat.new()
    styling.bg_color = Color(0.029, 0.044, 0.061, 0.79)
    styling.border_width_left = 2
    styling.border_color = Color(0.30, 0.78, 0.84, 0.80)
    styling.corner_radius_top_left = 3
    styling.corner_radius_top_right = 3
    styling.corner_radius_bottom_left = 3
    styling.corner_radius_bottom_right = 3
    panel.add_theme_stylebox_override("panel", styling)
    add_child(panel)
    return panel


func _compact_rows(panel: PanelContainer) -> VBoxContainer:
    var margins := MarginContainer.new()
    margins.add_theme_constant_override("margin_left", 12)
    margins.add_theme_constant_override("margin_right", 10)
    margins.add_theme_constant_override("margin_top", 4)
    margins.add_theme_constant_override("margin_bottom", 4)
    panel.add_child(margins)
    var rows := VBoxContainer.new()
    rows.add_theme_constant_override("separation", 1)
    margins.add_child(rows)
    return rows


func _compact_text(parent: VBoxContainer, content: String,
        heading: bool = false, font_size: int = 0) -> Label:
    var label := Label.new()
    label.text = content
    label.add_theme_font_size_override("font_size", font_size if font_size > 0 else (11 if heading else 12))
    label.add_theme_color_override("font_color", TEXT_SECONDARY if heading else TEXT_PRIMARY)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.clip_text = true
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    parent.add_child(label)
    return label


func _layout_compact() -> void:
    var viewport_width: float = get_viewport().get_visible_rect().size.x
    # F37 compatibility threshold: viewport_width >= 1040.0 hides the shortcut
    # panel on smaller viewports; never allow two bottom cards to overlap.
    if compact_controls_panel != null:
        compact_controls_panel.visible = viewport_width >= 1040.0

func _build_top_strip() -> void:
    var title_panel := _new_panel("TopTitleStrip", Control.PRESET_TOP_WIDE, 250.0, 8.0, -250.0, 34.0)
    add_child(title_panel)
    top_title = _panel_label(title_panel, "TopTitle", "LM-01 DESCENT HUD", 14, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)

    var mode_panel := _new_panel("TopModeStrip", Control.PRESET_TOP_WIDE, 8.0, 8.0, -8.0, 34.0)
    mode_panel.offset_left = 260.0
    add_child(mode_panel)
    top_mode = _panel_label(mode_panel, "TopMode", "MANUAL / WIDE VIEW", 13, TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)


func _build_left_navigation_block() -> void:
    var nav_root := Control.new()
    nav_root.name = "LeftNavRoot"
    nav_root.anchor_left = 0.0
    nav_root.anchor_top = 0.0
    nav_root.anchor_right = 0.0
    nav_root.anchor_bottom = 0.0
    nav_root.offset_left = 8.0
    nav_root.offset_top = 42.0
    nav_root.offset_right = 278.0
    nav_root.offset_bottom = 348.0
    nav_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(nav_root)

    left_compass = HudCompassDisplayScript.new()
    left_compass.name = "LeftCompassRose"
    left_compass.position = Vector2(0, 0)
    left_compass.size = Vector2(270, 270)
    nav_root.add_child(left_compass)

    altitude_box = _floating_box(nav_root, "LeftAltBox", Vector2(6, 274), Vector2(122, 28), "ALT RAD 0.0")
    caution_box = _floating_box(nav_root, "LeftCautionBox", Vector2(134, 274), Vector2(136, 28), "PAD TRACK")


func _build_center_instrument_stack() -> void:
    var root := Control.new()
    root.name = "CenterInstrumentStack"
    root.anchor_left = 0.5
    root.anchor_right = 0.5
    root.anchor_top = 1.0
    root.anchor_bottom = 1.0
    root.offset_left = -245.0
    root.offset_right = 80.0
    root.offset_top = -236.0
    root.offset_bottom = -8.0
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    hspeed_tape = HudTapeGaugeScript.new()
    hspeed_tape.name = "HSpeedTape"
    hspeed_tape.position = Vector2(0, 0)
    hspeed_tape.size = Vector2(74, 214)
    root.add_child(hspeed_tape)

    engine_gauge = HudArcGaugeScript.new()
    engine_gauge.name = "MainEngineGauge"
    engine_gauge.position = Vector2(82, 0)
    engine_gauge.size = Vector2(116, 102)
    root.add_child(engine_gauge)

    twr_gauge = HudArcGaugeScript.new()
    twr_gauge.name = "TwrGauge"
    twr_gauge.position = Vector2(82, 110)
    twr_gauge.size = Vector2(116, 102)
    root.add_child(twr_gauge)

    fuel_gauge = _vertical_bar_panel(root, "FuelBarPanel", Vector2(206, 0), Vector2(40, 214), "FUEL")
    tilt_gauge = _vertical_bar_panel(root, "TiltBarPanel", Vector2(252, 0), Vector2(40, 214), "TILT")
    gimbal_gauge = _vertical_bar_panel(root, "GimbalBarPanel", Vector2(298, 0), Vector2(40, 214), "GMBL")
    rcs_gauge = _vertical_bar_panel(root, "RcsBarPanel", Vector2(344, 0), Vector2(40, 214), "RCS")

    burn_info = _floating_box(root, "BurnInfo", Vector2(82, 216), Vector2(150, 22), "BURN 0.0 s")
    fuel_info = _floating_box(root, "FuelInfo", Vector2(236, 216), Vector2(148, 22), "MASS 1000 kg")


func _build_right_vertical_block() -> void:
    var root := Control.new()
    root.name = "RightVerticalBlock"
    root.anchor_left = 1.0
    root.anchor_right = 1.0
    root.anchor_top = 0.0
    root.anchor_bottom = 0.0
    root.offset_left = -184.0
    root.offset_right = -8.0
    root.offset_top = 42.0
    root.offset_bottom = 348.0
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    altitude_tape = HudTapeGaugeScript.new()
    altitude_tape.name = "AltitudeTape"
    altitude_tape.position = Vector2(0, 0)
    altitude_tape.size = Vector2(114, 300)
    root.add_child(altitude_tape)

    vs_tape = HudTapeGaugeScript.new()
    vs_tape.name = "VerticalSpeedTape"
    vs_tape.position = Vector2(120, 0)
    vs_tape.size = Vector2(56, 300)
    root.add_child(vs_tape)

    vs_box = _floating_box(root, "VsReadout", Vector2(120, 302), Vector2(56, 24), "VS 0.0")


func _build_bottom_strip() -> void:
    var left := _new_panel("BottomStatusPanel", Control.PRESET_BOTTOM_WIDE, 8.0, -34.0, -390.0, -8.0)
    add_child(left)
    bottom_status = _panel_label(left, "BottomStatus", "FLT NOMINAL", 12, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)

    var right := _new_panel("BottomControlsPanel", Control.PRESET_BOTTOM_WIDE, 396.0, -34.0, -8.0, -8.0)
    add_child(right)
    bottom_controls = _panel_label(right, "BottomControls", "↑↓ throttle · WASD attitude · QE yaw · C/V cam · T PID · R/N reset", 11, TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)


func _new_panel(node_name: String, preset: int, left: float, top: float, right: float, bottom: float) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.name = node_name
    panel.set_anchors_preset(preset)
    panel.offset_left = left
    panel.offset_top = top
    panel.offset_right = right
    panel.offset_bottom = bottom
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_BG
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1
    style.border_color = PANEL_BORDER
    style.corner_radius_top_left = 2
    style.corner_radius_top_right = 2
    style.corner_radius_bottom_left = 2
    style.corner_radius_bottom_right = 2
    panel.add_theme_stylebox_override("panel", style)
    return panel


func _panel_label(panel: PanelContainer, node_name: String, text: String,
        font_size: int, color: Color, align: HorizontalAlignment) -> Label:
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 8)
    margin.add_theme_constant_override("margin_top", 4)
    margin.add_theme_constant_override("margin_right", 8)
    margin.add_theme_constant_override("margin_bottom", 4)
    panel.add_child(margin)
    var label := Label.new()
    label.name = node_name
    label.text = text
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    margin.add_child(label)
    return label


func _floating_box(parent: Control, node_name: String, at: Vector2, dims: Vector2, text: String) -> Label:
    var panel := PanelContainer.new()
    panel.name = node_name
    panel.position = at
    panel.size = dims
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_BG
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1
    style.border_color = PANEL_BORDER
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)
    return _panel_label(panel, node_name + "Label", text, 11, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)


func _vertical_bar_panel(parent: Control, node_name: String, at: Vector2, dims: Vector2, title: String) -> ProgressBar:
    var panel := PanelContainer.new()
    panel.name = node_name
    panel.position = at
    panel.size = dims
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_BG
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1
    style.border_color = PANEL_BORDER
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)

    var title_label := Label.new()
    title_label.text = title
    title_label.position = Vector2(4, 4)
    title_label.size = Vector2(dims.x - 8, 14)
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title_label.add_theme_font_size_override("font_size", 10)
    title_label.add_theme_color_override("font_color", TEXT_PRIMARY)
    panel.add_child(title_label)

    var bar := ProgressBar.new()
    bar.name = title + "Gauge"
    bar.position = Vector2(dims.x * 0.5 - 7.0, 22)
    bar.size = Vector2(14, dims.y - 46)
    bar.min_value = 0.0
    bar.max_value = 100.0
    bar.show_percentage = false
    bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var track := StyleBoxFlat.new()
    track.bg_color = Color(0.18, 0.20, 0.22)
    var fill := StyleBoxFlat.new()
    fill.bg_color = COLOR_NORMAL
    bar.add_theme_stylebox_override("background", track)
    bar.add_theme_stylebox_override("fill", fill)
    panel.add_child(bar)

    var readout := Label.new()
    readout.name = title + "Readout"
    readout.text = "0"
    readout.position = Vector2(2, dims.y - 20)
    readout.size = Vector2(dims.x - 4, 16)
    readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
    readout.add_theme_font_size_override("font_size", 10)
    readout.add_theme_color_override("font_color", TEXT_SECONDARY)
    panel.add_child(readout)
    return bar


func _set_bar_color(bar: ProgressBar, color: Color) -> void:
    var style: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
    if style != null:
        style.bg_color = color


func _set_aux_readout(progress: ProgressBar, text: String) -> void:
    var label: Label = progress.get_parent().get_node(progress.name.replace("Gauge", "Readout")) as Label
    if label != null:
        label.text = text


func set_telemetry(rocket: RocketPhysics, episode: EpisodeController,
        paused: bool, reference_pid: bool, follow_camera: bool) -> void:
    var center_altitude: float = rocket.center_altitude_m()
    var clearance: float = rocket.collider_clearance_m()
    var vertical: float = rocket.linear_velocity.y
    var horizontal_speed: float = Vector2(rocket.linear_velocity.x, rocket.linear_velocity.z).length()
    var descent_speed: float = maxf(-vertical, 0.0)
    var tilt: float = rocket.tilt_degrees()
    var planar_offset := Vector2(rocket.global_position.x, rocket.global_position.z)
    var planar_distance: float = planar_offset.length()
    var heading := wrapf(rad_to_deg(atan2(-rocket.global_transform.basis.z.x, -rocket.global_transform.basis.z.z)) + 360.0, 0.0, 360.0)
    var course := wrapf(rad_to_deg(atan2(-planar_offset.x, -planar_offset.y)) + 360.0, 0.0, 360.0)
    var drift := wrapf(course - heading + 540.0, 0.0, 360.0) - 180.0
    var thrust_n: float = rocket.throttle * rocket.physics_config.max_thrust_newtons
    var twr: float = 0.0
    if rocket.mass > 0.0 and rocket.physics_config.lunar_gravity_m_s2 > 0.0:
        twr = thrust_n / (rocket.mass * rocket.physics_config.lunar_gravity_m_s2)
    var net_vertical_accel: float = thrust_n / maxf(rocket.mass, 0.001) - rocket.physics_config.lunar_gravity_m_s2
    var fuel_pct: float = clampf(rocket.fuel_fraction() * 100.0, 0.0, 100.0)
    var burn_time_full: float = rocket.fuel_kg / rocket.physics_config.fuel_flow_at_full_kg_s if rocket.physics_config.fuel_flow_at_full_kg_s > 0.0 else 0.0
    var gimbal_mag_pct := clampf(maxf(absf(rocket.gimbal_x), absf(rocket.gimbal_z)) * 100.0, 0.0, 100.0)
    var rcs_pct := clampf(absf(rocket.yaw_rcs) * 100.0, 0.0, 100.0)

    altitude_label.text = "ALTITUDE (CENTER):      %.2f m" % center_altitude
    speed_label.text = "VERTICAL SPEED:    %.2f m/s" % vertical
    position_label.text = "POSITION: X %.1f m | Z %.1f m" % [rocket.global_position.x, rocket.global_position.z]
    attitude_label.text = "TILT: %.1f°" % tilt
    throttle_label.text = "MAIN ENGINE: %3.0f %%" % (rocket.throttle * 100.0)
    throttle_bar.value = rocket.throttle * 100.0
    fuel_label.text = "FUEL: %.1f kg" % rocket.fuel_kg
    fuel_bar.value = fuel_pct
    status_label.text = "EPISODE: %s" % episode.result_name()

    var camera_name := "FOLLOW" if follow_camera else "WIDE VIEW"
    var observer_camera: Camera3D = get_node_or_null("../ObserverCamera") as Camera3D
    if observer_camera != null and observer_camera.current:
        camera_name = "OBSERVER"
    mode_label.text = "%s | %s%s" % ["PID" if reference_pid else "MANUAL", camera_name, " | PAUSED" if paused else ""]
    controls_label.text = "↑↓ throttle · WASD/QE attitude · 0/1 engine\nR reset · N randomize · P pause · C/V camera · T PID"

    if compact_altitude != null:
        compact_altitude.text = "%.1f m" % clearance
    if compact_motion != null:
        compact_motion.text = "V/S %+.1f m/s   H/S %.1f" % [vertical, horizontal_speed]
    if compact_engine != null:
        compact_engine.text = "%d%%" % roundi(rocket.throttle * 100.0) if rocket.throttle > 0.015 else "OFF"
    if compact_fuel != null:
        compact_fuel.text = "FUEL %.0f%%   TWR %.2f" % [fuel_pct, twr]
    if compact_status != null:
        var flight_state: String = "DESCENT / STABLE"
        if paused:
            flight_state = "SIMULATION PAUSED"
        elif descent_speed > rocket.physics_config.safe_vertical_impact_m_s:
            flight_state = "WARNING / FAST DESCENT"
        elif planar_distance > 4.0:
            flight_state = "WARNING / OFF PAD"
        elif episode.is_finished():
            flight_state = episode.result_name()
        compact_status.text = flight_state

    if top_title != null:
        top_title.text = $Panel/Margin/VBox/Title.text if not $Panel/Margin/VBox/Title.text.is_empty() else "LM-01 DESCENT HUD"
    if top_mode != null:
        top_mode.text = "%s   /   %s" % [mode_label.text, "T+ %.1f s" % episode.elapsed_s]
    if bottom_status != null:
        var status_text := "FLT NOMINAL"
        if paused:
            status_text = "PAUSED"
        elif fuel_pct <= 10.0:
            status_text = "FUEL CRITICAL"
        elif descent_speed > rocket.physics_config.safe_vertical_impact_m_s:
            status_text = "DESCENT TOO FAST"
        elif planar_distance > 4.0:
            status_text = "CORRECT PAD TRACK"
        bottom_status.text = "%s   ·   X %+.1f Z %+.1f   ·   MASS %.1f kg" % [status_text, rocket.global_position.x, rocket.global_position.z, rocket.mass]
    if bottom_controls != null:
        bottom_controls.text = "↑↓ throttle · WASD attitude · QE yaw · C/V cam · PgUp/PgDn zoom · T PID · R/N reset"

    if left_compass != null and left_compass.has_method("set_navigation"):
        left_compass.set_navigation(heading, course, drift, planar_distance)
    if altitude_box != null:
        altitude_box.text = "ALT RAD %.1f m" % clearance
    if caution_box != null:
        var caution := "PAD LOCK"
        if paused:
            caution = "PAUSED"
        elif fuel_pct <= 10.0:
            caution = "FUEL LOW"
        elif descent_speed > rocket.physics_config.safe_vertical_impact_m_s:
            caution = "SINK HIGH"
        elif planar_distance > 4.0:
            caution = "OFF TRACK"
        caution_box.text = caution

    if hspeed_tape != null and hspeed_tape.has_method("set_gauge"):
        hspeed_tape.set_gauge("H SPEED", "m/s", horizontal_speed, 1.0, 1, false)
    if engine_gauge != null and engine_gauge.has_method("set_gauge"):
        engine_gauge.set_gauge("ENGINE #1", rocket.throttle * 100.0, 0.0, 100.0, "%d%%" % int(round(rocket.throttle * 100.0)), "THR")
    if twr_gauge != null and twr_gauge.has_method("set_gauge"):
        twr_gauge.set_gauge("TWR", twr, 0.0, 3.0, "%.2f" % twr, "NET %+.1f" % net_vertical_accel)

    if fuel_gauge != null:
        fuel_gauge.value = fuel_pct
        _set_bar_color(fuel_gauge, COLOR_DANGER if fuel_pct <= 10.0 else COLOR_CAUTION if fuel_pct <= 25.0 else COLOR_NORMAL)
        _set_aux_readout(fuel_gauge, "%d%%" % int(round(fuel_pct)))
    if tilt_gauge != null:
        tilt_gauge.value = clampf(tilt / maxf(rocket.physics_config.safe_tilt_deg, 0.001) * 100.0, 0.0, 100.0)
        _set_bar_color(tilt_gauge, COLOR_DANGER if tilt > rocket.physics_config.safe_tilt_deg else COLOR_CAUTION if tilt > rocket.physics_config.safe_tilt_deg * 0.7 else COLOR_NORMAL)
        _set_aux_readout(tilt_gauge, "%d°" % int(round(tilt)))
    if gimbal_gauge != null:
        gimbal_gauge.value = gimbal_mag_pct
        _set_aux_readout(gimbal_gauge, "%d%%" % int(round(gimbal_mag_pct)))
    if rcs_gauge != null:
        rcs_gauge.value = rcs_pct
        _set_aux_readout(rcs_gauge, "%d%%" % int(round(rcs_pct)))
    if burn_info != null:
        burn_info.text = "BURN %.1f s   ·   THRUST %.0f N" % [burn_time_full, thrust_n]
    if fuel_info != null:
        fuel_info.text = "MASS %.1f kg   ·   CLR %.1f m" % [rocket.mass, clearance]

    if altitude_tape != null and altitude_tape.has_method("set_gauge"):
        altitude_tape.set_gauge("ALTITUDE", "m", center_altitude, 20.0, 0, false)
    if vs_tape != null and vs_tape.has_method("set_gauge"):
        vs_tape.set_gauge("VS", "m/s", vertical, 1.0, 1, true)
    if vs_box != null:
        vs_box.text = "VS %+.1f" % vertical
