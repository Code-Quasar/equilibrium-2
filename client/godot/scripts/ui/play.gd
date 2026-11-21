class_name Play
extends Control
## The live city, kept simple: the map fills the screen; a few numbers say
## what the city has and needs; bubbles over buildings say what each one is
## missing. No reports. Every number comes from the last player_view and every
## button sends an action whose server receipt is shown.

const PANELS := ["market", "rivals", "building", "policy"]
## City needs: key, badge, short name, what to build when short.
const NEEDS := [
	["homes", "homes", "Homes", "Short of homes: build a Residential District."],
	["jobs", "jobs", "Jobs", "Not enough jobs: build a Commercial District or a Factory."],
	["power", "power", "Power", "Not enough electricity: build a power plant, or buy power in Trade."],
	["services", "people", "Services", "Not enough services: build a Public Services Center."],
	["waste", "waste", "Street waste", "Waste is piling up: build a Recovery Hub to collect it."],
	["air", "pollution", "Environment", "Environment drives residents: Green Space cleans the air; fewer factories and landfills help."],
]
## What a bubble over a building means.
const BUBBLES := {
	"road": "Needs a road to the main road",
	"off": "Switched off",
	"coin": "Not enough money to run it",
	"power": "Not enough electricity",
	"people": "Not enough workers",
	"waste": "Waste is not being collected here",
}

var art: Art
var session: Session
var toast: Callable

var map: CityMap                  # the world map; App owns it, this screen drives it
var placing := {}                 # {type, at, ok, why}: a building being dragged into place
var tab := ""                     # "", "build", or a panel in PANELS
var selected := -1
var confirm := ""                 # action awaiting a second tap (demolish, cancel)
var market_form := {"type": "electricity", "rate": 5, "price": 0}

var _reserved := {}               # tile -> action id of a construction on its way
var _card_drag := {}              # a build card pressed, before it becomes a drag
var _card_dragging := false
var _modebar: PanelContainer
var _panel: PanelContainer
var _panel_title: Label
var _body: VBoxContainer
var _drawer: PanelContainer
var _drawer_cards := {}           # building type -> {button, price}
var _activity: VBoxContainer
var _banner: PanelContainer
var _blockers: Array[Control] = []
var _smile: Label
var _pop: Control
var _rank_label: Label
var _need_chips := {}
var _cash: Control
var _mats: Control
var _timer: Control
var _net: Label
var _last_pop := -1
var _pop_delta := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _corner(preset: int, x: float, y: float, child: Control) -> Control:
	child.set_anchors_preset(preset)
	var right := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var bottom := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	child.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	child.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	child.offset_left = -x if right else x
	child.offset_right = -x if right else x
	child.offset_top = -y if bottom else y
	child.offset_bottom = -y if bottom else y
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(child)
	return child


