class_name CityMap
extends Node2D
## The city as an open isometric map the player designs: land, river and
## forests, the fixed main road, the player's own roads with traffic, and
## the buildings where the player put them. Buildings show the last
## player_view: construction progress, switched off, or cut off from the road
## network.
##
## Gestures: one finger pans (or draws roads in road mode, or drags the
## building being placed); two fingers pinch to zoom and pan; tap a building
## to select it.

signal tapped(tile: int)                 # -1: open ground
signal ghost_dragged(cell: Vector2i)
signal ghost_dropped(cell: Vector2i)
signal roads_changed

const HW := 16.0
const HH := 8.0

var art: Art
var layout: CityLayout
var city: Dictionary = {}
var tick := 0
var selected := -1
var placing: Dictionary = {}             # {type, at, ok, why}
var road_mode := ""                      # "", "draw", "erase"
var needs := {}                          # tile -> what the building lacks: road, off, coin, power, people, waste
var stale := false
var ui_blocks: Callable = func(_p: Vector2) -> bool: return false
var clock: Callable = func() -> float: return 0.0

var camera: Camera2D
var traffic: Traffic
var objects: Node2D
var over: Node2D
var _touches := {}
var _drag := 0.0
var _pinch := 0.0
var _ghost_drag := false
var _painting := false
var _last_paint := Vector2i(-999, -999)
var _rotors: Array[Sprite2D] = []
var _bars: Array = []
var _bubbles: Array[Sprite2D] = []
var _key := ""
var _path := ""


func _ready() -> void:
	traffic = Traffic.new()
	traffic.z_index = 1
	add_child(traffic)
	objects = Node2D.new()
	objects.y_sort_enabled = true
	objects.z_index = 2
	add_child(objects)
	over = Node2D.new()
	over.z_index = 5
	add_child(over)
	over.draw.connect(_draw_overlay)
	camera = Camera2D.new()
	camera.zoom = Vector2(1.15, 1.15)
	add_child(camera)


static func iso(u: float, v: float, z := 0.0) -> Vector2:
	return Vector2((u - v) * HW, (u + v) * HH - z)


func cell_poly(x: float, y: float, inset := 0.0) -> PackedVector2Array:
	return PackedVector2Array([iso(x + inset, y + inset), iso(x + 1 - inset, y + inset), iso(x + 1 - inset, y + 1 - inset), iso(x + inset, y + 1 - inset)])


func rect_poly(r: Rect2i, inset := 0.0) -> PackedVector2Array:
	return PackedVector2Array([iso(r.position.x + inset, r.position.y + inset), iso(r.end.x - inset, r.position.y + inset), iso(r.end.x - inset, r.end.y - inset), iso(r.position.x + inset, r.end.y - inset)])


## Shows a city. A new key (match and seat) loads that design from the device.
## Buildings without a spot here (a Foundation building, or a match continued
## from another device) are placed beside the main road. reserved holds tiles
## whose construction is on its way to the server.
func show_city(c: Dictionary, now_tick: int, key: String, reserved: Dictionary = {}) -> void:
	if key != _key or layout == null:
		_key = key
		_path = "user://layout_%s.json" % key.md5_text()
		layout = CityLayout.new(key)
		layout.load_from(_path)
		traffic.layout = layout
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
	traffic.set_demand(c, layout)
	rebuild()


func save() -> void:
	if layout and _path != "":
		layout.save(_path)


func recenter() -> void:
	camera.position = iso(layout.center().x, layout.center().y) + Vector2(110, 0) / camera.zoom.x


func zoom_by(f: float) -> void:
	var z := clampf(camera.zoom.x * f, 0.6, 4.0)
	camera.zoom = Vector2(z, z)


func building_on(tile: int) -> Dictionary:
	for b in city.get("buildings", []):
		if int(b["tile"]) == tile:
			return b
	return {}


# ---------------------------------------------------------------- ground ---

func _hash(x: int, y: int) -> float:
	var n := (x * 374761393 + y * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 1000) / 1000.0


