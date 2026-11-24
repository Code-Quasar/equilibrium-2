extends SceneTree
## Records gameplay footage for the presentation from the real game. Two copies run
## at once against one server in developer mode, as player A (an industrial city)
## and player B (a balanced city with its recovery chain); both play the three ECO
## EMERGENCIES with real mouse gestures. Frames are saved as JPEGs, named by wall
## clock time, in one folder per segment, so the two players' screens can be laid
## side by side afterwards (tools/make_gifs.py).
##
##   godot --headless --path . --script server/main.gd -- --port 9087 --dev-cash 4000 \
##       --dev-emergencies collection_crisis@270,sorting_overload@330,recycling_breakdown@390
##   godot --path client/godot --script res://tools/record_showcase.gd -- ws://127.0.0.1:9087 A OUT_A SYNC_FILE
##   godot --path client/godot --script res://tools/record_showcase.gd -- ws://127.0.0.1:9087 B OUT_B SYNC_FILE

const SIZE := Vector2i(1280, 720)
## With "side" as the fifth argument the two windows sit side by side without
## overlapping (an overlapped window can stop being redrawn on Windows).
const SIDE := Vector2i(760, 428)
## [name, first tick, last tick, frames per second (0: one per tick)]
const SEGMENTS := {
	"A": [["build", 3, 46, 10], ["lapse", 46, 262, 0], ["em1", 266, 318, 10], ["em2", 326, 378, 10], ["em3", 386, 438, 10]],
	"B": [["build", 3, 46, 10], ["pipeline", 46, 96, 8], ["lapse", 96, 262, 0], ["em1", 266, 318, 10], ["em2", 326, 378, 10], ["em3", 386, 438, 10]],
}
const PLANS := {
	"A": [["factory", "S"], ["fossil_power_plant", "S"], ["factory", "S"], ["commercial_district", "S"], ["fossil_power_plant", "M"],
		["factory", "M"], ["residential_district", "S"], ["factory", "S"], ["fossil_power_plant", "S"], ["factory", "M"], ["commercial_district", "M"],
		["factory", "S"], ["residential_district", "M"], ["factory", "S"], ["fossil_power_plant", "S"], ["factory", "S"]],
	"B": [["recycling_center", "S"], ["residential_district", "M"], ["factory", "S"], ["renewable_power_plant", "S"], ["park", "S"],
		["biogas_facility", "S"], ["commercial_district", "S"], ["public_services_center", "S"], ["park", "S"], ["residential_district", "M"],
		["factory", "S"], ["renewable_power_plant", "S"], ["recycling_center", "S"], ["park", "M"], ["commercial_district", "S"], ["residential_district", "S"]],
}

var app: Node
var s: Session
var url := ""
var role := "A"
var out := ""
var sync := ""
var step := 0
var t := 0.0
var plan_i := 0
var last_frame_ms := 0
var last_tick := -1
var gestures: Array = []          # [[points in window space], frame index]
var placed_slowly := 0
var acted := {}
var busy := false                 # a slow placement is being shown
var mode := ""                    # "side", or "visit": A builds while B watches A's city


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	url = a[0]
	role = a[1]
	out = a[2]
	sync = a[3]
	mode = a[4] if a.size() > 4 else ""
	var side_by_side := mode in ["side", "visit"]
	DisplayServer.window_set_size(SIDE if side_by_side else SIZE)
	if side_by_side:
		DisplayServer.window_set_position(Vector2i(0 if role == "A" else 768, 40))
	else:
		DisplayServer.window_set_position(Vector2i(0 if role == "A" else 120, 0 if role == "A" else 80))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)


func play() -> Play:
	return app.play


func tick() -> int:
	return int(s.view.get("tick", -1))


func event() -> Dictionary:
	var e: Variant = s.view.get("public", {}).get("emergency")
	return e if e != null else {}


func _process(delta: float) -> bool:
	t += delta
	if s == null and app.session != null:
		s = app.session
		s.store = "user://showcase_%s.cfg" % role
		s._forget_seat()
	match step:
		0:
			if t > 1.0:
				if role == "A":
					s.create(url)
				step = 1
		1:
			if role == "A" and s.phase == "lobby" and s.join_code != "":
				FileAccess.open(sync, FileAccess.WRITE).store_string(s.join_code)
				s.set_ready(true)
				step = 2
			elif role == "B" and FileAccess.file_exists(sync) and s.phase == "menu":
				s.join(url, FileAccess.get_file_as_string(sync).strip_edges())
				step = 2
		2:
			if role == "B" and s.phase == "lobby":
				s.set_ready(true)
				step = 3
			elif role == "A":
				var humans: Array = s.lobby.get("seats", []).filter(func(r): return r.get("controller", "") == "human" and r.get("ready", false))
				if humans.size() >= 2:
					s.start_match()
					step = 3
		3:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
				s.choose_foundation("industrial_legacy" if role == "A" else "circular_foundation")
			if s.phase == "play" and app.play != null:
				app.map.camera.size = 13.0
				step = 4
		4:
			if mode == "visit":
				_visit_show()
				_record_visit()
				if tick() > 52:
					print("DONE ", role)
					quit()
				return false
			_city()
			_emergency()
			_gestures()
			_record()
			if tick() > 440 or s.phase == "over":
				print("DONE ", role)
				quit()
	return false


