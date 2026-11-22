extends SceneTree
## COLLECTION CRISIS regression, in the real app against a server in developer mode
## with three collection rounds in a row (no restart in between):
##
##   godot --headless --path . --script server/main.gd -- --port 9085 \
##       --dev-emergencies collection_crisis@15,collection_crisis@60,collection_crisis@105
##   godot --path client/godot --script res://tests/collection_rounds.gd -- ws://127.0.0.1:9085 /tmp/shots 1170x540
##
## In every round each item that comes onto the belt is drawn there, the alert never
## covers the running game, and every item is routed with a real mouse drag (or the
## tap-then-tap fallback); each right routing is scored once by the server and plays
## its sounds. After each round no minigame stays in the scene.

var app: Node
var s: Session
var url := "ws://127.0.0.1:9085"
var out := "/tmp/shots"
var size := Vector2i(1170, 540)
var step := 0
var t := 0.0
var fails := 0
var rounds := 0
var total_routed := 0
var covered := false
var tapped := false
var sounds_before := 0


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


func layer() -> EmergencyLayer:
	return app.play.emergency if app.play else null


func event() -> Dictionary:
	var e: Variant = s.view.get("public", {}).get("emergency")
	return e if e != null else {}


func mouse(pos: Vector2, pressed: bool) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT; m.pressed = pressed; m.position = pos; m.global_position = pos
	Input.parse_input_event(m)


func drag(game: Control, a: Vector2, z: Vector2) -> void:
	# Game coordinates -> window coordinates (the window may be scaled).
	var g := root.get_final_transform() * game.get_global_transform()
	mouse(g * a, true)
	for i in range(1, 7):
		var mm := InputEventMouseMotion.new()
		mm.position = g * a.lerp(z, i / 6.0); mm.global_position = mm.position; mm.relative = (z - a) / 6.0; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
	mouse(g * z, false)


func _process(delta: float) -> bool:
	t += delta
	if s == null and app.session != null:
		s = app.session
		s.store = "user://collection_rounds.cfg"
		s._forget_seat()
	match step:
		0:
			if t > 1.0:
				s.create(url); step = 1
		1:
			if s.phase == "lobby" and s.join_code != "":
				s.set_ready(true); step = 2; t = 0.0
		2:
			if t > 0.5:
				s.start_match(); step = 3
		3:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
				s.choose_foundation("circular_foundation")
			if s.phase == "play" and layer() != null:
				step = 4
		4:
			if layer().alert_visible():
				layer().respond()
				sounds_before = int(UI.music.played.get("bin", 0))
				covered = false
				step = 5; t = 0.0
		5:
			var game: CollectionGame = layer().game() if layer().game_visible() else null
			if game == null:
				return false
			if layer().alert_visible():
				covered = true
			if game.active() and t > 0.15:
				var ms := game.now_ms()
				for item in game._items():
					var id := int(item.id)
					if game.done.has(id):
						continue
					var p: Variant = game._item_pos(item, ms)
					if p == null or (p as Vector2).x < 40 or (p as Vector2).x > game.size.x - 40:
						continue
					var bin: int = CollectionGame.CATEGORY[str(item.kind)]
					if not tapped:
						# The tap-then-tap fallback, once per run.
						tapped = true
						var gt := root.get_final_transform() * game.get_global_transform()
						mouse(gt * (p as Vector2), true)
						mouse(gt * (p as Vector2), false)
						mouse(gt * game._bin_rect(bin).get_center(), true)
						mouse(gt * game._bin_rect(bin).get_center(), false)
					else:
						drag(game, p, game._bin_rect(bin).get_center())
					t = 0.0
					break
			if str(event().get("phase", "")) == "results":
				var spawned := game._items().filter(func(i): return int(i.spawn_ms) + 300 < 25000)
				var unseen := spawned.filter(func(i): return not game.drawn.has(int(i.id)) and not game.done.has(int(i.id)))
				ok(unseen.is_empty(), "round %d: every item that came on the belt was drawn (%d items)" % [rounds + 1, spawned.size()])
				ok(not covered, "round %d: the alert never covered the running game" % [rounds + 1])
				var me: Dictionary = event().leaderboard[s.seat]
				ok(int(me.correct) == game.routed_ok and int(me.correct) >= spawned.size() - 3, "round %d: %d routings scored once each by the server" % [rounds + 1, int(me.correct)])
				ok(int(me.wrong) == 0 and int(me.score) >= 10 * int(me.correct), "round %d: right bins only, never a double score" % [rounds + 1])
				ok(int(UI.music.played.get("bin", 0)) - sounds_before >= int(me.correct) / 2, "round %d: bin sounds kept playing (%d)" % [rounds + 1, int(UI.music.played.get("bin", 0)) - sounds_before])
				total_routed += int(me.correct)
				root.get_texture().get_image().save_png("%s/round%d_%dx%d.png" % [out, rounds + 1, size.x, size.y])
				step = 6; t = 0.0
		6:
			if event().is_empty() and t > 0.3:
				ok(root.find_children("*", "EmergencyGame", true, false).is_empty(), "round %d: no minigame left in the scene" % [rounds + 1])
				rounds += 1
				if rounds == 3:
					ok(total_routed >= 30, "%d objects routed over three rounds without restarting" % total_routed)
					ok(tapped, "the tap-then-tap fallback was used")
					print("fails=%d" % fails)
					s._forget_seat()
					quit(1 if fails else 0)
				else:
					step = 4
	if t > 80.0:
		print("FAIL timeout at step %d" % step)
		quit(2)
	return false