func _draw() -> void:
	if layout == null:
		return
	var L := layout
	for y in L.h:
		for x in L.w:
			var p := Vector2i(x, y)
			var n := _hash(x, y)
			var col: Color
			match L.kind(p):
				CityLayout.WATER:
					col = Color("#4fa3d9").lerp(Color("#3b8cc6"), n * 0.6)
				CityLayout.FLOOD:
					col = Color("#a9cc8f").lerp(Color("#9bc283"), n)
				CityLayout.FOREST:
					col = Color("#7cb85c").lerp(Color("#6aa64e"), n)
				_:
					col = Color("#8cc56a").lerp(Color("#7ab85c"), n * 0.8)
			draw_colored_polygon(cell_poly(x, y), col)
			if L.kind(p) == CityLayout.FLOOD:
				var c := iso(x + 0.5, y + 0.5)
				draw_line(c + Vector2(-3, 1), c + Vector2(-3, -2), Color(0.2, 0.45, 0.5, 0.45), 0.6)
				draw_line(c + Vector2(2, 2), c + Vector2(2, -1.5), Color(0.2, 0.45, 0.5, 0.45), 0.6)
	for t in L.placements:
		var r := L.rect(t)
		draw_colored_polygon(rect_poly(r), Color("#c9c3b2"))
		draw_polyline(rect_poly(r) + PackedVector2Array([rect_poly(r)[0]]), Color(1, 1, 1, 0.35), 0.8)
	for p in L.roads:
		_draw_road(p)
	for y in L.h:
		for x in L.w:
			var p := Vector2i(x, y)
			if L.kind(p) == CityLayout.FOREST and not L.roads.has(p) and L.tile_at(p) < 0:
				for k in 2:
					var c := iso(x + 0.3 + _hash(x + k, y) * 0.4, y + 0.3 + _hash(y, x + k) * 0.4)
					_tree(c, 0.8 + _hash(x * 3 + k, y) * 0.4, k)


func _tree(c: Vector2, s: float, k: int) -> void:
	draw_line(c, c - Vector2(0, 3 * s), Color("#7a5233"), 1.0)
	draw_circle(c - Vector2(0, 5.5 * s), 3.6 * s, Color("#3c7d3b") if k == 0 else Color("#4f9a48"))


func _draw_road(p: Vector2i) -> void:
	var bridge := layout.is_bridge(p)
	var main := layout.main_road.has(p)
	var poly := cell_poly(p.x, p.y)
	var col := Color("#b08a5b") if bridge else (Color("#4a505e") if main else Color("#5b6170"))
	draw_colored_polygon(poly, col)
	if not layout.connected(p):
		draw_colored_polygon(poly, Color(0.91, 0.36, 0.29, 0.45))
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(1, 1, 1, 0.18), 0.5)
	var c := iso(p.x + 0.5, p.y + 0.5)
	var mark := Color("#f2c230", 0.9) if main else Color("#f4f1e6", 0.85)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if layout.roads.has(p + d):
			var e := iso(p.x + 0.5 + d.x * 0.5, p.y + 0.5 + d.y * 0.5)
			draw_line(c.lerp(e, 0.25), c.lerp(e, 0.85), mark, 0.8 if main else 0.6)


# --------------------------------------------------------------- objects ---

func rebuild() -> void:
	if layout == null:
		return
	UI.clear(objects)
	_rotors.clear()
	_bars.clear()
	_bubbles.clear()
	for b in city.get("buildings", []):
		if layout.placements.has(int(b["tile"])):
			_add_building(b)
	if not placing.is_empty():
		_add_sprite(Catalogue.sprite(placing["type"], 1), Rect2i(placing["at"], Vector2i(CityLayout.FOOT, CityLayout.FOOT)), {"ghost": true, "ok": placing.get("ok", false)})
	queue_redraw()
	over.queue_redraw()


func _project_for(id: int) -> Variant:
	for p in city.get("projects", []):
		if p != null and int(p["building_id"]) == id:
			return p
	return null