func _build() -> void:
	map.tapped.connect(_on_tile)
	map.ghost_dragged.connect(_on_ghost_drag)
	map.ghost_dropped.connect(_on_ghost_drop)
	map.ui_blocks = blocks

	# Top left: Satisfaction, residents and rank, then what the city needs.
	var tl := UI.vbox(6)
	var row := UI.hbox(10)
	var smile := PanelContainer.new()
	smile.add_theme_stylebox_override("panel", UI.box(Color("#2fb27a"), 40, Color.WHITE, 3, 0, Color(), 6))
	smile.custom_minimum_size = Vector2(72, 72)
	_smile = UI.label("", "HudValue")
	_smile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_smile.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_smile.add_theme_font_size_override("font_size", 20)
	smile.add_child(_smile)
	row.add_child(smile)
	var who := UI.vbox(4)
	_pop = UI.counter("people", 130, 34)
	who.add_child(_pop)
	_rank_label = UI.label("", "HudSmall")
	who.add_child(_rank_label)
	row.add_child(who)
	tl.add_child(row)
	var needs := UI.hbox(6)
	for n in NEEDS:
		var chip := Button.new()
		chip.add_theme_stylebox_override("normal", UI.box(Color(0.06, 0.11, 0.16, 0.82), 12, Color(), 0, 0, Color(), 4))
		chip.add_theme_stylebox_override("hover", UI.box(Color(0.06, 0.11, 0.16, 0.9), 12, Color(), 0, 0, Color(), 4))
		chip.add_theme_stylebox_override("pressed", UI.box(Color(0.12, 0.2, 0.26, 0.95), 12, Color(), 0, 0, Color(), 4))
		chip.custom_minimum_size = Vector2(74, 52)
		var col := UI.vbox(0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var b := UI.badge(n[1], 24)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(b)
		var l := UI.label("", "HudSmall")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
		chip.add_child(col)
		var hint: String = n[3]
		chip.pressed.connect(func(): toast.call(hint, "info"))
		needs.add_child(chip)
		_need_chips[n[0]] = l
	tl.add_child(needs)
	_blockers.append(_corner(Control.PRESET_TOP_LEFT, 10, 8, tl))

	# Top right: money, materials, time left, connection.
	var tr := UI.hbox(16)
	_cash = UI.counter("coin", 110)
	_mats = UI.counter("materials", 90)
	_timer = UI.counter("timer", 86)
	tr.add_child(_cash)
	tr.add_child(_mats)
	tr.add_child(_timer)
	var right := UI.vbox(2, [tr])
	_net = UI.label("", "HudCaption")
	_net.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_net)
	_blockers.append(_corner(Control.PRESET_TOP_RIGHT, 12, 10, right))

	# Coming crisis, top middle.
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 70
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)

	# Bottom left: trade, rivals, waste policy.
	var bl := UI.hbox(12)
	bl.add_child(UI.round_button("btn_blue", "trade", "Trade", func(): _open("market")))
	bl.add_child(UI.round_button("btn_blue", "region", "Rivals", func(): _open("rivals")))
	bl.add_child(UI.round_button("btn_green", "waste", "Policy", func(): _open("policy")))
	_blockers.append(_corner(Control.PRESET_BOTTOM_LEFT, 14, 10, bl))

	# Bottom right: roads and the build bar.
	var br := UI.hbox(12)
	br.add_child(UI.round_button("btn_orange", "road", "Roads", func(): _open(""); road_mode("draw")))
	br.add_child(UI.round_button("btn_green", "plus", "Build", func(): _open("" if tab == "build" else "build"), 72))
	_blockers.append(_corner(Control.PRESET_BOTTOM_RIGHT, 14, 10, br))

	# The build bar: every building in a row; drag one up onto the map.
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 8
	var cards := UI.hbox(10)
	scroll.add_child(cards)
	for t in Catalogue.BUILDINGS:
		cards.add_child(_drawer_card(t))
	UI.pass_touches(cards)
	_drawer = UI.panel("Side", scroll)
	_drawer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_drawer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drawer.offset_left = 10
	_drawer.offset_right = -110
	_drawer.offset_bottom = -8
	_drawer.offset_top = -190
	_drawer.visible = false
	add_child(_drawer)
	_blockers.append(_drawer)

	# One panel on the right for trade, rivals, a building, or the policy.
	var pv := UI.vbox(8)
	var head := UI.hbox()
	_panel_title = UI.label("", "Title")
	head.add_child(_panel_title)
	head.add_child(UI.spacer())
	head.add_child(UI.round_button("btn_red", "close", "", func(): selected = -1; _open(""), 40))
	pv.add_child(head)
	var ps := ScrollContainer.new()
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ps.scroll_deadzone = 8
	pv.add_child(ps)
	_body = UI.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(_body)
	_panel = UI.panel("Side", pv)
	_panel.anchor_left = 1
	_panel.anchor_right = 1
	_panel.anchor_bottom = 1
	_panel.offset_left = -400
	_panel.offset_right = -8
	_panel.offset_top = 92
	_panel.offset_bottom = -96
	_panel.visible = false
	add_child(_panel)
	_blockers.append(_panel)

	# Placement and road bar, where the panel would be.
	_modebar = PanelContainer.new()
	_modebar.add_theme_stylebox_override("panel", UI.box(UI.PAPER, 16, UI.LINE, 1, 3, UI.LIP, 12))
	_modebar.anchor_left = 1
	_modebar.anchor_right = 1
	_modebar.offset_left = -400
	_modebar.offset_right = -8
	_modebar.offset_top = 92
	_modebar.visible = false
	add_child(_modebar)
	_blockers.append(_modebar)

	# Recent actions and their receipts.
	_activity = UI.vbox(4)
	_activity.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_activity.offset_left = 12
	_activity.offset_top = 40
	_activity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_activity)


func _drawer_card(t: String) -> Control:
	var box := UI.vbox(2)
	box.custom_minimum_size = Vector2(132, 0)
	var thumb := TextureRect.new()
	thumb.texture = art.sprite(Catalogue.sprite(t, 1))
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(120, 70)
	box.add_child(thumb)
	var name := UI.label(Catalogue.building_name(t), "Small", true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_color_override("font_color", UI.INK)
	box.add_child(name)
	var price := UI.label("", "Small")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(price)
	var b := UI.button("Place", "PrimaryButton", "", func(): start_placing(t))
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 13)
	box.add_child(b)
	var card := UI.panel("Card", box)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.gui_input.connect(func(e): _card_input(e, t, not b.disabled))
	thumb.gui_input.connect(func(e): _card_input(e, t, not b.disabled))
	_drawer_cards[t] = {"button": b, "price": price}
	return card


