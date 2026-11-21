class_name CityMap
extends Node3D
## The city in 3D, seen through an isometric camera: land, river and woods,
## the fixed main road and the player's own roads built from road pieces,
## buildings made of Kenney models on their sites, and traffic. It shows the
## last player_view only: buildings rise while under construction, darken
## when switched off or cut off from the roads, and carry a bubble saying
## what they lack.
##
## Gestures: one finger pans (or draws roads in road mode, or drags the
## building being placed); two fingers pinch to zoom and pan; tap a building
## to select it. On desktop the wheel zooms and right-drag pans.

signal tapped(tile: int)                 # -1: open ground
signal ghost_dragged(cell: Vector2i)
signal ghost_dropped(cell: Vector2i)
signal roads_changed

var art: Art
var layout: CityLayout
var city: Dictionary = {}
var tick := 0
var selected := -1
var placing: Dictionary = {}             # {type, at, ok, why}
var road_mode := ""                      # "", "draw", "erase"
var stale := false
var needs := {}                          # tile -> what the building lacks
var ui_blocks: Callable = func(_p: Vector2) -> bool: return false
var clock: Callable = func() -> float: return 0.0
var demo := false                        # menu backdrop: no input, slow orbit
var read_only := false                   # visiting a rival: look, never change

var camera: Camera3D
var traffic: Traffic
var _target := Vector3.ZERO             # the ground point the camera looks at
var _ground: MeshInstance3D
var _forest: Node3D
var _roads: Node3D
var _buildings: Node3D
var _marks: Node3D                       # selection, ghost, bubbles
var _grow: Array = []                    # [node, start tick, end tick] rising buildings
var _touches := {}
var _drag := 0.0
var _pinch := 0.0
var _ghost_drag := false
var _painting := false
var _last_paint := Vector2i(-999, -999)
var _key := ""
var _path := ""
var _dim: StandardMaterial3D
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _red: StandardMaterial3D
var _blueprint: StandardMaterial3D
var _ground_sig := ""                    # placements + roads the ground was built for
var _frame: Node3D                       # the landscape around the playable map
var _building_ids := {}                  # ids under construction at the last rebuild
var _bar_tex: ImageTexture


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#8fc4e8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#ffffff")
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.0
	camera.rotation_degrees = Vector3(-35.264, 45, 0)
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	for n in ["_ground_holder", "_forest", "_roads", "_buildings", "_marks"]:
		var node := Node3D.new()
		node.name = n
		add_child(node)
	_forest = get_node("_forest")
	_roads = get_node("_roads")
	_buildings = get_node("_buildings")
	_marks = get_node("_marks")
	traffic = Traffic.new()
	add_child(traffic)
	_dim = _overlay(Color(0.12, 0.14, 0.2, 0.55))
	_ghost_ok = _overlay(Color(0.31, 0.9, 0.47, 0.55))
	_ghost_bad = _overlay(Color(0.91, 0.36, 0.29, 0.6))
	_red = _overlay(Color(0.91, 0.36, 0.29, 0.5))
	_blueprint = _overlay(Color(0.55, 0.86, 1.0, 0.3))
	_blueprint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var img := Image.create(64, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_bar_tex = ImageTexture.create_from_image(img)
	_frame = Node3D.new()
	_frame.name = "_frame"
	add_child(_frame)


static func _overlay(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Shows a city. A new key (match and seat) loads that design from the device.
## Buildings without a spot here (a Foundation building, or a match continued
## from another device) are placed beside the main road. reserved holds tiles
## whose construction is on its way to the server.
func show_city(c: Dictionary, now_tick: int, key: String, reserved: Dictionary = {}) -> void:
	if key != _key or layout == null:
		_key = key
		_path = "user://layout3d_%s.json" % key.md5_text()
		layout = CityLayout.new(key)
		layout.load_from(_path)
		traffic.layout = layout
		_build_frame()
		_build_ground()
		_build_roads()
		recenter()
	city = c
	tick = now_tick
	var have := {}
	var changed := false
	for b in c.get("buildings", []):
		var t := int(b["tile"])
		have[t] = true
		if not layout.placements.has(t):
			layout.auto_place(t)
			changed = true
	for t in layout.placements.keys():
		if not have.has(t) and not reserved.has(t):
			layout.unplace(t)
			changed = true
	if changed:
		save()
		_build_roads()
		_build_ground()
	traffic.set_demand(c, layout)
	rebuild()


## The menu's backdrop: a sample town on the same map, purely decorative,
## seen from a slowly circling camera. It is never sent anywhere.
func show_demo() -> void:
	demo = true
	_key = "menu-demo"
	_path = ""
	layout = CityLayout.new("menu-demo")
	traffic.layout = layout
	var types := ["residential_district", "commercial_district", "residential_district", "public_services_center",
		"park", "residential_district", "recycling_center", "renewable_power_plant", "commercial_district",
		"collection_center", "residential_district", "biogas_facility", "sorting_center", "factory"]
	var bs := []
	for i in types.size():
		layout.auto_place(i)
		bs.append({"id": i, "tile": i, "type": types[i], "size": ["M", "S", "L"][i % 3], "status": "complete", "op": {"fraction_micro": 1000000}})
	city = {"buildings": bs, "population": 1800, "projects": []}
	_build_frame()
	_build_ground()
	_build_roads()
	recenter()
	camera.size = 17.0
	traffic.set_demand(city, layout)
	rebuild()


func save() -> void:
	if layout and _path != "":
		layout.save(_path)


func recenter() -> void:
	# Start on the main road near the middle, where the city will grow.
	var c := layout.spot_beside_main()
	_target = Vector3(c.x + 3, 0, c.y + 2) if c.x >= 0 else Vector3(layout.center().x, 0, layout.center().y)
	_place_camera()


func zoom_by(f: float) -> void:
	camera.size = clampf(camera.size / f, 8.0, 60.0)


func _place_camera() -> void:
	camera.position = _target + camera.transform.basis.z * 80.0


func building_on(tile: int) -> Dictionary:
	for b in city.get("buildings", []):
		if int(b["tile"]) == tile:
			return b
	return {}


static func cell_center(x: float, y: float) -> Vector3:
	return Vector3(x + 0.5, 0, y + 0.5)


# ---------------------------------------------------------------- ground ---

## One mesh for all the land: a quad per cell, coloured by terrain; water
## sits a little lower. Trees on forest cells are MultiMeshes.
func _build_ground() -> void:
	_ground_sig = _sig()
	var holder := get_node("_ground_holder")
	UI.clear(holder)
	UI.clear(_forest)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := layout
	for y in L.h:
		for x in L.w:
			var p := Vector2i(x, y)
			var n := _hash(x, y)
			var col: Color
			var h := 0.0
			match L.kind(p):
				CityLayout.WATER:
					col = Color("#4fa3d9").lerp(Color("#3b8cc6"), n * 0.5)
					h = -0.12
				CityLayout.FLOOD:
					col = Color("#b4d495").lerp(Color("#a5c886"), n)
				CityLayout.FOREST:
					col = Color("#6fae54").lerp(Color("#62a04a"), n)
				_:
					col = Color("#86c264").lerp(Color("#7bb85a"), n * 0.7)
			if L.tile_at(p) >= 0:
				col = Color("#b8b6ad")
			st.set_color(col)
			st.set_normal(Vector3.UP)
			for v in [Vector3(x, h, y), Vector3(x + 1, h, y), Vector3(x + 1, h, y + 1), Vector3(x, h, y), Vector3(x + 1, h, y + 1), Vector3(x, h, y + 1)]:
				st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	_ground = MeshInstance3D.new()
	_ground.mesh = st.commit()
	_ground.material_override = mat
	holder.add_child(_ground)
	# Woods: a few tree models, scattered by a hash so they never move.
	var spots := {}
	for y in L.h:
		for x in L.w:
			var p := Vector2i(x, y)
			if L.kind(p) == CityLayout.FOREST and not L.roads.has(p) and L.tile_at(p) < 0:
				var k := int(_hash(x * 7, y * 3) * Models.TREES.size()) % Models.TREES.size()
				if not spots.has(k):
					spots[k] = []
				spots[k].append(Vector3(x + 0.25 + _hash(x, y + 9) * 0.5, 0, y + 0.25 + _hash(y, x + 9) * 0.5))
	for k in spots:
		var mt: Array = Models.mesh(Models.TREES[k])
		if mt.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mt[0]
		mm.instance_count = spots[k].size()
		for i in spots[k].size():
			var s := 0.45 + _hash(i, k) * 0.25
			var xf := Transform3D(Basis(Vector3.UP, _hash(k, i) * TAU).scaled(Vector3(s, s, s)), spots[k][i]) * (mt[1] as Transform3D)
			mm.set_instance_transform(i, xf)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		_forest.add_child(mi)


# ----------------------------------------------------------------- frame ---

const FRAME := 44         # cells of landscape beyond each map edge
const SEA := -0.22

## Scenery around the playable land: low hills and beaches toward the camera,
## forested slopes rising to rocky, snow-capped mountains on the far sides,
## the river running out to a surrounding sea. Nothing here can be built on.
func _build_frame() -> void:
	UI.clear(_frame)
	var L := layout
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#2b6f9e")
	sm.roughness = 0.35
	sea.material_override = sm
	sea.position = Vector3(L.w / 2.0, SEA, L.h / 2.0)
	_frame.add_child(sea)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2
	var trees := {}
	var rocks := {}
	for gz in range(-FRAME, L.h + FRAME, step):
		for gx in range(-FRAME, L.w + FRAME, step):
			if gx >= 0 and gz >= 0 and gx + step <= L.w and gz + step <= L.h:
				continue
			var q := [Vector2(gx, gz), Vector2(gx + step, gz), Vector2(gx + step, gz + step), Vector2(gx, gz + step)]
			var hs := []
			for v in q:
				hs.append(_land_h(v.x, v.y))
			for i in [0, 1, 2, 0, 2, 3]:
				var hv: float = hs[i]
				st.set_color(_land_color(hv, q[i]))
				st.add_vertex(Vector3(q[i].x, hv, q[i].y))
			# Scatter trees on green slopes and rocks on high ground.
			var c := Vector2(gx + 1, gz + 1)
			var hc := _land_h(c.x, c.y)
			var r := _hash(gx * 3 + 11, gz * 5 + 7)
			if hc > 0.35 and hc < 4.2 and r < 0.55:
				var k := int(_hash(gx, gz * 9) * 6.0) % 6
				trees.get_or_add(k, []).append(Vector3(c.x + (_hash(gx, gz) - 0.5), hc - 0.05, c.y + (_hash(gz, gx) - 0.5)))
			elif hc >= 4.2 and hc < 7.0 and r < 0.18:
				var k2 := int(_hash(gz, gx * 9) * 4.0) % 4
				rocks.get_or_add(k2, []).append(Vector3(c.x, hc - 0.1, c.y))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var land := MeshInstance3D.new()
	land.mesh = st.commit()
	land.material_override = mat
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.add_child(land)
	var tree_models := ["nature/tree_pineDefaultA", "nature/tree_pineRoundB", "nature/tree_pineTallA", "nature/tree_oak", "nature/tree_default", "nature/tree_pineSmallC"]
	var rock_models := ["nature/rock_largeA", "nature/rock_tallB", "nature/stone_largeC", "nature/rock_largeD"]
	_scatter(trees, tree_models, 0.75, 0.5)
	_scatter(rocks, rock_models, 1.4, 1.2)


func _scatter(spots: Dictionary, models: Array, base: float, spread: float) -> void:
	for k in spots:
		var mt: Array = Models.mesh(models[k])
		if mt.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mt[0]
		mm.instance_count = spots[k].size()
		for i in spots[k].size():
			var sc := base + _hash(i, k + 3) * spread
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _hash(k, i) * TAU).scaled(Vector3(sc, sc, sc)), spots[k][i]) * (mt[1] as Transform3D))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame.add_child(mi)


