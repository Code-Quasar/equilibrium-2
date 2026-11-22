extends Node
## Screen flow: menu → lobby → Foundation draft → city → results. Each screen
## is rebuilt only when what it shows changes; the city screen updates in place.

var art: Art
var session: Session
var root: Control
var screen: Control
var play: Play
var map: CityMap
var _backdrop: ColorRect
var _shown := ""
var _toast: PanelContainer
var _toast_label: Label
var _toast_t := 0.0
var _sub := ""                 # "howto" while How to Play is open over the menu
var _menu_map: CityMap
var _lift: Control
var _typed_address := ""
var _typed_code := ""


func _ready() -> void:
	Settings.load_all()
	art = Art.new()
	UI.art = art
	UI.sound = AudioStreamPlayer.new()
	UI.sound.bus = "SFX"
	UI.sound.stream = load("res://assets/kenney/sounds/click_002.ogg")
	UI.sound.volume_db = -6.0
	add_child(UI.sound)
	UI.thumbs = Thumbs.new()
	add_child(UI.thumbs)
	UI.music = Soundtrack.new()
	add_child(UI.music)
	UI.music.play_state.call_deferred("calm")
	session = Session.new()
	add_child(session)
	session.changed.connect(_on_changed)
	session.notice.connect(toast)
	var layer := CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.theme = UI.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Let touches through to the map wherever no screen or panel is on top.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_backdrop = ColorRect.new()
	_backdrop.color = Color("#101d29")
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_backdrop)
	_build_toast()
	get_tree().set_auto_accept_quit(false)
	_render()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if play and play.visible and play.close_panel():
			return
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		# Android may have suspended the socket: rejoin and take the server's state.
		if session.phase in ["draft", "play"] and not session.link.is_open() and session.has_saved_seat():
			session.rejoin()


func _process(delta: float) -> void:
	_keyboard_lift(delta)
	if _toast_t > 0:
		_toast_t -= delta
		if _toast_t <= 0:
			_toast.visible = false


func _on_changed(what: String) -> void:
	if what == "phase" or what == "link":
		_render()
	elif what in ["lobby", "draft"] and session.phase in ["lobby", "draft"]:
		_render(true)
	elif session.phase == "play" and play:
		play.refresh(what)
		if what == "view":
			UI.music.follow(session.view)
	elif session.phase == "over" and what == "view":
		_render()


func _render(force := false) -> void:
	var key := session.phase
	if key == "play":
		_show_play()
		return
	if key == _shown and not force and key != "menu":
		return
	match key:
		"menu", "cancelled":
			_show_menu()
		"connecting":
			_show_connecting()
		"lobby":
			_show_lobby()
		"draft":
			_show_draft()
		"over":
			_show_results()
	_shown = key


# ------------------------------------------------------------------ frame ---

func _set_screen(c: Control) -> void:
	if screen:
		screen.queue_free()
		screen = null
	_lift = null
	if play:
		play.visible = false
	if map:
		map.visible = false
	if c:
		_show_backdrop_city(false)
	if c:
		root.add_child(c)
		root.move_child(c, 1)
		screen = c


func _page() -> Array:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sm := UI.safe_margins(root)
	m.add_theme_constant_override("margin_left", 44 + int(sm[0]))
	m.add_theme_constant_override("margin_right", 44 + int(sm[2]))
	m.add_theme_constant_override("margin_top", 22 + int(sm[1]))
	m.add_theme_constant_override("margin_bottom", 22 + int(sm[3]))
	scroll.add_child(m)
	var col := UI.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(col)
	return [page, col]


func _hero(types: Array = ["residential_district", "recycling_center", "biogas_facility", "renewable_power_plant"]) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	for n in types:
		var t := TextureRect.new()
		t.texture = UI.thumbs.get_thumb(n, "M")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(124, 100)
		row.add_child(t)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color("#86c264"), 22, Color(), 0, 0, Color(), 10))
	p.add_child(row)
	return p


func _field(text: String, hint: String) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	f.placeholder_text = hint
	f.custom_minimum_size.y = 48
	return f


