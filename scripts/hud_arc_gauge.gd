extends Control
class_name HudArcGauge

const FG := Color(0.92, 0.94, 0.96)
const BG := Color(0.10, 0.12, 0.14, 0.88)
const OK := Color(0.15, 0.80, 0.30)
const WARN := Color(0.92, 0.78, 0.22)
const DANGER := Color(0.86, 0.20, 0.18)

var title: String = "ENGINE"
var value: float = 0.0
var min_value: float = 0.0
var max_value: float = 1.0
var value_text: String = "0%"
var subtitle: String = "IDLE"

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_gauge(new_title: String, v: float, min_v: float, max_v: float, display: String, sub: String) -> void:
    title = new_title
    value = v
    min_value = min_v
    max_value = max_v
    value_text = display
    subtitle = sub
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BG, true)
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.28, 0.32, 1.0), false, 1.0)
    var font: Font = get_theme_default_font()
    draw_string(font, Vector2(8, 14), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 13, FG)
    var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.52)
    var radius: float = minf(size.x, size.y) * 0.30
    _arc_segment(c, radius, deg_to_rad(140), deg_to_rad(255), OK, 6.0)
    _arc_segment(c, radius, deg_to_rad(255), deg_to_rad(300), WARN, 6.0)
    _arc_segment(c, radius, deg_to_rad(300), deg_to_rad(320), DANGER, 6.0)
    for i in range(6):
        var t: float = float(i) / 5.0
        var ang: float = lerpf(deg_to_rad(140.0), deg_to_rad(320.0), t)
        var inner: Vector2 = c + Vector2(cos(ang), sin(ang)) * (radius - 10.0)
        var outer: Vector2 = c + Vector2(cos(ang), sin(ang)) * (radius + 2.0)
        draw_line(inner, outer, FG, 1.0)
    var ratio: float = 0.0 if is_equal_approx(max_value, min_value) else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
    var needle_ang: float = lerpf(deg_to_rad(140.0), deg_to_rad(320.0), ratio)
    var tip: Vector2 = c + Vector2(cos(needle_ang), sin(needle_ang)) * (radius - 8.0)
    draw_line(c, tip, FG, 2.0)
    draw_circle(c, 4.0, FG)
    draw_string(font, Vector2(size.x * 0.5 - 18, size.y - 22), value_text, HORIZONTAL_ALIGNMENT_LEFT, 40, 15, FG)
    draw_string(font, Vector2(size.x * 0.5 - 20, size.y - 6), subtitle, HORIZONTAL_ALIGNMENT_LEFT, 50, 11, Color(0.72, 0.76, 0.80))

func _arc_segment(c: Vector2, radius: float, from_ang: float, to_ang: float, color: Color, width: float) -> void:
    draw_arc(c, radius, from_ang, to_ang, 32, color, width)
