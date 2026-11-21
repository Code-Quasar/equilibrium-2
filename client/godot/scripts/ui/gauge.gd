class_name Gauge
extends Control
## A round Satisfaction gauge: a 270° ring that fills with the value, coloured
## along its length from red through yellow to green. It eases toward each new
## authoritative value instead of jumping.

signal tapped
signal held

var value := 0.0              # 0..100, from the server
var _shown := 0.0
var _press_ms := -1
var _held := false
var _font: Font

const RED := Color("#e8553f")
const YELLOW := Color("#f2c14a")
const GREEN := Color("#3fcf8e")


func _init() -> void:
	custom_minimum_size = Vector2(84, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UI.number_font()


static func colour_at(v: float) -> Color:
	v = clampf(v / 100.0, 0.0, 1.0)
	return RED.lerp(YELLOW, v / 0.55) if v < 0.55 else YELLOW.lerp(GREEN, (v - 0.55) / 0.45)


func _process(delta: float) -> void:
	if absf(_shown - value) > 0.05:
		_shown = lerpf(_shown, value, clampf(delta * 5.0, 0.0, 1.0))
		queue_redraw()
	if _press_ms >= 0 and not _held and Time.get_ticks_msec() - _press_ms > 450:
		_held = true
		held.emit()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			held.emit()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_ms = Time.get_ticks_msec()
				_held = false
			else:
				if _press_ms >= 0 and not _held:
					UI.click()
					tapped.emit()
				_press_ms = -1
		accept_event()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 7.0
	draw_circle(c, r + 6.0, Color(0.05, 0.09, 0.12, 0.82))
	var a0 := deg_to_rad(135.0)
	var span := deg_to_rad(270.0)
	draw_arc(c, r, a0, a0 + span, 48, Color(1, 1, 1, 0.13), 7.0, true)
	var f := clampf(_shown / 100.0, 0.0, 1.0)
	var segs := maxi(int(48 * f), 1)
	for i in segs:
		var t0 := float(i) / segs * f
		var t1 := float(i + 1) / segs * f
		draw_arc(c, r, a0 + span * t0, a0 + span * t1 + 0.01, 3, colour_at(t1 * 100.0), 7.0, true)
	var txt := "%d" % int(round(_shown))
	var fs := 24
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, c + Vector2(-w / 2.0, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var cap := "SATISFIED"
	var cw := _font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(_font, c + Vector2(-cw / 2.0, 20), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.65))
