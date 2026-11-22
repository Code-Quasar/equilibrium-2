class_name Play
extends Control
## The live city, kept simple: the map fills the screen; a few numbers say
## what the city has and needs; bubbles over buildings say what each one is
## missing. No reports. Every number comes from the last player_view and every
## button sends an action whose server receipt is shown.

const PANELS := ["market", "rivals", "building", "waste"]
## The city's standing figures on the HUD: key, badge, short name. Services and
## street waste live in the Waste panel and the long-press details.
const NEEDS := [
	["homes", "homes", "Homes"],
	["jobs", "jobs", "Jobs"],
	["power", "power", "Power"],
	["air", "pollution", "Environment"],
]
## What a HUD figure means, shown when it is tapped. Explanations only: a
## figure in trouble is reported by its status strip and the building alerts,
## never by a tap.
const EXPLAIN := {
	"satisfaction": ["Satisfaction", "How content residents are, 0 to 100. Every 20 s some residents move from less to more satisfying cities. Environment counts 35, jobs 20, homes, power and services 15 each."],
	"population": ["Residents", "Your score: the city with the most residents when the match ends wins."],
	"homes": ["Homes", "Homes in your Residential Districts against residents. Full comfort needs 15 % spare homes, and newcomers need a free one."],
	"jobs": ["Jobs", "Residents at work. The city employs the first 1,000; your buildings employ the rest."],
	"power": ["Power", "Electricity delivered against what the city and its buildings ask for."],
	"air": ["Environment", "0 to 100: air pollution, landfill damage and waste lying around lower it; parks add amenity."],
	"money": ["Cash", "Cash you can spend on construction, upkeep and trade. Cash held for contracts is not counted."],
	"materials": ["Materials", "Stock for construction and factories, up to 500. What is missing is bought for cash."],
	"time": ["Time left", "The match lasts 20 minutes. Each crisis is announced 45 s before it starts."],
}
## Why a building cannot be started, on its build card.
const LOCKS := {
	"requires_collection_center": "Needs Collection",
	"requires_sorting_center": "Needs Sorting",
	"prerequisite_under_construction": "Wait for it",
	"construction_slots_full": "Busy",
	"insufficient_funds": "Too costly",
	"not_enough_time": "No time",
	"no_free_tile": "No site",
	"match_closed": "Over",
}
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
var open_settings: Callable = func(): pass

var map: CityMap                  # the world map; App owns it, this screen drives it
var placing := {}                 # {type, size, at, ok, why}, plus {move: id, from: tile} when moving one
var tab := ""                     # "", "build", or a panel in PANELS
var selected := -1
var confirm := ""                 # action awaiting a second tap (demolish, cancel)
var market_form := {"type": "electricity", "rate": 5, "duration": 120}
var build_size := "S"             # the size the build bar shows and places
var sell_amount := 10

var _reserved := {}               # tile -> action id of a construction or move on its way
var _moves := {}                  # new tile -> the tile a moving building leaves
var _crises_seen := {}            # crisis ids whose arrival was already marked
var _edge: EdgePulse
var _details_open := false        # the building panel shows its full description
var _card_drag := {}              # a build card pressed, before it becomes a drag
var _card_dragging := false
var _modebar: PanelContainer
var _panel: PanelContainer
var _panel_title: Label
var _body: VBoxContainer
var _drawer: PanelContainer
var _drawer_cards := {}           # building type -> {button, price, buy, thumb, keys}
var _size_buttons := {}           # size -> its button in the build bar
var _activity: VBoxContainer
var _banner: PanelContainer
var _blockers: Array[Control] = []
var _gauge: Gauge
var _pop_card: HudCard
var _rank_label: Label
var _need_chips := {}             # need key -> HudCard
var _cash: HudCard
var _mats: HudCard
var _timer: HudCard
var _net: Label
var _diag: Label
var _popover: Control
var _tip: PanelContainer            # the explanation of a tapped HUD figure
var _tip_left := 0.0
var _safe: Array = [0, 0, 0, 0]
var _corners: Array = []          # [preset, x, y, control] placed in the safe area
var _safe_check := 0.0
var visiting := -1                # a rival's city_id while visiting it, read-only
var _own_controls: Array[Control] = []
var _visit_bar: PanelContainer
var _visit_label: Label
var _alerts: VBoxContainer
var _alert_seen := {}             # category -> building ids already announced
var _alert_dismissed := {}        # category -> true while the player has closed it
var _hist: Array = []             # [tick, money, population, materials] per received tick
var _zoom: Control
var _last_pop := -1
var _pop_delta := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe = UI.safe_margins(self)
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)


## Places every edge-anchored piece of the interface inside the safe area, at a
## width that suits the screen. Runs again whenever the screen size or the
## safe area changes (rotating a phone moves its notch to the other side).
func _layout() -> void:
	_safe = UI.safe_margins(self)
	var vp := get_viewport_rect().size
	for c in _corners:
		_place_corner(c[0], c[1], c[2], c[3])
	# The side panel and the mode bar: right edge, never wider than a third of
	# the screen plus a little, growing leftwards so the close button is always
	# on screen.
	var w := clampf(vp.x * 0.34, 340.0, 430.0)
	for c in [_panel, _modebar]:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		c.offset_right = -8.0 - _safe[2]
		c.offset_left = c.offset_right - w
		c.offset_top = 72.0 + _safe[1]
		c.custom_minimum_size.x = w
	_panel.offset_bottom = -96.0 - _safe[3]
	_drawer.offset_left = 10.0 + _safe[0]
	_drawer.offset_right = -110.0 - _safe[2]
	_drawer.offset_bottom = -8.0 - _safe[3]
	_drawer.offset_top = -254.0 - _safe[3]
	_zoom.offset_left = -60.0 - _safe[2]
	_zoom.offset_right = -12.0 - _safe[2]
	_alerts.offset_left = 10.0 + _safe[0]
	_alerts.offset_top = 160.0 + _safe[1]
	_activity.offset_left = 12.0 + _safe[0]
	_activity.offset_top = -100.0 - _safe[3]
	_activity.offset_bottom = -100.0 - _safe[3]
	_banner.offset_top = 70.0 + _safe[1]
	_visit_bar.offset_top = -16.0 - _safe[3]
	_visit_bar.offset_bottom = -16.0 - _safe[3]


func _corner(preset: int, x: float, y: float, child: Control) -> Control:
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(child)
	_corners.append([preset, x, y, child])
	_place_corner(preset, x, y, child)
	return child


func _place_corner(preset: int, x: float, y: float, child: Control) -> void:
	child.set_anchors_preset(preset)
	var right := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var bottom := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	# Keep clear of notches, rounded corners and system bars.
	x += float(_safe[2] if right else _safe[0])
	y += float(_safe[3] if bottom else _safe[1])
	child.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	child.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	child.offset_left = -x if right else x
	child.offset_right = -x if right else x
	child.offset_top = -y if bottom else y
	child.offset_bottom = -y if bottom else y


