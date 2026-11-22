class_name EmergencyLayer
extends Control
## The ECO EMERGENCIES on screen: the infrastructure alert, the minigame with its
## shared header (time, score, combo, the four cities' live scores, the shared
## progress meter), the countdown, the results, and a pill back to an emergency
## the player stepped away from. Everything shown comes from the server's view;
## only the player's own score is predicted until the server confirms it.

const META := {
	"collection_crisis": {"title": "COLLECTION CENTER NEEDS YOUR HELP!", "facility": "Collection Center", "building": "collection_center",
		"text": "Incoming waste is overwhelming our collection crews. Help route materials before the collection window closes.",
		"go": "ASSIST COLLECTION", "game": "FAST WASTE ROUTING", "reward": "COLLECTION SURGE", "stage": "collection",
		"how": "Drag each item into its bin, or tap it and then the bin.", "badge": "waste", "color": Color("#2a9d8f")},
	"sorting_overload": {"title": "SORTING CENTER NEEDS YOUR HELP!", "facility": "Sorting Center", "building": "sorting_center",
		"text": "A contaminated batch has reached the sorting line. Separate recoverable materials before they are rejected.",
		"go": "ASSIST SORTING", "game": "PRECISION SLICE", "reward": "PRECISION BOOST", "stage": "sorting",
		"how": "Swipe through bottles, cans, cardboard and glass. Never cut greasy packaging, batteries or medical waste.", "badge": "materials", "color": Color("#7b5cd6")},
	"recycling_breakdown": {"title": "RECYCLING PLANT NEEDS YOUR HELP!", "facility": "Recycling Center", "building": "recycling_center",
		"text": "Processing equipment needs urgent maintenance. Stabilize the machinery to keep recovery operations running.",
		"go": "REPAIR MACHINERY", "game": "KEEP THE LINE ALIVE", "reward": "RECOVERY SURGE", "stage": "recycling",
		"how": "Fix the bottleneck first: pull a jammed shredder back along its track, vent the filter into the green, tap the press when the marker is in the green.", "badge": "event", "color": Color("#d9772b")},
}
const STAGE_NAMES := {"collection": "collection", "sorting": "sorting", "recycling": "recycling"}

var session: Session
var view: Dictionary = {}
var _event: Dictionary = {}
var _own: Dictionary = {}
var _dismissed := {}                 # event id -> true: the player chose the city
var _open := ""                      # event id whose minigame is on screen
var _game: EmergencyGame
var _alert: Control
var _shell: Control
var _header: Dictionary = {}
var _pill: Button
var _banner: PanelContainer
var _banner_left := 0.0
var _countdown_last := -1
var _final_warned := false
var _result_shown := ""
var _sent := {}                      # action id -> sent ms, for confirmation delay
var _confirm_ms := -1.0
var _view_gap_ms := -1.0
var _last_view_ms := 0


func _init(s: Session) -> void:
	session = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 25


# ------------------------------------------------------------------- clock ---

## ms since the round's active start, by the server's clock: the last view's tick
## plus the time since it arrived.
func event_ms() -> int:
	if _event.is_empty():
		return -1
	var elapsed := Time.get_ticks_msec() - session.view_ms
	return (int(view.get("tick", 0)) - int(_event.active)) * 1000 + mini(elapsed, 1500)


## The phase by the same clock, so the countdown and the end are smooth.
func phase() -> String:
	if _event.is_empty():
		return ""
	var t := int(view.get("tick", 0)) + float(mini(Time.get_ticks_msec() - session.view_ms, 1500)) / 1000.0
	if str(_event.phase) in ["results", "finalizing", "complete"]:
		return "results"
	if t < float(_event.countdown):
		return "joining"
	if t < float(_event.active):
		return "countdown"
	if t < float(_event.end):
		return "active"
	return "results"


func sent(aid: String) -> void:
	_sent[aid] = Time.get_ticks_msec()


# ----------------------------------------------------------------- refresh ---