func _build_toast() -> void:
	_toast_label = UI.label("", "", true)
	_toast_label.add_theme_color_override("font_color", Color.WHITE)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = PanelContainer.new()
	_toast.add_child(_toast_label)
	# Bottom middle of the city, above the tab bar, clear of the side panel.
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -250
	_toast.offset_right = 150
	_toast.offset_top = -118
	_toast.offset_bottom = -76
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast.z_index = 10
	root.add_child(_toast)


func toast(text: String, level := "info") -> void:
	var col: Color = {"good": Color("#1f8a5b"), "bad": Color("#b9422f"), "warn": Color("#c27a10")}.get(level, UI.INK)
	_toast.add_theme_stylebox_override("panel", UI.box(col, 12, Color(), 0, 0, Color(), 10))
	_toast_label.text = text
	_toast.visible = true
	_toast_t = 3.5
	root.move_child(_toast, root.get_child_count() - 1)


# ------------------------------------------------------------------- menu ---

## The title screen over a slowly circling sample town: brand on one side,
## the actions on a dark glass panel on the other (stacked when tall).
func _show_menu() -> void:
	UI.music.play_state("calm")
	if _sub == "howto":
		_show_howto()
		return
	var page := _world_page()
	var portrait := _portrait()
	var lay: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	lay.add_theme_constant_override("separation", 18 if portrait else 40)
	lay.alignment = BoxContainer.ALIGNMENT_CENTER
	lay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page[1].add_child(lay)
	lay.add_child(_brand(portrait))
	if not portrait:
		lay.add_child(UI.spacer())
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkGlass"
	panel.custom_minimum_size.x = 400 if not portrait else 0
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if portrait:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(panel)
	var box := UI.vbox(10)
	panel.add_child(box)
	box.add_child(UI.label("Server address · port", "OnDarkCaption"))
	var addr := AddressField.new(_address_text())
	box.add_child(addr)
	addr.changed.connect(func(): _typed_address = addr.address())
	var go := func(then: Callable):
		if not addr.validate():
			addr.focus_first_problem()
			return
		get_viewport().gui_release_focus()
		Settings.address = addr.address()
		Settings.save()
		then.call(Settings.address_to_url(addr.address()))
	var create := UI.button("Create game", "PrimaryButton", "plus", func(): go.call(func(u): session.create(u)))
	create.custom_minimum_size.y = 52
	box.add_child(create)
	var code := LineEdit.new()
	code.theme_type_variation = "DarkField"
	code.text = _typed_code
	code.placeholder_text = "4-digit code"
	code.add_theme_font_override("font", UI.number_font())
	code.max_length = 4
	code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	code.custom_minimum_size.y = 50
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Join codes are four digits: anything else typed or pasted is dropped.
	code.text_changed.connect(func(t: String):
		var digits := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != t:
			code.text = digits
			code.caret_column = digits.length()
		_typed_code = digits)
	var join_now := func():
		if code.text.strip_edges() == "":
			toast("Enter the code the host shared", "warn")
			code.grab_focus()
			return
		go.call(func(u): session.join(u, code.text))
	var join := UI.button("Join", "", "play", join_now)
	join.custom_minimum_size = Vector2(110, 50)
	box.add_child(UI.hbox(8, [code, join]))
	# Done / Enter moves on: each address box → the code → join. A bad
	# address keeps its box open for correction.
	addr.submitted.connect(func():
		if addr.validate():
			code.grab_focus()
		else:
			addr.focus_first_problem())
	code.text_submitted.connect(func(_t):
		get_viewport().gui_release_focus()
		if code.text.strip_edges() != "":
			join_now.call())
	if session.has_saved_seat():
		var cont := UI.button("Continue your match", "SoftButton", "play", func(): session.rejoin())
		cont.custom_minimum_size.y = 48
		box.add_child(cont)
	var row := UI.hbox(8)
	for item in [["How to Play", func(): _sub = "howto"; _show_menu()], ["Settings", func(): _open_settings()]]:
		var b := UI.button(item[0], "GhostButton", "", item[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 46
		row.add_child(b)
	if OS.get_name() not in ["iOS", "Web"]:
		var ex := UI.button("Exit", "GhostButton", "", func(): get_tree().quit())
		ex.custom_minimum_size = Vector2(80, 46)
		row.add_child(ex)
	box.add_child(row)


## Emblem and wordmark, in the game's Pixelify Sans.
func _brand(portrait: bool) -> Control:
	var col := UI.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var em := TextureRect.new()
	em.texture = load("res://assets/brand/emblem.svg")
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var side := 92 if portrait else 132
	em.custom_minimum_size = Vector2(side, side)
	var word := UI.label("EQUILIBRIUM", "Wordmark")
	word.add_theme_constant_override("outline_size", 10)
	word.add_theme_color_override("font_outline_color", Color(0.03, 0.07, 0.1, 0.55))
	if portrait:
		word.add_theme_font_size_override("font_size", 34)
	var tag := UI.label("Four cities. One shared population. Twenty minutes.", "OnDark", true)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color(0.03, 0.07, 0.1, 0.6))
	tag.custom_minimum_size.x = 300
	if portrait:
		for n in [em, word, tag]:
			n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(em)
		col.add_child(word)
	else:
		em.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(em)
		col.add_child(word)
	col.add_child(tag)
	return col


func _portrait() -> bool:
	var vp := root.get_viewport_rect().size
	return vp.x < 760 or vp.y > vp.x


## The address as the player typed it last, or the saved one, without ws://.
func _address_text() -> String:
	if _typed_address != "":
		return _typed_address
	if Settings.address != "":
		return Settings.address
	if session.server_url != "":
		return Settings.url_to_address(session.server_url)
	return "127.0.0.1:9080"


## A full-screen page over the 3D backdrop: a soft dark wash for legibility,
## safe-area margins, a lift for the on-screen keyboard and tap-outside to
## dismiss it. Returns [page, content column].
func _world_page(scroll := false) -> Array:
	_set_screen(null)
	_show_backdrop_city(true)
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	page.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			get_viewport().gui_release_focus())
	var wash := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.06, 0.09, 0.82))
	g.set_color(1, Color(0.03, 0.06, 0.09, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	wash.texture = gt
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(wash)
	_lift = Control.new()
	_lift.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_lift)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := UI.safe_margins(root)
	var pad := 20 if _portrait() else 48
	m.add_theme_constant_override("margin_left", int(sm[0]) + pad)
	m.add_theme_constant_override("margin_right", int(sm[2]) + pad)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 18)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 18)
	var col := UI.vbox(14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if scroll:
		var sc := ScrollContainer.new()
		sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_lift.add_child(sc)
		sc.add_child(m)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_lift.add_child(m)
	m.add_child(col)
	root.add_child(page)
	root.move_child(page, 1)
	screen = page
	return [page, col]


func _show_backdrop_city(on: bool) -> void:
	if on and _menu_map == null:
		_menu_map = CityMap.new()
		_menu_map.art = art
		add_child(_menu_map)
		_menu_map.show_demo()
	if _menu_map and not on:
		# Gone entirely outside the menu: the game map alone owns the camera.
		_menu_map.queue_free()
		_menu_map = null
	_backdrop.visible = not on


## Keeps the focused field above the on-screen keyboard.
func _keyboard_lift(delta: float) -> void:
	if _lift == null or not is_instance_valid(_lift):
		return
	var want := 0.0
	var kb := DisplayServer.virtual_keyboard_get_height() if OS.has_feature("mobile") else 0
	var focus := root.get_viewport().gui_get_focus_owner()
	if kb > 0 and focus is LineEdit and _lift.is_ancestor_of(focus):
		var win := DisplayServer.window_get_size()
		var vp := root.get_viewport_rect().size
		var kb_ui := float(kb) * vp.y / maxf(float(win.y), 1.0)
		var bottom := focus.get_global_rect().end.y - _lift.position.y
		want = minf(0.0, vp.y - kb_ui - 16.0 - bottom)
	_lift.position.y = lerpf(_lift.position.y, want, clampf(delta * 14.0, 0.0, 1.0))


func _open_settings() -> void:
	var mc := UI.modal(root, "Settings", 520)
	var body: VBoxContainer = mc[1]
	body.add_child(UI.label("Sound", "Chapter"))
	for item in [["Master", "master"], ["Music", "music"], ["Effects", "sfx"]]:
		var row := UI.hbox(12)
		var l := UI.label(item[0], "OnDark")
		l.custom_minimum_size.x = 92
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Settings.value(item[1])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.y = 36
		var pct := UI.label("%d%%" % int(round(sl.value * 100)), "OnDarkCaption")
		pct.custom_minimum_size.x = 46
		pct.add_theme_font_override("font", UI.number_font())
		var key: String = item[1]
		sl.value_changed.connect(func(v: float):
			Settings.set_value(key, v)
			pct.text = "%d%%" % int(round(v * 100))
			Settings.apply_audio())
		sl.drag_ended.connect(func(_c): Settings.save(); UI.click())
		row.add_child(sl)
		row.add_child(pct)
		body.add_child(row)
	body.add_child(_toggle("Mute all sound", Settings.muted, func(on): Settings.muted = on; Settings.save()))
	body.add_child(UI.label("Display", "Chapter"))
	body.add_child(_toggle("Reduce motion", Settings.reduce_motion, func(on): Settings.reduce_motion = on; Settings.save()))
	body.add_child(UI.label("Crises then glow once at the screen edges instead of pulsing.", "OnDarkCaption", true))
	body.add_child(_toggle("Vibration", Settings.vibration, func(on): Settings.vibration = on; Settings.save()))
	body.add_child(UI.label("Short taps on phones when an emergency action lands. Never needed to play.", "OnDarkCaption", true))
	body.add_child(UI.label("Connection", "Chapter"))
	body.add_child(_toggle("Secure connection (wss://)", Settings.secure, func(on): Settings.secure = on; Settings.save()))
	body.add_child(UI.label("Use it when the server sits behind TLS. Most local servers use the plain connection.", "OnDarkCaption", true))
	body.add_child(UI.label("Developer", "Chapter"))
	body.add_child(_toggle("Network diagnostics overlay", Settings.diagnostics, func(on):
		Settings.diagnostics = on
		Settings.save()
		if play:
			play.refresh("link")))
	body.add_child(UI.label("Shows round-trip time, jitter, action latency and how fresh the last update is.", "OnDarkCaption", true))


func _toggle(text: String, on: bool, changed: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.custom_minimum_size.y = 44
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(k, Color("#dfe9ee"))
	c.toggled.connect(func(v: bool): UI.click(); changed.call(v))
	return c


func _show_connecting() -> void:
	var page := _world_page()
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page[1].add_child(center)
	var p := PanelContainer.new()
	p.theme_type_variation = "DarkGlass"
	center.add_child(p)
	var box := UI.vbox(12)
	p.add_child(box)
	box.add_child(UI.label("Connecting…", "OnDarkTitle"))
	box.add_child(UI.label(Settings.url_to_address(session.server_url), "OnDarkCaption"))
	box.add_child(UI.button("Cancel", "GhostButton", "close", func(): session.leave()))


# ------------------------------------------------------------ how to play ---

const HOWTO := [
	["01", "Objective", ["residential_district"], ["people"],
		"Four cities draw residents from one shared population. When the 20 minutes run out, the city with the most residents wins. Ties go to Satisfaction, then Environment, then cash."],
	["02", "Build", ["commercial_district", "factory"], ["coin", "timer"],
		"Open Build, pick Small, Medium or Large and drag a building onto open land. Each costs cash plus materials and takes real seconds to finish; two can be under construction at once. Watch it rise: the bar shows how far along it is. A building can later grow one size at a time and keeps working while it does. Cities start with no materials: construction buys any it lacks for cash, so recovering your own is cheaper."],
	["03", "Roads", ["residential_district"], ["warning"],
		"One main road crosses the map and cannot be removed. Draw your own roads for free. A building works only when it touches a road joined to the main road; otherwise it is switched off and shows a road bubble."],
	["04", "Residents and Satisfaction", ["public_services_center", "park"], ["homes", "jobs"],
		"Homes, jobs, public services, enough power and a clean environment raise Satisfaction. From 1:20 into the match and every 20 seconds after, residents move toward clearly more satisfying cities, a few at a time and only as far as there are homes for them."],
	["05", "Electricity", ["renewable_power_plant", "fossil_power_plant"], ["power"],
		"Power plants generate electricity and most buildings use it. Fossil plants are quick and cheap but dirty the air; renewable plants are clean. A shortage lowers Satisfaction, and spare power can be sold."],
	["06", "Waste", ["collection_center", "sorting_center", "recycling_center", "biogas_facility"], ["waste", "materials"],
		"Homes and businesses produce recyclable, organic and residual waste, and the city fleet hauls what it can to the landfill. Build the recovery chain in order: a Collection Center collects more and salvages some recyclables; a Sorting Center separates the rest and reuses more; a Recycling Center then makes the most materials and a Biogas Facility turns organics into power. Each step recovers more from the same waste. Materials pay for construction and feed factories; landfill damage lasts until parks with clean air to spare repair it."],
	["07", "Trade", ["commercial_district"], ["offers"],
		"In Trade, offer spare electricity, recycling or organic treatment to the other cities at fixed prices, or accept their offers for one to five minutes. The buyer's escrow holds the most a contract could cost; only real deliveries are paid and the rest comes back."],
	["08", "Crises", ["fossil_power_plant"], ["event", "pollution"],
		"Three crises are announced 45 seconds ahead and last a minute and a half: Smog Alert at 5:00, Waste Surge at 10:00 and Power Shortage at 15:00. Their damage stays after they end, so prepare before they arrive. EQUILIBRIUM 2050 marks the end of the match."],
	["09", "Win", ["residential_district", "commercial_district"], ["badge", "appeal"],
		"Keep residents satisfied and housed, keep power and waste under control, and watch your rivals in the Rivals panel, where you can also visit their cities. The final ranking is decided by the server at the end of the match."],
]


func _show_howto() -> void:
	var pc := _world_page(true)
	var col: VBoxContainer = pc[1]
	var head := UI.hbox(12)
	var back := UI.button("Back", "GhostButton", "close", func(): _sub = ""; _show_menu())
	back.custom_minimum_size = Vector2(110, 46)
	head.add_child(back)
	var t := UI.label("How to Play", "Wordmark")
	t.add_theme_font_size_override("font_size", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	col.add_child(head)
	# Chapter chips: jump straight to a chapter.
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	col.add_child(chips)
	var cards: Array[Control] = []
	var portrait := _portrait()
	for ch in HOWTO:
		var card := PanelContainer.new()
		card.theme_type_variation = "DarkGlass"
		card.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.09, 0.12, 0.84), 20, Color(1, 1, 1, 0.12), 1, 0, Color(), 18))
		var lay: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
		lay.add_theme_constant_override("separation", 18)
		card.add_child(lay)
		var pics := HBoxContainer.new()
		pics.add_theme_constant_override("separation", 0)
		pics.custom_minimum_size = Vector2(260 if not portrait else 0, 120)
		pics.alignment = BoxContainer.ALIGNMENT_CENTER
		var art_box := PanelContainer.new()
		art_box.theme_type_variation = "Inset"
		art_box.add_child(pics)
		art_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for b in ch[2]:
			var tr := TextureRect.new()
			tr.texture = UI.thumbs.get_thumb(b, "M" if ch[0] in ["01", "09"] else "S")
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(minf(170.0, 250.0 / ch[2].size()), 130)
			pics.add_child(tr)
		lay.add_child(art_box)
		var text := UI.vbox(6)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := UI.hbox(8)
		top.add_child(UI.label(ch[0], "Chapter"))
		for bn in ch[3]:
			var bt := TextureRect.new()
			bt.texture = art.badge(bn)
			bt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			bt.custom_minimum_size = Vector2(22, 22)
			top.add_child(bt)
		text.add_child(top)
		text.add_child(UI.label(ch[1], "OnDarkTitle"))
		text.add_child(UI.label(ch[4], "OnDark", true))
		lay.add_child(text)
		col.add_child(card)
		cards.append(card)
		var chip := UI.button("%s %s" % [ch[0], ch[1]], "GhostButton", "", func():
			var sc := col.get_parent().get_parent() as ScrollContainer
			if sc:
				create_tween().tween_property(sc, "scroll_vertical", int(card.position.y), 0.35).set_trans(Tween.TRANS_CUBIC))
		chip.add_theme_font_size_override("font_size", 12)
		chip.custom_minimum_size.y = 36
		chips.add_child(chip)
	var done := UI.button("Got it — back to the menu", "PrimaryButton", "check", func(): _sub = ""; _show_menu())
	done.custom_minimum_size.y = 50
	col.add_child(done)