## Prices, locks and money update in place, so a card being pressed is never
## rebuilt under the finger.
func _drawer_refresh() -> void:
	var o := own()
	var dev := int(o.get("development_micro", 0))
	var cash := int(o.get("available_money_micro", 0))
	var mats := int(o.get("materials_micro", 0))
	var disc := int(Catalogue.data().get("material_discount_percent", 0))
	var free := _slots_free()
	for t in _drawer_cards:
		var s := Catalogue.spec(t)
		var cost := int(s.get("l1", {}).get("cost_micro", 0))
		var pay := cost - mini(mats, cost * disc / 100)
		var locked := dev < int(s.get("build_unlock_micro", 0))
		var c: Dictionary = _drawer_cards[t]
		var b: Button = c["button"]
		c["price"].text = ("🔒 Dev %s" % Catalogue.micro(s["build_unlock_micro"])) if locked else "💰 %s · ⏱ %s" % [Catalogue.micro(pay), Catalogue.clock(int(s.get("l1", {}).get("duration_seconds", 0)))]
		b.disabled = locked
		b.text = "Locked" if locked else ("Busy" if free == 0 else ("Too costly" if cash < pay else "Place"))


## Tests only: put the camera back after an input check.
func recenter_for_test() -> void:
	map.recenter()


func _open(key: String) -> void:
	tab = key
	confirm = ""
	if key != "":
		placing = {}
		map.placing = {}
		if map.road_mode != "":
			road_mode("")
	refresh("all")


## Back button: closes whatever is open, one layer at a time.
func close_panel() -> bool:
	if map.road_mode != "":
		road_mode("")
		refresh("all")
		return true
	if not placing.is_empty():
		_cancel_place()
		return true
	if confirm != "":
		confirm = ""
		refresh("all")
		return true
	if tab != "" or selected >= 0:
		selected = -1
		_open("")
		return true
	return false


func _on_tile(t: int) -> void:
	if map.road_mode != "":
		return
	if not placing.is_empty():
		toast.call("Drag the building to move it", "info")
		return
	if t < 0 or t == selected:
		selected = -1
		_open("")
		return
	selected = t
	_open("building")


## True when a screen point is on interface the map must ignore.
func blocks(pos: Vector2) -> bool:
	if not visible:
		return true
	for c in _blockers:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


# ---------------------------------------------------------------- refresh ---

func v() -> Dictionary:
	return session.view


func own() -> Dictionary:
	return v().get("own_city", {})


func tick() -> int:
	return int(v().get("tick", 0))


func refresh(what: String) -> void:
	if v().is_empty():
		return
	_track_population()
	_hud_refresh()
	_settle_reservations()
	map.selected = selected
	map.stale = not session.live
	map.needs = _building_needs()
	if not _card_dragging and not map.is_dragging_ghost():
		map.show_city(own(), tick(), str(v().get("match_id", "")) + ":" + str(session.seat), _reserved)
	_enforce_roads()
	_modebar_refresh()
	_activity_refresh()
	_banner_refresh()
	if tab == "build":
		_drawer_refresh()
	if tab not in PANELS or (what == "actions" and tab != "building"):
		return
	if tab == "market" and what == "view" and _editing():
		return
	_panel_refresh()


func _hud_refresh() -> void:
	var o := own()
	var sat := float(o.get("satisfaction_micro", 0) if o.get("satisfaction_micro") != null else 0) / Catalogue.MICRO
	_smile.text = "%d%%" % int(round(sat))
	(_smile.get_parent() as PanelContainer).add_theme_stylebox_override("panel", UI.box(Color("#2fb27a") if sat >= 75 else (Color("#f29a3d") if sat >= 55 else Color("#e85d4a")), 40, Color.WHITE, 3, 0, Color(), 6))
	UI.set_counter(_pop, "%s%s" % [Catalogue.fmt(o.get("population", 0)), ("  %+d" % _pop_delta) if _pop_delta != 0 else ""])
	_rank_label.text = "   #%d of 4 cities" % _rank()
	UI.set_counter(_cash, Catalogue.micro(o.get("available_money_micro", 0)))
	UI.set_counter(_mats, Catalogue.micro(o.get("materials_micro", 0)))
	var left := int(v().get("public", {}).get("duration_ticks", 1200)) - tick()
	UI.set_counter(_timer, Catalogue.clock(left), Color("#ff8a78") if left <= 60 else Color.WHITE)
	_net.text = ("● live %d ms" % int(maxf(session.link.rtt_avg_ms, 0))) if session.live else "● reconnecting…"
	_net.add_theme_color_override("font_color", Color("#69e0b4") if session.live else Color("#f28a72"))
	# What the city has against what it needs. Homes and services count in full
	# at 115 % of residents, as in Satisfaction.
	var cap: Dictionary = o.get("capacity", {})
	var e: Dictionary = o.get("electricity", {})
	var pop := float(o.get("population", 0))
	var req := pop * 1.15
	var street := 0.0
	for x in o.get("uncollected_micro", []):
		street += float(x) / Catalogue.MICRO
	var rows := {
		"homes": [float(cap.get("housing", 0)), req],
		"jobs": [float(cap.get("potential_jobs", 0)), pop],
		"power": [float(e.get("delivered", 0)) / Catalogue.MICRO, float(e.get("demand", 0)) / Catalogue.MICRO],
		"services": [float(cap.get("services_micro", 0)) / Catalogue.MICRO, req],
	}
	for k in rows:
		var have: float = rows[k][0]
		var need: float = rows[k][1]
		_chip(k, "%s/%s" % [UI.compact(have), UI.compact(need)], have >= need * 0.999)
	_chip("waste", UI.compact(street), street < 1.0)
	var env := float(o.get("environment_micro", 0)) / Catalogue.MICRO
	_chip("air", "%d%%" % int(round(env)), env >= 70.0)