func _build() -> void:
	map.tapped.connect(_on_tile)
	map.long_pressed.connect(start_moving)
	map.ghost_dragged.connect(_on_ghost_drag)
	map.ghost_dropped.connect(_on_ghost_drop)
	map.ui_blocks = blocks

	# Top left: the Satisfaction gauge, residents and rank, then what the
	# city has against what it needs. Tap a figure for a hint, hold it (or
	# right click) for the details.
	var tl := UI.vbox(6)
	var row := UI.hbox(8)
	_gauge = Gauge.new()
	_gauge.tapped.connect(func(): _explain("satisfaction", _gauge))
	_gauge.held.connect(func(): _details("satisfaction", _gauge))
	row.add_child(_gauge)
	var who := UI.vbox(6)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pop_card = HudCard.new("people", "Residents", true)
	_pop_card.tapped.connect(func(): _explain("population", _pop_card))
	_pop_card.held.connect(func(): _details("population", _pop_card))
	who.add_child(_pop_card)
	_rank_label = UI.label("", "HudSmall")
	who.add_child(_rank_label)
	row.add_child(who)
	tl.add_child(row)
	var needs := UI.hbox(6)
	for n in NEEDS:
		var card := HudCard.new(n[1], n[2])
		card.alarm_text = false
		var key: String = n[0]
		card.tapped.connect(func(): _explain(key, card))
		card.held.connect(func(): _details(key, card))
		needs.add_child(card)
		_need_chips[key] = card
	tl.add_child(needs)
	_blockers.append(_corner(Control.PRESET_TOP_LEFT, 10, 8, tl))

	# Top right: money first, then materials and the clock.
	var tr := UI.hbox(8)
	_cash = HudCard.new("coin", "Cash", true)
	_cash.tapped.connect(func(): _explain("money", _cash))
	_cash.held.connect(func(): _details("money", _cash))
	_mats = HudCard.new("materials", "Materials", true)
	_mats.custom_minimum_size.x = 112
	_mats.tapped.connect(func(): _explain("materials", _mats))
	_mats.held.connect(func(): _details("materials", _mats))
	_timer = HudCard.new("timer", "Time left", true)
	_timer.custom_minimum_size.x = 112
	_timer.tapped.connect(func(): _explain("time", _timer))
	_timer.held.connect(func(): _details("time", _timer))
	tr.add_child(_cash)
	tr.add_child(_mats)
	tr.add_child(_timer)
	var right := UI.vbox(4, [tr])
	_net = UI.label("", "HudCaption")
	_net.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_net)
	_blockers.append(_corner(Control.PRESET_TOP_RIGHT, 12, 8, right))
	_diag = UI.label("", "HudCaption")
	_diag.add_theme_font_override("font", UI.number_font())
	_diag.add_theme_font_size_override("font_size", 11)
	_diag.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_diag.offset_left = 14
	_diag.offset_top = -112
	_diag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_diag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diag.visible = false
	add_child(_diag)

	# Coming crisis, top middle.
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)

	# Right edge: zoom and back-to-city, for any mouse, touchpad or finger.
	var zoom := UI.vbox(8)
	zoom.add_child(UI.round_button("btn_blue", "plus", "", func(): map.zoom_by(1.25), 46))
	zoom.add_child(UI.round_button("btn_blue", "minus", "", func(): map.zoom_by(0.8), 46))
	zoom.add_child(UI.round_button("btn_blue", "center", "", func(): map.recenter(), 46))
	zoom.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	zoom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom.grow_vertical = Control.GROW_DIRECTION_BOTH
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zoom)
	_blockers.append(zoom)
	_zoom = zoom

	# Bottom left: trade, rivals, waste and materials.
	var bl := UI.hbox(12)
	bl.add_child(UI.round_button("btn_blue", "trade", "Trade", func(): _open("market")))
	bl.add_child(UI.round_button("btn_blue", "region", "Rivals", func(): _open("rivals")))
	bl.add_child(UI.round_button("btn_green", "waste", "Waste", func(): _open("waste")))
	bl.add_child(UI.round_button("btn_purple", "settings", "Settings", func(): _open(""); open_settings.call()))
	_blockers.append(_corner(Control.PRESET_BOTTOM_LEFT, 14, 10, bl))
	_own_controls.append(bl)

	# Bottom right: roads and the build bar.
	var br := UI.hbox(12)
	br.add_child(UI.round_button("btn_orange", "road", "Roads", func(): _open(""); road_mode("draw")))
	br.add_child(UI.round_button("btn_green", "plus", "Build", func(): _open("" if tab == "build" else "build"), 72))
	_blockers.append(_corner(Control.PRESET_BOTTOM_RIGHT, 14, 10, br))
	_own_controls.append(br)

	# Visiting a rival: who it is, and the way home.
	_visit_bar = PanelContainer.new()
	_visit_bar.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.09, 0.12, 0.9), 18, Color("#ffd257"), 1, 0, Color(), 10))
	_visit_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_visit_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_visit_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_visit_bar.visible = false
	var vb := UI.hbox(14)
	_visit_label = UI.label("", "OnDark")
	_visit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_child(_visit_label)
	var home := UI.button("Return to My City", "PrimaryButton", "play", func(): visit(-1))
	home.custom_minimum_size.y = 46
	vb.add_child(home)
	_visit_bar.add_child(vb)
	add_child(_visit_bar)
	_blockers.append(_visit_bar)

	# The build bar: a size choice, then every building in a row; drag one up onto the map.
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 8
	var cards := UI.hbox(10)
	scroll.add_child(cards)
	for t in Catalogue.BUILDINGS:
		cards.add_child(_drawer_card(t))
	UI.pass_touches(cards)
	_drawer = UI.panel("Side", UI.vbox(6, [_size_row(), scroll]))
	_drawer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_drawer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drawer.visible = false
	add_child(_drawer)
	_blockers.append(_drawer)

	# One panel on the right for trade, rivals, a building, or waste and materials.
	var pv := UI.vbox(8)
	var head := UI.hbox()
	_panel_title = UI.label("", "Title")
	# A long name must not widen the panel: it is cut with an ellipsis instead.
	_panel_title.clip_text = true
	_panel_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_panel_title)
	head.add_child(UI.round_button("btn_red", "close", "", func(): selected = -1; _open(""), 40))
	pv.add_child(head)
	var ps := ScrollContainer.new()
	# Content never widens the panel: it wraps to the panel's width.
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
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
	_panel.visible = false
	add_child(_panel)
	_blockers.append(_panel)

	# Placement and road bar, where the panel would be.
	_modebar = PanelContainer.new()
	_modebar.add_theme_stylebox_override("panel", UI.box(UI.PAPER, 16, UI.LINE, 1, 3, UI.LIP, 12))
	_modebar.anchor_left = 1
	_modebar.anchor_right = 1
	_modebar.visible = false
	add_child(_modebar)
	_blockers.append(_modebar)

	# A red pulse at the screen edges when a crisis strikes.
	_edge = EdgePulse.new()
	add_child(_edge)

	# Recent actions and their receipts, above the bottom-left buttons.
	_activity = UI.vbox(4)
	_activity.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_activity.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_activity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_activity)

	# What real buildings are missing, one card per problem, under the HUD.
	_alerts = UI.vbox(6)
	_alerts.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_alerts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alerts)
	_blockers.append(_alerts)


func _drawer_card(t: String) -> Control:
	var box := UI.vbox(2)
	box.custom_minimum_size = Vector2(132, 0)
	var thumb := TextureRect.new()
	thumb.texture = UI.thumbs.get_thumb(t, build_size)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(120, 80)
	box.add_child(thumb)
	var name := UI.label(Catalogue.building_name(t), "Small", true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_color_override("font_color", UI.INK)
	box.add_child(name)
	# What it is for, at a glance: its main effect at the chosen size.
	var keys := CenterContainer.new()
	keys.custom_minimum_size.y = 26
	box.add_child(keys)
	var price := UI.label("", "Small")
	price.add_theme_font_override("font", UI.number_font())
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(price)
	# What the materials not in stock add: construction buys the shortfall.
	var buy := UI.label("", "Small")
	buy.add_theme_font_override("font", UI.number_font())
	buy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(buy)
	var b := UI.button("Place", "PrimaryButton", "", func(): start_placing(t))
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 13)
	box.add_child(b)
	var card := UI.panel("Card", box)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.gui_input.connect(func(e): _card_input(e, t, not b.disabled))
	thumb.gui_input.connect(func(e): _card_input(e, t, not b.disabled))
	_drawer_cards[t] = {"button": b, "price": price, "buy": buy, "thumb": thumb, "keys": keys}
	return card


