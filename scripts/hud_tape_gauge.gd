extends Control
class_name HudTapeGauge

const BG := Color(0.10, 0.12, 0.14, 0.88)
const FG := Color(0.92, 0.94, 0.96)
const SUB := Color(0.68, 0.74, 0.80)
const ACCENT := Color(0.13, 0.83, 1.0)

var title: String = "ALTITUDE"
var units: String = "m"
var value: float = 0.0
var center_value: float = 0.0
var step: float = 10.0
var digits: int = 0
var signed_mode: bool = false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_gauge(new_title: String, new_units: String, new_value: float, new_step: float, new_digits: int = 0, signed: bool = false) -> void:
    title = new_title
    units = new_units
    value = new_value
    center_value = new_value
    step = maxf(new_step, 0.001)
    digits = new_digits
    signed_mode = signed
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BG, true)
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.28, 0.32, 1.0), false, 1.0)
    var font: Font = get_theme_default_font()
    draw_string(font, Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, 13, FG)
    var header: Rect2 = Rect2(6, 18, size.x - 12, 20)
    draw_rect(header, Color(0.06, 0.08, 0.10, 1.0), true)
    draw_rect(header, ACCENT, false, 2.0)
    draw_string(font, Vector2(10, 33), _format(value), HORIZONTAL_ALIGNMENT_LEFT, header.size.x - 20, 15, ACCENT)
    var top: float = 46.0
    var bottom: float = size.y - 12.0
    var center_y: float = lerpf(top, bottom, 0.5)
    draw_line(Vector2(size.x * 0.58, top), Vector2(size.x * 0.58, bottom), FG, 2.0)
    var half_span_steps: int = 4
    for i in range(-half_span_steps, half_span_steps + 1):
        var y: float = center_y + float(i) * ((bottom - top) / 8.0)
        var len: float = 12.0 if i == 0 else 8.0
        draw_line(Vector2(size.x * 0.58 - len, y), Vector2(size.x * 0.58, y), FG, 2.0 if i == 0 else 1.0)
        var label_val: float = center_value - float(i) * step
        draw_string(font, Vector2(6, y + 5), _format(label_val), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.46 - 8, 13, FG if i == 0 else SUB)
    var bug: PackedVector2Array = PackedVector2Array([
        Vector2(size.x * 0.58 + 2, center_y), Vector2(size.x - 10, center_y - 8),
        Vector2(size.x - 10, center_y + 8), Vector2(size.x * 0.58 + 2, center_y)
    ])
    draw_colored_polygon(bug, FG)
    draw_string(font, Vector2(size.x - 30, size.y - 2), units, HORIZONTAL_ALIGNMENT_LEFT, 24, 12, SUB)

func _format(v: float) -> String:
    if digits <= 0:
        return ("%+d" if signed_mode else "%d") % int(round(v))
    return ("%+.*f" if signed_mode else "%.*f") % [digits, v]