func _chip(key: String, text: String, ok: bool) -> void:
	var l: Label = _need_chips[key]
	l.text = text
	l.add_theme_color_override("font_color", Color.WHITE if ok else Color("#ff8a78"))


## What each building is missing, from the authoritative view and the road
## network: the first problem wins.
func _building_needs() -> Dictionary:
	var o := own()
	var out := {}
	var staffing := int(o.get("capacity", {}).get("staffing_micro", 1000000))
	var street := 0
	for x in o.get("uncollected_micro", []):
		street += int(x)
	for b in o.get("buildings", []):
		if b.get("status", "") != "complete" or tick() == 0:
			continue
		var t := int(b["tile"])
		var type := str(b["type"])
		var need := ""
		var pf: Variant = b.get("power_factor_micro")
		if not map.layout or not map.layout.linked(t):
			need = "road"
		elif not b.get("enabled", true):
			need = "off"
		elif not b.get("funded", true):
			need = "coin"
		elif pf != null and int(pf) < 1000000:
			need = "power"
		elif staffing < 1000000 and int(Catalogue.spec(type).get("l1", {}).get("jobs", 0)) > 0:
			need = "people"
		elif type == "residential_district" and street > 0:
			need = "waste"
		if need != "":
			out[t] = need
	return out


func _banner_refresh() -> void:
	var ev: Dictionary = v().get("public", {}).get("events", {})
	var active: Array = ev.get("active", [])
	var warn: Array = ev.get("warnings", [])
	var text := ""
	var col := Color("#17323a")
	if not active.is_empty():
		text = "⚠ %s — %s" % [Catalogue.event_name(active[0]), Catalogue.EVENTS.get(active[0], ["", ""])[1]]
		col = Color("#b9422f")
	elif not warn.is_empty():
		var start := 0
		for e in Catalogue.data().get("events", []):
			if e["id"] == warn[0]:
				start = int(e["start"])
		text = "%s in %s" % [Catalogue.event_name(warn[0]), Catalogue.clock(start - tick())]
		col = Color("#c27a10")
	_banner.visible = text != ""
	if text != "":
		_banner.add_theme_stylebox_override("panel", UI.box(Color(col, 0.92), 12, Color(), 0, 0, Color(), 8))
		UI.clear(_banner)
		_banner.add_child(UI.label(text, "HudSmall"))


func _panel_refresh() -> void:
	UI.clear(_body)
	match tab:
		"market":
			_market_panel()
		"rivals":
			_rivals_panel()
		"policy":
			_policy_panel()
		"building":
			var b := _building_at(selected)
			if b.is_empty():
				selected = -1
				tab = ""
				_panel.visible = false
				return
			_building_panel(b)
	UI.pass_touches(_body)


func _card(child: Control) -> void:
	_body.add_child(UI.panel("Card", child))


func _section(text: String) -> void:
	_body.add_child(UI.label(text, "Caption"))


## One building: what it does, what it needs, and what you can do with it.
func _building_panel(b: Dictionary) -> void:
	var t := str(b["type"])
	var level := int(b.get("level", 1))
	var id := int(b["id"])
	_panel_title.text = "%s · Lv %d" % [Catalogue.building_name(t), level]
	var p: Variant = _project_for(id)
	var lines := [Catalogue.role(t)]
	var need: String = map.needs.get(int(b["tile"]), "")
	if p != null:
		lines.append("🏗 %s in %s" % ["Upgrading" if str(p.get("kind", "")) == "upgrade" else "Being built", Catalogue.clock(int(p["complete_tick"]) - tick())])
	elif need != "":
		lines.append("[color=#b9422f]⚠ %s[/color]" % BUBBLES.get(need, need))
	else:
		lines.append("[color=#1f8a5b]✓ Working[/color]")
	_card(UI.rich("\n".join(lines)))
	var s := Catalogue.spec(t)
	var acts := UI.vbox(6)
	if p != null:
		acts.add_child(_danger("cancel", "Cancel", "cancel_project", {"building_id": id}, "Cancel %s" % Catalogue.building_name(t)))
	elif b.get("status", "") == "complete":
		if level == 1:
			var up: Dictionary = s.get("upgrade", {})
			var locked := int(own().get("development_micro", 0)) < int(s.get("upgrade_unlock_micro", 0))
			var lbl := "Upgrade · 💰 %s · ⏱ %s" % [Catalogue.micro(up.get("cost_micro", 0)), Catalogue.clock(int(up.get("duration_seconds", 0)))]
			if locked:
				lbl = "Upgrade 🔒 Dev %s" % Catalogue.micro(s.get("upgrade_unlock_micro", 0))
			var ub := UI.button(lbl, "PrimaryButton", "", func(): session.act("upgrade", {"building_id": id}, "Upgrade %s" % Catalogue.building_name(t)))
			ub.disabled = locked or session.pending_for("upgrade", "building_id", id)
			acts.add_child(ub)
		if b.get("enabled", true):
			acts.add_child(UI.button("Switch off", "SoftButton", "", func(): session.act("disable", {"building_id": id}, "Switch off %s" % Catalogue.building_name(t))))
		else:
			var on := UI.button("Switch on", "PrimaryButton", "", func(): map.layout.road_off.erase(id); session.act("enable", {"building_id": id}, "Switch on %s" % Catalogue.building_name(t)))
			if not map.layout.linked(int(b["tile"])):
				on.text = "Draw a road to it first"
				on.disabled = true
			acts.add_child(on)
		acts.add_child(_danger("demolish", "Demolish", "demolish", {"building_id": id}, "Demolish %s" % Catalogue.building_name(t)))
	_card(acts)


