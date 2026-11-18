extends Node
## F09: local presentation preferences only. No rocket state, gameplay input,
## reward, observation, TCP or physics configuration is read/written here.
## F1: panel, F2: particles, M: mute, PageUp/PageDown: zoom.

const PREFS_FILE: String = "user://rocket_presentation_v1.cfg"
const ZOOM_MIN: float = 0.80
const ZOOM_MAX: float = 1.35
const SAVE_DELAY_S: float = 0.50

@onready var flight_audio: Node = get_node("../FlightAudio")
@onready var visual_fx: Node3D = get_node("../VisualFX")
@onready var context_camera: Camera3D = get_node("../Camera3D")
@onready var observer_camera: Camera3D = get_node("../ObserverCamera")

var mute: bool = false
var reduced_fx: bool = false
var master_level: float = 1.0
var engine_level: float = 1.0
var rcs_level: float = 1.0
var touchdown_level: float = 1.0
var zoom_level: float = 1.0

var _panel: PanelContainer
var _mute_button: CheckButton
var _fx_button: CheckButton
var _zoom_slider: HSlider
var _save_remaining: float = -1.0
var _active_ui: bool = false
var _audio_diag_label: Label


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        set_process(false)
        set_process_unhandled_key_input(false)
        return
    _load_preferences()
    _build_panel()
    _active_ui = true
    _apply_preferences()


func _process(delta: float) -> void:
    if _audio_diag_label != null:
        _audio_diag_label.text = str(flight_audio.call("diagnostic_status"))
    if _save_remaining < 0.0:
        return
    _save_remaining -= maxf(delta, 0.0)
    if _save_remaining <= 0.0:
        _save_remaining = -1.0
        _save_preferences()


func _exit_tree() -> void:
    if _active_ui and _save_remaining >= 0.0:
        _save_preferences()


func _load_preferences() -> void:
    var config := ConfigFile.new()
    if config.load(PREFS_FILE) != OK:
        return
    var saved_mute: Variant = config.get_value("audio", "mute", false)
    var saved_fx: Variant = config.get_value("visual", "reduced_fx", false)
    if typeof(saved_mute) == TYPE_BOOL:
        mute = saved_mute
    if typeof(saved_fx) == TYPE_BOOL:
        reduced_fx = saved_fx
    master_level = _read_level(config, "audio", "master", 1.0, 0.0, 1.0)
    engine_level = _read_level(config, "audio", "engine", 1.0, 0.0, 1.0)
    rcs_level = _read_level(config, "audio", "rcs", 1.0, 0.0, 1.0)
    touchdown_level = _read_level(config, "audio", "touchdown", 1.0, 0.0, 1.0)
    zoom_level = _read_level(config, "visual", "zoom", 1.0, ZOOM_MIN, ZOOM_MAX)


func _read_level(config: ConfigFile, section: String, key: String,
        default_value: float, minimum: float, maximum: float) -> float:
    var raw: Variant = config.get_value(section, key, default_value)
    if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
        return default_value
    var result: float = float(raw)
    if not is_finite(result):
        return default_value
    return clampf(result, minimum, maximum)


func _save_preferences() -> void:
    var config := ConfigFile.new()
    config.set_value("audio", "mute", mute)
    config.set_value("audio", "master", master_level)
    config.set_value("audio", "engine", engine_level)
    config.set_value("audio", "rcs", rcs_level)
    config.set_value("audio", "touchdown", touchdown_level)
    config.set_value("visual", "reduced_fx", reduced_fx)
    config.set_value("visual", "zoom", zoom_level)
    var result: int = config.save(PREFS_FILE)
    if result != OK:
        push_warning("F09: could not persist presentation preferences: %s" % result)


func _apply_preferences() -> void:
    flight_audio.call("configure_mix", mute, master_level, engine_level,
        rcs_level, touchdown_level)
    visual_fx.call("set_quality_profile", reduced_fx)
    context_camera.call("set_zoom_factor", zoom_level)
    observer_camera.call("set_zoom_factor", zoom_level)


func _changed() -> void:
    _apply_preferences()
    _save_remaining = SAVE_DELAY_S


