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
				var cam: Vector3 = app.map.camera.position
				var press := InputEventScreenTouch.new(); press.index = 0; press.pressed = true; press.position = Vector2(420, 300)
				root.push_input(press)
				var drag := InputEventScreenDrag.new(); drag.index = 0; drag.position = Vector2(320, 260); drag.relative = Vector2(-100, -40)
				root.push_input(drag)
				var up := InputEventScreenTouch.new(); up.index = 0; up.pressed = false; up.position = Vector2(320, 260)
				root.push_input(up)
				print(("PASS" if root.get_viewport().get_camera_3d() == app.map.camera else "FAIL") + " the game map's camera is the one on screen")
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
				# Drag a Collection Center beside the main road, houses further out.
				var L: CityLayout = app.map.layout
				var near := L.spot_beside_main()
				app.play.start_placing("collection_center")
				app.play._on_ghost_drag(near + Vector2i(1, 1))
				set_meta("near", near)
				go()
		6:
			if t > 0.4:
				shot("5b_dragging")
				app.play._on_ghost_drop(get_meta("near") + Vector2i(1, 1))
				app.play.start_placing("residential_district")
				var at: Vector2i = get_meta("near") + Vector2i(4, 5)
				app.play._on_ghost_drop(at + Vector2i(1, 1))
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
					if not app.map.building_on(tl).is_empty() and app.map.building_on(tl)["type"] == "collection_center":
						app.play._on_tile(tl)
				step = 7
				t = 0.0
		7:
			if t > 0.6:
				shot("6_building_panel")
				app.play._open("waste")
				go()
		8:
			if t > 0.6:
				shot("7_waste")
				s.act("publish_offer", {"type": "electricity", "rate": 5000000}, "Offer Electricity")
				app.play._open("market")
				go()
		9:
			if t > 1.6:
				shot("8_trade")
				# TEST FIXTURE ONLY: a rival's offer and an active contract, to show
				# how the Trade panel lists them; the next server view replaces them.
				var rival := int(s.view["opponents"][0]["city_id"])
				var tk := int(s.view["tick"])
				s.view["marketplace"]["offers"].append({"id": 900, "seller": rival, "type": "recyclable", "rate_micro": 5000000, "price_micro": 750000, "created_tick": tk})
				s.view["own_city"]["contracts"].append({"id": 901, "buyer": s.seat, "seller": rival, "type": "electricity", "rate_micro": 10000000,
					"price_micro": 220000, "start_tick": tk - 30, "end_tick": tk + 90, "status": "active", "escrow_micro": 4400000,
					"delivered_micro": 300000000, "paid_micro": 1100000, "last_delivery_micro": 10000000, "closed_tick": -1})
				app.play.refresh("all")
				step = 400
				t = 0.0
		400:
			if t > 0.2:
				(app.play._body.get_parent() as ScrollContainer).scroll_vertical = 330
				step = 401
				t = 0.0
		401:
			if t > 0.15:
				shot("8b_trade_fixture")
				(app.play._body.get_parent() as ScrollContainer).scroll_vertical = 2000
				step = 402
				t = 0.0
		402:
			if t > 0.15:
				shot("8c_trade_fixture_contracts")
				app.play._open("rivals")
				step = 10
				t = 0.0
		10:
			if t > 0.6:
				shot("9_rivals")
				app.play._open("")
				go()
		11:
			if t > 0.6:
				shot("10_city_with_needs")
				app.play._details("power", app.play._need_chips["power"])
				step = 300
				t = 0.0
		300:
			if t > 0.5:
				shot("10b_power_details")
				app.play._details("money", app.play._cash)
				step = 301
				t = 0.0
		301:
			if t > 0.5:
				shot("10c_money_details")
				app.play.close_details()
				var rival := int(s.view["opponents"][0]["city_id"])
				print(("PASS" if s.view["opponents"][0].has("buildings") else "FAIL") + " rivals carry a public building list")
				app.play.visit(rival)
				step = 302
				t = 0.0
		302:
			if t > 1.2:
				shot("10d_visiting_rival")
				print(("PASS" if app.play.visiting >= 0 and app.map.read_only else "FAIL") + " visit mode is read-only")
				app.play.visit(-1)
				step = 303
				t = 0.0
		303:
			if t > 0.8:
				print(("PASS" if app.play.visiting == -1 and not app.map.read_only else "FAIL") + " back in my own city")
				shot("10e_back_home")
				# TEST FIXTURE ONLY: a final result shaped like match_finished.
				var ranks := []
				for r in s.view["public"]["rankings"]:
					ranks.append(r)
				s.final_result = {"type": "match_finished", "winners": [int(ranks[0]["city_id"])], "rankings": ranks, "duration": 1200}
				s.phase = "over"
				s.changed.emit("phase")
				step = 12
				t = 0.0
		12:
			if t > 0.8:
				shot("11_results_fixture")
				s._forget_seat()
				quit(0)
	if t > 30.0:
		print("TIMEOUT at step %d phase %s" % [step, s.phase if s else "?"])
		quit(2)
	return false