func refresh(v: Dictionary) -> void:
	view = v
	var now := Time.get_ticks_msec()
	if _last_view_ms > 0:
		var gap := float(now - _last_view_ms)
		_view_gap_ms = gap if _view_gap_ms < 0 else lerpf(_view_gap_ms, gap, 0.3)
	_last_view_ms = now
	for aid in _sent.keys():
		var a: Dictionary = session.actions.get(aid, {})
		if a.get("status", "") in ["applied", "rejected"]:
			var d := float(int(a.get("done_ms", now)) - int(_sent[aid]))
			_confirm_ms = d if _confirm_ms < 0 else lerpf(_confirm_ms, d, 0.3)
			_sent.erase(aid)
	var ev: Variant = v.get("public", {}).get("emergency")
	_own = v.get("own_city", {}).get("emergency", {}) if v.get("own_city", {}).get("emergency") != null else {}
	if ev == null:
		_event = {}
		_close_game()
		_close_alert()
		_pill_refresh()
		return
	var fresh: bool = _event.get("id", "") != ev.id
	_event = ev
	if fresh:
		_countdown_last = -1
		_final_warned = false
		if UI.music:
			UI.music.sfx("alert")
	var ph := str(ev.phase)
	var open_phase := ph in ["announcement", "joining", "countdown", "active"]
	# The game of this event is on screen: nothing may cover it, whatever the flags say.
	if game_visible() and _shell.get_meta("id", "") == ev.id:
		_open = ev.id
	if _open == ev.id:
		_alert_refresh(false)
		_shell_refresh()
	elif open_phase and not _dismissed.has(ev.id):
		_alert_refresh(true)
	else:
		_close_alert()
	if ph in ["results", "finalizing"] and _open != ev.id and _result_shown != ev.id:
		_result_shown = ev.id
		_announce_result()
	_pill_refresh()


## The player's city owns a finished building of this emergency's stage.
func owns_facility(type: String) -> bool:
	for b in view.get("own_city", {}).get("buildings", []):
		if b.get("type", "") == META[type].building and b.get("status", "") == "complete":
			return true
	return false


# ------------------------------------------------------------------- alert ---

func _alert_refresh(show: bool) -> void:
	if not show:
		_close_alert()
		return
	var m: Dictionary = META[_event.type]
	if _alert == null or not is_instance_valid(_alert) or _alert.get_meta("id", "") != _event.id:
		_close_alert()
		_alert = _build_alert(m)
		_alert.set_meta("id", _event.id)
		add_child(_alert)
	var count: Label = _alert.get_meta("count")
	var dots: HBoxContainer = _alert.get_meta("dots")
	var left := int(_event.active) - int(view.get("tick", 0))
	if str(_event.phase) == "active":
		count.text = "UNDER WAY · %s LEFT" % Catalogue.clock(int(_event.end) - int(view.get("tick", 0)))
	else:
		count.text = "STARTS IN %s" % Catalogue.clock(maxi(left, 0))
	for i in 4:
		var row: Dictionary = _event.leaderboard[i]
		var dot: Control = dots.get_child(i)
		dot.modulate = Color(1, 1, 1, 1.0 if row.joined else 0.3)


