class_name RecyclingGame
extends EmergencyGame
## RECYCLING BREAKDOWN · keep the line alive. SHREDDER -> FILTER -> PRESS run as one
## line whose efficiency is that of its weakest stage. Faults arrive on the server's
## schedule: shredder jams (drag the rollers back along the jam's release track),
## filter pressure (pick the valve that lands it in the green band without
## overcorrecting), press drift (tap while the calibration marker is in the safe
## band). The plant model is the server's own file: the last server state plus the
## player's unconfirmed actions, replayed to now, is what the screen shows.

const Plant = preload("res://scripts/ui/emergency/plant_model.gd")
const NAMES := ["SHREDDER", "FILTER", "PRESS"]
const DIRS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var _base: Dictionary = {}           # the server's last state of this player's line
var _local: Array = []               # [machine, answer, t_ms, action id] not yet in the base
var _now: Dictionary = {}            # the line as shown this frame
var _drag := {}
var _spin := 0.0
var _flow := 0.0
var _glow := [0.0, 0.0, 0.0]
var _bad := [0.0, 0.0, 0.0]
var _alarm := {}                     # cue -> true while its condition lasts
var _note := {}                      # {text, life} under the line meter
var repaired := 0                    # tests only: correct local interventions


func setup(event: Dictionary, own: Dictionary, host: Node) -> void:
	super.setup(event, own, host)
	_base = (own.get("plant") as Dictionary).duplicate(true) if own.get("plant") != null else Plant.new_state()


func follow(event: Dictionary, own: Dictionary) -> void:
	super.follow(event, own)
	if own.get("plant") != null:
		_base = (own.plant as Dictionary).duplicate(true)
	var sim := int(_base.sim_ms)
	_local = _local.filter(func(a):
		var st: String = layer.session.actions.get(a[3], {}).get("status", "rejected")
		return st in ["sending", "queued"] or (st == "applied" and int(a[2]) >= sim))


func _faults() -> Array:
	return ev.get("challenge", {}).get("faults", [])


func _p() -> Dictionary:
	return ev.get("challenge", {}).get("params", {})


func _sc() -> Dictionary:
	return ev.get("scoring", {})


## The line now: the server's state, the player's own unconfirmed actions, then time.
func _predict(to_ms: int) -> Dictionary:
	var s: Dictionary = _base.duplicate(true)
	if _p().is_empty():
		return s
	var acts: Array = _local.duplicate()
	acts.sort_custom(func(a, b): return int(a[2]) < int(b[2]))
	for a in acts:
		if int(a[2]) >= int(s.sim_ms):
			Plant.advance(s, _faults(), _p(), _sc(), int(a[2]))
			Plant.act(s, _p(), int(a[0]), int(a[1]), int(a[2]))
	Plant.advance(s, _faults(), _p(), _sc(), clampi(to_ms, 0, int(_p().get("active_ms", 25000))))
	return s


func score() -> int:
	return Plant.score(_now, _sc()) if not _now.is_empty() and not _sc().is_empty() else _confirmed


func streak() -> int:
	return int(_now.get("high_ms", 0)) / 1000 if not _now.is_empty() else 0


func _machine(i: int) -> Rect2:
	var top := size.y * 0.22
	var w := size.x / 3.0
	return Rect2(w * i + 10, top, w - 20, size.y - top - 10)


func tick(delta: float) -> void:
	_now = _predict(now_ms())
	if _now.is_empty() or _p().is_empty():
		return
	var e: Array = Plant.efficiency(_now, _p())
	_spin += delta * 6.0 * float(e[0]) / 1000.0
	_flow += delta * float(e[3]) / 1000.0
	for i in 3:
		_glow[i] = maxf(0.0, _glow[i] - delta * 1.5)
		_bad[i] = maxf(0.0, _bad[i] - delta * 2.0)
	if not _note.is_empty():
		_note.life -= delta
		if _note.life <= 0.0:
			_note = {}
	if not active():
		return
	# One cue per change of state, never a wall of alarms.
	_cue("jam", int(_now.jam_dir) >= 0, "jam")
	_cue("pressure", int(_now.pressure) > int(_p().green_max), "pressure")
	_cue("drift", int(_now.drift) != 0, "misalign")
	var line := int(_now.line)
	if line < 300 and not _alarm.get("critical", false):
		_alarm["critical"] = true
		sound("critical")
	elif line >= 900 and _alarm.get("critical", false):
		_alarm["critical"] = false
		sound("recover")


func _cue(key: String, on: bool, sfx: String) -> void:
	if on and not _alarm.get(key, false):
		sound(sfx)
	_alarm[key] = on