func _add_building(b: Dictionary) -> void:
	var t := int(b["tile"])
	var linked := layout.linked(t)
	var st := {"pending": b.get("status", "") != "complete", "enabled": b.get("enabled", true),
		"running": b.get("operational", true) or tick == 0, "cut_off": not linked}
	var node := _add_sprite(Catalogue.sprite(str(b["type"]), int(b.get("level", 1))), layout.rect(t), st)
	if node == null:
		return
	var top := iso(layout.rect(t).position.x + 2.0, layout.rect(t).position.y + 2.0) - node.position + Vector2(-16, -44)
	var p: Variant = _project_for(int(b["id"]))
	if p != null:
		var done := int(p["complete_tick"])
		var start := int(b.get("created_tick", 0))
		if str(p.get("kind", "")) == "upgrade":
			start = done - int(Catalogue.spec(str(b["type"])).get("upgrade", {}).get("duration_seconds", 1))
		var bg := Polygon2D.new()
		bg.polygon = PackedVector2Array([top + Vector2(-1, -1), top + Vector2(33, -1), top + Vector2(33, 4), top + Vector2(-1, 4)])
		bg.color = Color(0.06, 0.1, 0.14, 0.85)
		node.add_child(bg)
		var fill := Polygon2D.new()
		fill.polygon = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 3), Vector2(0, 3)])
		fill.position = top
		fill.color = Color("#f3c86b")
		node.add_child(fill)
		_bars.append([fill, start, done, 32.0])
	var need: String = needs.get(t, "road" if not linked else "")
	if need != "" and p == null:
		# A thought bubble with what the building is missing.
		var bubble := Sprite2D.new()
		bubble.texture = art.badge("bubble")
		bubble.scale = Vector2(0.3, 0.3)
		bubble.position = top + Vector2(16, -12)
		bubble.set_meta("y", bubble.position.y)
		var mark := Sprite2D.new()
		match need:
			"road":
				mark.texture = art.icon("road")
				mark.modulate = Color("#d8402c")
				mark.scale = Vector2(1.25, 1.25)
			"off":
				mark.texture = art.badge("warning")
				mark.scale = Vector2(0.5, 0.5)
			_:
				mark.texture = art.badge(need)
				mark.scale = Vector2(0.55, 0.55)
		mark.position = Vector2(0, -6)
		bubble.add_child(mark)
		node.add_child(bubble)
		_bubbles.append(bubble)


## Draws a sprite centred in a 4×4 site.
func _add_sprite(name: String, r: Rect2i, st: Dictionary) -> Node2D:
	var info := art.info(name)
	var tex := art.sprite(name)
	if info.is_empty() or tex == null:
		return null
	var fw := int(info["w"])
	var fh := int(info["h"])
	var at := Vector2i(r.position.x + (CityLayout.FOOT - fw) / 2, r.position.y + (CityLayout.FOOT - fh) / 2)
	var node := Node2D.new()
	node.position = iso(at.x + fw, at.y + fh)
	objects.add_child(node)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.scale = Vector2.ONE / Art.SPRITE_SCALE
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var top := iso(at.x, at.y)
	spr.position = top + Vector2(info["offset"][0], info["offset"][1]) - node.position
	node.add_child(spr)
	if st.get("ghost", false):
		spr.modulate = Color(0.75, 1, 0.8, 0.85) if st["ok"] else Color(1, 0.6, 0.55, 0.8)
	elif st.get("pending", false):
		spr.modulate = Color(1, 0.95, 0.8, 0.5)
	elif st.get("cut_off", false) or not st.get("enabled", true):
		spr.modulate = Color(0.55, 0.58, 0.66)
	elif not st.get("running", true):
		spr.modulate = Color(0.72, 0.75, 0.86)
	var live: bool = not st.get("ghost", false) and not st.get("pending", false) and st.get("enabled", true) and st.get("running", true) and not st.get("cut_off", false)
	for kind in info.get("anchors", {}):
		for a in info["anchors"][kind]:
			var local := top + Vector2(a[0], a[1]) - node.position
			if kind == "rotor":
				var rotor := Sprite2D.new()
				rotor.texture = art.sprite("rotor")
				rotor.scale = Vector2.ONE / Art.SPRITE_SCALE
				rotor.position = local
				rotor.set_meta("spin", live)
				node.add_child(rotor)
				_rotors.append(rotor)
			elif live:
				var smoke := Smoke.new()
				smoke.kind = kind
				smoke.seed = fmod(local.x * 0.37 + local.y * 0.11, 1.0)
				smoke.position = local
				node.add_child(smoke)
	return node