func _build_alert(m: Dictionary) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var card := PanelContainer.new()
	var st := UI.box(Color("#14222c"), 20, m.color, 3, 0, Color(), 0)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 24
	card.add_theme_stylebox_override("panel", st)
	var vp := get_viewport_rect().size
	card.custom_minimum_size.x = minf(560.0, vp.x - 60.0)
	center.add_child(card)
	var col := UI.vbox(0)
	card.add_child(col)
	# A striped alert band in the facility's colour.
	var band := PanelContainer.new()
	var bs := UI.box(m.color, 18, Color(), 0, 0, Color(), 10)
	bs.corner_radius_bottom_left = 0
	bs.corner_radius_bottom_right = 0
	band.add_theme_stylebox_override("panel", bs)
	var bh := UI.hbox(10)
	bh.add_child(UI.badge(m.badge, 34))
	var owned := owns_facility(_event.type)
	var where := UI.label(("%s · infrastructure alert" % m.facility) if owned else ("Regional recycling challenge · %s" % STAGE_NAMES[m.stage]), "Value", true)
	where.add_theme_color_override("font_color", Color.WHITE)
	where.add_theme_font_size_override("font_size", 15)
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(where)
	var count := UI.label("", "Value")
	count.add_theme_font_override("font", UI.number_font())
	count.add_theme_color_override("font_color", Color.WHITE)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(count)
	band.add_child(bh)
	col.add_child(band)
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 18 if side != "top" else 14)
	col.add_child(body)
	var inner := UI.vbox(10)
	body.add_child(inner)
	var title := UI.label(m.title, "OnDarkTitle", true)
	title.add_theme_font_size_override("font_size", 24)
	inner.add_child(title)
	inner.add_child(UI.label(m.text, "OnDark", true))
	var reward := PanelContainer.new()
	reward.add_theme_stylebox_override("panel", UI.box(Color(1, 0.84, 0.3, 0.12), 12, Color(1, 0.84, 0.3, 0.5), 1, 0, Color(), 8))
	var rr := UI.hbox(8)
	rr.add_child(UI.label("★", "OnDarkTitle"))
	var pct := int(round((float(_event.multiplier_micro) / 1000000.0 - 1.0) * 100.0))
	var rt := UI.label("Winner: %s · +%d%% %s throughput for %s" % [m.reward, pct, m.stage, Catalogue.clock(int(_event.boost_seconds))], "OnDark", true)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rr.add_child(rt)
	reward.add_child(rr)
	inner.add_child(reward)
	if not owned:
		inner.add_child(UI.label("You have no %s yet: a win still counts, and its boost works once you build one." % m.facility, "OnDarkCaption", true))
	var dots := UI.hbox(6)
	for i in 4:
		var d := PanelContainer.new()
		d.add_theme_stylebox_override("panel", UI.box(m.color if i != session.seat else Color("#ffd257"), 99, Color(), 0, 0, Color(), 4))
		var l := UI.label("You" if i == session.seat else "City %d" % (i + 1), "Small")
		l.add_theme_color_override("font_color", Color.WHITE)
		d.add_child(l)
		dots.add_child(d)
	inner.add_child(UI.hbox(8, [UI.label("Responding:", "OnDarkCaption"), dots]))
	var buttons := UI.hbox(10)
	var later := UI.button("CONTINUE CITY", "GhostButton", "", func(): decline())
	later.custom_minimum_size = Vector2(0, 52)
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := UI.button(m.go, "PrimaryButton", "play", func(): respond())
	go.custom_minimum_size = Vector2(0, 52)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.size_flags_stretch_ratio = 1.4
	buttons.add_child(later)
	buttons.add_child(go)
	inner.add_child(buttons)
	dim.set_meta("count", count)
	dim.set_meta("dots", dots)
	go.call_deferred("grab_focus")
	return dim


func _close_alert() -> void:
	if _alert and is_instance_valid(_alert):
		_alert.queue_free()
	_alert = null


## RESPOND: join on the server and open the minigame at once.
func respond() -> void:
	if _event.is_empty():
		return
	UI.click()
	if not _own.get("joined", false):
		session.act("emergency_join", {"event": _event.id}, "Respond to %s" % META[_event.type].facility, true)
	_open = _event.id
	_close_alert()
	_shell_refresh()


## CONTINUE CITY: the alert goes and does not come back for this event.
func decline() -> void:
	if _event.is_empty():
		return
	UI.click()
	_dismissed[_event.id] = true
	_close_alert()
	_pill_refresh()


## Back to the city while still playing; the pill brings the game back.
func step_away() -> void:
	_close_game()
	_pill_refresh()


func _unhandled_key_input(e: InputEvent) -> void:
	if _alert and is_instance_valid(_alert) and e.is_pressed() and not e.is_echo():
		if e.is_action("ui_cancel"):
			decline()
			accept_event()


# ---------------------------------------------------------------- the game ---

