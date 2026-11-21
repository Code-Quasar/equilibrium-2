extends Node
## Screen flow: menu → lobby → Foundation draft → city → results. Each screen
## is rebuilt only when what it shows changes; the city screen updates in place.

const DEFAULT_URL := "ws://127.0.0.1:9080"

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
var _howto := false


func _ready() -> void:
	art = Art.new()
	UI.art = art
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
	if play:
		play.visible = false
	if map:
		map.visible = false
	_backdrop.visible = true
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
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 44)
	m.add_theme_constant_override("margin_top", 22)
	m.add_theme_constant_override("margin_bottom", 22)
	scroll.add_child(m)
	var col := UI.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(col)
	return [page, col]


func _hero(names: Array = ["residential_m", "recycling_center_m", "biogas_plant_m", "renewable_plant_s"]) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", -10)
	for n in names:
		var t := TextureRect.new()
		t.texture = art.sprite(n)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(112, 112)
		row.add_child(t)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color("#8cc56a"), 22, Color(), 0, 0, Color(), 10))
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
	_toast.offset_left = -470
	_toast.offset_right = 50
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

func _show_menu() -> void:
	var pc := _page()
	_set_screen(pc[0])
	var page: VBoxContainer = pc[1]
	var cols := UI.hbox(28)
	page.add_child(cols)
	var left := UI.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	cols.add_child(left)
	left.add_child(UI.label("EQUILIBRIUM", "Display"))
	left.add_child(UI.label("Four cities. One shared population. Twenty minutes to build the city people choose to live in.", "Value", true))
	left.add_child(_hero())
	if _howto:
		left.add_child(UI.panel("Card", UI.label(
			"• Residents are the prize: the city with the most at the end wins.\n" +
			"• Homes, jobs, services, power and a clean environment raise Satisfaction, and residents move toward the most satisfying city every 20 seconds.\n" +
			"• Waste piles up unless you collect it (Recovery Hub), recycle it into materials (Recycling Center), turn organics into power (Biogas) or landfill it.\n" +
			"• Trade treatment and electricity with rival cities. Four announced crises test everyone.", "", true)))
	var box := UI.vbox(10)
	box.add_child(UI.label("Play online", "Title"))
	box.add_child(UI.label("Server address", "Caption"))
	var url := _field(session.server_url if session.server_url != "" else DEFAULT_URL, DEFAULT_URL)
	url.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	box.add_child(url)
	box.add_child(UI.button("Create game", "PrimaryButton", "plus", func(): session.create(url.text)))
	var code := _field("", "Join code")
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join := UI.button("Join", "", "play", func():
		if code.text.strip_edges() == "":
			toast("Enter the code the host shared", "warn")
		else:
			session.join(url.text, code.text))
	box.add_child(UI.hbox(8, [code, join]))
	if session.has_saved_seat():
		box.add_child(UI.button("Continue your match", "SoftButton", "play", func(): session.rejoin()))
	box.add_child(UI.button("How to play" if not _howto else "Hide how to play", "SoftButton", "", func(): _howto = not _howto; _show_menu()))
	var card := UI.panel("Card", box)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(card)


func _show_connecting() -> void:
	var pc := _page()
	_set_screen(pc[0])
	pc[1].add_child(UI.label("Connecting…", "Display"))
	pc[1].add_child(UI.label(session.server_url, "Caption"))
	pc[1].add_child(UI.button("Cancel", "SoftButton", "close", func(): session.leave()))


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

func _show_draft() -> void:
	var pc := _page()
	_set_screen(pc[0])
	var col: VBoxContainer = pc[1]
	var d := session.draft
	var order: Array = d.get("order", [])
	var choices: Array = d.get("choices", [null, null, null, null])
	var available: Array = d.get("available_foundations", [])
	var turn := int(d.get("turn_seat", -1))
	var mine := turn == session.seat
	col.add_child(UI.label("Choose your Foundation", "Display"))
	var status := ""
	if not session.draft_choice.is_empty():
		status = "Sending your choice…" if session.draft_choice["status"] == "sending" else "Choice received — confirming…"
	elif mine:
		status = "Your turn: pick the head start only your city will have."
	elif turn >= 0:
		status = "Waiting for City %d to choose…" % (turn + 1)
	else:
		status = "All chosen — the match is starting."
	var st := UI.label(status, "Value", true)
	st.add_theme_color_override("font_color", UI.PRIMARY_DARK if mine else UI.MUTED)
	col.add_child(st)
	if not session.live:
		col.add_child(UI.pill("Reconnecting…", UI.WARN))
	var picks := UI.hbox(10)
	for k in order.size():
		var s := int(order[k])
		var f: Variant = choices[s] if s < choices.size() else null
		var who := "You" if s == session.seat else "City %d" % (s + 1)
		var txt := "%d. %s — %s" % [k + 1, who, Catalogue.FOUNDATIONS[f][0] if f != null else ("choosing…" if s == turn else "…")]
		picks.add_child(UI.label(txt, "Caption"))
	col.add_child(UI.panel("Card", picks))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	col.add_child(grid)
	var cat: Dictionary = Catalogue.data().get("foundations", {})
	for id in Catalogue.FOUNDATIONS:
		var meta: Array = Catalogue.FOUNDATIONS[id]
		var taken: bool = not (id in available)
		var pending: bool = session.draft_choice.get("foundation", "") == id
		var box := UI.vbox(8)
		var row := UI.hbox(12)
		var t := TextureRect.new()
		t.texture = art.sprite(meta[2])
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(92, 92)
		row.add_child(t)
		var info := UI.vbox(4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(meta[0], "Title"))
		info.add_child(UI.label(meta[1], "Caption", true))
		var pkg: Dictionary = cat.get(id, {})
		var start := "Starts with %s cash" % Catalogue.fmt(float(pkg.get("money", 0)))
		if str(pkg.get("building", "")) != "":
			start += " and a %s" % Catalogue.building_name(pkg["building"])
		info.add_child(UI.label(start, "Small", true))
		row.add_child(info)
		box.add_child(row)
		var label := "Taken" if taken else ("Sending…" if pending else ("Choose" if mine else "Not your turn"))
		var b := UI.button(label, "PrimaryButton" if mine and not taken else "SoftButton", "check" if mine and not taken else "", func(): session.choose_foundation(id))
		b.disabled = taken or not mine or not session.draft_choice.is_empty() or not session.live
		box.add_child(b)
		var card := UI.panel("Card", box)
		card.modulate = Color(1, 1, 1, 0.5) if taken else Color.WHITE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)


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
	_backdrop.visible = false
	if play == null:
		play = Play.new()
		play.map = map
		play.art = art
		play.session = session
		play.toast = toast
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
		var lines := ["Recycled: %s units" % Catalogue.micro(own.get("waste_totals", {}).get("recycled", 0)),
			"Organic waste treated: %s units" % Catalogue.micro(own.get("waste_totals", {}).get("organic_processed", 0)),
			"Materials recovered: %s" % Catalogue.micro(own.get("recovered_micro", 0)),
			"Sent to landfill: %s units" % Catalogue.micro(own.get("disposed_micro", 0))]
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