## The build bar's size choice: every card shows and places that size.
func _size_row() -> Control:
	var row := UI.hbox(8)
	row.add_child(UI.label("Size", "Caption"))
	for s in Catalogue.SIZES:
		var size: String = s
		var b := UI.button(Catalogue.size_name(size), "PrimaryButton" if size == build_size else "SoftButton", "", func(): _set_build_size(size))
		b.custom_minimum_size = Vector2(96, 34)
		b.add_theme_font_size_override("font_size", 13)
		_size_buttons[size] = b
		row.add_child(b)
	var note := UI.label("Upgrading later costs a little more than building big now.", "Small", true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	return row


func _set_build_size(size: String) -> void:
	build_size = size
	for s in _size_buttons:
		_size_buttons[s].theme_type_variation = "PrimaryButton" if s == size else "SoftButton"
	for t in _drawer_cards:
		_drawer_cards[t]["thumb"].texture = UI.thumbs.get_thumb(t, size)
	_drawer_refresh()


## Prices and locks update in place, so a card being pressed is never rebuilt
## under the finger. Whether a building can start comes from the server's own
## check in the last view; the figures are the exported catalogue's. Until the
## first view arrives every card waits.
func _drawer_refresh() -> void:
	var options: Dictionary = own().get("build_options", {})
	var stock := float(own().get("materials_micro", 0)) / Catalogue.MICRO
	var buy_price := float(Catalogue.data().get("materials", {}).get("buy_price", 0))
	for t in _drawer_cards:
		var tier := Catalogue.tier(t, build_size)
		var c: Dictionary = _drawer_cards[t]
		var b: Button = c["button"]
		UI.clear(c["keys"])
		var main := _effects(t, build_size).filter(func(x): return x[2] == "good").slice(0, 1)
		if main.is_empty():
			main = _effects(t, build_size).slice(0, 1)
		var chips := UI.hbox(3)
		for x in main:
			chips.add_child(UI.stat_chip(x[0], x[1], UI.INK, x[2]))
		c["keys"].add_child(chips)
		var need := float(tier.get("construction_materials", 0))
		c["price"].text = Catalogue.price_text(float(tier.get("construction_credits", 0)), need, int(tier.get("construction_seconds", 0)))
		var short := maxf(0.0, need - stock)
		c["buy"].text = "buys %s mat: +💰 %s" % [Catalogue.fmt(ceilf(short)), Catalogue.fmt(ceilf(short * buy_price))] if short > 0.0 else "materials in stock"
		var known: Dictionary = options.get(t, {})
		if not known.has(build_size):
			b.disabled = true
			b.text = "…"
			b.tooltip_text = ""
			continue
		var why := str(known[build_size])
		b.disabled = why != ""
		b.text = "Place" if why == "" else LOCKS.get(why, "Not now")
		b.tooltip_text = "" if why == "" else (Catalogue.error_text(why) if Catalogue.error_text(why) != "" else why.replace("_", " "))


## Tests only: put the camera back after an input check.
func recenter_for_test() -> void:
	map.recenter()


func _open(key: String) -> void:
	if key != tab:
		(_body.get_parent() as ScrollContainer).scroll_vertical = 0
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
	if close_details():
		return true
	if visiting >= 0:
		visit(-1)
		return true
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
	_details_open = false
	if visiting >= 0:
		return
	if map.road_mode != "":
		return
	if not placing.is_empty():
		toast.call("Drag the building to move it", "info")
		return
	if t < 0 or t == selected:
		selected = -1
		_open("")
		return
	if t != selected:
		(_body.get_parent() as ScrollContainer).scroll_vertical = 0
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
	map.stale = not session.live
	if visiting >= 0:
		_visit_refresh()
		_banner_refresh()
		if tab == "rivals" and what == "view":
			_panel_refresh()
		return
	map.selected = selected
	map.needs = _building_needs()
	_alerts_refresh(map.needs)
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
	var t := tick()
	if _hist.is_empty() or int(_hist[-1][0]) != t:
		_hist.append([t, int(o.get("money_micro", 0)), int(o.get("population", 0)), int(o.get("materials_micro", 0))])
		if _hist.size() > 90:
			_hist.pop_front()
	var evaluated: bool = o.get("satisfaction_micro") != null
	var sat := float(o.get("satisfaction_micro", 0) if evaluated else 0) / Catalogue.MICRO
	_gauge.value = sat
	_pop_card.set_value("%s%s" % [Catalogue.fmt(o.get("population", 0)), ("  %+d" % _pop_delta) if _pop_delta != 0 else ""])
	_rank_label.text = "   Rank #%d of 4" % _rank()
	var net := _per_minute(1)
	_cash.set_value(Catalogue.micro(o.get("available_money_micro", 0)), "bad" if net < 0 and float(o.get("available_money_micro", 0)) < -net * Catalogue.MICRO else "")
	_mats.set_value(Catalogue.micro(o.get("materials_micro", 0)))
	var left := int(v().get("public", {}).get("duration_ticks", 1200)) - t
	_timer.set_value(Catalogue.clock(left), "bad" if left <= 60 else "")
	_net.text = "" if session.live else "● reconnecting…"
	_net.add_theme_color_override("font_color", Color("#f28a72"))
	_diag_refresh()
	# What the city has against what it needs. Homes and services count in full
	# at the Satisfaction comfort level (115 % of residents).
	var cap: Dictionary = o.get("capacity", {})
	var p: Dictionary = o.get("power", {})
	var pop := float(o.get("population", 0))
	var rows := {
		"homes": [float(cap.get("housing", 0)), pop * _slack("housing_slack")],
		"jobs": [float(cap.get("employed", 0)), pop],
		"power": [_delivered_power(p), _requested_power(p)],
	}
	for k in rows:
		var have: float = rows[k][0]
		var need: float = rows[k][1]
		var st := "ok" if have >= need * 0.999 else ("warn" if have >= need * 0.85 else "bad")
		_need_chips[k].set_value("%s/%s" % [UI.compact(have), UI.compact(need)], st if evaluated else "")
	var env := float(o.get("environment_micro", 0)) / Catalogue.MICRO
	_need_chips["air"].set_value("%d%%" % int(round(env)), "ok" if env >= 70.0 else ("warn" if env >= 50.0 else "bad"))
	if _popover and is_instance_valid(_popover) and _popover.visible:
		_details(str(_popover.get_meta("key")), null)
	if _tip and is_instance_valid(_tip) and _tip.visible:
		_explain(str(_tip.get_meta("key")), null)


static func _sum(values: Array) -> float:
	var total := 0.0
	for x in values:
		total += float(x)
	return total


static func _slack(key: String) -> float:
	return float(Catalogue.data().get(key, 1.15))


static func _delivered_power(p: Dictionary) -> float:
	return float(int(p.get("municipal_delivered_micro_E", 0)) + int(p.get("buildings_delivered_micro_E", 0))) / Catalogue.MICRO


static func _requested_power(p: Dictionary) -> float:
	return float(int(p.get("municipal_requested_micro_E", 0)) + int(p.get("buildings_requested_micro_E", 0))) / Catalogue.MICRO


## Seconds until the next move of residents, or -1 when none is left.
func _next_migration() -> int:
	var mig: Dictionary = Catalogue.data().get("migration", {})
	var first := int(mig.get("first", 80))
	var last := int(mig.get("last", 1180))
	var every := int(mig.get("interval", 20))
	var t := tick()
	var next := first if t < first else first + ((t - first) / every + 1) * every
	return next - t if next <= last else -1


## The change of a tracked figure per minute, from the snapshots received
## over the last minute (index: 1 money, 2 population, 3 materials).
func _per_minute(i: int) -> float:
	if _hist.size() < 2:
		return 0.0
	var last: Array = _hist[-1]
	var first: Array = _hist[0]
	for h in _hist:
		if int(last[0]) - int(h[0]) <= 60:
			first = h
			break
	var dt := float(int(last[0]) - int(first[0]))
	if dt <= 0:
		return 0.0
	return float(int(last[i]) - int(first[i])) / dt * 60.0 / (Catalogue.MICRO if i != 2 else 1.0)


func _diag_refresh() -> void:
	_diag.visible = Settings.diagnostics
	if not Settings.diagnostics:
		return
	var l := session.link
	var age := (Time.get_ticks_msec() - session.view_ms) if session.view_ms > 0 else -1
	_diag.text = "DEV · net\nrtt %d ms  avg %d  jitter %d\nack %s  view age %s  seq %d" % [
		int(l.rtt_ms), int(l.rtt_avg_ms), int(l.jitter_ms),
		("%d ms" % int(session.ack_avg_ms)) if session.ack_avg_ms >= 0 else "–",
		("%d ms" % age) if age >= 0 else "–", int(v().get("view_seq", 0))]


## A popover of authoritative figures behind a HUD card. Opens under the
## card; tapping elsewhere closes it. Refreshed with each new view.
func _details(key: String, anchor: Control) -> void:
	if _popover == null or not is_instance_valid(_popover):
		_popover = PanelContainer.new()
		_popover.add_theme_stylebox_override("panel", UI.box(Color("#14222c"), 16, Color(1, 1, 1, 0.16), 1, 0, Color(), 14))
		_popover.mouse_filter = Control.MOUSE_FILTER_STOP
		_popover.z_index = 15
		add_child(_popover)
	if anchor != null:
		UI.click()
		_popover.set_meta("anchor", anchor)
	_popover.set_meta("key", key)
	UI.clear(_popover)
	var col := UI.vbox(4)
	_popover.add_child(col)
	var rows := _detail_rows(key)
	var title := UI.label(str(rows[0]), "OnDarkTitle")
	title.add_theme_font_size_override("font_size", 15)
	col.add_child(title)
	for r in rows.slice(1):
		if r is String:
			var l := UI.label(r, "OnDarkCaption", true)
			l.custom_minimum_size.x = 240
			col.add_child(l)
			continue
		var line := UI.hbox(14)
		var k := UI.label(str(r[0]), "OnDarkCaption")
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(k)
		var val := UI.label(str(r[1]), "OnDark")
		val.add_theme_font_override("font", UI.number_font())
		val.add_theme_font_size_override("font_size", 14)
		if r.size() > 2:
			val.add_theme_color_override("font_color", r[2])
		line.add_child(val)
		col.add_child(line)
	_popover.visible = true
	_popover.reset_size()
	var a: Control = _popover.get_meta("anchor")
	if a and is_instance_valid(a):
		var ar := a.get_global_rect()
		var vp := get_viewport_rect().size
		var sz := _popover.get_combined_minimum_size()
		_popover.position = Vector2(clampf(ar.position.x, 8, vp.x - sz.x - 8), clampf(ar.end.y + 6, 8, vp.y - sz.y - 8))


## A compact, translucent note explaining a tapped HUD figure: what it is, its
## value now and, for figures that trend, how it moved over the last minute.
## Under the figure; a tap anywhere else or a few seconds close it.
func _explain(key: String, anchor: Control) -> void:
	if anchor != null:
		close_details()
	if _tip == null or not is_instance_valid(_tip):
		_tip = PanelContainer.new()
		_tip.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.1, 0.13, 0.82), 12, Color(1, 1, 1, 0.12), 1, 0, Color(), 10))
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip.z_index = 15
		add_child(_tip)
	if anchor != null:
		_tip.set_meta("anchor", anchor)
		_tip_left = 4.5
	_tip.set_meta("key", key)
	UI.clear(_tip)
	var meta: Array = EXPLAIN.get(key, [key, ""])
	var col := UI.vbox(3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UI.hbox(10)
	var title := UI.label(meta[0], "OnDarkTitle")
	title.add_theme_font_size_override("font_size", 15)
	head.add_child(title)
	var now := _explain_value(key)
	if now != "":
		var val := UI.label(now, "OnDark")
		val.add_theme_font_override("font", UI.number_font())
		head.add_child(UI.spacer())
		head.add_child(val)
	col.add_child(head)
	var text := UI.label(meta[1], "OnDarkCaption", true)
	text.custom_minimum_size.x = 280
	col.add_child(text)
	_tip.add_child(col)
	_tip.visible = true
	_tip.reset_size()
	var a: Variant = _tip.get_meta("anchor", null)
	if a is Control and is_instance_valid(a):
		var ar: Rect2 = (a as Control).get_global_rect()
		var vp := get_viewport_rect().size
		var sz := _tip.get_combined_minimum_size()
		_tip.position = Vector2(clampf(ar.position.x, 8 + _safe[0], vp.x - sz.x - 8 - _safe[2]), clampf(ar.end.y + 6, 8, vp.y - sz.y - 8 - _safe[3]))


## The figure's value now, with its trend over the last minute where it has one.
func _explain_value(key: String) -> String:
	var o := own()
	var trend := func(i: int) -> String:
		var x := _per_minute(i)
		if absf(x) < 0.05:
			return ""
		return "  %s%s / min" % ["+" if x > 0 else "−", Catalogue.fmt(absf(x)) if absf(x) >= 10 else "%.1f" % absf(x)]
	match key:
		"satisfaction":
			return Catalogue.micro(o["satisfaction_micro"], 1) if o.get("satisfaction_micro") != null else ""
		"population":
			return Catalogue.fmt(float(o.get("population", 0))) + trend.call(2)
		"money":
			return Catalogue.micro(o.get("available_money_micro", 0)) + trend.call(1)
		"materials":
			return Catalogue.micro(o.get("materials_micro", 0)) + trend.call(3)
		"air":
			return Catalogue.micro(o.get("environment_micro", 0), 1)
		"time":
			return Catalogue.clock(int(v().get("public", {}).get("duration_ticks", 1200)) - tick())
		"homes":
			return "%s / %s" % [Catalogue.fmt(float(o.get("capacity", {}).get("housing", 0))), Catalogue.fmt(float(o.get("population", 0)))]
		"jobs":
			return "%s / %s" % [Catalogue.fmt(float(o.get("capacity", {}).get("employed", 0))), Catalogue.fmt(float(o.get("population", 0)))]
		"power":
			var p: Dictionary = o.get("power", {})
			return "%s / %s E" % [UI.compact(_delivered_power(p)), UI.compact(_requested_power(p))]
	return ""


## Tests only: whether the explanation of a figure is on screen.
func explanation_visible() -> bool:
	return _tip != null and is_instance_valid(_tip) and _tip.visible


func _process(delta: float) -> void:
	_safe_check -= delta
	if _safe_check <= 0.0:
		_safe_check = 1.0
		if UI.safe_margins(self) != _safe:
			_layout()
	if explanation_visible():
		_tip_left -= delta
		if _tip_left <= 0.0:
			_tip.visible = false


func close_details() -> bool:
	if _popover and is_instance_valid(_popover) and _popover.visible:
		_popover.visible = false
		return true
	return false


func _detail_rows(key: String) -> Array:
	var o := own()
	var cap: Dictionary = o.get("capacity", {})
	var p: Dictionary = o.get("power", {})
	var w: Dictionary = o.get("waste", {}).get("totals", {})
	var pop := float(o.get("population", 0))
	var good := Color("#69e0b4")
	var bad := Color("#ff9c8a")
	var sg := func(x: float, unit := "") -> Array:
		return ["%s%s%s" % ["+" if x > 0 else "", Catalogue.fmt(x) if absf(x) >= 10 else "%.1f" % x, unit], good if x > 0 else (bad if x < 0 else Color.WHITE)]
	match key:
		"satisfaction":
			var c: Dictionary = o.get("satisfaction_components_micro", {})
			var out: Array = ["Satisfaction %s" % (Catalogue.micro(o["satisfaction_micro"], 1) if o.get("satisfaction_micro") != null else "–")]
			for part in [["housing", "Homes"], ["employment", "Jobs"], ["services", "Services"], ["power", "Power"], ["environment", "Environment"]]:
				if c.has(part[0]):
					out.append([part[1], Catalogue.micro(c[part[0]], 1)])
			out.append(["Service capacity", "%s / %s" % [Catalogue.micro(cap.get("services_micro", 0)), Catalogue.fmt(pop * _slack("services_slack"))]])
			out.append(["Waste on the street", Catalogue.micro(_sum(o.get("street_micro", [])), 1)])
			out.append("Residents move toward the more satisfying cities.")
			return out
		"population":
			var d: Array = sg.call(_per_minute(2), " / min")
			var next := _next_migration()
			return ["Residents", ["Now", Catalogue.fmt(pop)], ["Change", d[0], d[1]], ["Homes", Catalogue.fmt(float(cap.get("housing", 0)))],
				["Rank", "#%d of 4" % _rank()], ["Next move of residents", ("%d s" % next) if next >= 0 else "none left"]]
		"homes":
			return ["Homes", ["Housing capacity", Catalogue.fmt(float(cap.get("housing", 0)))], ["Residents", Catalogue.fmt(pop)],
				["Full comfort at 115 %", Catalogue.fmt(pop * _slack("housing_slack"))], "No home, no newcomer: build Residential Districts to grow."]
		"jobs":
			var e: Dictionary = o.get("employment", {})
			return ["Jobs", ["Residents at work", Catalogue.fmt(float(cap.get("employed", 0)))], ["In municipal jobs", Catalogue.fmt(float(e.get("municipal", 0)))],
				["In your buildings", Catalogue.fmt(float(e.get("buildings", 0)))], ["Residents", Catalogue.fmt(pop)],
				"Buildings need workers to run; the first residents work for the city."]
		"power":
			var rows: Array = ["Electricity"]
			for f in [["municipal_micro_E", "From the grid"], ["plants_micro_E", "From your plants"], ["biogas_micro_E", "From biogas"],
					["imports_micro_E", "Bought"], ["exports_micro_E", "Sold"], ["unused_micro_E", "Unused"]]:
				rows.append([f[1], Catalogue.micro(p.get(f[0], 0), 1)])
			rows.append(["Requested", "%.1f" % _requested_power(p)])
			rows.append(["Delivered", "%.1f" % _delivered_power(p), bad if _delivered_power(p) < _requested_power(p) else Color.WHITE])
			rows.append(["Reliability", "%s %%" % Catalogue.micro(int(p.get("reliability_micro", 0)) * 100, 0)])
			return rows
		"services":
			return ["Services", ["Service capacity", Catalogue.micro(cap.get("services_micro", 0))], ["Needed (115 % of residents)", Catalogue.fmt(pop * _slack("services_slack"))],
				"Public Services Centers add capacity."]
		"waste":
			var rows2: Array = ["Waste"]
			var street: Array = o.get("street_micro", [])
			for i in 3:
				rows2.append(["On the street · %s" % Catalogue.WASTE[i], Catalogue.micro(street[i] if i < street.size() else 0, 1)])
			var sorted: Array = o.get("sorted_micro", [])
			rows2.append(["Collected, awaiting sorting", Catalogue.micro(_sum(o.get("mixed_micro", [])), 1)])
			rows2.append(["Sorted · recyclable", Catalogue.micro(sorted[0] if sorted.size() > 0 else 0, 1)])
			rows2.append(["Sorted · organic", Catalogue.micro(sorted[1] if sorted.size() > 1 else 0, 1)])
			rows2.append(["Waiting for the landfill", Catalogue.micro(o.get("disposal_micro", 0), 1)])
			rows2.append(["Materials recovered so far", Catalogue.micro(_recovered(w), 1)])
			rows2.append(["Landfilled so far", Catalogue.micro(w.get("landfilled", 0))])
			return rows2
		"air":
			return ["Environment", ["Environment", Catalogue.micro(o.get("environment_micro", 0), 1)], ["Air pollution", "−" + Catalogue.micro(o.get("air_micro", 0), 1)],
				["Landfill damage", "−" + Catalogue.micro(o.get("landfill_damage_micro", 0), 1)], ["Waste lying around", "−" + Catalogue.micro(o.get("pressure_micro", 0), 1)],
				["Park amenity", "+" + Catalogue.micro(o.get("amenity_micro", 0), 1)], "Landfill damage never fades; parks clean only the air."]
		"money":
			var n: Array = sg.call(_per_minute(1), " / min")
			var rows4: Array = ["Cash", ["Available", Catalogue.micro(o.get("available_money_micro", 0))], ["Balance", Catalogue.micro(o.get("money_micro", 0))]]
			var held := int(o.get("money_micro", 0)) - int(o.get("available_money_micro", 0))
			if held > 0:
				rows4.append(["Held in contract escrow", Catalogue.micro(held, 1)])
			rows4.append(["Net over the last minute", n[0], n[1]])
			var unpaid := int(o.get("finance", {}).get("unpaid_municipal_upkeep_micro", 0))
			if unpaid > 0:
				rows4.append(["City upkeep left unpaid", Catalogue.micro(unpaid, 1), bad])
			return rows4
		"materials":
			var m: Array = sg.call(_per_minute(3), " / min")
			var ml: Dictionary = o.get("materials", {})
			return ["Materials", ["In stock", "%s / %s" % [Catalogue.micro(o.get("materials_micro", 0)), Catalogue.fmt(float(Catalogue.data().get("materials", {}).get("capacity", 500)))]],
				["Salvaged by collection", Catalogue.micro(w.get("salvaged", 0), 1)], ["Reused by sorting", Catalogue.micro(w.get("sorting_reuse", 0), 1)],
				["Made by recycling", Catalogue.micro(w.get("recycled_materials", 0), 1)], ["Used from stock", Catalogue.micro(ml.get("used", 0), 1)],
				["Bought", Catalogue.micro(ml.get("purchased", 0), 1)], ["Sold", Catalogue.micro(ml.get("sold", 0), 1)], ["Change", m[0], m[1]]]
		"time":
			var cr: Dictionary = v().get("public", {}).get("crisis", {})
			var rows3: Array = ["Match clock", ["Elapsed", Catalogue.clock(tick())], ["Left", Catalogue.clock(int(v().get("public", {}).get("duration_ticks", 1200)) - tick())]]
			for id in cr.get("active", []):
				rows3.append(["Now", Catalogue.event_name(id), bad])
			for id in cr.get("announced", []):
				rows3.append(["Coming", Catalogue.event_name(id), Color("#ffd257")])
			for x in Catalogue.data().get("crises", []):
				if int(x["start_tick"]) > tick():
					rows3.append(["Next crisis", "%s at %s" % [Catalogue.event_name(x["id"]), Catalogue.clock(int(x["start_tick"]))]])
					break
			return rows3
	return [key]


static func _recovered(w: Dictionary) -> int:
	return int(w.get("salvaged", 0)) + int(w.get("sorting_reuse", 0)) + int(w.get("recycled_materials", 0))


## Building notifications, from the same per-building problems the bubbles
## show: one card per kind of problem naming the buildings it affects. A card
## appears once when a problem starts (with a gold flash on the HUD figure it
## concerns), stays while it lasts unless tapped away, and goes when it ends.
const ALERTS := {
	"road": ["warning", "Not connected to a road", ""],
	"off": ["warning", "Switched off", ""],
	"coin": ["coin", "Not enough money to run", "money"],
	"power": ["power", "Not enough electricity", "power"],
	"people": ["people", "Not enough workers", "population"],
	"waste": ["waste", "Waste is not being collected", "waste"],
}


func _alerts_refresh(needs: Dictionary) -> void:
	var by_kind := {}
	for t in needs:
		var b := _building_at(int(t))
		if b.is_empty():
			continue
		by_kind.get_or_add(str(needs[t]), []).append(b)
	# Problems that ended: forget them so they can be announced again later.
	for k in _alert_seen.keys():
		if not by_kind.has(k):
			_alert_seen.erase(k)
			_alert_dismissed.erase(k)
	UI.clear(_alerts)
	var shown := 0
	for k in by_kind:
		var list: Array = by_kind[k]
		var ids := {}
		for b in list:
			ids[int(b["id"])] = true
		var before: Dictionary = _alert_seen.get(k, {})
		var fresh := false
		for id in ids:
			if not before.has(id):
				fresh = true
		_alert_seen[k] = ids
		if fresh:
			_alert_dismissed.erase(k)
			if UI.music:
				UI.music.alert("notice")
			_flash(str(ALERTS.get(k, ["", "", ""])[2]))
		if _alert_dismissed.has(k) or shown >= 3:
			continue
		shown += 1
		_alerts.add_child(_alert_card(k, list))


func _alert_card(kind: String, list: Array) -> Control:
	var meta: Array = ALERTS.get(kind, ["warning", kind, ""])
	var names := []
	for b in list.slice(0, 2):
		names.append(Catalogue.building_name(str(b["type"])))
	var who := ", ".join(names) + ("" if list.size() <= 2 else " and %d more" % (list.size() - 2))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.09, 0.12, 0.88), 12, Color("#ffb648") if kind != "road" else Color("#ff7a66"), 1, 0, Color(), 7))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.custom_minimum_size.x = 250
	var row := UI.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := UI.badge(str(meta[0]), 24)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	var col := UI.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := UI.label(str(meta[1]), "HudSmall")
	a.add_theme_constant_override("outline_size", 0)
	var b2 := UI.label(who, "HudCaption")
	b2.add_theme_constant_override("outline_size", 0)
	b2.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	for l in [a, b2]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	row.add_child(col)
	var x := UI.label("✕", "HudCaption")
	x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(x)
	p.add_child(row)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			UI.click()
			_alert_dismissed[kind] = true
			p.queue_free()
			accept_event())
	return p