func _process(delta: float) -> void:
	for r in _rotors:
		if r.get_meta("spin", false):
			r.rotation += delta * 2.4
	var tsec := Time.get_ticks_msec() / 1000.0
	for b in _bubbles:
		b.position.y = float(b.get_meta("y")) + sin(tsec * 4.0) * 1.5
	if not _bars.is_empty():
		var now: float = clock.call()
		for bar in _bars:
			var f := clampf((now - float(bar[1])) / maxf(float(bar[2]) - float(bar[1]), 1.0), 0.0, 1.0)
			(bar[0] as Polygon2D).scale = Vector2(maxf(f * float(bar[3]), 0.5), 1)
	if selected >= 0 or not placing.is_empty():
		over.queue_redraw()


# --------------------------------------------------------------- overlay ---

func _draw_overlay() -> void:
	if layout == null:
		return
	var t_ms := Time.get_ticks_msec() / 1000.0
	if not placing.is_empty():
		var r := Rect2i(placing["at"], Vector2i(CityLayout.FOOT, CityLayout.FOOT))
		var poly := rect_poly(r)
		over.draw_colored_polygon(poly, Color(0.31, 0.9, 0.47, 0.35) if placing.get("ok", false) else Color(0.91, 0.36, 0.29, 0.4))
		over.draw_polyline(poly + PackedVector2Array([poly[0]]), Color.WHITE, 1.2)
	if selected >= 0 and layout.placements.has(selected):
		var a := 0.6 + 0.4 * sin(t_ms * 5.0)
		var poly := rect_poly(layout.rect(selected), -0.15)
		over.draw_polyline(poly + PackedVector2Array([poly[0]]), Color(1, 1, 1, a), 2.0)
	if stale:
		var vp := get_viewport_rect().size
		var inv := get_canvas_transform().affine_inverse()
		over.draw_rect(Rect2(inv * Vector2.ZERO, inv.basis_xform(vp)), Color(0.06, 0.1, 0.14, 0.3))


# ----------------------------------------------------------------- input ---

func screen_to_cell(pos: Vector2) -> Vector2i:
	var wp := get_canvas_transform().affine_inverse() * pos
	var a := wp.x / HW
	var b := wp.y / HH
	return Vector2i(int(floor((a + b) / 2.0)), int(floor((b - a) / 2.0)))


func center_cell() -> Vector2i:
	return screen_to_cell(get_viewport().get_visible_rect().size / 2.0 - Vector2(200, 0))


func is_dragging_ghost() -> bool:
	return _ghost_drag or _painting


func _on_ghost(cell: Vector2i) -> bool:
	if placing.is_empty():
		return false
	return Rect2i(placing["at"], Vector2i(CityLayout.FOOT, CityLayout.FOOT)).grow(2).has_point(cell)


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
		queue_redraw()
		rebuild()
		roads_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if layout == null or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and ui_blocks.call(event.position):
			return
		if not event.pressed and not _touches.has(event.index):
			return
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_drag = 0.0
				_ghost_drag = _on_ghost(screen_to_cell(event.position))
				_painting = road_mode != "" and not _ghost_drag
				_last_paint = Vector2i(-999, -999)
				if _painting:
					_paint(screen_to_cell(event.position))
			else:
				_ghost_drag = false
				_painting = false
			_pinch = 0.0
		else:
			if _ghost_drag and _touches.size() == 1:
				ghost_dropped.emit(screen_to_cell(event.position))
			elif _touches.size() == 1 and _drag < 14.0 and not _painting:
				tapped.emit(layout.tile_at(screen_to_cell(event.position)))
			_ghost_drag = false
			_painting = false
			_touches.erase(event.index)
			_pinch = 0.0
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		_touches[event.index] = event.position
		if _touches.size() == 1 and _ghost_drag:
			ghost_dragged.emit(screen_to_cell(event.position))
		elif _touches.size() == 1 and _painting:
			_paint(screen_to_cell(event.position))
		elif _touches.size() == 1:
			camera.position -= event.relative / camera.zoom.x
			_drag += event.relative.length()
		elif _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch > 0.0:
				zoom_by(d / _pinch)
			_pinch = d
			camera.position -= event.relative / camera.zoom.x / 2.0
			_drag = 99.0
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not ui_blocks.call(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(0.89)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		# Desktop: right-drag pans, also while drawing roads.
		camera.position -= event.relative / camera.zoom.x
