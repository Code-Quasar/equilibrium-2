extends SceneTree
## ECO EMERGENCIES in the real app against a server started in developer mode
## with a fixed schedule (collection at 25 s, sorting at 75 s, recycling at 125 s):
## the alert, responding and declining, playing each minigame with real mouse
## input, the results, the boost badge, and no minigame left behind. Saves a
## screenshot of each step.
##
##   godot --headless --path . --script server/main.gd -- --port 9082 \
##       --dev-emergencies collection_crisis@25,sorting_overload@75,recycling_breakdown@125
##   godot --path client/godot --script res://tests/emergencies.gd -- ws://127.0.0.1:9082 /tmp/shots 1170x540

var app: Node
var s: Session
var url := "ws://127.0.0.1:9082"
var out := "/tmp/shots"
var size := Vector2i(1170, 540)
var step := 0
var t := 0.0
var fails := 0
var played := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: url = args[0]
	if args.size() > 1: out = args[1]
	if args.size() > 2:
		var p := args[2].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(size)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)


func ok(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		fails += 1


func shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s_%dx%d.png" % [out, name, size.x, size.y])


func layer() -> EmergencyLayer:
	return app.play.emergency if app.play else null


func event() -> Dictionary:
	var e: Variant = s.view.get("public", {}).get("emergency")
	return e if e != null else {}


func go(n: int) -> void:
	step = n
	t = 0.0


## A real mouse gesture through the viewport, from a to z in the game's local space.
func drag(game: Control, a: Vector2, z: Vector2) -> void:
	# Game coordinates -> window coordinates (the window may be scaled).
	var g := root.get_final_transform() * game.get_global_transform()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = g * a; press.global_position = press.position
	Input.parse_input_event(press)
	for i in range(1, 7):
		var mm := InputEventMouseMotion.new()
		mm.position = g * a.lerp(z, i / 6.0); mm.global_position = mm.position; mm.relative = (z - a) / 6.0; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = g * z; up.global_position = up.position
	Input.parse_input_event(up)


func _process(delta: float) -> bool:
	t += delta
	if s == null and app.session != null:
		s = app.session
		s.store = "user://emergencies_test.cfg"
		s._forget_seat()
	match step:
		0:
			if t > 1.0:
				s.create(url)
				go(1)
		1:
			if s.phase == "lobby" and s.join_code != "":
				s.set_ready(true)
				go(2)
		2:
			if t > 0.5:
				s.start_match()
				go(3)
		3:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
				s.choose_foundation("circular_foundation")
			if s.phase == "play" and layer() != null:
				go(4)
		# ---- Collection Crisis: respond and play.
		4:
			if layer().alert_visible():
				ok(event().get("type", "") == "collection_crisis", "the collection emergency is announced to the player")
				go(5)
		5:
			if t > 0.6:
				shot("e1_alert")
				layer().respond()
				go(6)
		6:
			if layer().game_visible() and t > 0.5:
				shot("e2_countdown")
				ok(layer().game() is CollectionGame, "responding opens the collection minigame")
				go(7)
		7:
			var game: CollectionGame = layer().game()
			if game and game.active():
				var ms := game.now_ms()
				for item in game._items():
					if game.done.has(int(item.id)):
						continue
					var p: Variant = game._item_pos(item, ms)
					if p == null or (p as Vector2).x < 60 or (p as Vector2).x > game.size.x - 60:
						continue
					var bin: int = CollectionGame.CATEGORY[str(item.kind)]
					drag(game, p, game._bin_rect(bin).get_center())
					played += 1
					break
				if played >= 4 and t > 2.0:
					shot("e3_collection")
					go(8)
		8:
			var game: CollectionGame = layer().game() if layer().game_visible() else null
			if game and game.active():
				# Keep routing until the round ends.
				var ms := game.now_ms()
				for item in game._items():
					if not game.done.has(int(item.id)) and game._item_pos(item, ms) != null and t > 0.5:
						game.route(int(item.id), CollectionGame.CATEGORY[str(item.kind)])
						t = 0.0
						break
			if str(event().get("phase", "")) == "results" and t > 1.6:
				shot("e4_results")
				var res: Dictionary = event().get("result", {})
				ok(int(res.get("winner", -1)) == s.seat, "the only player who scored wins")
				ok(int(event().leaderboard[s.seat].score) > 0, "the server scored the routed items")
				go(9)
		9:
			if not s.view.get("own_city", {}).get("boosts", []).is_empty() and app.play._boost.visible:
				layer().step_away()
				go(10)
		10:
			if t > 0.8:
				shot("e5_boost_badge")
				ok(app.play._boost.visible and app.play.map.highlight.size() > 0, "the boost shows on the HUD and its Collection Center glows")
				go(11)
		# ---- Sorting Overload: decline, then join late from the pill.
		11:
			if layer().alert_visible() and event().get("type", "") == "sorting_overload":
				layer().decline()
				go(12)
		12:
			if t > 3.0 and not has_meta("declined"):
				set_meta("declined", true)
				ok(not layer().alert_visible(), "a declined alert does not come back")
				ok(not layer().game_visible(), "declining leaves the city on screen")
			if t > 3.0 and str(event().get("phase", "")) == "active":
				shot("e6_declined_pill")
				layer().respond()
				go(13)
		13:
			var game: SortingGame = layer().game() if layer().game_visible() else null
			if game and game.active():
				var ms := game.now_ms()
				for o in game._objects():
					if game.done.has(int(o.id)) or SortingGame.CLASS[str(o.kind)] != 0:
						continue
					var at: Variant = SortingGame.position(o, ms)
					if at == null or (at as Vector2).y > 900:
						continue
					var c := game._to_screen(at)
					drag(game, c - Vector2(120, 30), c + Vector2(120, 30))
					break
				if game.now_ms() > 9000 and not has_meta("sshot"):
					set_meta("sshot", true)
					shot("e7_sorting")
			if str(event().get("phase", "")) == "results" and t > 0.8:
				shot("e8_sorting_results")
				ok(int(event().leaderboard[s.seat].correct) > 0, "real swipes sliced recyclables, confirmed by the server")
				layer().step_away()
				go(14)
		# ---- Recycling Breakdown.
		14:
			if layer().alert_visible() and event().get("type", "") == "recycling_breakdown":
				shot("e9_recycling_alert")
				layer().respond()
				go(15)
		15:
			var game: RecyclingGame = layer().game() if layer().game_visible() else null
			if game and game.active() and not game._now.is_empty():
				var n: Dictionary = game._now
				var pp: Dictionary = game._p()
				if int(n.jam_dir) >= 0 and game.now_ms() > 12000 and not has_meta("fshot"):
					set_meta("fshot", true)
					shot("e10a_recycling_fault")
				if int(n.jam_dir) >= 0 and t > 0.4:
					# A real drag along the jam's release track.
					var c := game._machine(0).get_center()
					var dir: Vector2 = RecyclingGame.DIRS[int(n.jam_dir)]
					drag(game, c, c + dir * (float(n.jam_dist) / 1000.0 + 0.05) * game._track_scale())
					t = 0.0
				elif int(n.pressure) > int(pp.green_max) and t > 0.4:
					var valve := 0 if int(n.pressure) - int(pp.valve_small) <= int(pp.green_max) else 1
					drag(game, game._valve_rect(valve).get_center(), game._valve_rect(valve).get_center())
					t = 0.0
				elif (absi(int(n.align) - 500) > int(pp.align_ok) or int(n.drift) != 0) and absi(game.Plant.marker(pp, game.now_ms()) - 500) < game.Plant.press_band(pp, game.now_ms()) / 2:
					game.intervene(2, 0)
				if game.now_ms() > 19000 and not has_meta("rshot"):
					set_meta("rshot", true)
					shot("e10_recycling")
			if str(event().get("phase", "")) == "results" and t > 0.8:
				shot("e11_recycling_results")
				ok(int(event().leaderboard[s.seat].correct) > 0, "repairs confirmed by the server")
				ok(int(event().leaderboard[s.seat].score) > 100, "a well-run line scores well (%d)" % int(event().leaderboard[s.seat].score))
				go(16)
		16:
			if event().is_empty() and t > 0.5:
				var games := root.find_children("*", "EmergencyGame", true, false)
				ok(not layer().game_visible() and games.is_empty(), "no minigame is left in the scene after the event")
				ok(not layer().alert_visible(), "no alert is left")
				shot("e12_city_after")
				# Synchronization measured on this run (no simulated values).
				print("MEASURED rtt_avg=%d ms jitter=%d ms view_interval=%d ms score_confirm=%d ms" % [int(s.link.rtt_avg_ms), int(s.link.jitter_ms),
					int(layer()._view_gap_ms), int(layer()._confirm_ms)])
				print("fails=%d" % fails)
				s._forget_seat()
				quit(1 if fails else 0)
	if t > 70.0:
		print("FAIL timeout at step %d (phase %s, event %s)" % [step, s.phase if s else "?", str(event().get("phase", "none"))])
		quit(2)
	return false