# ------------------------------------------------------------------ the city ---

func _city() -> void:
	if tick() < 2 or not event().is_empty():
		return
	var p := play()
	var own: Dictionary = s.view.get("own_city", {})
	if role == "B":
		# A slow camera drift while building; the recovery chain's panels after.
		if tick() < 46:
			app.map._pan(Vector2(640, 360), Vector2(640.04, 360.012))
		if tick() == 50 and not acted.has("waste"):
			acted["waste"] = true
			p._open("waste")
		if tick() == 62 and not acted.has("panel"):
			acted["panel"] = true
			for b in own.get("buildings", []):
				if b["type"] == "sorting_center":
					p._on_tile(int(b["tile"]))
		if tick() == 74 and not acted.has("recycler"):
			acted["recycler"] = true
			for b in own.get("buildings", []):
				if b["type"] == "recycling_center":
					p._on_tile(int(b["tile"]))
		if tick() == 88 and not acted.has("close"):
			acted["close"] = true
			p._open("")
	if role == "A" and tick() == 30 and not acted.has("factory"):
		acted["factory"] = true
		for b in own.get("buildings", []):
			if b["type"] == "factory":
				p._on_tile(int(b["tile"]))
	if role == "A" and tick() == 42 and not acted.has("closeA"):
		acted["closeA"] = true
		p._open("")
	if busy or plan_i >= PLANS[role].size() or not p.placing.is_empty() or p._slots_free() == 0 or t < 1.5:
		return
	var item: Array = PLANS[role][plan_i]
	var options: Dictionary = own.get("build_options", {})
	if str(options.get(item[0], {}).get(item[1], "x")) != "":
		return
	t = 0.0
	plan_i += 1
	p.build_size = item[1]
	var spot: Vector2i = app.map.layout.spot_beside_main()
	if spot.x < 0:
		return
	if placed_slowly < 2 and tick() < 40:
		# Shown as a player does it: open Build, pick, drag the ghost to its site.
		placed_slowly += 1
		busy = true
		p._open("build")
		p._set_build_size(item[1])
		var from := spot + Vector2i(-6, 5)
		await create_timer(0.8).timeout
		p.start_placing(item[0], from)
		for k in range(1, 13):
			await create_timer(0.07).timeout
			p._on_ghost_drag(Vector2i(roundi(lerpf(from.x, spot.x, k / 12.0)), roundi(lerpf(from.y, spot.y, k / 12.0))) + Vector2i(1, 1))
		await create_timer(0.4).timeout
		p._on_ghost_drop(spot + Vector2i(1, 1))
		busy = false
	else:
		p.start_placing(item[0], spot + Vector2i(1, 1))
		p._on_ghost_drop(spot + Vector2i(1, 1))


# -------------------------------------------------------------- emergencies ---

func _emergency() -> void:
	var e := event()
	if e.is_empty():
		return
	var L: EmergencyLayer = play().emergency
	if L.alert_visible() and tick() >= int(e.start) + (1 if role == "A" else 3):
		L.respond()
	if str(e.phase) == "results" and not acted.has("back" + str(e.id)) and tick() >= int(e.end) + 4:
		acted["back" + str(e.id)] = true
		L.step_away()
	var g: Variant = L.game() if L.game_visible() else null
	if g == null or not g.active() or not gestures.is_empty():
		return
	# A is a decent player, B a strong one: B reacts sooner and misses less.
	var pause := 0.55 if role == "A" else 0.3
	if t < pause:
		return
	t = 0.0
	var gt: Transform2D = root.get_final_transform() * (g as Control).get_global_transform()
	if g is CollectionGame:
		var ms: int = g.now_ms()
		for item in g._items():
			if g.done.has(int(item.id)):
				continue
			var pos: Variant = g._item_pos(item, ms)
			if pos == null or (pos as Vector2).x < 80 or (pos as Vector2).x > g.size.x * 0.8:
				continue
			var bin: int = CollectionGame.CATEGORY[str(item.kind)]
			if role == "A" and int(item.id) % 7 == 3:
				bin = (bin + 1) % 3
			_gesture(gt, pos, g._bin_rect(bin).get_center(), 14)
			return
	elif g is SortingGame:
		var ms2: int = g.now_ms()
		for o in g._objects():
			if g.done.has(int(o.id)) or SortingGame.CLASS[str(o.kind)] != 0:
				continue
			var at: Variant = SortingGame.position(o, ms2 + 120)
			if at == null or (at as Vector2).y > 850:
				continue
			if role == "A" and int(o.id) % 4 == 1:
				continue
			var c: Vector2 = g._to_screen(at)
			_gesture(gt, c + Vector2(-150, 50), c + Vector2(150, -50), 7)
			return
	elif g is RecyclingGame:
		var n: Dictionary = g._now
		var pp: Dictionary = g._p()
		if n.is_empty():
			return
		if int(n.jam_dir) >= 0:
			var c2: Vector2 = g._machine(0).get_center()
			var dir: Vector2 = RecyclingGame.DIRS[int(n.jam_dir)]
			_gesture(gt, c2, c2 + dir * (float(n.jam_dist) / 1000.0 + 0.08) * g._track_scale(), 12)
		elif int(n.pressure) > int(pp.green_max):
			var v := 0 if int(n.pressure) - int(pp.valve_small) <= int(pp.green_max) else 1
			_gesture(gt, g._valve_rect(v).get_center(), g._valve_rect(v).get_center(), 2)
		elif (absi(int(n.align) - 500) > int(pp.align_ok) or int(n.drift) != 0) and absi(RecyclingGame.Plant.marker(pp, g.now_ms()) - 500) < RecyclingGame.Plant.press_band(pp, g.now_ms()) / 2:
			var c3: Vector2 = g._machine(2).get_center()
			_gesture(gt, c3, c3, 2)