# ------------------------------------------------------------------ lobby ---

func _show_lobby() -> void:
	var pc := _page()
	_set_screen(pc[0])
	var page: VBoxContainer = pc[1]
	var cols := UI.hbox(28)
	page.add_child(cols)
	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UI.label("Lobby", "Display"))
	if session.join_code != "":
		left.add_child(UI.label("Join code", "Caption"))
		var code := UI.label(session.join_code, "Title")
		code.add_theme_font_override("font", UI.number_font())
		code.add_theme_font_size_override("font_size", 30)
		left.add_child(code)
		left.add_child(UI.label("Send it to your friends. They enter the same server address and join with it.", "Caption", true))
		left.add_child(UI.button("Copy code", "SoftButton", "", func(): DisplayServer.clipboard_set(session.join_code); toast("Code copied", "good")))
	else:
		left.add_child(UI.label("You joined this lobby. The host starts the match once everyone is ready.", "Caption", true))
	left.add_child(UI.label("Empty seats become bots when the match starts.", "Caption", true))
	left.add_child(UI.button("Leave", "SoftButton", "close", func(): session.leave()))
	var right := UI.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var seats: Array = session.lobby.get("seats", [])
	var my_ready := false
	var all_ready := true
	for row in seats:
		var s := int(row["seat"])
		var who := "Open seat — a bot will play"
		var ctl := str(row.get("controller", "open"))
		if ctl == "human":
			who = "You" if s == session.seat else "Player %d" % (s + 1)
			if not row.get("ready", false):
				all_ready = false
		elif ctl == "bot":
			who = "Bot"
		if s == session.seat:
			my_ready = bool(row.get("ready", false))
		var line := UI.hbox(10)
		line.add_child(UI.label("City %d" % (s + 1), "Value"))
		line.add_child(UI.label(who, "Caption"))
		line.add_child(UI.spacer())
		if int(session.lobby.get("host_seat", -1)) == s:
			line.add_child(UI.pill("host", UI.CARDS))
		if ctl == "human":
			line.add_child(UI.pill("ready" if row.get("ready", false) else "not ready", UI.PRIMARY if row.get("ready", false) else UI.WARN))
			if not row.get("connected", true):
				line.add_child(UI.pill("offline", UI.DANGER))
		right.add_child(UI.panel("Card", line))
	right.add_child(UI.button("I'm not ready" if my_ready else "I'm ready", "SoftButton" if my_ready else "PrimaryButton", "check", func(): session.set_ready(not my_ready)))
	if session.is_host:
		var start := UI.button("Start match", "PrimaryButton", "play", func(): session.start_match())
		start.disabled = not all_ready
		right.add_child(start)
		if not all_ready:
			right.add_child(UI.label("Every player must be ready.", "Caption"))
	else:
		right.add_child(UI.label("Waiting for the host to start.", "Caption"))