## Smooth value noise on a coarse lattice.
func _noise(x: float, z: float, cell: float) -> float:
	var fx := x / cell
	var fz := z / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := smoothstep(0.0, 1.0, fx - ix)
	var tz := smoothstep(0.0, 1.0, fz - iz)
	var a := lerpf(_hash(ix, iz), _hash(ix + 1, iz), tx)
	var b := lerpf(_hash(ix, iz + 1), _hash(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz)


## Height of the land outside the map; 0 at the map's edge.
func _land_h(x: float, z: float) -> float:
	var L := layout
	var cx := clampf(x, 0.0, L.w - 0.01)
	var cz := clampf(z, 0.0, L.h - 0.01)
	var d := Vector2(x - cx, z - cz).length()
	if d <= 0.0:
		return 0.0
	# The river carries on straight out to the sea.
	for o in [0, -2, 2]:
		var e := Vector2i(int(cx) + (o if absf(x - cx) < 0.001 else 0), int(cz) + (o if absf(z - cz) < 0.001 else 0))
		if L.inside(e) and L.kind(e) == CityLayout.WATER:
			return SEA - 0.3
	var n := _noise(x + 300, z + 300, 9.0) * 0.65 + _noise(x + 70, z + 10, 4.0) * 0.35
	var edge := clampf(d / 4.0, 0.0, 1.0)
	var far := 1.0 if (x < 0 or z < 0) else 0.0
	if x < 0 and z > L.h * 0.6 or z < 0 and x > L.w * 0.6:
		far = 0.5
	if far > 0.0:
		# Slopes up to a mountain ridge, then down to the sea far out.
		var ridge := sin(PI * clampf((d - 2.0) / 38.0, 0.0, 1.0))
		var h := ridge * (2.0 + 9.0 * n * n + 2.0 * _noise(x, z, 2.5)) * far + (1.0 - far) * (0.6 * n)
		if d > 36.0:
			h = lerpf(h, SEA - 0.6, clampf((d - 36.0) / 6.0, 0.0, 1.0))
		return h * edge
	# Toward the camera: gentle hills, then a beach.
	var hill := 0.5 + 1.1 * n
	var shore := clampf((d - 9.0) / 7.0, 0.0, 1.0)
	return lerpf(hill * edge, SEA - 0.5, shore)


func _land_color(h: float, at: Vector2) -> Color:
	var n := _noise(at.x + 40, at.y + 90, 3.0)
	if h < SEA + 0.25:
		return Color("#e3d39a").lerp(Color("#d6c486"), n)
	if h < 2.4:
		return Color("#7fbb5c").lerp(Color("#68a64c"), clampf(h / 2.4, 0.0, 1.0) * 0.7 + n * 0.3)
	if h < 5.2:
		return Color("#5f8f4a").lerp(Color("#8a8f86"), clampf((h - 2.4) / 2.8, 0.0, 1.0))
	if h < 8.0:
		return Color("#8d918a").lerp(Color("#a3a6a0"), n)
	return Color("#eef2f4").lerp(Color("#dde4e8"), n)


func _hash(x: int, y: int) -> float:
	var n := (x * 374761393 + y * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 1000) / 1000.0


# ----------------------------------------------------------------- roads ---

## A road piece for every road cell, chosen and turned by which neighbours
## are roads. Unjoined roads are tinted red; the main road has a sign.
func _build_roads() -> void:
	UI.clear(_roads)
	for p in layout.roads:
		var n := layout.roads.has(p + Vector2i(0, -1))
		var e := layout.roads.has(p + Vector2i(1, 0))
		var s := layout.roads.has(p + Vector2i(0, 1))
		var w := layout.roads.has(p + Vector2i(-1, 0))
		var count := int(n) + int(e) + int(s) + int(w)
		var piece := Models.ROAD_STRAIGHT
		var turn := 0.0
		if layout.is_bridge(p):
			piece = Models.ROAD_BRIDGE
			turn = 0.0 if (n or s) else 90.0
		elif count == 4:
			piece = Models.ROAD_CROSS
		elif count == 3:
			piece = Models.ROAD_T
			# The open side decides the turn.
			turn = 180.0 if not s else (90.0 if not w else (0.0 if not n else 270.0))
		elif count == 2 and ((n and s) or (e and w)):
			turn = 90.0 if (n and s) else 0.0
		elif count == 2:
			piece = Models.ROAD_BEND
			turn = 90.0 if (s and e) else (180.0 if (n and e) else (270.0 if (n and w) else 0.0))
		elif count == 1:
			piece = Models.ROAD_END
			turn = 90.0 if n else (180.0 if w else (270.0 if s else 0.0))
		else:
			piece = Models.ROAD_END
		var node := Models.spawn(piece)
		node.position = cell_center(p.x, p.y) + Vector3(0, 0.01, 0)
		node.rotation_degrees.y = turn
		if layout.is_bridge(p):
			node.position.y = -0.12
		if not layout.connected(p):
			_overlay_all(node, _red)
		_roads.add_child(node)


static func _overlay_all(node: Node, mat: Material) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = mat


# ------------------------------------------------------------- buildings ---

func _sig() -> String:
	return "%s|%d" % [str(layout.placements), layout.version]


func rebuild() -> void:
	if layout == null:
		return
	# Sites and roads keep the ground paved and free of trees.
	if _sig() != _ground_sig:
		_build_ground()
	UI.clear(_buildings)
	UI.clear(_marks)
	_grow.clear()
	for b in city.get("buildings", []):
		if layout.placements.has(int(b["tile"])):
			_add_building(b)
	if not placing.is_empty():
		var ghost := _compose(str(placing["type"]), str(placing["size"]), Vector2i(placing["at"]))
		_overlay_all(ghost, _ghost_ok if placing.get("ok", false) else _ghost_bad)
		_buildings.add_child(ghost)
		_mark_site(Vector2i(placing["at"]), Color(0.31, 0.9, 0.47, 0.35) if placing.get("ok", false) else Color(0.91, 0.36, 0.29, 0.4))
	if selected >= 0 and layout.placements.has(selected):
		_mark_site(layout.placements[selected], Color(1, 0.84, 0.3, 0.45))


## A building's models on its site, at its size.
func _compose(type: String, size: String, at: Vector2i) -> Node3D:
	var root := Models.compose(type, size, float(CityLayout.FOOT))
	root.position = Vector3(at.x + CityLayout.FOOT / 2.0, 0, at.y + CityLayout.FOOT / 2.0)
	return root


func _add_building(b: Dictionary) -> void:
	var t := int(b["tile"])
	var id := int(b["id"])
	var at: Vector2i = layout.placements[t]
	var node := _compose(str(b["type"]), str(b.get("size", "S")), at)
	_buildings.add_child(node)
	var p: Variant = _project_for(id)
	if b.get("status", "") != "complete" or p != null:
		# Under construction: a see-through outline of the finished building,
		# the solid part rising inside it, and a bar with the share done,
		# all from the server's ticks.
		var done := int(p["complete_tick"]) if p != null else tick + 1
		var start := int(b.get("created_tick", 0))
		var target := str(p.get("target_size", b.get("size", "S"))) if p != null else str(b.get("size", "S"))
		if p != null and str(p.get("kind", "")) == "upgrade":
			start = done - int(Catalogue.upgrade_to(str(b["type"]), target).get("seconds", 1))
		var ghost := _compose(str(b["type"]), target, at)
		_override_all(ghost, _blueprint)
		_marks.add_child(ghost)
		if b.get("visitor", false):
			# A rival's progress is not public: just the outline and a low frame.
			node.scale = Vector3(1, 0.15, 1)
		else:
			var bar := _progress_bar(node.position + Vector3(0, 2.7, 0))
			_grow.append([node, start, done, bar[0], bar[1]])
		_building_ids[id] = true
		for c in [Vector3(-0.95, 0, 0.95), Vector3(0.95, 0, -0.95)]:
			var cone := Models.spawn(Models.CONE)
			cone.position = node.position + c
			_marks.add_child(cone)
	elif _building_ids.has(id):
		# Just finished: a short pop and a ring of light.
		_building_ids.erase(id)
		_celebrate(node)
	var need: String = needs.get(t, "" if (read_only or layout.linked(t)) else "road")
	if need != "" and p == null:
		_overlay_all(node, _dim)
		_bubble(node.position + Vector3(0, 2.2, 0), need)


static func _override_all(node: Node, mat: Material) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A small bar and a percentage over a building site, always facing the camera.
func _progress_bar(at: Vector3) -> Array:
	var bg := Sprite3D.new()
	bg.texture = _bar_tex
	bg.modulate = Color(0.05, 0.09, 0.12, 0.8)
	bg.pixel_size = 0.026
	bg.scale = Vector3(1.06, 1.6, 1)
	bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg.no_depth_test = true
	bg.render_priority = 3
	bg.position = at
	_marks.add_child(bg)
	var fill := Sprite3D.new()
	fill.texture = _bar_tex
	fill.modulate = Color("#69e0b4")
	fill.pixel_size = 0.026
	fill.centered = false
	fill.offset = Vector2(-32, -4)
	fill.region_enabled = true
	fill.region_rect = Rect2(0, 0, 1, 8)
	fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fill.no_depth_test = true
	fill.render_priority = 4
	fill.position = at
	_marks.add_child(fill)
	var pct := Label3D.new()
	pct.font = UI.number_font()
	pct.font_size = 44
	pct.outline_size = 12
	pct.outline_modulate = Color(0.05, 0.09, 0.12, 0.9)
	pct.pixel_size = 0.012
	pct.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pct.no_depth_test = true
	pct.render_priority = 5
	pct.outline_render_priority = 4
	pct.position = at + Vector3(0, 0.38, 0)
	_marks.add_child(pct)
	return [fill, pct]


func _celebrate(node: Node3D) -> void:
	if UI.music and not read_only:
		UI.music.alert("built")
	node.scale = Vector3(1.12, 0.75, 1.12)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.05
	ring.mesh = tm
	var mat := _overlay(Color(1.0, 0.86, 0.4, 0.9))
	ring.material_override = mat
	ring.position = node.position + Vector3(0, 0.1, 0)
	_marks.add_child(ring)
	var t2 := ring.create_tween().set_parallel()
	t2.tween_property(ring, "scale", Vector3(2.2, 1, 2.2), 0.8).set_ease(Tween.EASE_OUT)
	t2.tween_property(mat, "albedo_color:a", 0.0, 0.8)


func _project_for(id: int) -> Variant:
	for p in city.get("projects", []):
		if p != null and int(p["building_id"]) == id:
			return p
	return null


## A flat coloured square on a site: selection or the ghost's footprint.
func _mark_site(at: Vector2i, c: Color) -> void:
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(CityLayout.FOOT + 0.3, CityLayout.FOOT + 0.3)
	q.mesh = pm
	q.material_override = _overlay(c)
	q.position = Vector3(at.x + CityLayout.FOOT / 2.0, 0.03, at.y + CityLayout.FOOT / 2.0)
	_marks.add_child(q)


## A thought bubble with what the building is missing, always facing the camera.
func _bubble(at: Vector3, need: String) -> void:
	var s := Sprite3D.new()
	s.texture = art.badge("bubble")
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.pixel_size = 0.012
	s.position = at
	s.render_priority = 1
	_marks.add_child(s)
	var icon := Sprite3D.new()
	match need:
		"road":
			icon.texture = art.icon("road")
			icon.modulate = Color("#d8402c")
			icon.pixel_size = 0.03
		"off":
			icon.texture = art.badge("warning")
			icon.pixel_size = 0.007
		_:
			icon.texture = art.badge(need)
			icon.pixel_size = 0.007
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.render_priority = 2
	icon.position = at + Vector3(0, 0.08, 0)
	_marks.add_child(icon)


func _notification(what: int) -> void:
	# Only the map on screen may own the view; a hidden map (the menu's
	# backdrop) must never keep the camera.
	if what == NOTIFICATION_VISIBILITY_CHANGED and camera:
		if is_visible_in_tree():
			camera.make_current()
		else:
			camera.clear_current(false)


func _process(delta: float) -> void:
	if visible and camera and not camera.current:
		camera.make_current()
	if demo and visible:
		camera.rotation_degrees.y = fmod(camera.rotation_degrees.y + delta * 2.2, 360.0)
		_place_camera()
	if not _grow.is_empty():
		var now: float = clock.call()
		for g in _grow:
			var f := clampf((now - float(g[1])) / maxf(float(g[2]) - float(g[1]), 1.0), 0.0, 1.0)
			(g[0] as Node3D).scale = Vector3(1, maxf(f, 0.04), 1)
			var fill := g[3] as Sprite3D
			if is_instance_valid(fill):
				# Eases toward the new tick's share instead of jumping.
				var w := lerpf(fill.region_rect.size.x, maxf(64.0 * f, 1.0), 0.2)
				fill.region_rect = Rect2(0, 0, w, 8)
				(g[4] as Label3D).text = "%d%%" % int(f * 100.0)


# ----------------------------------------------------------------- input ---

## The map cell under a screen point, by casting onto the ground.
func screen_to_cell(pos: Vector2) -> Vector2i:
	var g := _ground_point(pos)
	return Vector2i(int(floor(g.x)), int(floor(g.z)))


func _ground_point(pos: Vector2) -> Vector3:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	if absf(d.y) < 0.0001:
		return o
	return o + d * (-o.y / d.y)


func center_cell() -> Vector2i:
	return screen_to_cell(get_viewport().get_visible_rect().size / 2.0 - Vector2(200, 0))


func is_dragging_ghost() -> bool:
	return _ghost_drag or _painting


func _on_ghost(cell: Vector2i) -> bool:
	if placing.is_empty():
		return false
	return Rect2i(placing["at"], Vector2i(CityLayout.FOOT, CityLayout.FOOT)).grow(2).has_point(cell)


func _pan(from: Vector2, to: Vector2) -> void:
	_target += _ground_point(from) - _ground_point(to)
	_target.y = 0
	_place_camera()


## Lays or erases road cells along a finger stroke, filling gaps between
## sampled cells so fast strokes leave no holes.
func _paint(cell: Vector2i) -> void:
	var from := _last_paint if _last_paint.x > -999 else cell
	var changed := false
	var p := from
	while true:
		changed = (layout.add_road(p) if road_mode == "draw" else layout.remove_road(p)) or changed
		if p == cell:
			break
		var d := cell - p
		p += Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	_last_paint = cell
	if changed:
		save()
		_build_roads()
		rebuild()
		roads_changed.emit()


## Real touches on a phone and the real mouse on a desktop drive the map.
## Copies Godot makes of one from the other (device DEVICE_ID_EMULATION) are
## ignored: their positions can disagree with each other, which made the
## first drag jump across the map.
func _unhandled_input(event: InputEvent) -> void:
	if layout == null or not is_visible_in_tree() or demo:
		return
	var emulated := event.device == InputEvent.DEVICE_ID_EMULATION
	if event is InputEventScreenTouch and not emulated:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position)
	elif event is InputEventScreenDrag and not emulated:
		_move(event.index, event.position, event.relative)
	elif event is InputEventMouseButton and not emulated:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press(0, event.position)
				else:
					_release(0, event.position)
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed and not ui_blocks.call(event.position):
					zoom_by(1.12)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed and not ui_blocks.call(event.position):
					zoom_by(0.89)
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not emulated:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move(0, event.position, event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			# Desktop: right-drag always pans, also while drawing roads.
			_pan(event.position - event.relative, event.position)
	elif event is InputEventMagnifyGesture:
		# Touchpad pinch.
		zoom_by(event.factor)
	elif event is InputEventPanGesture:
		# Touchpad two-finger scroll moves the map.
		_pan(Vector2.ZERO, -event.delta * 12.0)
	elif event is InputEventKey and event.pressed:
		# Keyboard: arrows or WASD move, + and - zoom.
		var step := 40.0
		match event.keycode:
			KEY_LEFT, KEY_A:
				_pan(Vector2.ZERO, Vector2(step, 0))
			KEY_RIGHT, KEY_D:
				_pan(Vector2.ZERO, Vector2(-step, 0))
			KEY_UP, KEY_W:
				_pan(Vector2.ZERO, Vector2(0, step))
			KEY_DOWN, KEY_S:
				_pan(Vector2.ZERO, Vector2(0, -step))
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_by(1.2)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_by(0.83)


func _press(index: int, pos: Vector2) -> void:
	if ui_blocks.call(pos):
		return
	_touches[index] = pos
	if _touches.size() == 1:
		_drag = 0.0
		_ghost_drag = _on_ghost(screen_to_cell(pos))
		_painting = road_mode != "" and not _ghost_drag
		_last_paint = Vector2i(-999, -999)
		if _painting:
			_paint(screen_to_cell(pos))
	else:
		_ghost_drag = false
		_painting = false
	_pinch = 0.0
	get_viewport().set_input_as_handled()


func _release(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	if _ghost_drag and _touches.size() == 1:
		ghost_dropped.emit(screen_to_cell(pos))
	elif _touches.size() == 1 and _drag < 14.0 and not _painting:
		tapped.emit(layout.tile_at(screen_to_cell(pos)))
	_ghost_drag = false
	_painting = false
	_touches.erase(index)
	_pinch = 0.0
	get_viewport().set_input_as_handled()


func _move(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _touches.has(index):
		return
	var before: Vector2 = _touches[index]
	_touches[index] = pos
	if _touches.size() == 1 and _ghost_drag:
		ghost_dragged.emit(screen_to_cell(pos))
	elif _touches.size() == 1 and _painting:
		_paint(screen_to_cell(pos))
	elif _touches.size() == 1:
		# Each event's own movement is reliable; a stored press position may
		# not be (a pointer can jump between the press and the first move).
		_pan(pos - relative, pos)
		_drag += relative.length()
	elif _touches.size() >= 2:
		var pts: Array = _touches.values()
		var d: float = (pts[0] as Vector2).distance_to(pts[1])
		if _pinch > 0.0:
			zoom_by(d / _pinch)
		_pinch = d
		_pan(before, before + relative / 2.0)
		_drag = 99.0
	get_viewport().set_input_as_handled()