## A short gold flash on the HUD figure a notification concerns.
func _flash(target: String) -> void:
	match target:
		"money":
			_cash.pulse()
		"population":
			_pop_card.pulse()
		"":
			pass
		_:
			if _need_chips.has(target):
				_need_chips[target].pulse()


## What each building is missing, from the authoritative view and the road
## network: the first problem wins.
func _building_needs() -> Dictionary:
	var o := own()
	var out := {}
	var street := _sum(o.get("street_micro", []))
	for b in o.get("buildings", []):
		if b.get("status", "") != "complete" or tick() == 0:
			continue
		var t := int(b["tile"])
		var type := str(b["type"])
		var op: Dictionary = b.get("op", {})
		var need := ""
		if not map.layout or not map.layout.linked(t):
			need = "road"
		elif not b.get("enabled", true):
			need = "off"
		elif not op.get("funded", false):
			need = "coin"
		elif int(op.get("requested_micro_E", 0)) > 0 and int(op.get("power_micro", 0)) < 1000000:
			need = "power"
		elif Catalogue.figure(type, str(b.get("size", "S")), "job_slots") > 0 and int(op.get("staff_micro", 0)) < 1000000:
			need = "people"
		elif type == "residential_district" and street > 0:
			need = "waste"
		if need != "":
			out[t] = need
	return out