# ------------------------------------------------------------------ draft ---

## All four Foundations side by side, each with its colour, starting package,
## strengths and trade-off; above them every seat's pick in its own chip, so
## nothing is hidden. Human seats choose first; bots then take what is left.
func _show_draft() -> void:
	var pc := _page()
	_set_screen(pc[0])
	var col: VBoxContainer = pc[1]
	col.add_theme_constant_override("separation", 10)
	var d := session.draft
	var order: Array = d.get("order", [])
	var choices: Array = d.get("choices", [null, null, null, null])
	var available: Array = d.get("available_foundations", [])
	var turn := int(d.get("turn_seat", -1))
	var mine := turn == session.seat
	var bots := {}
	for row in session.lobby.get("seats", []):
		if str(row.get("controller", "")) == "bot":
			bots[int(row["seat"])] = true
	var status := ""
	if not session.draft_choice.is_empty():
		status = "Sending your choice…" if session.draft_choice["status"] == "sending" else "Choice received — confirming…"
	elif mine:
		status = "Your turn: pick the head start only your city will have."
	elif turn >= 0:
		status = ("Bots are choosing from what is left…" if bots.has(turn) else "Waiting for City %d to choose…" % (turn + 1))
	else:
		status = "All chosen — the match is starting."
	var head := UI.hbox(14)
	head.add_child(UI.label("Choose your Foundation", "Display"))
	var st := UI.label(status, "Value", true)
	st.add_theme_color_override("font_color", UI.PRIMARY_DARK if mine else UI.MUTED)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(st)
	if not session.live:
		head.add_child(UI.pill("Reconnecting…", UI.WARN))
	col.add_child(head)
	# Every seat's pick, in draft order, each in a chip of its own.
	var picks := UI.hbox(8)
	for k in order.size():
		var seat := int(order[k])
		var f: Variant = choices[seat] if seat < choices.size() else null
		var who := "You" if seat == session.seat else ("Bot · City %d" % (seat + 1) if bots.has(seat) else "City %d" % (seat + 1))
		var chip := UI.vbox(0)
		chip.add_child(UI.label("%d · %s" % [k + 1, who], "Small"))
		var what := UI.label("", "Value", true)
		if f != null:
			what.text = Catalogue.FOUNDATIONS[f][0]
			what.add_theme_color_override("font_color", Catalogue.FOUNDATIONS[f][2].darkened(0.15))
		else:
			what.text = "Choosing…" if seat == turn else ("After the players" if bots.has(seat) else "Waiting")
			what.add_theme_color_override("font_color", UI.MUTED)
		chip.add_child(what)
		var box := PanelContainer.new()
		var tint: Color = Catalogue.FOUNDATIONS[f][2] if f != null else UI.LINE
		box.add_theme_stylebox_override("panel", UI.box(UI.PAPER2 if seat != turn else Color("#e6f6ee"), 12, tint, 2 if f != null or seat == turn else 1, 0, Color(), 8))
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_stretch_ratio = 1.0
		box.add_child(chip)
		picks.add_child(box)
	col.add_child(picks)
	var row := UI.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var cat: Dictionary = Catalogue.data().get("foundations", {})
	for id in Catalogue.FOUNDATIONS:
		var taken: bool = not (id in available)
		var pending: bool = session.draft_choice.get("foundation", "") == id
		var owner := choices.find(id)
		row.add_child(_foundation_card(id, cat.get(id, {}), taken, pending, mine, owner))