func _shell_refresh() -> void:
	if _shell == null or not is_instance_valid(_shell) or _shell.get_meta("id", "") != _event.id:
		_close_game()
		_open = _event.id
		_build_shell()
		_shell.set_meta("id", _event.id)
		add_child(_shell)
	if _game:
		_game.follow(_event, _own)
	var board: VBoxContainer = _header.board
	UI.clear(board)
	var rows: Array = _event.leaderboard.duplicate()
	rows.sort_custom(func(a, b): return int(a.score) > int(b.score) if int(a.score) != int(b.score) else int(a.city_id) < int(b.city_id))
	for r in rows:
		var me: bool = int(r.city_id) == session.seat
		var line := UI.hbox(6)
		var name := UI.label(("You" if me else "City %d" % (int(r.city_id) + 1)) + ("" if r.joined else " · away"), "Small")
		name.add_theme_color_override("font_color", Color("#ffd257") if me else (Color.WHITE if r.joined else Color(1, 1, 1, 0.45)))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		var sc := UI.label(str(int(r.score)), "Small")
		sc.add_theme_font_override("font", UI.number_font())
		sc.add_theme_color_override("font_color", Color.WHITE)
		line.add_child(sc)
		board.add_child(line)
	var shared := int(_event.shared)
	var goal := maxi(1, _goal())
	(_header.meter as ProgressBar).value = clampf(float(shared) / float(goal), 0.0, 1.0)
	(_header.meter_label as Label).text = "Together: %d recovered" % shared
	if str(_event.phase) in ["results", "finalizing"] and _event.result != null:
		_results()


## Interventions the shared meter fills toward: what one player could do in the round.
func _goal() -> int:
	var c: Dictionary = _event.get("challenge", {})
	return c.get("items", c.get("objects", c.get("faults", []))).size() * 2


func _build_shell() -> void:
	var m: Dictionary = META[_event.type]
	_shell = Control.new()
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.06, 0.08, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.add_child(bg)
	var sm := UI.safe_margins(self)
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", int(sm[0]) + 12)
	frame.add_theme_constant_override("margin_right", int(sm[2]) + 12)
	frame.add_theme_constant_override("margin_top", int(sm[1]) + 8)
	frame.add_theme_constant_override("margin_bottom", int(sm[3]) + 8)
	_shell.add_child(frame)
	var row := UI.hbox(10)
	frame.add_child(row)
	# Left: the game under its header.
	var main := UI.vbox(6)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(main)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UI.box(m.color.darkened(0.35), 14, m.color, 2, 0, Color(), 8))
	var hh := UI.hbox(14)
	head.add_child(hh)
	hh.add_child(UI.badge(m.badge, 32))
	var titles := UI.vbox(0)
	var t1 := UI.label(m.game, "OnDarkTitle")
	t1.add_theme_font_size_override("font_size", 17)
	titles.add_child(t1)
	var t2 := UI.label(m.how, "OnDarkCaption", true)
	t2.add_theme_font_size_override("font_size", 11)
	titles.add_child(t2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(titles)
	var combo := UI.label("", "OnDarkTitle")
	combo.add_theme_color_override("font_color", Color("#ffd257"))
	hh.add_child(combo)
	var score := UI.label("0", "OnDarkTitle")
	score.add_theme_font_override("font", UI.number_font())
	score.add_theme_font_size_override("font_size", 26)
	hh.add_child(UI.vbox(0, [UI.label("SCORE", "OnDarkCaption"), score]))
	var timer := UI.label("0:25", "OnDarkTitle")
	timer.add_theme_font_override("font", UI.number_font())
	timer.add_theme_font_size_override("font_size", 26)
	hh.add_child(UI.vbox(0, [UI.label("TIME", "OnDarkCaption"), timer]))
	main.add_child(head)
	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel", UI.box(Color("#0c1418"), 14, Color(1, 1, 1, 0.1), 1, 0, Color(), 0))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	main.add_child(stage)
	match _event.type:
		"collection_crisis":
			_game = CollectionGame.new()
		"sorting_overload":
			_game = SortingGame.new()
		_:
			_game = RecyclingGame.new()
	_game.setup(_event, _own, self)
	stage.add_child(_game)
	_game.predicted.connect(func(s: int, k: int):
		score.text = str(s)
		combo.text = ("×%d" % k) if k >= 2 else "")
	var over := CenterContainer.new()
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(over)
	var big := UI.label("", "Wordmark")
	big.add_theme_font_size_override("font_size", 72)
	big.add_theme_constant_override("outline_size", 14)
	big.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.08, 0.9))
	over.add_child(big)
	# Right: the four cities, the shared meter, the way back.
	var side := UI.vbox(8)
	side.custom_minimum_size.x = clampf(get_viewport_rect().size.x * 0.2, 180.0, 240.0)
	row.add_child(side)
	var lb := PanelContainer.new()
	lb.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.06), 14, Color(1, 1, 1, 0.1), 1, 0, Color(), 10))
	var lbc := UI.vbox(6)
	lbc.add_child(UI.label("LIVE SCORES", "Chapter"))
	var board := UI.vbox(4)
	lbc.add_child(board)
	lb.add_child(lbc)
	side.add_child(lb)
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size.y = 14
	meter.max_value = 1.0
	meter.add_theme_stylebox_override("fill", UI.box(Color("#3fdc8f"), 99, Color(), 0, 0, Color(), 0))
	meter.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.1), 99, Color(), 0, 0, Color(), 0))
	var meter_label := UI.label("", "OnDarkCaption", true)
	side.add_child(UI.vbox(4, [UI.label("CITIES TOGETHER", "Chapter"), meter, meter_label]))
	side.add_child(UI.spacer(false))
	var diag := UI.label("", "OnDarkCaption", true)
	diag.add_theme_font_size_override("font_size", 10)
	side.add_child(diag)
	var back := UI.button("Back to city", "GhostButton", "", func(): step_away())
	back.custom_minimum_size.y = 48
	side.add_child(back)
	_header = {"score": score, "timer": timer, "combo": combo, "board": board, "meter": meter, "meter_label": meter_label,
		"big": big, "diag": diag, "stage": stage}


