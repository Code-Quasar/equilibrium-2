class_name HudCard
extends PanelContainer
## One HUD figure: icon, value, a short caption and a status strip. A tap
## gives the hint; a long press (or right click) asks for the details.
## pulse() flashes a gold outline for about a second.

signal tapped
signal held

const OK := Color("#3fcf8e")
const WARN := Color("#f2c14a")
const BAD := Color("#ff7a66")

var value_label: Label
var alarm_text := true            # false: a bad state shows only in the strip
var caption: Label
var _strip: ColorRect
var _style: StyleBoxFlat
var _press_ms := -1
var _held := false
var _pulse := 0.0


func _init(badge: String, cap: String, wide := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style = UI.box(Color(0.05, 0.09, 0.12, 0.8), 14, Color(1, 1, 1, 0.1), 1, 0, Color(), 6)
	_style.content_margin_left = 8
	_style.content_margin_right = 10
	_style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", _style)
	custom_minimum_size = Vector2(132 if wide else 96, 50)
	var row := UI.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := UI.badge(badge, 26 if wide else 22)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	var col := UI.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label = UI.label("–", "HudValue")
	value_label.add_theme_font_override("font", UI.number_font())
	value_label.add_theme_font_size_override("font_size", 19 if wide else 15)
	value_label.add_theme_constant_override("outline_size", 0)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption = UI.label(cap.to_upper(), "HudCaption")
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	caption.add_theme_constant_override("outline_size", 0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(value_label)
	col.add_child(caption)
	row.add_child(col)
	add_child(row)
	_strip = ColorRect.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.color = Color(0, 0, 0, 0)
	_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.offset_top = -3
	_strip.offset_left = 10
	_strip.offset_right = -10
	_strip.offset_bottom = -2
	# Drawn over the container's own layout.
	_strip.top_level = false


func _ready() -> void:
	add_child(_strip)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and _strip and _strip.get_parent() == self:
		fit_child_in_rect(_strip, Rect2(10, size.y - 4, size.x - 20, 2.5))


## state: "ok", "warn", "bad" or "" for no strip.
func set_value(text: String, state := "") -> void:
	value_label.text = text
	var col: Color = {"ok": OK, "warn": WARN, "bad": BAD}.get(state, Color(0, 0, 0, 0))
	_strip.color = col
	value_label.add_theme_color_override("font_color", BAD if state == "bad" and alarm_text else Color.WHITE)


func pulse() -> void:
	_pulse = 1.1


func _process(delta: float) -> void:
	if _press_ms >= 0 and not _held and Time.get_ticks_msec() - _press_ms > 450:
		_held = true
		held.emit()
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta, 0.0)
		var k := sin(minf(_pulse / 1.1, 1.0) * PI)
		_style.border_color = Color(1, 1, 1, 0.1).lerp(Color("#ffd257"), k)
		_style.set_border_width_all(1 + int(round(2 * k)))
		_style.bg_color = Color(0.05, 0.09, 0.12, 0.8).lerp(Color(0.35, 0.27, 0.05, 0.9), k * 0.6)


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