func _policy_panel() -> void:
	_panel_title.text = "Reduce Waste"
	var o := own()
	var on := bool(o.get("reduce_waste", false))
	var pdata: Dictionary = Catalogue.data().get("policy", {})
	var box := UI.vbox(8)
	box.add_child(UI.label("ON" if on else "OFF", "Display"))
	box.add_child(UI.label("Homes make 25 % less waste and businesses 10 % less. Costs %s a minute and a little business income." % Catalogue.micro(pdata.get("policy_fee_micro_per_minute", 0)), "Caption", true))
	var cool := int(o.get("policy_change_at", 0)) - tick()
	var pb := UI.button("Turn %s" % ("off" if on else "on"), "PrimaryButton", "", func(): session.act("set_reduce_waste", {"enabled": not on}, "Reduce Waste %s" % ("off" if on else "on")))
	if cool > 0:
		pb.text = "Can change in %s" % Catalogue.clock(cool)
		pb.disabled = true
	box.add_child(pb)
	_card(box)


func start_placing(type: String, at_cell: Variant = null) -> void:
	road_mode("")
	var cell: Vector2i = at_cell if at_cell != null else map.center_cell()
	placing = {"type": type, "at": cell, "ok": false, "why": ""}
	selected = -1
	tab = ""
	_snap(cell)
	refresh("all")


func _snap(cell: Vector2i) -> void:
	var at := cell - Vector2i(CityLayout.FOOT / 2, CityLayout.FOOT / 2)
	placing["at"] = at
	placing["why"] = map.layout.why_not(at)
	if placing["why"] == "" and _free_tile() < 0:
		placing["why"] = "all 36 building sites are used"
	placing["ok"] = placing["why"] == ""
	map.placing = placing
	map.rebuild()
	_modebar_refresh()


## The lowest engine site number with no building and no construction on its way.
func _free_tile() -> int:
	var used := {}
	for b in own().get("buildings", []):
		used[int(b["tile"])] = true
	for tl in _reserved:
		used[tl] = true
	for tl in CityLayout.SITES:
		if not used.has(tl):
			return tl
	return -1


func _on_ghost_drag(cell: Vector2i) -> void:
	if not placing.is_empty() and cell - Vector2i(CityLayout.FOOT / 2, CityLayout.FOOT / 2) != placing["at"]:
		_snap(cell)


func _on_ghost_drop(cell: Vector2i) -> void:
	_on_ghost_drag(cell)
	_confirm_place()


func _confirm_place() -> void:
	if placing.is_empty() or not placing.get("ok", false):
		return
	var type: String = placing["type"]
	var tl := _free_tile()
	map.layout.place(tl, placing["at"])
	map.save()
	# Reserve before sending: the send triggers a refresh that would otherwise
	# drop a spot with no building behind it yet.
	_reserved[tl] = ""
	var aid := session.act("construct", {"building_type": type, "tile": tl}, "Build %s" % Catalogue.building_name(type))
	if aid != "":
		_reserved[tl] = aid
	else:
		_reserved.erase(tl)
		map.layout.unplace(tl)
	if not map.layout.linked(tl):
		toast.call("Connect it to a road, or it will not work", "warn")
	_cancel_place()


func _cancel_place() -> void:
	placing = {}
	map.placing = {}
	map.rebuild()
	refresh("all")


## Constructions the server refused give their spot back; executed ones stop
## being reservations once the building shows up in the view.
func _settle_reservations() -> void:
	var built := {}
	for b in own().get("buildings", []):
		built[int(b["tile"])] = true
	for tl in _reserved.keys():
		if _reserved[tl] == "":
			continue   # still being sent
		var a: Dictionary = session.actions.get(_reserved[tl], {})
		if built.has(tl):
			_reserved.erase(tl)
		elif a.get("status", "") == "rejected" or a.is_empty():
			_reserved.erase(tl)
			map.layout.unplace(tl)
			map.save()


