class_name UI
extends RefCounted
## The style guide (design/style-guide.html) as a Godot theme, plus small
## factories so screens can be built in code.

const PAPER := Color("#fbf8f1")
const PAPER2 := Color("#f2ede1")
const INK := Color("#1e2b26")
const MUTED := Color("#6b7a72")
const LINE := Color("#e3dccb")
const LIP := Color("#d6cfbd")
const PRIMARY := Color("#2fb27a")
const PRIMARY_DARK := Color("#1f8a5b")
const MONEY := Color("#f2b33d")
const PEOPLE := Color("#3d9be9")
const DANGER := Color("#e85d4a")
const DANGER_DARK := Color("#b9422f")
const WARN := Color("#f29a3d")
const CARDS := Color("#8e7cf0")

const CATEGORY := {
	"urban": ["Housing & services", Color("#d9694a")],
	"economy": ["Business & industry", Color("#3fa7b5")],
	"energy": ["Energy", Color("#f2c230")],
	"environment": ["Waste & nature", Color("#4caf7a")],
}

static var art: Art


static func box(bg: Color, radius := 16, border := Color(0, 0, 0, 0), border_w := 0, lip := 0, lip_color := Color(0, 0, 0, 0), pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	if lip > 0:
		s.border_width_bottom = border_w + lip
		s.border_color = lip_color
	s.set_content_margin_all(pad)
	s.corner_detail = 6
	s.anti_aliasing = true
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	var regular := SystemFont.new()
	regular.font_names = PackedStringArray(["Nunito", "Roboto", "Noto Sans", "sans-serif"])
	regular.font_weight = 600
	var bold := SystemFont.new()
	bold.font_names = regular.font_names
	bold.font_weight = 800
	t.default_font = regular
	t.default_font_size = 16

	t.set_color("font_color", "Label", INK)
	for v in [["Title", 20, bold, INK], ["Display", 28, bold, INK], ["Caption", 13, regular, MUTED], ["Value", 16, bold, INK], ["Small", 12, regular, MUTED]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], v[1])
		t.set_font("font", v[0], v[2])
		t.set_color("font_color", v[0], v[3])

	t.set_stylebox("panel", "PanelContainer", box(PAPER, 16, LINE, 1))
	t.set_type_variation("Sheet", "PanelContainer")
	var sheet := box(PAPER, 22, LINE, 1, 0, Color(), 14)
	sheet.corner_radius_bottom_left = 0
	sheet.corner_radius_bottom_right = 0
	sheet.shadow_color = Color(0, 0, 0, 0.22)
	sheet.shadow_size = 14
	t.set_stylebox("panel", "Sheet", sheet)
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(Color.WHITE, 14, LINE, 1, 3, LINE, 10))
	t.set_type_variation("Glass", "PanelContainer")
	var glass := box(Color(PAPER, 0.95), 14, Color(0, 0, 0, 0), 0, 0, Color(), 8)
	glass.shadow_color = Color(0, 0, 0, 0.18)
	glass.shadow_size = 8
	glass.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "Glass", glass)
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(PAPER2, 99, Color(), 0, 0, Color(), 6))

	_button(t, "Button", Color.WHITE, LIP, INK, regular)
	_button(t, "PrimaryButton", PRIMARY, PRIMARY_DARK, Color.WHITE, bold)
	_button(t, "DangerButton", DANGER, DANGER_DARK, Color.WHITE, bold)
	_button(t, "SoftButton", PAPER2, LINE, INK, regular)
	t.set_type_variation("TabButton", "Button")
	var flat := box(Color(0, 0, 0, 0), 12, Color(), 0, 0, Color(), 4)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		t.set_stylebox(st, "TabButton", flat)
	t.set_color("font_color", "TabButton", MUTED)
	t.set_color("font_pressed_color", "TabButton", PRIMARY)
	t.set_color("font_hover_pressed_color", "TabButton", PRIMARY)
	t.set_color("icon_normal_color", "TabButton", MUTED)
	t.set_color("icon_pressed_color", "TabButton", PRIMARY)
	t.set_color("icon_hover_pressed_color", "TabButton", PRIMARY)
	t.set_font_size("font_size", "TabButton", 11)
	t.set_font("font", "TabButton", bold)

	var field := box(Color.WHITE, 10, LINE, 1, 0, Color(), 8)
	for c in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, field)
		t.set_stylebox("focus", c, box(Color.WHITE, 10, PRIMARY, 2, 0, Color(), 8))
		t.set_color("font_color", c, INK)
	t.set_stylebox("normal", "OptionButton", box(Color.WHITE, 10, LINE, 1, 0, Color(), 8))
	t.set_stylebox("hover", "OptionButton", box(Color.WHITE, 10, LINE, 1, 0, Color(), 8))
	t.set_stylebox("pressed", "OptionButton", box(PAPER2, 10, LINE, 1, 0, Color(), 8))
	t.set_color("font_color", "OptionButton", INK)
	t.set_stylebox("panel", "PopupMenu", box(PAPER, 12, LINE, 1, 0, Color(), 8))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", PRIMARY)

	# HUD text sits straight on the map: white with a dark outline.
	for v in [["HudValue", 19, bold], ["HudSmall", 12, bold], ["HudCaption", 11, bold]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], v[1])
		t.set_font("font", v[0], v[2])
		t.set_color("font_color", v[0], Color.WHITE)
		t.set_color("font_outline_color", v[0], Color(0.05, 0.1, 0.12, 0.9))
		t.set_constant("outline_size", v[0], 5)
	t.set_type_variation("Hud", "PanelContainer")
	var hud := box(Color(0.07, 0.11, 0.14, 0.72), 99, Color(1, 1, 1, 0.12), 1, 0, Color(), 4)
	hud.content_margin_left = 30
	hud.content_margin_right = 12
	t.set_stylebox("panel", "Hud", hud)
	t.set_type_variation("Dock", "PanelContainer")
	var dock := box(Color(0.07, 0.11, 0.14, 0.62), 22, Color(1, 1, 1, 0.12), 1, 0, Color(), 8)
	t.set_stylebox("panel", "Dock", dock)
	t.set_type_variation("Side", "PanelContainer")
	var side := box(PAPER, 22, LINE, 1, 0, Color(), 14)
	side.shadow_color = Color(0, 0, 0, 0.3)
	side.shadow_size = 16
	t.set_stylebox("panel", "Side", side)
	t.set_stylebox("background", "ProgressBar", box(PAPER2, 99, Color(), 0, 0, Color(), 0))
	t.set_stylebox("fill", "ProgressBar", box(PRIMARY, 99, Color(), 0, 0, Color(), 0))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t