func _banner_refresh() -> void:
	var cr: Dictionary = v().get("public", {}).get("crisis", {})
	var active: Array = cr.get("active", [])
	var coming: Array = cr.get("announced", [])
	# A crisis striking (and EQUILIBRIUM 2050, which has no active time,
	# when it is announced) pulses the screen edges once per match.
	for id in active + coming.filter(func(x): return x == "equilibrium_2050"):
		if not _crises_seen.has(id):
			_crises_seen[id] = true
			if session.live and tick() > 0:
				_edge.play(Settings.reduce_motion)
	var text := ""
	var col := Color("#17323a")
	if not active.is_empty():
		text = "⚠ %s — %s" % [Catalogue.event_name(active[0]), Catalogue.EVENTS.get(active[0], ["", ""])[1]]
		col = Color("#b9422f")
	elif not coming.is_empty():
		var start := int(Catalogue.crisis(coming[0]).get("start_tick", tick()))
		text = "%s in %s" % [Catalogue.event_name(coming[0]), Catalogue.clock(start - tick())]
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
		"waste":
			_waste_panel()
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


## One building at a glance: its role and state, what it gives and takes as
## figures, its tiers with what the next one adds and costs, and what you can
## do with it. The full description waits behind More.
func _building_panel(b: Dictionary) -> void:
	var t := str(b["type"])
	var size := str(b.get("size", "S"))
	var id := int(b["id"])
	var op: Dictionary = b.get("op", {})
	var complete: bool = b.get("status", "") == "complete"
	_panel_title.text = Catalogue.building_name(t)
	var p: Variant = _project_for(id)
	var upgrading: bool = p != null and str(p.get("kind", "")) == "upgrade"
	var need: String = map.needs.get(int(b["tile"]), "")
	# Role and state.
	var top := UI.vbox(4)
	var head := UI.hbox(10)
	var pic := TextureRect.new()
	pic.texture = UI.thumbs.get_thumb(t, size)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(64, 52)
	head.add_child(pic)
	var role := UI.label(Catalogue.role(t), "Caption", true)
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(role)
	top.add_child(head)
	var state := ""
	var tone := UI.PRIMARY_DARK
	if not complete:
		state = "Being built · %s left" % Catalogue.clock(int(p["complete_tick"]) - tick()) if p != null else "Being built"
		tone = UI.MUTED
	elif need != "":
		state = "⚠ " + BUBBLES.get(need, need)
		tone = UI.DANGER_DARK
	elif op.get("funded", false):
		state = "✓ Working at %s %%" % Catalogue.micro(int(op.get("fraction_micro", 0)) * 100, 0)
	if state != "":
		var sl := UI.label(state, "Value", true)
		sl.add_theme_color_override("font_color", tone)
		top.add_child(sl)
	if upgrading:
		var left := int(p["complete_tick"]) - tick()
		var total := int(Catalogue.upgrade_to(t, str(p["target_size"])).get("seconds", 1))
		top.add_child(UI.label("Growing to %s · %s left · keeps working meanwhile" % [Catalogue.size_name(str(p["target_size"])), Catalogue.clock(left)], "Small", true))
		top.add_child(UI.bar(1.0 - float(left) / maxf(float(total), 1.0)))
	_card(top)
	# What it gives and what it takes, at this size.
	var fx := UI.vbox(4)
	fx.add_child(_chips(_effects(t, size, op if complete else {})))
	_card(fx)
	# Tiers: where it stands, what the next one adds and costs.
	_card(_tier_track(t, size, str(p["target_size"]) if upgrading else ""))
	# Actions. Buttons keep short labels; consequences sit in a caption.
	var acts := UI.vbox(6)
	var note := func(text: String) -> void: acts.add_child(UI.label(text, "Caption", true))
	if p != null:
		note.call("Cancelling returns 80 % of the cash and every material unit.")
		acts.add_child(_danger("cancel", "Cancel upgrade" if upgrading else "Cancel", "cancel_project", {"building_id": id}, "Cancel %s" % Catalogue.building_name(t)))
	if complete and p == null:
		var row := UI.hbox(6)
		if b.get("enabled", true):
			row.add_child(UI.button("Switch off", "SoftButton", "", func(): session.act("disable", {"building_id": id}, "Switch off %s" % Catalogue.building_name(t))))
		else:
			var on := UI.button("Switch on", "PrimaryButton", "", func(): map.layout.road_off.erase(id); session.act("enable", {"building_id": id}, "Switch on %s" % Catalogue.building_name(t)))
			if not map.layout.linked(int(b["tile"])):
				on.text = "Needs a road"
				on.disabled = true
			row.add_child(on)
		row.add_child(UI.button("Move", "SoftButton", "", func(): start_moving(int(b["tile"]))))
		for c in row.get_children():
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(row)
		note.call("Off: no output, 20 % standby upkeep. Demolishing returns 10 % of its price. Holding it on the map also picks it up to move.")
		acts.add_child(_danger("demolish", "Demolish", "demolish", {"building_id": id}, "Demolish %s" % Catalogue.building_name(t)))
	elif not complete:
		acts.add_child(UI.button("Move", "SoftButton", "", func(): start_moving(int(b["tile"]))))
	_card(acts)
	# Everything else, on request.
	var more := UI.button("More about this building", "SoftButton", "", func(): _details_open = not _details_open; refresh("all"))
	_body.add_child(more)
	if _details_open:
		var facts := UI.vbox(2)
		for f in _tier_facts(t, size):
			facts.add_child(UI.label(f, "Small", true))
		_card(facts)