## One Foundation: colour band and name, its starting buildings, cash as a chip,
## two strengths and a trade-off, and the choose button.
func _foundation_card(id: String, pkg: Dictionary, taken: bool, pending: bool, mine: bool, owner: int) -> Control:
	var meta: Array = Catalogue.FOUNDATIONS[id]
	var colour: Color = meta[2]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.box(UI.PAPER, 16, colour if not taken else UI.LINE, 2, 4, colour.darkened(0.25) if not taken else UI.LIP, 0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	var col := UI.vbox(6)
	card.add_child(col)
	var band := PanelContainer.new()
	var bs := UI.box(colour if not taken else UI.MUTED, 14, Color(), 0, 0, Color(), 8)
	bs.corner_radius_bottom_left = 0
	bs.corner_radius_bottom_right = 0
	band.add_theme_stylebox_override("panel", bs)
	var name := UI.label(meta[0], "Value", true)
	name.add_theme_color_override("font_color", Color.WHITE)
	band.add_child(name)
	col.add_child(band)
	var inner := UI.vbox(6)
	var pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(inner)
	col.add_child(pad)
	var starts: Array = pkg.get("buildings", [])
	var pics := UI.hbox(2)
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	for x in (starts if not starts.is_empty() else [{"type": "commercial_district", "size": "S"}]):
		var t := TextureRect.new()
		t.texture = UI.thumbs.get_thumb(str(x["type"]), str(x["size"]))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(64, 56)
		t.modulate = Color(1, 1, 1, 0.35) if starts.is_empty() else Color.WHITE
		pics.add_child(t)
	inner.add_child(pics)
	inner.add_child(UI.label(meta[1], "Caption", true))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	chips.add_child(UI.stat_chip("coin", Catalogue.fmt(float(pkg.get("cash", 0))), UI.MONEY))
	for x in starts:
		chips.add_child(UI.stat_chip("build", "%s %s" % [Catalogue.short_name(str(x["type"])), str(x["size"])], colour))
	inner.add_child(chips)
	for good in meta[3]:
		inner.add_child(UI.pro_con(good, true))
	inner.add_child(UI.pro_con(meta[4], false))
	inner.add_child(UI.spacer(false))
	var label := "Taken" if taken else ("Sending…" if pending else ("Choose" if mine else "Not your turn"))
	if owner >= 0:
		label = "Yours" if owner == session.seat else "City %d" % (owner + 1)
	var b := UI.button(label, "PrimaryButton" if mine and not taken else "SoftButton", "check" if mine and not taken else "", func(): session.choose_foundation(id))
	b.disabled = taken or not mine or not session.draft_choice.is_empty() or not session.live
	b.custom_minimum_size.y = 46
	inner.add_child(b)
	card.modulate = Color(1, 1, 1, 0.6) if taken and owner != session.seat else Color.WHITE
	return card


# -------------------------------------------------------------------- play ---

func _show_play() -> void:
	if screen:
		screen.queue_free()
		screen = null
	if map == null:
		# The map lives in the game world, under the interface layer.
		map = CityMap.new()
		map.art = art
		map.clock = func() -> float: return float(session.view.get("tick", 0))
		add_child(map)
	map.visible = true
	_show_backdrop_city(false)
	_backdrop.visible = false
	if play == null:
		play = Play.new()
		play.map = map
		play.art = art
		play.session = session
		play.toast = toast
		play.open_settings = _open_settings
		root.add_child(play)
		root.move_child(play, 1)
	play.visible = true
	_shown = "play"
	play.refresh("all")


# ---------------------------------------------------------------- results ---

func _show_results() -> void:
	var pc := _page()
	_set_screen(pc[0])
	var page: VBoxContainer = pc[1]
	var fr: Variant = session.final_result
	var rows: Array = fr.get("rankings", []) if typeof(fr) == TYPE_DICTIONARY else []
	var winners: Array = fr.get("winners", []) if typeof(fr) == TYPE_DICTIONARY else []
	var won := session.seat in winners
	var cols := UI.hbox(28)
	page.add_child(cols)
	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UI.label("2050", "Caption"))
	left.add_child(UI.label("You win!" if won else ("Shared victory" if winners.size() > 1 and won else "Match over"), "Display"))
	left.add_child(UI.label("Most residents after 20 minutes wins; ties go to Satisfaction, then Environment, then cash.", "Caption", true))
	left.add_child(_hero())
	var own: Dictionary = session.view.get("own_city", {})
	if not own.is_empty():
		var w: Dictionary = own.get("waste", {}).get("totals", {})
		var lines := ["Materials recovered: %s (collection %s, sorting %s, recycling %s)" % [
				Catalogue.micro(int(w.get("salvaged", 0)) + int(w.get("sorting_reuse", 0)) + int(w.get("recycled_materials", 0))),
				Catalogue.micro(w.get("salvaged", 0)), Catalogue.micro(w.get("sorting_reuse", 0)), Catalogue.micro(w.get("recycled_materials", 0))],
			"Organic waste turned into power: %s units" % Catalogue.micro(w.get("digested", 0)),
			"Sent to landfill: %s units" % Catalogue.micro(w.get("landfilled", 0))]
		left.add_child(UI.panel("Card", UI.label("Your circular economy\n" + "\n".join(lines), "", true)))
	left.add_child(UI.button("Back to menu", "PrimaryButton", "play", func(): session.leave()))
	var right := UI.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UI.label("Final ranking", "Title"))
	if rows.is_empty():
		right.add_child(UI.label("Waiting for the final result…", "Caption"))
	for r in rows:
		var cid := int(r["city_id"])
		var row := UI.hbox(10, [UI.label("%d" % int(r["rank"]), "Display")])
		var name := ("Your city" if cid == session.seat else "City %d" % (cid + 1))
		row.add_child(UI.vbox(0, [UI.label(name + ("  🏆" if cid in winners else ""), "Value"),
			UI.label("Satisfaction %s · Environment %s" % [Catalogue.micro(r.get("satisfaction_micro", 0), 1), Catalogue.micro(r.get("environment_micro", 0), 1)], "Small")]))
		row.add_child(UI.spacer())
		row.add_child(UI.label("%s residents" % Catalogue.fmt(float(r["population"])), "Value"))
		right.add_child(UI.panel("Card", row))