static func _button(t: Theme, kind: String, bg: Color, lip_col: Color, fg: Color, font: Font) -> void:
	if kind != "Button":
		t.set_type_variation(kind, "Button")
	var normal := box(bg, 99, lip_col, 1 if kind == "Button" else 0, 4, lip_col, 10)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var pressed := box(bg.darkened(0.06), 99, lip_col, 1 if kind == "Button" else 0, 1, lip_col, 10)
	pressed.content_margin_left = 18
	pressed.content_margin_right = 18
	pressed.content_margin_top = 13
	var disabled := normal.duplicate()
	disabled.bg_color = Color(bg, 0.45)
	disabled.border_color = Color(lip_col, 0.35)
	t.set_stylebox("normal", kind, normal)
	t.set_stylebox("hover", kind, normal)
	t.set_stylebox("focus", kind, StyleBoxEmpty.new())
	t.set_stylebox("pressed", kind, pressed)
	t.set_stylebox("hover_pressed", kind, pressed)
	t.set_stylebox("disabled", kind, disabled)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, kind, fg)
	t.set_color("font_disabled_color", kind, Color(fg, 0.5))
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		t.set_color(c, kind, fg)
	t.set_font("font", kind, font)
	t.set_constant("h_separation", kind, 6)
	t.set_constant("icon_max_width", kind, 22)


# ------------------------------------------------------------- factories ---

