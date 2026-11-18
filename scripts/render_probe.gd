extends Node
## Opt-in F05 graphics evidence. No changes to physics, episode state, or TCP.
## Enable ONLY in a rendered Windows run: F05_PROBE_DIR=<absolute directory>.
## Captures actual Godot viewport frames; the source ZIP contains no captures.

const WARMUP_FRAMES := 90
const MEASURE_FRAMES := 240

var _active := false
var _frames_seen := 0
var _frame_times_ms: Array[float] = []
var _screenshots: Array[Dictionary] = []
var _output_dir := ""
var _started_ms := 0


func _ready() -> void:
	set_process(false)
	_output_dir = OS.get_environment("F05_PROBE_DIR")
	if _output_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var err := DirAccess.make_dir_recursive_absolute(_output_dir)
	if err != OK:
		push_error("F05 probe: cannot create output directory, code " + str(err))
		get_tree().quit(1)
		return
	_started_ms = Time.get_ticks_msec()
	_active = true
	set_process(true)
	print("F05_RENDER_PROBE_START: graphics mode=" + DisplayServer.get_name())


func _process(delta: float) -> void:
	if not _active:
		return
	_frames_seen += 1
	if _frames_seen <= WARMUP_FRAMES:
		return
	if delta <= 0.0 or not is_finite(delta):
		push_error("F05 probe: invalid rendered frame delta")
		_finish(false)
		return
	_frame_times_ms.append(delta * 1000.0)
	if _frame_times_ms.size() == 1:
		_capture("first_frame.png")
	if _frame_times_ms.size() == 180:
		_capture("late_frame.png")
	if _frame_times_ms.size() >= MEASURE_FRAMES:
		_finish(true)


func _capture(filename: String) -> void:
	var filepath := _output_dir.path_join(filename)
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_screenshots.append({"file": filename, "status": "FAIL", "reason": "empty viewport"})
		return
	var err := img.save_png(filepath)
	if err != OK:
		_screenshots.append({"file": filename, "status": "FAIL", "reason": str(err)})
		return
	_screenshots.append({
		"file": filename, "status": "OK", "sha256": FileAccess.get_sha256(filepath),
		"bytes": FileAccess.get_file_as_bytes(filepath).size(),
		"width": img.get_width(), "height": img.get_height()
	})


func _percentile(sorted_samples: Array[float], fraction: float) -> float:
	var index := clampi(ceili(float(sorted_samples.size()) * fraction) - 1, 0, sorted_samples.size() - 1)
	return sorted_samples[index]


func _finish(valid_samples: bool) -> void:
	_active = false
	set_process(false)
	var sorted_samples := _frame_times_ms.duplicate()
	sorted_samples.sort()
	var total_ms := 0.0
	for value in _frame_times_ms:
		total_ms += value
	var fps := 0.0
	var p95_ms := 0.0
	var p99_ms := 0.0
	if total_ms > 0.0:
		fps = 1000.0 * float(_frame_times_ms.size()) / total_ms
	if not sorted_samples.is_empty():
		p95_ms = _percentile(sorted_samples, 0.95)
		p99_ms = _percentile(sorted_samples, 0.99)
	var screenshots_ok := _screenshots.size() == 2
	for row in _screenshots:
		screenshots_ok = screenshots_ok and row["status"] == "OK"
	var valid := valid_samples and _frame_times_ms.size() == MEASURE_FRAMES and screenshots_ok
	var window := get_viewport().get_visible_rect().size
	var report := {
		"schema_version": 1,
		"created_utc": Time.get_datetime_string_from_system(true, true),
		"status": "PASS" if valid else "FAIL",
		"mode": "Godot windowed render sampling (NOT a physics benchmark)",
		"engine": str(Engine.get_version_info().get("string", "unknown")),
		"os": OS.get_name(),
		"display": DisplayServer.get_name(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"resolution": [int(window.x), int(window.y)],
		"warmup_frames": WARMUP_FRAMES,
		"measured_frames": _frame_times_ms.size(),
		"average_fps": snappedf(fps, 0.001),
		"p95_frame_ms": snappedf(p95_ms, 0.001),
		"p99_frame_ms": snappedf(p99_ms, 0.001),
		"elapsed_wall_seconds": snappedf(float(Time.get_ticks_msec() - _started_ms) / 1000.0, 0.001),
		"screenshots": _screenshots,
		"source": "actual Godot viewport at F05_probe, not synthetic images"
	}
	var report_file := FileAccess.open(_output_dir.path_join("render_metrics.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("F05 probe: failed to write metrics receipt")
		get_tree().quit(1)
		return
	report_file.store_string(JSON.stringify(report, "  ") + "\n")
	report_file.close()
	print("F05_RENDER_PROBE_" + report["status"] + ": fps=" + str(report["average_fps"]))
	get_tree().quit(0 if valid else 1)
