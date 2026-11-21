extends SceneTree
## Drives the real app (windowed, not headless) through every screen against a
## fresh running server and saves a PNG of each, for visual review.
## The results screen is filled from a labelled test fixture, because a real
## final result takes a full 20-minute match.
##
##   godot --path client/godot --script res://tests/capture.gd -- ws://127.0.0.1:9080 /tmp/shots 1170x540

var app: Node
var s: Session
var step := 0
var t := 0.0
var url := "ws://127.0.0.1:9080"
var out := "/tmp/shots"
var size := Vector2i(1170, 540)


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


func shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%dx%d.png" % [out, name, size.x, size.y])
	print("saved ", name)


func go(n := 1) -> void:
	step += n
	t = 0.0


func _process(delta: float) -> bool:
	t += delta
	if s == null and app.session != null:
		s = app.session
		s.store = "user://capture.cfg"
		s._forget_seat()
	match step:
		0:
			if t > 1.0:
				shot("1_menu")
				s.create(url)
				go()
		1:
			if s.phase == "lobby" and s.join_code != "" and t > 0.8:
				shot("2_lobby")
				s.set_ready(true)
				go()
		2:
			if t > 0.6:
				s.start_match()
				go()
		3:
			if s.phase == "draft" and t > 0.8:
				shot("3_draft")
				go()
		4:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
				s.choose_foundation("circular_foundation" if "circular_foundation" in s.draft["available_foundations"] else s.draft["available_foundations"][0])
			if s.phase == "play" and not s.view.is_empty() and t > 2.5:
				shot("4_city")
				# Panning with real input events, as a finger and as a mouse send them.
				var cam: Vector2 = app.map.camera.position
				var press := InputEventScreenTouch.new(); press.index = 0; press.pressed = true; press.position = Vector2(420, 300)
				root.push_input(press)
				var drag := InputEventScreenDrag.new(); drag.index = 0; drag.position = Vector2(320, 260); drag.relative = Vector2(-100, -40)
				root.push_input(drag)
				var up := InputEventScreenTouch.new(); up.index = 0; up.pressed = false; up.position = Vector2(320, 260)
				root.push_input(up)
				print(("PASS" if app.map.camera.position != cam else "FAIL") + " a finger drag pans the map")
				cam = app.map.camera.position
				var mb := InputEventMouseButton.new(); mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = true; mb.position = Vector2(420, 300); mb.global_position = mb.position
				Input.parse_input_event(mb)
				var mm := InputEventMouseMotion.new(); mm.position = Vector2(500, 330); mm.global_position = mm.position; mm.relative = Vector2(80, 30); mm.button_mask = MOUSE_BUTTON_MASK_LEFT
				Input.parse_input_event(mm)
				var mu := InputEventMouseButton.new(); mu.button_index = MOUSE_BUTTON_LEFT; mu.pressed = false; mu.position = Vector2(500, 330); mu.global_position = mu.position
				Input.parse_input_event(mu)
				set_meta("cam", cam)
				go(-4 + 200)
		200:
			if t > 0.3:
				print(("PASS" if app.map.camera.position != get_meta("cam") else "FAIL") + " a mouse drag pans the map")
				app.play.recenter_for_test()
				app.play._open("build")
				step = 5
				t = 0.0
		5:
			if t > 0.6:
				shot("5_build_list")
				# Drag a Recovery Hub beside the main road, houses further out.
				var L: CityLayout = app.map.layout
				var near := L.spot_beside_main()
				app.play.start_placing("recovery_hub")
				app.play._on_ghost_drag(near + Vector2i(2, 2))
				set_meta("near", near)
				go()
		6:
			if t > 0.4:
				shot("5b_dragging")
				app.play._on_ghost_drop(get_meta("near") + Vector2i(2, 2))
				app.play.start_placing("residential_district")
				var at: Vector2i = get_meta("near") + Vector2i(6, 7)
				app.play._on_ghost_drop(at + Vector2i(2, 2))
				go(-6 + 100)
		100:
			if t > 1.0:
				app.play.road_mode("draw")
				step = 101
				t = 0.0
		101:
			if t > 0.4:
				shot("5c_roads_mode")
				app.play.road_mode("")
				for tl in app.map.layout.placements:
					if not app.map.building_on(tl).is_empty() and app.map.building_on(tl)["type"] == "recovery_hub":
						app.play._on_tile(tl)
				step = 7
				t = 0.0
		7:
			if t > 0.6:
				shot("6_building_panel")
				app.play._open("policy")
				go()
		8:
			if t > 0.6:
				shot("7_policy")
				app.play._open("market")
				go()
		9:
			if t > 0.6:
				shot("8_trade")
				app.play._open("rivals")
				go()
		10:
			if t > 0.6:
				shot("9_rivals")
				app.play._open("")
				go()
		11:
			if t > 0.6:
				shot("10_city_with_needs")
				# TEST FIXTURE ONLY: a final result shaped like match_finished.
				var ranks := []
				for r in s.view["public"]["rankings"]:
					ranks.append(r)
				s.final_result = {"type": "match_finished", "winners": [int(ranks[0]["city_id"])], "rankings": ranks, "duration": 1200}
				s.phase = "over"
				s.changed.emit("phase")
				go()
		12:
			if t > 0.8:
				shot("11_results_fixture")
				s._forget_seat()
				quit(0)
	if t > 30.0:
		print("TIMEOUT at step %d phase %s" % [step, s.phase if s else "?"])
		quit(2)
	return false
