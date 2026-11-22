class_name EmergencyGame
extends Control
## What the three ECO EMERGENCIES minigames share: the event clock, sending a
## validated action, the locally predicted score that the server's score corrects,
## and quick feedback (floating points, sparks, a flash). Each game draws itself
## and turns input into actions; it never decides a score on its own.

signal predicted(score: int, streak: int)

var layer: Node                     # EmergencyLayer: clock and session
var ev: Dictionary = {}             # the event as the server sent it
var done := {}                      # ids this player already acted on
var _pending := []                  # [action id, score delta, streak after]
var _confirmed := 0                 # the server's score for this player
var _streak := 0
var _display := 0.0                 # the score shown, easing to its target
var _fx: FxLayer


func setup(event: Dictionary, own: Dictionary, host: Node) -> void:
	layer = host
	ev = event
	for id in own.get("done", []):
		done[int(id)] = true
	_confirmed = int(own.get("score", 0))
	_streak = int(own.get("streak", 0))
	_display = _confirmed
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fx = FxLayer.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)


## A new authoritative view: refresh the challenge-independent figures.
func follow(event: Dictionary, own: Dictionary) -> void:
	ev = event
	_confirmed = int(own.get("score", 0))
	_streak = int(own.get("streak", 0))
	for id in own.get("done", []):
		done[int(id)] = true
	_pending = _pending.filter(func(p): return layer.session.actions.get(p[0], {}).get("status", "rejected") in ["sending", "queued"])


## ms since the round started, by the server's clock.
func now_ms() -> int:
	return layer.event_ms()


func active() -> bool:
	return layer.phase() == "active" and now_ms() >= 0 and now_ms() < int(ev.get("end", 0) - ev.get("active", 0)) * 1000


## The score to show: the server's, plus actions it has not confirmed yet.
func score() -> int:
	var s := _confirmed
	for p in _pending:
		s = maxi(0, s + int(p[1]))
	return s


func streak() -> int:
	return int(_pending[-1][2]) if not _pending.is_empty() else _streak


## Sends one action and predicts its outcome with the server's rules.
## kind: "correct", "incorrect" or "hazard".
func send(command: String, payload: Dictionary, outcome: String) -> void:
	var rules: Dictionary = ev.get("scoring", {})
	var s := streak()
	var delta := 0
	if outcome == "correct":
		s += 1
		delta = int(rules.get("correct", 10)) + (int(rules.get("streak_bonus", 0)) if s % maxi(1, int(rules.get("streak", 5))) == 0 else 0)
	else:
		s = 0
		delta = -int(rules.get("hazard" if outcome == "hazard" else "incorrect", 10))
	payload["event"] = ev["id"]
	var aid: String = layer.session.act(command, payload, "Emergency action", true)
	if aid != "":
		_pending.append([aid, delta, s])
		layer.sent(aid)
	if outcome == "correct" and s > 0 and s % maxi(1, int(rules.get("streak", 5))) == 0:
		combo(s)


func _process(delta: float) -> void:
	_display = lerpf(_display, float(score()), clampf(delta * 10.0, 0.0, 1.0))
	predicted.emit(int(round(_display)), streak())
	tick(delta)
	queue_redraw()
	_fx.queue_redraw()


## Per-frame game logic; overridden.
func tick(_delta: float) -> void:
	pass


# ------------------------------------------------------------------ feedback ---

func pop(at: Vector2, text: String, good: bool) -> void:
	_fx.floats.append({"at": at, "text": text, "color": Color("#3fdc8f") if good else Color("#ff6b5e"), "life": 1.0})


func sparks(at: Vector2, color: Color, n := 14) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(120.0, 340.0)
		_fx.parts.append({"at": at, "v": v, "life": randf_range(0.35, 0.7), "color": color, "size": randf_range(3.0, 7.0)})


func flash(color: Color) -> void:
	_fx.flash = Color(color, 0.32)


func combo(n: int) -> void:
	_fx.combo = {"text": "COMBO ×%d" % n, "life": 1.2}
	if UI.music:
		UI.music.sfx("combo")


func sound(kind: String) -> void:
	if UI.music:
		UI.music.sfx(kind)


## Feedback drawn above the game: points, sparks, a screen flash, combo banners.
class FxLayer:
	extends Control
	var floats: Array = []
	var parts: Array = []
	var flash := Color(0, 0, 0, 0)
	var combo := {}

	func _process(delta: float) -> void:
		for f in floats:
			f.life -= delta
			f.at += Vector2(0, -60.0 * delta)
		floats = floats.filter(func(f): return f.life > 0.0)
		for p in parts:
			p.life -= delta
			p.at += p.v * delta
			p.v *= 0.9
			p.v.y += 500.0 * delta
		parts = parts.filter(func(p): return p.life > 0.0)
		flash.a = maxf(0.0, flash.a - delta * 1.4)
		if not combo.is_empty():
			combo.life -= delta
			if combo.life <= 0.0:
				combo = {}

	func _draw() -> void:
		if flash.a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), flash)
		for p in parts:
			draw_circle(p.at, p.size * clampf(p.life * 2.0, 0.2, 1.0), Color(p.color, clampf(p.life * 2.0, 0.0, 1.0)))
		var font := UI.number_font()
		for f in floats:
			var a: float = clampf(float(f.life) * 1.5, 0.0, 1.0)
			var at: Vector2 = f.at - Vector2(font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x / 2.0, 0)
			draw_string_outline(font, at, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color(0.05, 0.08, 0.1, a))
			draw_string(font, at, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(f.color, a))
		if not combo.is_empty():
			var k: float = clampf(float(combo.life), 0.0, 1.0)
			var s: float = 44.0 + (1.2 - float(combo.life)) * 30.0
			var at := Vector2(size.x / 2.0, size.y * 0.32)
			var pf := UI.font(500)
			var w: float = pf.get_string_size(combo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s)).x
			draw_string_outline(pf, at - Vector2(w / 2.0, 0), combo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s), 12, Color(0.05, 0.08, 0.1, k))
			draw_string(pf, at - Vector2(w / 2.0, 0), combo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s), Color(1.0, 0.85, 0.25, k))