## What a building gives (+, green) and takes (−, red) at a size, as chips from
## the exported figures. With an operating record, workers and power show what
## it actually gets now.
static func _effects(t: String, size: String, op: Dictionary = {}) -> Array:
	var f := func(key: String) -> float: return Catalogue.figure(t, size, key)
	var n := func(x: float) -> String: return Catalogue.fmt(x) if absf(x) >= 10 or is_equal_approx(x, roundf(x)) else String.num(x, 2)
	var out: Array = []
	if f.call("housing_capacity") > 0:
		out.append(["homes", "+%s homes" % n.call(f.call("housing_capacity")), "good"])
	if f.call("service_capacity") > 0:
		out.append(["people", "+%s services" % n.call(f.call("service_capacity")), "good"])
	if f.call("gross_income_credits_per_min") > 0:
		out.append(["coin", "+%s / min" % n.call(f.call("gross_income_credits_per_min")), "good"])
	if f.call("power_generated_capacity") > 0:
		out.append(["power", "+%s E" % n.call(f.call("power_generated_capacity")), "good"])
	if f.call("collection_waste_per_min") > 0:
		out.append(["waste", "collects %s / min" % n.call(f.call("collection_waste_per_min")), "good"])
	if f.call("sorting_waste_per_min") > 0:
		out.append(["waste", "sorts %s / min" % n.call(f.call("sorting_waste_per_min")), "good"])
	if f.call("recycling_waste_per_min") > 0:
		out.append(["materials", "+%s mat / min" % n.call(f.call("recycling_waste_per_min") * f.call("material_yield_fraction")), "good"])
	if f.call("biogas_organic_waste_per_min") > 0:
		out.append(["power", "+%s E" % n.call(f.call("biogas_organic_waste_per_min") * f.call("biogas_energy_capacity_per_organic_unit_per_min")), "good"])
	if f.call("landfill_waste_per_min") > 0:
		out.append(["waste", "landfills %s / min" % n.call(f.call("landfill_waste_per_min")), ""])
	if f.call("air_cleanup_points_per_min") > 0:
		out.append(["pollution", "−%s air / min" % n.call(f.call("air_cleanup_points_per_min")), "good"])
		out.append(["appeal", "+%s amenity" % n.call(f.call("park_amenity_points")), "good"])
	if f.call("job_slots") > 0:
		var jobs: float = f.call("job_slots")
		out.append(["jobs", ("%d / %s jobs" % [int(op.get("workers", 0)), n.call(jobs)]) if op.get("funded", false) else "%s jobs" % n.call(jobs), ""])
	if f.call("power_demand_capacity") > 0:
		out.append(["power", "−%s E" % n.call(f.call("power_demand_capacity")), "bad"])
	if f.call("factory_materials_consumed_per_min") > 0:
		out.append(["materials", "−%s mat / min" % n.call(f.call("factory_materials_consumed_per_min")), "bad"])
	if f.call("waste_generated_per_min") > 0:
		out.append(["waste", "+%s waste / min" % n.call(f.call("waste_generated_per_min")), "bad"])
	if f.call("air_emissions_points_per_min") > 0:
		out.append(["pollution", "+%s air / min" % n.call(f.call("air_emissions_points_per_min")), "bad"])
	out.append(["coin", "−%s / min" % n.call(f.call("maintenance_credits_per_min")), "bad"])
	return out


static func _chips(list: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	for c in list:
		flow.add_child(UI.stat_chip(c[0], c[1], UI.INK, c[2]))
	return flow


## S · M · L in a row, the current size marked; then what the next size adds
## over this one and what growing costs, with the upgrade button.
func _tier_track(t: String, size: String, growing_to: String) -> Control:
	var box := UI.vbox(6)
	var track := UI.hbox(4)
	var order := ["S", "M", "L"]
	var here := order.find(size)
	for i in 3:
		var pill := PanelContainer.new()
		var reached := i <= here
		var target: bool = order[i] == growing_to
		var bg := UI.PRIMARY if i == here else (Color("#bfe8d3") if reached else (Color("#fff1cf") if target else UI.PAPER2))
		pill.add_theme_stylebox_override("panel", UI.box(bg, 10, Color("#d9a21b") if target else Color(), 2 if target else 0, 0, Color(), 6))
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := UI.label(Catalogue.size_name(order[i]), "Value")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color.WHITE if i == here else (UI.INK if reached or target else UI.MUTED))
		pill.add_child(l)
		track.add_child(pill)
		if i < 2:
			var arrow := UI.label("›", "Value")
			arrow.add_theme_color_override("font_color", UI.MUTED)
			track.add_child(arrow)
	box.add_child(track)
	if not Catalogue.NEXT_SIZE.has(size):
		box.add_child(UI.label("Large is the biggest size.", "Caption", true))
		return box
	var next: String = Catalogue.NEXT_SIZE[size]
	var gains := _tier_gains(t, size, next)
	if not gains.is_empty():
		box.add_child(UI.label("At %s" % Catalogue.size_name(next), "Small"))
		box.add_child(_chips(gains))
	var up := Catalogue.upgrade_to(t, next)
	var cost := [["coin", Catalogue.fmt(float(up.get("additional_credits", 0))), ""], ["materials", Catalogue.fmt(float(up.get("additional_materials", 0))), ""],
		["timer", Catalogue.clock(int(up.get("seconds", 0))), ""]]
	var row := UI.hbox(8)
	var costs := _chips(cost)
	costs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(costs)
	if growing_to == "":
		var b := _building_at(selected)
		var id := int(b.get("id", -1))
		var busy := _slots_free() == 0
		var ub := UI.button("Upgrade", "PrimaryButton", "", func(): session.act("upgrade", {"building_id": id}, "Upgrade %s to %s" % [Catalogue.building_name(t), Catalogue.size_name(next)]))
		ub.disabled = busy or session.pending_for("upgrade", "building_id", id) or b.get("status", "") != "complete"
		row.add_child(ub)
		box.add_child(row)
		box.add_child(UI.label("Both construction slots are busy." if busy else "It keeps working at its size until the upgrade is done.", "Caption", true))
	else:
		box.add_child(row)
	return box


## What the next size gives where it gives more (tier values are totals).
static func _tier_gains(t: String, from: String, to: String) -> Array:
	var now := _effects(t, from)
	var then := _effects(t, to)
	var out: Array = []
	for i in mini(now.size(), then.size()):
		if now[i][1] == then[i][1]:
			continue
		if now[i][2] == "good" or now[i][0] == "jobs":
			out.append([then[i][0], then[i][1], then[i][2]])
	return out


## What a tier does, as short lines, from the exported figures.
static func _tier_facts(t: String, size: String) -> Array:
	var f := func(key: String) -> float: return Catalogue.figure(t, size, key)
	var out: Array = []
	var pct := func(x: float) -> String: return "%d %%" % int(round(x * 100.0))
	if f.call("housing_capacity") > 0:
		out.append("Homes for %s residents" % Catalogue.fmt(f.call("housing_capacity")))
	if f.call("service_capacity") > 0:
		out.append("Services for %s residents" % Catalogue.fmt(f.call("service_capacity")))
	if f.call("gross_income_credits_per_min") > 0:
		out.append("Income up to %s / min" % Catalogue.fmt(f.call("gross_income_credits_per_min")))
	if f.call("factory_materials_consumed_per_min") > 0:
		out.append("Uses %s materials / min (stock first, then bought at %s)" % [Catalogue.fmt(f.call("factory_materials_consumed_per_min")), Catalogue.fmt(float(Catalogue.data().get("materials", {}).get("buy_price", 6)))])
	if f.call("waste_generated_per_min") > 0:
		out.append("Makes %s waste / min" % Catalogue.fmt(f.call("waste_generated_per_min")))
	if f.call("collection_waste_per_min") > 0:
		out.append("Collects %s waste / min and salvages %s of its recyclables" % [Catalogue.fmt(f.call("collection_waste_per_min")), pct.call(f.call("collection_direct_reuse_fraction"))])
	if f.call("sorting_waste_per_min") > 0:
		out.append("Sorts %s collected waste / min: catches %s of recyclables and %s of organics, reuses %s of the recyclables caught" % [Catalogue.fmt(f.call("sorting_waste_per_min")),
			pct.call(f.call("sort_capture_recyclable")), pct.call(f.call("sort_capture_organic")), pct.call(f.call("sorting_direct_reuse_fraction"))])
	if f.call("recycling_waste_per_min") > 0:
		out.append("Recycles %s sorted recyclables / min into %s materials" % [Catalogue.fmt(f.call("recycling_waste_per_min")), pct.call(f.call("material_yield_fraction"))])
	if f.call("biogas_organic_waste_per_min") > 0:
		out.append("Digests %s sorted organics / min for %s E each, next second" % [Catalogue.fmt(f.call("biogas_organic_waste_per_min")), String.num(f.call("biogas_energy_capacity_per_organic_unit_per_min"), 1)])
	if f.call("landfill_waste_per_min") > 0:
		out.append("Landfills %s waste / min, at %s each" % [Catalogue.fmt(f.call("landfill_waste_per_min")), String.num(float(Catalogue.data().get("landfill_fee", 0.85)), 2)])
	if f.call("power_generated_capacity") > 0:
		out.append("Generates %s E" % Catalogue.fmt(f.call("power_generated_capacity")))
	if f.call("air_emissions_points_per_min") > 0:
		out.append("Smoke: %s air points / min" % String.num(f.call("air_emissions_points_per_min"), 2))
	if f.call("air_cleanup_points_per_min") > 0:
		out.append("Cleans %s air points / min, +%s amenity" % [String.num(f.call("air_cleanup_points_per_min"), 2), String.num(f.call("park_amenity_points"), 1)])
	var needs := []
	if f.call("job_slots") > 0:
		needs.append("%s workers" % Catalogue.fmt(f.call("job_slots")))
	if f.call("power_demand_capacity") > 0:
		needs.append("%s E" % Catalogue.fmt(f.call("power_demand_capacity")))
	needs.append("%s / min upkeep" % Catalogue.fmt(f.call("maintenance_credits_per_min")))
	out.append("Needs " + ", ".join(needs))
	return out