func _gui_input(e: InputEvent) -> void:
	if not active():
		_drag = {}
		return
	var pos: Vector2
	if e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		pos = e.position
		accept_event()
		if e.pressed:
			if _machine(0).has_point(pos):
				_drag = {"from": pos, "to": pos}
			elif _machine(1).has_point(pos):
				for v in 3:
					if _valve_rect(v).grow(6).has_point(pos):
						intervene(1, v)
			elif _machine(2).has_point(pos):
				intervene(2, 0)
		elif not _drag.is_empty():
			var d: Vector2 = pos - _drag.from
			if d.length() > 16.0:
				var dir := (1 if d.x > 0 else 3) if absf(d.x) > absf(d.y) else (2 if d.y > 0 else 0)
				var dist := clampi(int(d.length() / _track_scale() * 1000.0), 0, 999)
				intervene(0, dir * 1000 + dist)
			_drag = {}
	elif (e is InputEventScreenDrag or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT)) and not _drag.is_empty():
		accept_event()
		_drag.to = e.position


## One intervention: judged at once on the predicted line, sent to the server
## unless there is nothing to fix (the server would refuse it anyway).
func intervene(machine: int, answer: int) -> void:
	var ms := now_ms()
	var probe: Dictionary = _predict(ms)
	var outcome: String = Plant.act(probe, _p(), machine, answer, ms)
	var c := _machine(machine).get_center()
	if outcome in ["no_fault", "invalid_choice"]:
		_note = {"text": "%s is fine: nothing to fix" % NAMES[machine].capitalize(), "life": 1.2}
		sound("partial")
		return
	var aid: String = layer.session.act("emergency_repair", {"event": ev["id"], "machine": machine, "answer": answer, "t_ms": ms}, "Emergency action", true)
	if aid != "":
		_local.append([machine, answer, ms, aid])
		layer.sent(aid)
	match outcome:
		"correct":
			repaired += 1
			_glow[machine] = 1.0
			pop(c, "+%d" % int(_sc().get("correct", 15)), true)
			sparks(c, Color("#ffd257"), 18)
			sound("repair")
			UI.haptic(15)
		"partial":
			pop(c, "not enough", true)
			sound("partial")
		_:
			_bad[machine] = 1.0
			pop(c, "−%d" % int(_sc().get("incorrect", 10)), false)
			flash(Color("#ff3b30"))
			sound("wrong")
			UI.haptic(40)


## Pixels for a release distance of 1000: the track always fits inside the shredder.
func _track_scale() -> float:
	var r := _machine(0)
	return maxf(minf(r.size.x, r.size.y) * 0.75, 1.0)


func _valve_rect(v: int) -> Rect2:
	var r := _machine(1)
	var w := (r.size.x - 40) / 3.0
	return Rect2(r.position.x + 14 + v * (w + 6), r.end.y - 64, w, 54)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color("#161c21"))
	if _now.is_empty() or _p().is_empty():
		return
	var e: Array = Plant.efficiency(_now, _p())
	var line := int(e[3])
	var ms := now_ms()
	var font := UI.font(500)
	var nums := UI.number_font()
	# Line efficiency: the headline figure, coloured by state; the bottleneck named.
	var col := Color("#3fdc8f") if line >= 800 else (Color("#f2b33d") if line >= 400 else Color("#ff4b3e"))
	var top := h * 0.2
	draw_rect(Rect2(0, 0, w, top), Color("#0f1418"))
	draw_string(font, Vector2(14, top * 0.4), "LINE EFFICIENCY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
	draw_string(nums, Vector2(14, top * 0.92), "%d%%" % int(round(line / 10.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(top * 0.5), col)
	var bar := Rect2(w * 0.24, top * 0.55, w * 0.5, 14)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * line / 1000.0, bar.size.y)), col)
	var worst := 0
	for i in 3:
		if e[i] < e[worst]:
			worst = i
	if e[worst] < 1000:
		draw_string(font, Vector2(bar.position.x, top * 0.4), "BOTTLENECK: %s" % NAMES[worst], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color("#ff8a7a") if e[worst] < 400 else Color("#f2c14a"))
	var up := int(_now.high_ms) / 1000
	if up >= 2:
		draw_string(font, Vector2(w * 0.78, top * 0.62), "UPTIME %ds" % up, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#69e0b4"))
	if not _note.is_empty():
		draw_string(UI.font(400), Vector2(w * 0.24, top * 0.95), _note.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, clampf(_note.life, 0.0, 1.0)))
	# Pipes with material flowing at the line's speed.
	for i in 2:
		var a := _machine(i)
		var b := _machine(i + 1)
		var y := a.position.y + a.size.y * 0.42
		draw_rect(Rect2(a.end.x - 8, y - 10, b.position.x - a.end.x + 16, 20), Color("#2f3b45"))
		var feed := float(e[i]) / 1000.0
		var k := fmod(_flow * 3.0, 1.0)
		for n in 3:
			var fx := a.end.x - 8 + (b.position.x - a.end.x + 16) * fmod(k + n / 3.0, 1.0)
			draw_circle(Vector2(fx, y), 5.0, Color(0.6, 0.85, 0.5, 0.25 + 0.6 * feed))
	for i in 3:
		_draw_machine(i, e[i], ms, font, nums)


