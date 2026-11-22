extends SceneTree
## Scratch: three collection rounds; logs the clock and which items each frame draws.
var app: Node
var s: Session
var step := 0
var t := 0.0
var round_no := 0
var log_t := 0.0
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1170, 540))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
func ev() -> Dictionary:
	var e: Variant = s.view.get("public", {}).get("emergency")
	return e if e != null else {}
func _process(delta: float) -> bool:
	t += delta
	if s == null and app.session != null:
		s = app.session; s.store = "user://probe.cfg"; s._forget_seat()
	match step:
		0:
			if t > 1.0: s.create(OS.get_cmdline_user_args()[0]); step = 1
		1:
			if s.phase == "lobby" and s.join_code != "": s.set_ready(true); step = 2; t = 0
		2:
			if t > 0.5: s.start_match(); step = 3
		3:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty(): s.choose_foundation("circular_foundation")
			if s.phase == "play" and app.play: step = 4
		4:
			var L: EmergencyLayer = app.play.emergency
			if L.alert_visible(): L.respond(); step = 5
		5:
			var L: EmergencyLayer = app.play.emergency
			var g: Variant = L.game() if L.game_visible() else null
			log_t += delta
			if g and log_t > 0.5:
				log_t = 0
				var ms: int = g.now_ms()
				var expected := []
				for it in g._items():
					if g._item_pos(it, ms) != null and not g.done.has(int(it.id)): expected.append(int(it.id))
				if ms > 0 and int(ms / 3000) != int((ms - 500) / 3000):
					root.get_texture().get_image().save_png("C:/Users/medaz/AppData/Local/Temp/claude/3e1ba1278d24cbfd/6366a5a0-7d07-4f57-8da6-a7de6125e643/scratchpad/probe_%05d.png" % ms)
				print("R%d tick=%s ms=%d phase=%s on_belt=%s drawn_total=%d size=%s" % [round_no, str(s.view.get("tick")), ms, L.phase(), str(expected), g.drawn.size(), str(g.size)])
			if str(ev().get("phase", "")) == "results" and g:
				var never := []
				for it in g._items():
					if int(it.spawn_ms) < 24000 and not g.drawn.has(int(it.id)) and not g.done.has(int(it.id)): never.append(int(it.id))
				print("R%d END items=%d drawn=%d never_drawn=%s" % [round_no, g._items().size(), g.drawn.size(), str(never)])
				step = 6
		6:
			if ev().is_empty():
				round_no += 1
				if round_no >= 1: quit()
				step = 4
	return false