## The circular economy at a glance: which stages are built, the waste waiting
## at each, the materials recovered, and a way to sell materials.
func _waste_panel() -> void:
	_panel_title.text = "Waste & materials"
	var o := own()
	var w: Dictionary = o.get("waste", {}).get("totals", {})
	var counts := {}
	for b in o.get("buildings", []):
		if b.get("status", "") == "complete":
			counts[str(b["type"])] = int(counts.get(str(b["type"]), 0)) + 1
	var chain := UI.vbox(4)
	chain.add_child(UI.label("Your recovery chain", "Value"))
	for t in ["collection_center", "sorting_center", "recycling_center", "biogas_facility", "landfill"]:
		var n := int(counts.get(t, 0))
		var req: Array = Catalogue.requires(t)
		var line := "✓ %s × %d" % [Catalogue.building_name(t), n] if n > 0 else "· %s — not built" % Catalogue.building_name(t)
		if n == 0 and not req.is_empty():
			line += " (needs %s)" % " and ".join(req.map(func(r): return Catalogue.building_name(r)))
		chain.add_child(UI.label(line, "Small", true))
	chain.add_child(UI.label("Each stage recovers more from the same waste: collection salvages a little, sorting reuses more, recycling the most. The city fleet only hauls to the landfill.", "Caption", true))
	_card(chain)
	var now := UI.vbox(2)
	now.add_child(UI.label("Waste now", "Value"))
	var sorted: Array = o.get("sorted_micro", [])
	for row in [["On the street", _sum(o.get("street_micro", []))], ["Collected, awaiting sorting", _sum(o.get("mixed_micro", []))],
			["Sorted recyclables", float(sorted[0]) if sorted.size() > 0 else 0.0], ["Sorted organics", float(sorted[1]) if sorted.size() > 1 else 0.0],
			["Waiting for the landfill", float(o.get("disposal_micro", 0))]]:
		now.add_child(UI.hbox(8, [UI.label(row[0], "Small"), UI.spacer(), UI.label(Catalogue.micro(row[1], 1), "Small")]))
	_card(now)
	var mats := UI.vbox(4)
	var mdata: Dictionary = Catalogue.data().get("materials", {})
	mats.add_child(UI.label("Materials: %s in stock" % Catalogue.micro(o.get("materials_micro", 0)), "Value"))
	mats.add_child(UI.label("Recovered so far: %s (collection %s, sorting %s, recycling %s)" % [Catalogue.micro(_recovered(w), 1), Catalogue.micro(w.get("salvaged", 0), 1),
		Catalogue.micro(w.get("sorting_reuse", 0), 1), Catalogue.micro(w.get("recycled_materials", 0), 1)], "Small", true))
	mats.add_child(UI.label("Construction and factories use stock first; anything missing is bought at %s each. Stock above %s sells by itself at %s." % [
		Catalogue.fmt(float(mdata.get("buy_price", 6))), Catalogue.fmt(float(mdata.get("capacity", 500))), Catalogue.fmt(float(mdata.get("sell_price", 2)))], "Caption", true))
	var amount := SpinBox.new()
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.min_value = 1
	amount.max_value = maxf(1.0, floorf(float(o.get("materials_micro", 0)) / Catalogue.MICRO))
	amount.value = minf(float(sell_amount), amount.max_value)
	amount.suffix = "units"
	amount.value_changed.connect(func(x): sell_amount = int(x))
	var sell := UI.button("Sell at %s each" % Catalogue.fmt(float(mdata.get("sell_price", 2))), "SoftButton", "", func():
		session.act("sell_materials", {"amount": int(amount.value) * int(Catalogue.MICRO)}, "Sell %d materials" % int(amount.value)))
	sell.disabled = int(o.get("materials_micro", 0)) < int(Catalogue.MICRO)
	mats.add_child(UI.hbox(8, [amount, sell]))
	_card(mats)


## Picks up one of the city's buildings (long press, or Move in its panel):
## a ghost follows the finger, and Move here asks the server to move it. The
## building stays where it is until the server has moved it.
func start_moving(t: int) -> void:
	if visiting >= 0 or map.road_mode != "" or not map.layout.placements.has(t):
		return
	var b := _building_at(t)
	if b.is_empty() or session.pending_for("move", "building_id", int(b["id"])):
		return
	UI.click()
	placing = {"type": str(b["type"]), "size": str(b.get("size", "S")), "move": int(b["id"]), "from": t,
		"at": map.layout.placements[t], "ok": false, "why": "drag it to a new spot"}
	selected = -1
	tab = ""
	map.placing = placing
	map.rebuild()
	refresh("all")


## Tests only: the move being prepared, or {}.
func moving() -> Dictionary:
	return placing if placing.has("move") else {}


func start_placing(type: String, at_cell: Variant = null) -> void:
	road_mode("")
	var cell: Vector2i = at_cell if at_cell != null else map.center_cell()
	placing = {"type": type, "size": build_size, "at": cell, "ok": false, "why": ""}
	selected = -1
	tab = ""
	_snap(cell)
	refresh("all")


func _snap(cell: Vector2i) -> void:
	var at := cell - Vector2i(CityLayout.FOOT / 2, CityLayout.FOOT / 2)
	placing["at"] = at
	var from := int(placing.get("from", -1))
	placing["why"] = map.layout.why_not(at, from)
	if from >= 0 and placing["why"] == "" and at == map.layout.placements.get(from, Vector2i(-99, -99)):
		placing["why"] = "it is already here"
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
	# A new building is built where it is dropped; a moved one waits for Move here.
	if not placing.has("move"):
		_confirm_place()


func _confirm_place() -> void:
	if placing.is_empty() or not placing.get("ok", false):
		return
	if placing.has("move"):
		_confirm_move()
		return
	var type: String = placing["type"]
	var size: String = placing["size"]
	var tl := _free_tile()
	map.layout.place(tl, placing["at"])
	map.save()
	# Reserve before sending: the send triggers a refresh that would otherwise
	# drop a spot with no building behind it yet.
	_reserved[tl] = ""
	var aid := session.act("construct", {"building_type": type, "size": size, "tile": tl}, "Build %s %s" % [Catalogue.size_name(size), Catalogue.building_name(type)])
	if aid != "":
		_reserved[tl] = aid
	else:
		_reserved.erase(tl)
		map.layout.unplace(tl)
	if not map.layout.linked(tl):
		toast.call("Connect it to a road, or it will not work", "warn")
	_cancel_place()