static func label(text: String, variation := "", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func rich(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_color_override("default_color", INK)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func button(text: String, variation := "", icon_name := "", on_press: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if icon_name != "" and art:
		b.icon = art.icon(icon_name)
		b.expand_icon = false
	b.custom_minimum_size.y = 48
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func badge(name: String, size := 40) -> TextureRect:
	var r := TextureRect.new()
	r.texture = art.badge(name) if art else null
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A glossy round button: a coloured disc, a white glyph, an optional count
## dot and a caption underneath.
static func round_button(base: String, glyph: String, caption: String, on_press: Callable, size := 60) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := TextureButton.new()
	b.texture_normal = art.badge(base)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(size, size)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if glyph != "":
		var g := TextureRect.new()
		g.texture = art.icon(glyph) if art.icon(glyph) else art.badge(glyph)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset := size * 0.27
		g.offset_left = inset
		g.offset_top = inset * 0.85
		g.offset_right = -inset
		g.offset_bottom = -inset * 1.1
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(g)
	b.button_down.connect(func(): b.self_modulate = Color(0.85, 0.85, 0.85); b.scale = Vector2(0.94, 0.94))
	b.button_up.connect(func(): b.self_modulate = Color.WHITE; b.scale = Vector2.ONE)
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	col.add_child(b)
	if caption != "":
		var l := label(caption, "HudCaption")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	col.set_meta("button", b)
	return col


## A red count dot for the corner of a round button; hidden at zero.
static func count_dot(button_box: Control, n: int) -> void:
	var b: TextureButton = button_box.get_meta("button")
	var dot: Label = b.get_node_or_null("Dot")
	if dot == null:
		dot = Label.new()
		dot.name = "Dot"
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_theme_stylebox_override("normal", box(DANGER, 99, Color.WHITE, 2, 0, Color(), 0))
		dot.add_theme_font_size_override("font_size", 12)
		dot.add_theme_color_override("font_color", Color.WHITE)
		dot.custom_minimum_size = Vector2(22, 22)
		dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -18
		dot.offset_right = 4
		dot.offset_top = -4
		dot.offset_bottom = 18
		b.add_child(dot)
	dot.text = "9+" if n > 9 else str(n)
	dot.visible = n > 0


## A dark HUD counter: a badge overlapping its left edge and a value.
static func counter(badge_name: String, min_width := 110, badge_size := 38) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -int(badge_size * 0.55))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := badge(badge_name, badge_size)
	b.z_index = 1
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	var p := PanelContainer.new()
	p.theme_type_variation = "Hud"
	p.custom_minimum_size = Vector2(min_width, 32)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := label("", "HudValue")
	p.add_child(v)
	row.add_child(p)
	row.set_meta("value", v)
	return row


static func set_counter(c: Control, text: String, color := Color.WHITE) -> void:
	var l: Label = c.get_meta("value")
	l.text = text
	l.add_theme_color_override("font_color", color)


static func icon(name: String, size := 22, tint := INK) -> TextureRect:
	var r := TextureRect.new()
	r.texture = art.icon(name) if art else null
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func hbox(sep := 8, children: Array = []) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	for c in children:
		b.add_child(c)
	return b


static func vbox(sep := 8, children: Array = []) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	for c in children:
		b.add_child(c)
	return b


static func panel(variation := "", child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if child:
		p.add_child(child)
	return p


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func bar(value: float, color := PRIMARY) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0
	p.max_value = 1
	p.value = clampf(value, 0, 1)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := box(color, 99, Color(), 0, 0, Color(), 0)
	p.add_theme_stylebox_override("fill", fill)
	return p


static func pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, 99, Color(), 0, 0, Color(), 4))
	var l := label(text, "Small")
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Lets touches fall through everything but real controls, so a swipe that
## starts on a card still scrolls the ScrollContainer around it.
static func pass_touches(node: Node) -> void:
	for c in node.get_children():
		if c is Control and not (c is BaseButton or c is LineEdit or c is SpinBox or c is ScrollContainer):
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		pass_touches(c)


static func compact(n: float) -> String:
	if absf(n) >= 100000:
		return "%dk" % int(round(n / 1000.0))
	if absf(n) >= 10000:
		return "%.1fk" % (n / 1000.0)
	return fmt(n)


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func fmt(n: float) -> String:
	var neg := n < 0
	var s := str(int(round(absf(n))))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func signed(n: float) -> String:
	return ("+" if n >= 0 else "") + fmt(n)
