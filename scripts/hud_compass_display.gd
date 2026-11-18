extends Control
class_name HudCompassDisplay

const RING_COLOR := Color(0.90, 0.92, 0.94)
const MUTED := Color(0.64, 0.68, 0.74)
const ACCENT := Color(0.96, 0.20, 0.82)
const CYAN := Color(0.13, 0.83, 1.0)
const BG := Color(0.10, 0.12, 0.15, 0.88)

var heading_deg: float = 0.0
var course_deg: float = 0.0
var drift_deg: float = 0.0
var target_distance_m: float = 0.0
var label_heading := "HDG"
var label_course := "CRS"
var marker_label := "PAD"

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()

func set_navigation(heading: float, course: float, drift: float, distance_m: float) -> void:
    heading_deg = wrapf(heading, 0.0, 360.0)
    course_deg = wrapf(course, 0.0, 360.0)
    drift_deg = wrapf(drift, -180.0, 180.0)
    target_distance_m = distance_m
    queue_redraw()

func _draw() -> void:
    var c: Vector2 = size * 0.5
    var radius: float = minf(size.x, size.y) * 0.42
    draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0), false)
    draw_circle(c, radius + 10.0, Color(0, 0, 0, 0.15))
    draw_circle(c, radius, BG)
    draw_arc(c, radius, 0.0, TAU, 96, RING_COLOR, 2.0)
    for i in range(36):
        var ang: float = deg_to_rad(float(i) * 10.0 - heading_deg - 90.0)
        var outer: Vector2 = c + Vector2(cos(ang), sin(ang)) * radius
        var inner_len: float = 10.0 if i % 3 == 0 else 5.0
        var inner: Vector2 = c + Vector2(cos(ang), sin(ang)) * (radius - inner_len)
        draw_line(inner, outer, RING_COLOR, 2.0 if i % 3 == 0 else 1.0)
    # Avoid Variant keys/values from a Dictionary while drawing with strict warnings.
    for cardinal in range(4):
        var bearing_deg: float = float(cardinal) * 90.0
        var letter: String = "N"
        match cardinal:
            1:
                letter = "E"
            2:
                letter = "S"
            3:
                letter = "W"
        var ang: float = deg_to_rad(bearing_deg - heading_deg - 90.0)
        var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * (radius - 26.0)
        draw_string(get_theme_default_font(), pos + Vector2(-5, 5), letter,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12 if size.x < 180.0 else 20, RING_COLOR)
    for deg in range(30, 360, 30):
        if deg % 90 == 0:
            continue
        var label: String = str(int(float(deg) / 10.0))
        var ang: float = deg_to_rad(float(deg) - heading_deg - 90.0)
        var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * (radius - 18.0)
        draw_string(get_theme_default_font(), pos + Vector2(-6, 4), label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 9 if size.x < 180.0 else 14, MUTED)
    var aircraft: PackedVector2Array = PackedVector2Array([
        c + Vector2(0, -18), c + Vector2(8, 0), c + Vector2(2, 0), c + Vector2(2, 22),
        c + Vector2(-2, 22), c + Vector2(-2, 0), c + Vector2(-8, 0)
    ])
    draw_polyline(aircraft, Color.WHITE, 2.0)
    draw_line(c + Vector2(-24, 0), c + Vector2(24, 0), Color.WHITE, 2.0)
    draw_line(c + Vector2(0, -24), c + Vector2(0, 26), Color.WHITE, 2.0)

    var course_ang: float = deg_to_rad(course_deg - heading_deg - 90.0)
    var course_tip: Vector2 = c + Vector2(cos(course_ang), sin(course_ang)) * (radius - 16.0)
    var arrow: PackedVector2Array = PackedVector2Array([
        course_tip,
        course_tip + Vector2(cos(course_ang + 2.6), sin(course_ang + 2.6)) * 12.0,
        course_tip + Vector2(cos(course_ang - 2.6), sin(course_ang - 2.6)) * 12.0,
        course_tip,
    ])
    draw_colored_polygon(arrow, ACCENT)

    var drift_ang: float = deg_to_rad(drift_deg - 90.0)
    var drift_tip: Vector2 = c + Vector2(cos(drift_ang), sin(drift_ang)) * (radius - 6.0)
    var drift_arrow: PackedVector2Array = PackedVector2Array([
        drift_tip,
        drift_tip + Vector2(cos(drift_ang + 2.7), sin(drift_ang + 2.7)) * 10.0,
        drift_tip + Vector2(cos(drift_ang - 2.7), sin(drift_ang - 2.7)) * 10.0,
        drift_tip,
    ])
    draw_colored_polygon(drift_arrow, CYAN)

    _draw_box(Rect2(Vector2(4, 6), Vector2(60, 22)), CYAN, "%s %03d" % [label_heading, int(round(heading_deg))])
    _draw_box(Rect2(Vector2(size.x - 64, 6), Vector2(60, 22)), ACCENT, "%s %03d" % [label_course, int(round(course_deg))])
    _draw_box(Rect2(Vector2(size.x * 0.5 - 36, size.y - 28), Vector2(72, 22)), ACCENT, "%s %.1f" % [marker_label, target_distance_m])

func _draw_box(rect: Rect2, accent: Color, text: String) -> void:
    draw_rect(rect, Color(0.12, 0.14, 0.17, 0.88), true)
    draw_rect(rect, accent, false, 2.0)
    draw_string(get_theme_default_font(), rect.position + Vector2(6, 16), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 14, accent)