func _draw_machine(i: int, eff: int, ms: int, font: Font, nums: Font) -> void:
	var p := _p()
	var r := _machine(i)
	var state := "ok" if eff >= 800 else ("warn" if eff >= 400 else "bad")
	var shake := Vector2.ZERO
	if state != "ok" and active():
		shake = Vector2(sin(float(ms) / 23.0), cos(float(ms) / 31.0)) * (1.5 if state == "warn" else 3.0)
	var body := Rect2(r.position + shake, r.size)
	draw_rect(Rect2(body.position + Vector2(4, 6), body.size), Color(0, 0, 0, 0.3))
	draw_rect(body, Color("#26313a"))
	var light := Color("#3fdc8f") if state == "ok" else (Color("#f2b33d") if state == "warn" else Color("#ff4b3e"))
	draw_rect(Rect2(body.position, Vector2(body.size.x, 34)), light.darkened(0.55))
	draw_circle(body.position + Vector2(18, 17), 7, light)
	draw_string(font, body.position + Vector2(32, 24), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(nums, body.position + Vector2(body.size.x - 58, 24), "%d%%" % int(round(eff / 10.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, light.lightened(0.3))
	if _glow[i] > 0.0:
		draw_rect(body, Color(0.25, 1.0, 0.6, 0.22 * _glow[i]))
	if _bad[i] > 0.0:
		draw_rect(body, Color(1.0, 0.25, 0.2, 0.28 * _bad[i]))
	var c := body.position + Vector2(body.size.x / 2.0, body.size.y * 0.42)
	var big := minf(body.size.x, body.size.y) * 0.17
	match i:
		0:
			# Two rollers; jammed, they stall with a lodged item, and a release track
			# shows which way and how far to pull them back.
			var jam := int(_now.jam_dir)
			for side in [-1.0, 1.0]:
				var g := c + Vector2(side * big * 0.75, 0)
				draw_circle(g, big * 0.7, Color("#56646e"))
				for t in 8:
					var ang: float = _spin * side + TAU * t / 8.0
					draw_line(g + Vector2(cos(ang), sin(ang)) * big * 0.42, g + Vector2(cos(ang), sin(ang)) * big * 0.85, Color("#9aa9b4"), 6)
				draw_circle(g, big * 0.2, Color("#26313a"))
			if jam >= 0:
				var dir: Vector2 = DIRS[jam]
				var length: float = float(_now.jam_dist) / 1000.0 * _track_scale()
				var end := c + dir * length
				draw_line(c, end, Color(1, 0.8, 0.3, 0.28), 22.0)
				draw_circle(end, 15, Color(1, 0.8, 0.3, 0.35 + 0.25 * sin(float(ms) / 110.0)))
				draw_arc(end, 15, 0, TAU, 20, Color(1, 0.85, 0.4, 0.9), 2.0)
				WasteArt.draw(self, "mixed_waste", c - dir * big * 0.25, big * 1.2, sin(float(ms) / 60.0) * 0.15)
				_meter(body, "LOAD", clampf(1.0 - float(_now.buffer_ms) / float(p.buffer_ms), 0.0, 1.0), Color("#ff4b3e"))
				if not _drag.is_empty():
					draw_line(_drag.from, _drag.to, Color(1, 1, 1, 0.6), 5.0)
			else:
				_meter(body, "LOAD", 0.15, Color("#3fdc8f"))
		1:
			# Pressure gauge and its bands; ghost marks show where each valve lands it.
			var rad := big * 1.25
			var gc := c + Vector2(0, -big * 0.1)
			draw_circle(gc, rad, Color("#e9eef2"))
			var green := float(p.green_max) / 1000.0
			var red := float(p.red_min) / 1000.0
			_band(gc, rad * 0.86, 0.0, green, Color("#3fdc8f"))
			_band(gc, rad * 0.86, green, red, Color("#f2b33d"))
			_band(gc, rad * 0.86, red, 1.0, Color("#ff4b3e"))
			var pr := float(_now.pressure) / 1000.0
			var hot := int(_now.pressure) > int(p.green_max)
			var amounts := [int(p.valve_small), int(p.valve_medium), int(p.valve_large)]
			if hot:
				for v in 3:
					var la := _gauge_angle(maxf(0.0, pr - float(amounts[v]) / 1000.0))
					draw_line(gc + Vector2(cos(la), sin(la)) * rad * 0.62, gc + Vector2(cos(la), sin(la)) * rad * 0.98, Color("#2f7fd6", 0.9), 3)
					draw_string(font, gc + Vector2(cos(la), sin(la)) * rad * 0.48 - Vector2(4, -4), ["S", "M", "L"][v], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#2f7fd6"))
			var na := _gauge_angle(pr)
			draw_line(gc, gc + Vector2(cos(na), sin(na)) * rad * 0.8, Color("#d9302a"), 4)
			draw_circle(gc, 6, Color("#26313a"))
			if ms < int(_now.block_until):
				draw_string(font, body.position + Vector2(14, body.size.y * 0.7), "BLOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ff4b3e"))
			for v in 3:
				var vr := _valve_rect(v)
				draw_rect(vr, Color("#2f7fd6") if hot else Color("#3b4954"))
				draw_rect(Rect2(vr.position, Vector2(vr.size.x, 4)), Color(1, 1, 1, 0.25))
				var t1: String = ["SMALL", "MEDIUM", "LARGE"][v]
				var fsz := int(clampf(vr.size.x / 7.0, 10.0, 14.0))
				draw_string(font, Vector2(vr.get_center().x - font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x / 2.0, vr.position.y + 22), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color.WHITE)
				var t2 := "−%d" % (amounts[v] / 10)
				draw_string(nums, Vector2(vr.get_center().x - nums.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / 2.0, vr.position.y + 42), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
		2:
			# The press head moves at its efficiency; below, alignment and calibration.
			var speed := float(eff) / 1000.0
			var stroke := (sin(float(ms) / 180.0 * maxf(speed, 0.1)) * 0.5 + 0.5) * big * 0.7
			draw_rect(Rect2(c.x - big * 0.18, c.y - big * 1.2, big * 0.36, big * 0.5 + stroke), Color("#9aa9b4"))
			draw_rect(Rect2(c.x - big * 0.9, c.y - big * 0.7 + stroke, big * 1.8, big * 0.4), Color("#c9d2d9"))
			draw_rect(Rect2(c.x - big * 1.1, c.y + big * 0.45, big * 2.2, big * 0.3), Color("#56697a"))
			var g := Rect2(body.position.x + 16, body.end.y - 58, body.size.x - 32, 22)
			draw_rect(g, Color("#11181d"))
			var band := float(Plant.press_band(p, ms)) / 1000.0
			draw_rect(Rect2(g.position.x + g.size.x * (0.5 - band), g.position.y, g.size.x * band * 2.0, g.size.y), Color("#3fdc8f", 0.85))
			var off := absi(int(_now.align) - 500) > int(p.align_ok)
			draw_rect(Rect2(g.position.x + g.size.x * float(_now.align) / 1000.0 - 3, g.position.y - 12, 6, 10), Color("#f2b33d") if off else Color("#3fdc8f"))
			if off or int(_now.drift) != 0:
				var mk := g.position.x + g.size.x * float(Plant.marker(p, ms)) / 1000.0
				draw_rect(Rect2(mk - 5, g.position.y - 6, 10, g.size.y + 12), Color("#ffd257"))
				draw_string(font, Vector2(g.position.x, g.end.y + 18), "TAP WHEN THE MARKER IS IN THE GREEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd257"))
			else:
				draw_string(UI.font(400), Vector2(g.position.x, g.end.y + 18), "aligned", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))


## A small vertical meter in a machine's corner.
func _meter(body: Rect2, label: String, value: float, color: Color) -> void:
	var m := Rect2(body.end.x - 22, body.position.y + 48, 10, body.size.y * 0.4)
	draw_rect(m, Color(1, 1, 1, 0.08))
	draw_rect(Rect2(m.position.x, m.end.y - m.size.y * value, m.size.x, m.size.y * value), color)
	draw_string(UI.font(400), Vector2(m.position.x - 18, m.end.y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))


func _gauge_angle(v: float) -> float:
	return PI * 0.75 + clampf(v, 0.0, 1.0) * PI * 1.5


func _band(c: Vector2, r: float, a: float, b: float, col: Color) -> void:
	draw_arc(c, r, _gauge_angle(a), _gauge_angle(b), 16, col, 8.0)