func _process(_delta: float) -> void:
	if _shell == null or not is_instance_valid(_shell) or _event.is_empty():
		_banner_tick(_delta)
		return
	var ph := phase()
	var big: Label = _header.big
	var timer: Label = _header.timer
	var active_len := int(_event.end) - int(_event.active)
	var ms := event_ms()
	if ph == "countdown" or ph == "joining":
		var n := int(ceil(float(-ms) / 1000.0))
		big.text = str(n) if n <= 3 else "GET READY"
		big.add_theme_font_size_override("font_size", 72 if n <= 3 else 40)
		if n <= 3 and n != _countdown_last and n > 0:
			_countdown_last = n
			if UI.music:
				UI.music.sfx("countdown")
		timer.text = Catalogue.clock(active_len)
	elif ph == "active":
		if _countdown_last != 0:
			_countdown_last = 0
			big.text = "GO!"
			if UI.music:
				UI.music.sfx("go")
			var tw := big.create_tween()
			tw.tween_interval(0.5)
			tw.tween_callback(func(): if big.text == "GO!": big.text = "")
		var left := maxi(0, active_len * 1000 - ms)
		timer.text = "0:%02d" % int(ceil(float(left) / 1000.0))
		timer.add_theme_color_override("font_color", Color("#ff6b5e") if left < 5000 else Color.WHITE)
		if left < 5000 and not _final_warned:
			_final_warned = true
			if UI.music:
				UI.music.sfx("final")
	elif _event.result == null and not (_header.stage as Control).has_meta("results"):
		big.text = "TIME!"
		timer.text = "0:00"
	if Settings.diagnostics:
		var l: Link = session.link
		(_header.diag as Label).text = "Measured · RTT %d ms · jitter %d ms\nview every %s · age %d ms · score confirmed in %s\n%s" % [
			int(l.rtt_avg_ms), int(l.jitter_ms), ("%d ms" % int(_view_gap_ms)) if _view_gap_ms >= 0 else "–",
			Time.get_ticks_msec() - session.view_ms, ("%d ms" % int(_confirm_ms)) if _confirm_ms >= 0 else "–",
			"in sync" if session.live else "reconnecting"]
	else:
		(_header.diag as Label).text = "" if session.live else "Reconnecting…"


