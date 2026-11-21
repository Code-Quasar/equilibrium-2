class_name UI
extends RefCounted
## The game's theme, built on the Kenney UI pack (CC0): its 9-slice buttons
## and panels, its Kenney Future font and its interface sounds, plus small
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
static var sound: AudioStreamPlayer      # set by the app; plays the click
static var thumbs: Thumbs                # set by the app; pictures of buildings
static var music: Soundtrack             # set by the app; ambient music and alerts
const KUI := "res://assets/kenney/ui/PNG/"
const COLOURS := {"btn_blue": "Blue", "btn_green": "Green", "btn_orange": "Yellow", "btn_red": "Red", "btn_purple": "Blue"}


## A Kenney UI image as a 9-slice style; depth images keep their bottom lip.
static func kbox(colour: String, image: String, pad := 10, side := 14) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(KUI + colour + "/Default/" + image + ".png")
	var depth := image.contains("depth")
	s.texture_margin_left = 16
	s.texture_margin_right = 16
	s.texture_margin_top = 14
	s.texture_margin_bottom = 20 if depth else 14
	s.content_margin_left = side
	s.content_margin_right = side
	s.content_margin_top = pad
	s.content_margin_bottom = pad + (4 if depth else 0)
	return s


static var _numbers: SystemFont


## A plain bold font for figures on the HUD, where "1,200/1,150" and "88%"
## must read at a glance.
static func number_font() -> Font:
	if _numbers == null:
		_numbers = SystemFont.new()
		_numbers.font_names = PackedStringArray(["Noto Sans", "Roboto", "DejaVu Sans", "sans-serif"])
		_numbers.font_weight = 800
	return _numbers