## A gesture played out over several frames: press, move, release.
func _gesture(gt: Transform2D, a: Vector2, z: Vector2, frames: int) -> void:
	var pts: Array = []
	for k in range(frames + 1):
		pts.append(gt * a.lerp(z, float(k) / frames))
	gestures.append([pts, 0])


func _gestures() -> void:
	if gestures.is_empty():
		return
	var g: Array = gestures[0]
	var pts: Array = g[0]
	var i: int = g[1]
	if i == 0:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = pts[0]; press.global_position = pts[0]
		Input.parse_input_event(press)
	elif i < pts.size():
		var mm := InputEventMouseMotion.new()
		mm.position = pts[i]; mm.global_position = pts[i]; mm.relative = pts[i] - pts[i - 1]; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
	else:
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = pts[-1]; up.global_position = pts[-1]
		Input.parse_input_event(up)
		gestures.pop_front()
		return
	g[1] = i + 1


# ------------------------------------------------------------- visit mode ---

## B opens Rivals and visits A's city before A builds; A then places a Factory
## the way a player does (open Build, drag the ghost to its site, drop it).
func _visit_show() -> void:
	var p := play()
	if role == "B":
		if tick() == 4 and not acted.has("rivals"):
			acted["rivals"] = true
			p._open("rivals")
		if tick() == 7 and not acted.has("visit"):
			acted["visit"] = true
			p._open("")
			for o in s.view.get("opponents", []):
				if o.get("foundation", "") == "industrial_legacy":
					p.visit(int(o["city_id"]))
		return
	if tick() == 13 and not acted.has("build"):
		acted["build"] = true
		p.build_size = "S"
		p._open("build")
		p._set_build_size("S")
		var spot: Vector2i = app.map.layout.spot_beside_main()
		var from := spot + Vector2i(-6, 5)
		await create_timer(1.0).timeout
		p.start_placing("factory", from)
		for k in range(1, 13):
			await create_timer(0.07).timeout
			p._on_ghost_drag(Vector2i(roundi(lerpf(from.x, spot.x, k / 12.0)), roundi(lerpf(from.y, spot.y, k / 12.0))) + Vector2i(1, 1))
		await create_timer(0.5).timeout
		p._on_ghost_drop(spot + Vector2i(1, 1))


func _record_visit() -> void:
	var tk := tick()
	if tk < 8 or tk > 50:
		return
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if now - last_frame_ms < 100:
		return
	last_frame_ms = now
	var dir: String = "%s/visit" % out
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg("%s/%013d_%04d.jpg" % [dir, now, tk], 0.9)


# ---------------------------------------------------------------- frames ---

func _record() -> void:
	var tk := tick()
	for seg in SEGMENTS[role]:
		if tk < seg[1] or tk > seg[2]:
			continue
		var now := int(Time.get_unix_time_from_system() * 1000.0)
		var due: bool = (tk != last_tick) if int(seg[3]) == 0 else (now - last_frame_ms >= 1000 / int(seg[3]))
		if not due:
			return
		last_frame_ms = now
		last_tick = tk
		var dir: String = "%s/%s" % [out, seg[0]]
		DirAccess.make_dir_recursive_absolute(dir)
		root.get_texture().get_image().save_jpg("%s/%013d_%04d.jpg" % [dir, now, tk], 0.88)
		return
