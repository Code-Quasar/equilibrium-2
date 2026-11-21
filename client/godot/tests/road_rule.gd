extends SceneTree
## End to end, through the real app and a fresh server: a building placed away
## from any road is switched off by the engine once finished; one beside the
## main road keeps working; drawing a road to the first switches it back on.
## Also checks the map model: the main road cannot be erased, buildings cannot
## stand on water or roads, and a saved design loads back.
##
##   godot --headless --path client/godot --script res://tests/road_rule.gd -- ws://127.0.0.1:9081

var app: Node
var s: Session
var step := 0
var t := 0.0
var fails := 0
var url := "ws://127.0.0.1:9081"
var far_tile := -1
var near_tile := -1


func ok(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		url = args[0]
	_model_checks()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)


func _model_checks() -> void:
	var L := CityLayout.new("model-test")
	var mp: Vector2i = L.main_road.keys()[0]
	ok(not L.remove_road(mp), "the main road cannot be erased")
	var water := Vector2i(-1, -1)
	for y in L.h:
		for x in L.w:
			if L.kind(Vector2i(x, y)) == CityLayout.WATER and water.x < 0:
				water = Vector2i(x, y)
	ok(L.why_not(water) != "", "no building on water")
	ok(L.why_not(mp - Vector2i(1, 1)) != "", "no building on a road")
	L.auto_place(0)
	ok(L.linked(0), "an auto-placed building touches the main road")
	var spot := Vector2i(3, L.h - 6)
	if L.why_not(spot) == "":
		L.place(1, spot)
		ok(not L.linked(1), "a building far from roads is not linked")
		var cell := Vector2i(spot.x + 2, spot.y - 1)
		ok(L.add_road(cell), "a road can be drawn")
		ok(not L.linked(1), "a road not joined to the main road does not link it")
		L.remove_road(cell)
	L.save("user://model_test.json")
	var L2 := CityLayout.new("model-test")
	L2.load_from("user://model_test.json")
	ok(L2.placements == L.placements and L2.roads.size() == L.roads.size(), "a saved design loads back")


func play() -> Play:
	return app.play


func building(tile: int) -> Dictionary:
	for b in s.view.get("own_city", {}).get("buildings", []):
		if int(b["tile"]) == tile:
			return b
	return {}


func go() -> void:
	step += 1
	t = 0.0


func _process(delta: float) -> bool:
	t += delta
	if s == null and app.session != null:
		s = app.session
		s.store = "user://road_test.cfg"
		s._forget_seat()
	match step:
		0:
			if t > 0.5:
				s.create(url)
				go()
		1:
			if s.phase == "lobby" and t > 0.5:
				s.set_ready(true)
				go()
		2:
			if t > 0.5:
				s.start_match()
				go()
		3:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
				s.choose_foundation(s.draft["available_foundations"][0])
			if s.phase == "play" and not s.view.is_empty() and t > 1.5:
				go()
		4:
			var L: CityLayout = app.map.layout
			# Near: a Green Space beside the main road. Far: houses in a corner.
			var near_at := L.spot_beside_main()
			var mp := near_at
			var far_at := Vector2i(-1, -1)
			for y in range(L.h - 6, 2, -1):
				for x in range(2, 12):
					if far_at.x < 0 and L.why_not(Vector2i(x, y)) == "" and Vector2(x, y).distance_to(Vector2(mp)) > 12:
						far_at = Vector2i(x, y)
			play().start_placing("residential_district")
			play()._snap(far_at + Vector2i(1, 1))
			far_tile = play()._free_tile()
			play()._confirm_place()
			play().start_placing("green_space")
			play()._snap(near_at + Vector2i(1, 1))
			near_tile = play()._free_tile()
			play()._confirm_place()
			print("   far_at %s tile %d placed %s linked %s | near_at %s tile %d placed %s linked %s" % [far_at, far_tile, L.placements.has(far_tile), L.linked(far_tile), near_at, near_tile, L.placements.has(near_tile), L.linked(near_tile)])
			ok(not L.linked(far_tile) and L.linked(near_tile), "placed one building off the network and one on it")
			go()
		5:
			var far := building(far_tile)
			var near := building(near_tile)
			if not far.is_empty() and far.get("status") == "complete" and not far.get("enabled", true) and t > 1.0:
				ok(true, "the server reports the unconnected building switched off")
				ok(not near.is_empty() and near.get("enabled", false), "the connected building stays on")
				# Draw a road from the far building to the main road: along its row, then its column.
				var L: CityLayout = app.map.layout
				var r := L.rect(far_tile)
				var mp: Vector2i = L.main_road.keys()[0]
				var y := r.position.y - 1
				var x := r.position.x
				var target_x := 0
				for p in L.main_road:
					if p.y == y:
						target_x = p.x
				if target_x == 0:
					# No main road cell on this row: go to the main road's first column, then along it.
					target_x = mp.x
				var dx := signi(target_x - x)
				while x != target_x:
					L.add_road(Vector2i(x, y))
					x += dx
				var dy := 1 if y < mp.y else -1
				var guard := 0
				while not L.connected(Vector2i(x, y)) and guard < 80:
					L.add_road(Vector2i(x, y))
					y += dy
					guard += 1
				L.add_road(Vector2i(x, y))
				app.map.save()
				ok(L.linked(far_tile), "a drawn road joins it to the main road")
				play().refresh("view")
				go()
			elif t > 60:
				ok(false, "unconnected building was not switched off (status %s enabled %s)" % [far.get("status"), far.get("enabled")])
				go()
		6:
			var far := building(far_tile)
			if far.get("enabled", false):
				ok(true, "connecting it switched it back on in the engine")
				print("fails=", fails)
				s._forget_seat()
				quit(1 if fails > 0 else 0)
			elif t > 30:
				ok(false, "still off after connecting")
				print("fails=", fails)
				quit(1)
	if t > 90:
		print("TIMEOUT step %d" % step)
		quit(2)
	return false