## The click from the Kenney interface sounds.
static func click() -> void:
	if sound and sound.is_inside_tree():
		sound.play()


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
	var regular: FontFile = load("res://assets/kenney/ui/Kenney Future Narrow.ttf")
	var bold: FontFile = load("res://assets/kenney/ui/Kenney Future.ttf")
	# Symbols the Kenney fonts lack (%, ·, emoji) come from the system font.
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Noto Sans", "Roboto", "DejaVu Sans", "sans-serif"])
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji"])
	for f in [regular, bold]:
		f.fallbacks = [fallback, emoji]
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
	t.set_stylebox("panel", "Card", kbox("Grey", "button_square_depth_flat", 10, 12))
	t.set_type_variation("Glass", "PanelContainer")
	var glass := box(Color(PAPER, 0.95), 14, Color(0, 0, 0, 0), 0, 0, Color(), 8)
	glass.shadow_color = Color(0, 0, 0, 0.18)
	glass.shadow_size = 8
	glass.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "Glass", glass)
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(PAPER2, 99, Color(), 0, 0, Color(), 6))

	_button(t, "Button", "Blue", Color.WHITE, bold)
	_button(t, "PrimaryButton", "Green", Color.WHITE, bold)
	_button(t, "DangerButton", "Red", Color.WHITE, bold)
	_button(t, "SoftButton", "Grey", INK, bold)
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
	for v in [["HudValue", 19, regular], ["HudSmall", 12, regular], ["HudCaption", 11, regular]]:
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
	t.set_stylebox("panel", "Side", kbox("Grey", "button_square_flat", 14, 14))
	t.set_stylebox("background", "ProgressBar", box(PAPER2, 99, Color(), 0, 0, Color(), 0))
	t.set_stylebox("fill", "ProgressBar", box(PRIMARY, 99, Color(), 0, 0, Color(), 0))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	for c in ["LineEdit", "SpinBox"]:
		t.set_color("caret_color", c, PRIMARY_DARK)
		t.set_constant("caret_width", c, 2)
		t.set_color("font_placeholder_color", c, Color(MUTED, 0.75))
		t.set_color("selection_color", c, Color(PRIMARY, 0.3))

	# Dark glass: the menu, modals and popovers over the 3D world.
	t.set_type_variation("DarkGlass", "PanelContainer")
	var dg := box(Color(0.05, 0.09, 0.12, 0.78), 22, Color(1, 1, 1, 0.14), 1, 0, Color(), 22)
	dg.shadow_color = Color(0, 0, 0, 0.35)
	dg.shadow_size = 18
	t.set_stylebox("panel", "DarkGlass", dg)
	t.set_type_variation("Modal", "PanelContainer")
	var md := box(Color("#14222c"), 22, Color(1, 1, 1, 0.16), 1, 0, Color(), 20)
	md.shadow_color = Color(0, 0, 0, 0.45)
	md.shadow_size = 24
	t.set_stylebox("panel", "Modal", md)
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", box(Color(1, 1, 1, 0.06), 14, Color(1, 1, 1, 0.08), 1, 0, Color(), 12))
	for v in [["Wordmark", 46, bold, Color.WHITE], ["OnDarkTitle", 21, bold, Color.WHITE], ["OnDark", 15, regular, Color("#dfe9ee")],
			["OnDarkCaption", 13, regular, Color("#9fb3bd")], ["OnDarkError", 13, regular, Color("#ff9c8a")], ["Chapter", 12, bold, Color("#69e0b4")]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], v[1])
		t.set_font("font", v[0], v[2])
		t.set_color("font_color", v[0], v[3])
	t.set_constant("outline_size", "Wordmark", 0)
	t.set_type_variation("GhostButton", "Button")
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var a: float = {"normal": 0.08, "hover": 0.16, "pressed": 0.22, "focus": 0.12, "disabled": 0.04, "hover_pressed": 0.22}[st]
		var g := box(Color(1, 1, 1, a), 14, Color(1, 1, 1, 0.18 if st != "focus" else 0.5), 1, 0, Color(), 10)
		g.content_margin_top = 10
		g.content_margin_bottom = 10
		t.set_stylebox(st, "GhostButton", g)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "GhostButton", Color.WHITE)
	t.set_color("font_disabled_color", "GhostButton", Color(1, 1, 1, 0.35))
	t.set_color("icon_normal_color", "GhostButton", Color.WHITE)
	t.set_font("font", "GhostButton", bold)
	t.set_font_size("font_size", "GhostButton", 15)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var cb := box(Color(1, 1, 1, 0.1 if st in ["hover", "hover_pressed"] else 0.05), 12, Color(1, 1, 1, 0.35 if st == "focus" else 0.1), 1, 0, Color(), 10)
		t.set_stylebox(st, "CheckButton", cb)
	t.set_font("font", "CheckButton", regular)
	t.set_font_size("font_size", "CheckButton", 15)
	t.set_type_variation("DarkField", "LineEdit")
	var df := box(Color(1, 1, 1, 0.93), 12, Color(1, 1, 1, 0), 0, 0, Color(), 10)
	t.set_stylebox("normal", "DarkField", df)
	t.set_stylebox("focus", "DarkField", box(Color.WHITE, 12, Color("#69e0b4"), 2, 0, Color(), 10))
	t.set_type_variation("DarkSlider", "HSlider")
	t.set_stylebox("slider", "HSlider", box(Color(0, 0, 0, 0.25), 99, Color(), 0, 0, Color(), 3))
	t.set_stylebox("grabber_area", "HSlider", box(PRIMARY, 99, Color(), 0, 0, Color(), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(PRIMARY, 99, Color(), 0, 0, Color(), 3))
	return t


## Space the device keeps for notches, rounded corners and system bars, in the
## interface's own units: [left, top, right, bottom].
static func safe_margins(node: CanvasItem) -> Array:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or OS.get_name() not in ["Android", "iOS"]:
		return [0, 0, 0, 0]
	var vp := node.get_viewport_rect().size
	var k := vp.x / float(win.x)
	return [maxf(safe.position.x, 0) * k, maxf(safe.position.y, 0) * k,
		maxf(win.x - safe.end.x, 0) * k, maxf(win.y - safe.end.y, 0) * k]


## A modal over everything: dims the screen, closes on the backdrop or Close,
## keeps inside the safe area and scrolls when it is taller than the screen.
## Returns [overlay, content column]; free the overlay to close it.
static func modal(host: Control, title: String, max_w := 560.0, on_close: Callable = Callable()) -> Array:
	var over := Control.new()
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_STOP
	over.z_index = 20
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.06, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.add_child(dim)
	var close := func():
		if on_close.is_valid():
			on_close.call()
		over.queue_free()
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close.call())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := safe_margins(host)
	for i in 4:
		m.add_theme_constant_override("margin_" + ["left", "top", "right", "bottom"][i], int(sm[i]) + 18)
	over.add_child(m)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(center)
	var p := PanelContainer.new()
	p.theme_type_variation = "Modal"
	var vp := host.get_viewport_rect().size
	var w: float = minf(max_w, vp.x - sm[0] - sm[2] - 36)
	var h: float = vp.y - sm[1] - sm[3] - 36
	p.custom_minimum_size.x = w
	center.add_child(p)
	var col := vbox(12)
	p.add_child(col)
	var head := hbox(10)
	var tl := label(title, "OnDarkTitle")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var x := Button.new()
	x.text = "✕"
	x.theme_type_variation = "GhostButton"
	x.custom_minimum_size = Vector2(44, 44)
	x.pressed.connect(func(): click(); close.call())
	head.add_child(x)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var body := vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	# Grow with the content but never past the screen; beyond that, scroll.
	var fit := func():
		var want := body.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = clampf(want, 40.0, maxf(h - 44 - 12 - 40, 80.0))
	body.minimum_size_changed.connect(fit)
	fit.call_deferred()
	host.add_child(over)
	return [over, body]


static func _button(t: Theme, kind: String, colour: String, fg: Color, font: Font) -> void:
	if kind != "Button":
		t.set_type_variation(kind, "Button")
	var normal := kbox(colour, "button_rectangle_depth_flat", 8, 18)
	var pressed := kbox(colour, "button_rectangle_flat", 8, 18)
	pressed.content_margin_top = 12
	var disabled := kbox(colour, "button_rectangle_depth_flat", 8, 18)
	disabled.modulate_color = Color(1, 1, 1, 0.45)
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
	t.set_font_size("font_size", kind, 15)
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
	b.pressed.connect(click)
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
	b.texture_normal = load(KUI + COLOURS[base] + "/Default/button_round_depth_gloss.png") if COLOURS.has(base) else art.badge(base)
	b.texture_pressed = load(KUI + COLOURS[base] + "/Default/button_round_gloss.png") if COLOURS.has(base) else null
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
	b.pressed.connect(click)
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
	v.add_theme_font_override("font", number_font())
	v.add_theme_font_size_override("font_size", 17)
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