## The round is over: final ranking, the winner and the boost.
func _results() -> void:
	var stage: PanelContainer = _header.stage
	if stage.has_meta("results"):
		return
	stage.set_meta("results", true)
	(_header.big as Label).text = ""
	var res: Dictionary = _event.result
	var m: Dictionary = META[_event.type]
	var won := int(res.winner) == session.seat
	if UI.music:
		UI.music.sfx("victory" if won else "defeat")
		if won:
			UI.music.sfx("boost")
	var cover := ColorRect.new()
	cover.color = Color(0.03, 0.06, 0.08, 0.82)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.box(Color("#14222c"), 18, META[_event.type].color, 2, 0, Color(), 22))
	card.custom_minimum_size.x = minf(520.0, stage.size.x - 40.0)
	center.add_child(card)
	var col := UI.vbox(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	var head := UI.label("YOU WIN!" if won else ("NO WINNER" if int(res.winner) < 0 else "CITY %d WINS" % (int(res.winner) + 1)), "Wordmark")
	head.add_theme_font_size_override("font_size", 44)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var pct := int(round((float(_event.multiplier_micro) / 1000000.0 - 1.0) * 100.0))
	var line := "%s: +%d%% %s throughput for %s" % [m.reward, pct, m.stage, Catalogue.clock(int(_event.boost_seconds))]
	if int(res.winner) < 0:
		line = "Nobody scored: no boost this time."
	elif won and not owns_facility(_event.type):
		line += "\nBuild a %s to use it." % m.facility
	var rl := UI.label(line, "OnDarkTitle", true)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_color_override("font_color", Color("#ffd257") if won else Color.WHITE)
	col.add_child(rl)
	var rank := 1
	for id in res.ranking:
		var r: Dictionary = _event.leaderboard[int(id)]
		col.add_child(UI.label("%d.  %s  ·  %d pts  ·  %d right, %d wrong" % [rank, "You" if int(id) == session.seat else "City %d" % (int(id) + 1),
			int(r.score), int(r.correct), int(r.wrong)], "OnDark"))
		rank += 1
	col.add_child(UI.label("Together the cities recovered %d items." % int(res.shared), "OnDarkCaption"))
	var back := UI.button("Back to city", "PrimaryButton", "check", func(): step_away())
	back.custom_minimum_size = Vector2(220, 50)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(back)
	# A short pop of the headline; the rest is there at once.
	head.pivot_offset = Vector2(200, 30)
	head.scale = Vector2(1.3, 1.3)
	head.create_tween().tween_property(head, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_game() -> void:
	if _shell and is_instance_valid(_shell):
		_shell.queue_free()
	_shell = null
	_game = null
	_header = {}
	_open = ""


# ------------------------------------------------------------ pill, banner ---

## While the player is in an emergency but on the city, a pill brings it back.
func _pill_refresh() -> void:
	var show: bool = not _event.is_empty() and _own.get("joined", false) and _open != _event.id and str(_event.phase) in ["countdown", "joining", "announcement", "active"]
	var undecided: bool = not _event.is_empty() and _dismissed.has(_event.id) and not _own.get("joined", false) and str(_event.phase) in ["announcement", "joining", "countdown", "active"]
	if not show and not undecided:
		if _pill and is_instance_valid(_pill):
			_pill.queue_free()
		_pill = null
		return
	if _pill == null or not is_instance_valid(_pill):
		_pill = UI.button("", "PrimaryButton", "play", func(): respond())
		_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_pill.offset_top = 110 + UI.safe_margins(self)[1]
		_pill.custom_minimum_size.y = 44
		add_child(_pill)
	var m: Dictionary = META[_event.type]
	_pill.text = ("Return to %s" if show else "Join %s") % m.game.capitalize()


## Players who did not take part learn the outcome in a short banner.
func _announce_result() -> void:
	var res: Variant = _event.result
	if res == null:
		return
	var m: Dictionary = META[_event.type]
	var text := "%s over: %s" % [m.game.capitalize(), "no winner" if int(res.winner) < 0 else ("you won %s!" % m.reward if int(res.winner) == session.seat else "City %d won %s" % [int(res.winner) + 1, m.reward])]
	if _banner == null or not is_instance_valid(_banner):
		_banner = PanelContainer.new()
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_banner.offset_top = 110 + UI.safe_margins(self)[1]
		add_child(_banner)
	_banner.add_theme_stylebox_override("panel", UI.box(Color(m.color.darkened(0.3), 0.94), 12, m.color, 1, 0, Color(), 10))
	UI.clear(_banner)
	var l := UI.label(text, "HudSmall")
	_banner.add_child(l)
	_banner_left = 5.0


func _banner_tick(delta: float) -> void:
	if _banner and is_instance_valid(_banner):
		_banner_left -= delta
		if _banner_left <= 0.0:
			_banner.queue_free()
			_banner = null


## Tests only.
func alert_visible() -> bool:
	return _alert != null and is_instance_valid(_alert)


func game_visible() -> bool:
	return _shell != null and is_instance_valid(_shell)


func game() -> EmergencyGame:
	return _game