func _confirm_move() -> void:
	var id := int(placing["move"])
	var from := int(placing["from"])
	var tl := _free_tile()
	if tl < 0:
		return
	map.layout.place(tl, placing["at"])
	map.save()
	_reserved[tl] = ""
	var aid := session.act("move", {"building_id": id, "tile": tl}, "Move %s" % Catalogue.building_name(str(placing["type"])))
	if aid != "":
		_reserved[tl] = aid
		_moves[tl] = from
	else:
		_reserved.erase(tl)
		map.layout.unplace(tl)
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
			# A moved building has left its old site: the server says so.
			if _moves.has(tl):
				var from: int = _moves[tl]
				_moves.erase(tl)
				if not built.has(from):
					map.layout.unplace(from)
				if selected == from:
					selected = tl
				map.save()
		elif a.get("status", "") == "rejected" or a.is_empty():
			_reserved.erase(tl)
			_moves.erase(tl)
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
	# A press anywhere closes an explanation; its own figure reopens it.
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and explanation_visible():
		var ta: Variant = _tip.get_meta("anchor", null)
		if not (ta is Control and is_instance_valid(ta) and (ta as Control).get_global_rect().has_point(event.position)):
			_tip.visible = false
	# A press anywhere outside the details popover closes it.
	if event is InputEventMouseButton and event.pressed and _popover and is_instance_valid(_popover) and _popover.visible:
		var a: Variant = _popover.get_meta("anchor", null)
		if not _popover.get_global_rect().has_point(event.global_position) and not (a is Control and is_instance_valid(a) and (a as Control).get_global_rect().has_point(event.global_position)):
			_popover.visible = false
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
	if _zoom:
		_zoom.visible = not _modebar.visible and tab not in PANELS
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
	var size: String = placing["size"]
	var moving_one := placing.has("move")
	var box := UI.vbox(6)
	var tier := Catalogue.tier(type, size)
	if moving_one:
		box.add_child(UI.label("Move %s %s" % [Catalogue.size_name(size), Catalogue.building_name(type)], "Value", true))
	else:
		box.add_child(UI.label("%s %s · %s" % [Catalogue.size_name(size), Catalogue.building_name(type), Catalogue.price_text(float(tier.get("construction_credits", 0)),
			float(tier.get("construction_materials", 0)), int(tier.get("construction_seconds", 0)))], "Value", true))
	var msg := "Drag it anywhere on open land, then lift your finger to build. Put it beside a road so it works."
	if moving_one:
		msg = "Drag it to open land, then Move here. Moving is free and it keeps working; put it beside a road."
	if not placing.get("ok", false):
		msg = ("Can't move it there: %s." if moving_one else "Can't build here: %s.") % placing.get("why", "")
	box.add_child(UI.label(msg, "Caption", true))
	var row := UI.hbox(8)
	row.add_child(UI.button("Cancel", "SoftButton", "close", _cancel_place))
	var ok := UI.button("Move here" if moving_one else "Build here", "PrimaryButton", "check", _confirm_place)
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
	var mk: Dictionary = Catalogue.data().get("market", {})
	var prices: Dictionary = mk.get("prices", {})
	# Offer: the service and how much. Power is in E, treatment in units per minute.
	var form := UI.vbox(6)
	form.add_child(UI.label("Offer spare capacity to rivals", "Value"))
	var svc := OptionButton.new()
	for k in Catalogue.SERVICES:
		svc.add_item(Catalogue.SERVICES[k])
	svc.select(Catalogue.SERVICES.keys().find(market_form["type"]))
	svc.item_selected.connect(func(i): market_form["type"] = Catalogue.SERVICES.keys()[i]; refresh("all"))
	form.add_child(svc)
	var power: bool = market_form["type"] == "electricity"
	var rate := SpinBox.new()
	rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate.min_value = 1
	rate.max_value = float(mk.get("electricity_max", 40)) if power else 500.0
	rate.value = clampf(float(market_form["rate"]), rate.min_value, rate.max_value)
	market_form["rate"] = int(rate.value)
	rate.suffix = "E" if power else "units/min"
	rate.value_changed.connect(func(x): market_form["rate"] = int(x))
	form.add_child(UI.hbox(8, [UI.label("Amount", "Caption"), rate]))
	form.add_child(UI.label("Fixed price: %s %s. You can only offer capacity your city had spare in the last second." % [
		String.num(float(prices.get(market_form["type"], 0)), 2), "per E·min" if power else "per unit treated"], "Caption", true))
	form.add_child(UI.button("Publish offer", "PrimaryButton", "", func():
		session.act("publish_offer", {"type": market_form["type"], "rate": int(market_form["rate"]) * int(Catalogue.MICRO)}, "Offer %s" % Catalogue.SERVICES[market_form["type"]])))
	_card(form)

	_section("Open offers")
	var length := SpinBox.new()
	length.min_value = float(mk.get("min_duration", 60))
	length.max_value = float(mk.get("max_duration", 300))
	length.step = 30
	length.value = float(market_form["duration"])
	length.suffix = "s"
	length.value_changed.connect(func(x): market_form["duration"] = int(x))
	_card(UI.vbox(4, [UI.hbox(8, [UI.label("Contract length", "Caption"), length]),
		UI.label("Your escrow holds the most a contract could cost; you pay only for what is delivered, and the rest comes back.", "Caption", true)]))
	var any := false
	for o in m.get("offers", []):
		any = true
		var seller := int(o["seller"])
		var oid := int(o["id"])
		var otype := str(o["type"])
		var orate := int(o["rate_micro"])
		var oprice := int(o["price_micro"])
		var box := UI.vbox(4)
		box.add_child(UI.label("%s %s %s at %s" % ["You sell" if seller == me else "City %d sells" % (seller + 1), Catalogue.micro(orate), _unit(otype) + " of " + Catalogue.SERVICES.get(otype, otype).to_lower(),
			Catalogue.micro(oprice, 2)], "", true))
		if seller == me:
			box.add_child(UI.button("Withdraw", "SoftButton", "close", func(): session.act("withdraw_offer", {"id": oid}, "Withdraw offer")))
		else:
			var dur := int(market_form["duration"])
			var hold := float(orate) * float(dur) / 60.0 * float(oprice) / (Catalogue.MICRO * Catalogue.MICRO)
			box.add_child(UI.label("For %s your escrow holds up to %s." % [Catalogue.clock(dur), String.num(hold, 2)], "Caption", true))
			box.add_child(UI.button("Accept", "PrimaryButton", "check", func():
				session.act("accept_offer", {"id": oid, "duration": int(market_form["duration"])}, "Accept offer from City %d" % (seller + 1))))
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
		var ktype := str(k["type"])
		var sell: bool = int(k["seller"]) == me
		var delivered := float(k.get("delivered_micro", 0)) / (60.0 if ktype == "electricity" else 1.0)
		var box := UI.vbox(4)
		box.add_child(UI.label("%s %s: %s %s — delivered %s %s, paid %s, ends in %s" % ["You sell to" if sell else "You buy from", "City %d" % (int(k["buyer"] if sell else k["seller"]) + 1),
			Catalogue.micro(k["rate_micro"]), _unit(ktype) + " of " + Catalogue.SERVICES.get(ktype, ktype).to_lower(), Catalogue.micro(delivered, 1),
			"E·min" if ktype == "electricity" else "units", Catalogue.micro(k.get("paid_micro", 0), 2), Catalogue.clock(int(k["end_tick"]) - tick())], "", true))
		box.add_child(_danger("cc%d" % cid, "Cancel", "cancel_contract", {"id": cid}, "Cancel contract"))
		_card(box)
	if not any:
		_card(UI.label("None.", "Caption"))


static func _unit(service: String) -> String:
	return "E" if service == "electricity" else "units/min"


func _rivals_panel() -> void:
	_panel_title.text = "Rivals"
	var rows: Array = v().get("public", {}).get("rankings", [])
	var most := 1.0
	for r in rows:
		most = maxf(most, float(r["population"]))
	for r in rows:
		var cid := int(r["city_id"])
		var fid := str(own().get("foundation", "")) if cid == session.seat else ""
		for o in v().get("opponents", []):
			if int(o["city_id"]) == cid:
				fid = str(o.get("foundation", ""))
		var meta: Array = Catalogue.FOUNDATIONS.get(fid, ["", "", UI.MUTED])
		var box := UI.vbox(4)
		var head := UI.hbox(8)
		var rank := UI.label("#%d" % int(r["rank"]), "Title")
		rank.add_theme_color_override("font_color", UI.PRIMARY_DARK if cid == session.seat else UI.INK)
		head.add_child(rank)
		var who := UI.vbox(0)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_child(UI.label("Your city" if cid == session.seat else "City %d" % (cid + 1), "Value", true))
		var fl := UI.label(meta[0], "Small", true)
		fl.add_theme_color_override("font_color", (meta[2] as Color).darkened(0.2))
		who.add_child(fl)
		head.add_child(who)
		box.add_child(head)
		box.add_child(UI.bar(float(r["population"]) / most, UI.PEOPLE if cid != session.seat else UI.PRIMARY))
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 4)
		chips.add_child(UI.stat_chip("people", Catalogue.fmt(r["population"])))
		chips.add_child(UI.stat_chip("appeal", Catalogue.micro(r["satisfaction_micro"], 1) if r.get("satisfaction_micro") != null else "–"))
		chips.add_child(UI.stat_chip("pollution", Catalogue.micro(r.get("environment_micro", 0), 1)))
		box.add_child(chips)
		if cid != session.seat:
			var c2 := cid
			var vb := UI.button("Return home" if visiting == cid else "Visit", "SoftButton" if visiting == cid else "", "region", func(): visit(-1 if visiting == c2 else c2))
			box.add_child(vb)
		_card(box)
	var next := _next_migration()
	var every := int(Catalogue.data().get("migration", {}).get("interval", 20))
	_card(UI.label(("Residents move toward more satisfying cities every %d s, as far as there are homes for them. Next move in %s." % [every, Catalogue.clock(next)]) if next >= 0 else "No more moves of residents: the ranking is set by who holds them now.", "Caption", true))


## Looks at a rival's city, read-only, from the public part of the view:
## its buildings, their size and whether they are finished. Its roads are
## not shared, so the buildings are arranged along the main road. visit(-1)
## returns home.
func visit(city_id: int) -> void:
	if city_id == visiting:
		return
	if city_id >= 0 and _rival(city_id).is_empty():
		toast.call("That city is not in the latest update", "warn")
		return
	if visiting < 0:
		_cancel_place()
		road_mode("")
	visiting = city_id
	selected = -1
	map.selected = -1
	map.read_only = visiting >= 0
	map.needs = {}
	for c in _own_controls:
		c.visible = visiting < 0
	_alerts.visible = visiting < 0
	_activity.visible = visiting < 0
	_visit_bar.visible = visiting >= 0
	if tab != "rivals":
		_open("")
	if visiting < 0:
		refresh("all")
		map.recenter()
		return
	_visit_refresh()
	map.recenter()
	UI.click()


func _rival(city_id: int) -> Dictionary:
	for o in v().get("opponents", []):
		if int(o["city_id"]) == city_id:
			return o
	return {}


func _visit_refresh() -> void:
	var o := _rival(visiting)
	if o.is_empty():
		visit(-1)
		return
	var f: String = Catalogue.FOUNDATIONS.get(str(o.get("foundation", "")), ["No Foundation"])[0]
	_visit_label.text = "Visiting City %d · %s · %s residents · view only" % [visiting + 1, f, Catalogue.fmt(float(o.get("population", 0)))]
	var bs := []
	for b in o.get("buildings", []):
		bs.append({"id": 100000 + int(b["tile"]), "tile": int(b["tile"]), "type": str(b["type"]), "size": str(b.get("size", "S")),
			"status": str(b.get("status", "complete")), "op": {"fraction_micro": 1000000}, "visitor": true})
	var city := {"buildings": bs, "population": o.get("population", 0), "projects": []}
	map.show_city(city, tick(), "visit:%s:%d" % [str(v().get("match_id", "")), visiting])


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
		_pop_card.pulse()
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