func _build_panel() -> void:
    var layer := CanvasLayer.new()
    layer.name = "PresentationPreferencesOverlay"
    layer.layer = 5
    add_child(layer)
    _panel = PanelContainer.new()
    _panel.name = "PresentationPreferences"
    layer.add_child(_panel)
    _panel.anchor_left = 1.0
    _panel.anchor_right = 1.0
    _panel.offset_left = -365.0
    _panel.offset_right = -16.0
    _panel.offset_top = 16.0
    _panel.offset_bottom = 540.0
    _panel.custom_minimum_size = Vector2(349.0, 0.0)
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    var background := StyleBoxFlat.new()
    background.bg_color = Color(0.045, 0.063, 0.075, 0.95)
    background.corner_radius_top_left = 3
    background.corner_radius_top_right = 3
    background.corner_radius_bottom_left = 3
    background.corner_radius_bottom_right = 3
    background.content_margin_left = 15.0
    background.content_margin_right = 15.0
    background.content_margin_top = 13.0
    background.content_margin_bottom = 13.0
    _panel.add_theme_stylebox_override("panel", background)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 7)
    _panel.add_child(layout)
    var title := Label.new()
    title.text = "PRESENTATION SETTINGS"
    title.add_theme_font_size_override("font_size", 17)
    layout.add_child(title)
    var hint := Label.new()
    hint.text = "F1 close | F2 particles | F3 audio | M mute"
    hint.add_theme_font_size_override("font_size", 11)
    hint.modulate = Color(0.72, 0.77, 0.82)
    layout.add_child(hint)
    _mute_button = _make_toggle(layout, "Mute audio", mute, _on_mute_changed)
    _add_slider(layout, "Master volume", master_level, 0.0, 1.0, _on_master_changed)
    _add_slider(layout, "Engine", engine_level, 0.0, 1.0, _on_engine_changed)
    _add_slider(layout, "RCS", rcs_level, 0.0, 1.0, _on_rcs_changed)
    _add_slider(layout, "Touchdown", touchdown_level, 0.0, 1.0, _on_touchdown_changed)
    var audition := Button.new()
    audition.text = "Test audio: engine / RCS / touchdown (F3)"
    audition.focus_mode = Control.FOCUS_NONE
    audition.add_theme_font_size_override("font_size", 12)
    layout.add_child(audition)
    audition.pressed.connect(_on_audio_test_pressed)
    _audio_diag_label = Label.new()
    _audio_diag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _audio_diag_label.add_theme_font_size_override("font_size", 11)
    _audio_diag_label.modulate = Color(0.75, 0.84, 0.86)
    layout.add_child(_audio_diag_label)
    var diagnostic_note := Label.new()
    diagnostic_note.text = "Test bypasses M and sliders, not Windows volume"
    diagnostic_note.add_theme_font_size_override("font_size", 11)
    layout.add_child(diagnostic_note)
    _fx_button = _make_toggle(layout, "Reduced particles", reduced_fx, _on_fx_changed)
    _zoom_slider = _add_slider(layout, "Camera zoom", zoom_level,
        ZOOM_MIN, ZOOM_MAX, _on_zoom_changed)
    var note := Label.new()
    note.text = "PageUp / PageDown: zoom  |  Settings saved"
    note.add_theme_font_size_override("font_size", 11)
    note.modulate = Color(0.72, 0.77, 0.82)
    layout.add_child(note)
    _panel.visible = false


func _make_toggle(parent: VBoxContainer, caption: String, value: bool,
        callback: Callable) -> CheckButton:
    var toggle := CheckButton.new()
    toggle.text = caption
    toggle.button_pressed = value
    toggle.focus_mode = Control.FOCUS_NONE
    parent.add_child(toggle)
    toggle.toggled.connect(callback)
    return toggle


func _add_slider(parent: VBoxContainer, caption: String, value: float,
        minimum: float, maximum: float, callback: Callable) -> HSlider:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    parent.add_child(row)
    var caption_label := Label.new()
    caption_label.text = caption
    caption_label.custom_minimum_size.x = 120.0
    caption_label.add_theme_font_size_override("font_size", 12)
    row.add_child(caption_label)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = 0.05
    slider.value = value
    slider.focus_mode = Control.FOCUS_NONE
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    slider.value_changed.connect(callback)
    return slider


func _on_audio_test_pressed() -> void:
    flight_audio.call("start_audio_test")


func _on_mute_changed(value: bool) -> void:
    mute = value
    _changed()

func _on_fx_changed(value: bool) -> void:
    reduced_fx = value
    _changed()

func _on_master_changed(value: float) -> void:
    master_level = value
    _changed()

func _on_engine_changed(value: float) -> void:
    engine_level = value
    _changed()

func _on_rcs_changed(value: float) -> void:
    rcs_level = value
    _changed()

func _on_touchdown_changed(value: float) -> void:
    touchdown_level = value
    _changed()

func _on_zoom_changed(value: float) -> void:
    zoom_level = value
    _changed()


func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_F1:
            _panel.visible = not _panel.visible
        KEY_F3:
            _on_audio_test_pressed()
        KEY_F2:
            reduced_fx = not reduced_fx
            _fx_button.set_pressed_no_signal(reduced_fx)
            _changed()
        KEY_M:
            mute = not mute
            _mute_button.set_pressed_no_signal(mute)
            _changed()
        KEY_PAGEUP:
            zoom_level = clampf(zoom_level + 0.05, ZOOM_MIN, ZOOM_MAX)
            _zoom_slider.set_value_no_signal(zoom_level)
            _changed()
        KEY_PAGEDOWN:
            zoom_level = clampf(zoom_level - 0.05, ZOOM_MIN, ZOOM_MAX)
            _zoom_slider.set_value_no_signal(zoom_level)
            _changed()
        _:
            return
    get_viewport().set_input_as_handled()