## Pressing a card in the build bar and dragging it up onto the map starts placing it.
func _card_input(event: InputEvent, type: String, enabled: bool) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_card_drag = {"type": type, "from": event.global_position}
	elif event is InputEventMouseMotion and not _card_drag.is_empty() and not _card_dragging and _card_drag["type"] == type:
		var d: Vector2 = event.global_position - _card_drag["from"]
		if d.y < -28 and absf(d.y) > absf(d.x):
			_card_dragging = true
			start_placing(type, map.screen_to_cell(event.global_position))


func _input(event: InputEvent) -> void:
	if not _card_dragging:
		if event is InputEventMouseButton and not event.pressed:
			_card_drag = {}
		return
	if event is InputEventScreenDrag or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_on_ghost_drag(map.screen_to_cell(event.global_position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_card_dragging = false
		_card_drag = {}
		_on_ghost_drop(map.screen_to_cell(event.global_position))
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ roads ---
# Roads are free and drawn by dragging; the main road cannot be removed.
# A building that touches no road joined to the main road does not work: the
# client switches it off with the engine's own disable command, and back on
# with enable once it is connected. The server itself knows no roads, so this
# rule lives in the client; bot cities do not follow it.


func road_mode(mode: String) -> void:
	map.road_mode = mode
	if mode != "":
		placing = {}
		map.placing = {}
		selected = -1
	_modebar_refresh()
	map.rebuild()


func _enforce_roads() -> void:
	if not session.live or session.phase != "play":
		return
	var L := map.layout
	var changed := false
	for b in own().get("buildings", []):
		if b.get("status", "") != "complete":
			continue
		var id := int(b["id"])
		var name := Catalogue.building_name(str(b["type"]))
		var linked := L.linked(int(b["tile"]))
		if not linked and b.get("enabled", true):
			if not session.pending_for("disable", "building_id", id):
				session.act("disable", {"building_id": id}, "%s has no road: off" % name)
				L.road_off[id] = true
				changed = true
		elif linked and not b.get("enabled", true) and L.road_off.has(id):
			if tick() >= int(b.get("reactivate_at", 0)) and not session.pending_for("enable", "building_id", id):
				session.act("enable", {"building_id": id}, "%s connected: on" % name)
				L.road_off.erase(id)
				changed = true
	if changed:
		map.save()


func _modebar_refresh() -> void:
	UI.clear(_modebar)
	var roads := map.road_mode != ""
	_modebar.visible = not placing.is_empty() or roads
	_panel.visible = not _modebar.visible and tab in PANELS
	_drawer.visible = not _modebar.visible and tab == "build"
	if roads:
		var box := UI.vbox(6)
		box.add_child(UI.label("Roads", "Value"))
		box.add_child(UI.label("Drag on the map to %s. Roads are free. Buildings only work when they touch a road joined to the main road (yellow lines); unjoined roads show red. Right-drag or two fingers to move the map." % ("draw roads" if map.road_mode == "draw" else "erase roads"), "Caption", true))
		var row := UI.hbox(8)
		row.add_child(UI.button("Draw", "PrimaryButton" if map.road_mode == "draw" else "SoftButton", "road", func(): road_mode("draw")))
		row.add_child(UI.button("Erase", "PrimaryButton" if map.road_mode == "erase" else "SoftButton", "close", func(): road_mode("erase")))
		var done := UI.button("Done", "PrimaryButton", "check", func(): road_mode(""); refresh("all"))
		done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(done)
		box.add_child(row)
		_modebar.add_child(box)
		return
	if placing.is_empty():
		return
	var type: String = placing["type"]
	var box := UI.vbox(6)
	var s := Catalogue.spec(type)
	box.add_child(UI.label("%s · 💰 %s · ⏱ %s" % [Catalogue.building_name(type), Catalogue.micro(s.get("l1", {}).get("cost_micro", 0)), Catalogue.clock(int(s.get("l1", {}).get("duration_seconds", 0)))], "Value"))
	var msg := "Drag it anywhere on open land, then lift your finger to build. Put it beside a road so it works."
	if not placing.get("ok", false):
		msg = "Can't build here: %s." % placing.get("why", "")
	box.add_child(UI.label(msg, "Caption", true))
	var row := UI.hbox(8)
	row.add_child(UI.button("Cancel", "SoftButton", "close", _cancel_place))
	var ok := UI.button("Build here", "PrimaryButton", "check", _confirm_place)
	ok.disabled = not placing.get("ok", false)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok)
	box.add_child(row)
	_modebar.add_child(box)


# ---------------------------------------------------------------- refresh ---


## A destructive action takes two taps: the first asks, the second sends.
func _danger(key: String, text: String, kind: String, payload: Dictionary, label: String) -> Button:
	if confirm == key + str(payload):
		return UI.button("Tap again to confirm: %s" % text.to_lower(), "PrimaryButton", "warning", func():
			confirm = ""
			session.act(kind, payload, label)
			refresh("all"))
	return UI.button(text, "SoftButton", "close", func(): confirm = key + str(payload); refresh("all"))


func _market_panel() -> void:
	_panel_title.text = "Trade"
	var m: Dictionary = v().get("marketplace", {})
	var me := session.seat
	var prices: Dictionary = Catalogue.data().get("market", {}).get("prices", {})
	# Form: what and how much. Rates are per minute for waste, in E for power.
	var form := UI.vbox(6)
	form.add_child(UI.label("Ask rivals for a service, or offer yours", "Value"))
	var svc := OptionButton.new()
	for k in Catalogue.SERVICES:
		svc.add_item(Catalogue.SERVICES[k])
	svc.select(Catalogue.SERVICES.keys().find(market_form["type"]))
	svc.item_selected.connect(func(i): market_form["type"] = Catalogue.SERVICES.keys()[i]; market_form["price"] = 0; refresh("all"))
	form.add_child(svc)
	var band: Dictionary = prices.get(market_form["type"], {})
	if int(market_form["price"]) == 0:
		market_form["price"] = int(band.get("standard", 0))
	var rate := SpinBox.new()
	rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate.min_value = 1
	rate.max_value = 500
	rate.value = int(market_form["rate"])
	rate.suffix = "E" if market_form["type"] == "electricity" else "units/min"
	rate.value_changed.connect(func(x): market_form["rate"] = int(x))
	var price := SpinBox.new()
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.min_value = float(band.get("minimum", 0)) / Catalogue.MICRO
	price.max_value = float(band.get("maximum", 0)) / Catalogue.MICRO
	price.step = float(band.get("step", 100000)) / Catalogue.MICRO
	price.value = float(market_form["price"]) / Catalogue.MICRO
	price.suffix = "/ E·min" if market_form["type"] == "electricity" else "/ unit"
	price.value_changed.connect(func(x): market_form["price"] = int(round(x * Catalogue.MICRO)))
	form.add_child(UI.hbox(8, [UI.label("Amount", "Caption"), rate]))
	form.add_child(UI.hbox(8, [UI.label("Price", "Caption"), price]))
	var micro_rate := func() -> int: return int(market_form["rate"]) * int(Catalogue.MICRO)
	form.add_child(UI.hbox(8, [
		UI.button("Request quotes", "PrimaryButton", "", func(): session.act("request_quotes", {"type": market_form["type"], "rate": micro_rate.call()}, "Request %s" % Catalogue.SERVICES[market_form["type"]])),
		UI.button("Publish offer", "SoftButton", "", func(): session.act("publish_offer", {"type": market_form["type"], "rate": micro_rate.call(), "price": int(market_form["price"])}, "Offer %s" % Catalogue.SERVICES[market_form["type"]]))]))
	_card(form)

	_section("Open requests")
	var any := false
	for r in m.get("requests", []):
		any = true
		var mine: bool = int(r["buyer"]) == me
		var box := UI.vbox(4)
		var window := int(r["quote_until"]) - tick()
		box.add_child(UI.label("%s wants %s %s — %s" % ["You" if mine else "City %d" % (int(r["buyer"]) + 1), Catalogue.micro(r["rate"]), Catalogue.SERVICES.get(r["type"], r["type"]),
			("quotes close in %ds" % window) if window > 0 else "choosing a quote (%ds)" % (int(r["select_until"]) - tick())], "", true))
		if not mine and window > 0:
			var rid := int(r["id"])
			var rtype: String = r["type"]
			var rrate := int(r["rate"])
			box.add_child(UI.button("Quote %s at my price" % Catalogue.micro(rrate), "PrimaryButton", "", func():
				var p := int(market_form["price"]) if market_form["type"] == rtype else int(prices.get(rtype, {}).get("standard", 0))
				session.act("submit_quote", {"type": rtype, "rate": rrate, "price": p, "request_id": rid}, "Quote to City %d" % (int(r["buyer"]) + 1))))
		_card(box)
	if not any:
		_card(UI.label("No open requests.", "Caption"))

	_section("Open offers")
	any = false
	for o in m.get("offers", []):
		any = true
		var seller := int(o["seller"])
		var oid := int(o["id"])
		var box := UI.vbox(4)
		var is_quote := int(o.get("request_id", -1)) >= 0
		box.add_child(UI.label("%s sells %s %s at %s%s" % ["You" if seller == me else "City %d" % (seller + 1), Catalogue.micro(o["rate"]), Catalogue.SERVICES.get(o["type"], o["type"]),
			Catalogue.micro(o["price"], 2), " (quote on request #%d)" % int(o["request_id"]) if is_quote else ""], "", true))
		if seller == me:
			box.add_child(UI.button("Withdraw", "SoftButton", "close", func(): session.act("withdraw_offer", {"id": oid}, "Withdraw offer")))
		else:
			box.add_child(UI.button("Accept", "PrimaryButton", "check", func(): session.act("accept_quote", {"id": oid}, "Accept offer from City %d" % (seller + 1))))
		_card(box)
	if not any:
		_card(UI.label("No open offers.", "Caption"))

	_section("Your contracts")
	any = false
	for k in own().get("contracts", []):
		if str(k.get("status", "")) != "active":
			continue
		any = true
		var cid := int(k["id"])
		var sell: bool = int(k["seller"]) == me
		var box := UI.vbox(4)
		box.add_child(UI.label("%s %s %s %s — delivered %s, paid %s, ends in %s" % ["You sell to" if sell else "You buy from", "City %d" % (int(k["buyer"] if sell else k["seller"]) + 1),
			Catalogue.micro(k["rate"]), Catalogue.SERVICES.get(k["type"], k["type"]), Catalogue.micro(k.get("delivered", 0), 1), Catalogue.micro(k.get("paid", 0), 1), Catalogue.clock(int(k["end_tick"]) - tick())], "", true))
		box.add_child(UI.hbox(6, [UI.button("Renew", "SoftButton", "", func(): session.act("renew_contract", {"id": cid}, "Renew contract")),
			_danger("cc", "Cancel", "cancel_contract", {"id": cid}, "Cancel contract")]))
		_card(box)
	if not any:
		_card(UI.label("None.", "Caption"))


func _rivals_panel() -> void:
	_panel_title.text = "Rivals"
	var rows: Array = v().get("public", {}).get("rankings", [])
	var total := 0.0
	for r in rows:
		total += float(r["population"])
	for r in rows:
		var cid := int(r["city_id"])
		var box := UI.vbox(4)
		var f := ""
		for o in v().get("opponents", []):
			if int(o["city_id"]) == cid:
				f = Catalogue.FOUNDATIONS.get(str(o.get("foundation", "")), [""])[0]
		if cid == session.seat:
			f = Catalogue.FOUNDATIONS.get(str(own().get("foundation", "")), [""])[0]
		box.add_child(UI.hbox(8, [UI.label("#%d %s" % [int(r["rank"]), "Your city" if cid == session.seat else "City %d" % (cid + 1)], "Value"), UI.spacer(), UI.label("%s residents" % Catalogue.fmt(r["population"]), "Value")]))
		box.add_child(UI.bar(float(r["population"]) / maxf(total, 1) * 2.0, UI.PEOPLE if cid != session.seat else UI.PRIMARY))
		box.add_child(UI.label("%s · Satisfaction %s · Environment %s · Development %s" % [f, Catalogue.micro(r.get("satisfaction_micro", 0), 1), Catalogue.micro(r.get("environment_micro", 0), 1), Catalogue.micro(r.get("development_micro", 0))], "Small", true))
		_card(box)
	var mig: Dictionary = Catalogue.data().get("migration", {})
	var first := int(mig.get("first", 80))
	var every := int(mig.get("interval", 20))
	var next := first if tick() < first else first + ((tick() - first) / every + 1) * every
	_card(UI.label("Residents move toward the most satisfying city every %d s. Next move in %s." % [every, Catalogue.clock(next - tick())], "Caption", true))


func _building_at(t: int) -> Dictionary:
	for b in own().get("buildings", []):
		if int(b["tile"]) == t:
			return b
	return {}


func _project_for(id: int) -> Variant:
	for p in own().get("projects", []):
		if p != null and int(p["building_id"]) == id:
			return p
	return null


func _slots_free() -> int:
	var n := 0
	for p in own().get("projects", []):
		if p == null:
			n += 1
	return n


func _track_population() -> void:
	var p := int(own().get("population", 0))
	if _last_pop >= 0 and p != _last_pop:
		_pop_delta = p - _last_pop
		toast.call("%s%d residents (now %d)" % ["+" if _pop_delta > 0 else "", _pop_delta, p], "good" if _pop_delta > 0 else "warn")
	_last_pop = p


func _rank() -> int:
	for r in v().get("public", {}).get("rankings", []):
		if int(r["city_id"]) == session.seat:
			return int(r["rank"])
	return 0


func _editing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f is LineEdit or f is SpinBox or f.get_parent() is SpinBox) and _panel.is_ancestor_of(f)


func _activity_refresh() -> void:
	UI.clear(_activity)
	for a in session.recent_actions(4):
		if a["status"] in ["applied", "rejected"] and Time.get_ticks_msec() - int(a["done_ms"]) > 6000:
			continue
		var mark: String = {"sending": "… sending", "queued": "⏳ accepted, runs next tick", "applied": "✓ done", "rejected": "✗ %s" % Catalogue.error_text(a["error"]) if Catalogue.error_text(a["error"]) != "" else "✗ " + str(a["error"]).replace("_", " ")}[a["status"]]
		var col: Color = {"sending": UI.INK, "queued": Color("#17323a"), "applied": UI.PRIMARY_DARK, "rejected": UI.DANGER_DARK}[a["status"]]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.88), 10, Color(), 0, 0, Color(), 6))
		var l := UI.label("%s  %s" % [a["label"], mark], "HudSmall")
		p.add_child(l)
		_activity.add_child(p)


