class_name CityLayout
extends RefCounted
## The map a player designs: open land with a river, floodplain and forests,
## one main road that cannot be removed, the roads the player draws (free),
## and where each building stands.
##
## The engine knows a city as 36 building sites (tiles 0–35) and nothing about
## where they are. This layout gives each tile a spot on the map, chosen by the
## player. It is saved on the device, per match and seat.
##
## Road rule: a building works only when it touches a road connected to the
## main road. The client enforces this with the engine's own disable/enable
## commands (see Play), so an unconnected building really stops working.

const FOOT := 2          # every building stands on a 2×2 site
const SIZE := 46
const SITES := 36        # engine tiles

const GRASS := 0
const FOREST := 1
const FLOOD := 2
const WATER := 3

var key := ""
var w := SIZE
var h := SIZE
var terrain := PackedByteArray()
var main_road := {}                 # Vector2i -> true, fixed
var roads := {}                     # Vector2i -> true, main road included
var placements := {}                # tile -> Vector2i top corner of its 4×4 site
var road_off := {}                  # building id -> true: switched off by the road rule
var nodes: Array[Vector2i] = []     # traffic graph: junctions, bends, ends
var links := {}
var version := 0                    # bumps whenever the road network changes
var _connected := {}                # road cells reachable from the main road
var _rng := RandomNumberGenerator.new()


func _init(k: String = "equilibrium") -> void:
	key = k
	_rng.seed = hash(k)
	terrain.resize(w * h)
	_river()
	_main_road()
	_forests()
	_refresh()


func center() -> Vector2:
	return Vector2(w / 2.0, h / 2.0)


func kind(p: Vector2i) -> int:
	return _at(p.x, p.y)


func is_bridge(p: Vector2i) -> bool:
	return roads.has(p) and kind(p) == WATER


func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


# --------------------------------------------------------------- buildings ---

func rect(tile: int) -> Rect2i:
	return Rect2i(placements[tile], Vector2i(FOOT, FOOT))


func tile_at(cell: Vector2i) -> int:
	for t in placements:
		if rect(t).has_point(cell):
			return t
	return -1


## Why a building cannot stand with its top corner here, or "".
func why_not(at: Vector2i, ignore := -1) -> String:
	var r := Rect2i(at, Vector2i(FOOT, FOOT))
	if at.x < 1 or at.y < 1 or r.end.x > w - 1 or r.end.y > h - 1:
		return "off the map"
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if kind(p) == WATER:
				return "on water"
			if roads.has(p):
				return "on a road"
	for t in placements:
		if t != ignore and rect(t).intersects(r):
			return "on another building"
	return ""


func place(tile: int, at: Vector2i) -> void:
	placements[tile] = at
	_refresh()


func unplace(tile: int) -> void:
	placements.erase(tile)
	_refresh()


## A spot for a building the player did not place on this device (a Foundation
## building, or a match continued elsewhere): right beside the main road, near
## the centre, so it is connected.
func auto_place(tile: int) -> void:
	var at := spot_beside_main()
	if at.x >= 0:
		place(tile, at)


## The free site touching the main road that is nearest the centre.
func spot_beside_main() -> Vector2i:
	var c := center()
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p in main_road:
		for off in [Vector2i(1, -1), Vector2i(-FOOT, -1), Vector2i(-1, 1), Vector2i(-1, -FOOT)]:
			var at: Vector2i = p + off
			if why_not(at) != "":
				continue
			var d := Vector2(at).distance_to(c)
			if d < best_d:
				best_d = d
				best = at
	return best


## Whether the building on tile touches a road joined to the main road.
func linked(tile: int) -> bool:
	if not placements.has(tile):
		return false
	var r := rect(tile)
	for i in FOOT:
		for p in [Vector2i(r.position.x + i, r.position.y - 1), Vector2i(r.position.x + i, r.end.y),
				Vector2i(r.position.x - 1, r.position.y + i), Vector2i(r.end.x, r.position.y + i)]:
			if _connected.has(p):
				return true
	return false


func connected(p: Vector2i) -> bool:
	return _connected.has(p)


# ------------------------------------------------------------------- roads ---

## Lays a road cell; roads are free. Returns false where one cannot go.
func add_road(p: Vector2i) -> bool:
	if not inside(p) or roads.has(p) or tile_at(p) >= 0:
		return false
	roads[p] = true
	_refresh()
	return true


## Removes a player road; the main road stays.
func remove_road(p: Vector2i) -> bool:
	if not roads.has(p) or main_road.has(p):
		return false
	roads.erase(p)
	_refresh()
	return true


func _refresh() -> void:
	# Roads joined to the main road, by flood fill.
	_connected.clear()
	var todo: Array[Vector2i] = []
	for p in main_road:
		_connected[p] = true
		todo.append(p)
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if roads.has(q) and not _connected.has(q):
				_connected[q] = true
				todo.append(q)
	_graph()


# ------------------------------------------------------------- persistence ---

func save(path: String) -> void:
	var own_roads := []
	for p in roads:
		if not main_road.has(p):
			own_roads.append([p.x, p.y])
	var spots := {}
	for t in placements:
		spots[str(t)] = [placements[t].x, placements[t].y]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"key": key, "roads": own_roads, "placements": spots, "road_off": road_off.keys()}))


func load_from(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("key") != key:
		return
	for p in data.get("roads", []):
		roads[Vector2i(int(p[0]), int(p[1]))] = true
	for t in data.get("placements", {}):
		var p: Array = data["placements"][t]
		placements[int(t)] = Vector2i(int(p[0]), int(p[1]))
	for id in data.get("road_off", []):
		road_off[int(id)] = true
	_refresh()


# --------------------------------------------------------------- generation ---

func _put(x: int, y: int, t: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		terrain[y * w + x] = t


func _at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return terrain[y * w + x]


## A river winding west to east, with floodplain banks.
func _river() -> void:
	var phase := _rng.randf() * TAU
	var base := int(h * 0.38) + _rng.randi_range(-2, 2)
	for x in w:
		var mid := base + int(round(sin(x * 0.15 + phase) * 3.0 + sin(x * 0.05 + phase * 2.0) * 2.0))
		for k in 3:
			_put(x, mid + k, WATER)
		for y in [mid - 1, mid + 3]:
			if _at(x, y) == GRASS:
				_put(x, y, FLOOD)
		if _rng.randf() < 0.35:
			for y in [mid - 2, mid + 4]:
				if _at(x, y) == GRASS:
					_put(x, y, FLOOD)


## The main road: from the north edge to the south edge through the middle,
## crossing the river on a bridge, with one bend so it is not a ruler line.
func _main_road() -> void:
	var x := w / 2 + _rng.randi_range(-3, 3)
	var bend := int(h * 0.62) + _rng.randi_range(-3, 3)
	var shift := _rng.randi_range(4, 8) * (1 if _rng.randf() < 0.5 else -1)
	for y in range(0, bend):
		main_road[Vector2i(x, y)] = true
	for i in range(0, absi(shift) + 1):
		main_road[Vector2i(x + i * signi(shift), bend)] = true
	for y in range(bend, h):
		main_road[Vector2i(x + shift, y)] = true
	for p in main_road:
		roads[p] = true


func _forests() -> void:
	var seeds := []
	# A few woods, mostly toward the edges, so the middle stays open to build on.
	for i in 9:
		var p := Vector2(_rng.randf() * w, _rng.randf() * h)
		if p.distance_to(center()) < w * 0.22:
			p = center() + (p - center()).normalized() * w * 0.32
		seeds.append([p, _rng.randf_range(2.5, 5.5)])
	for y in h:
		for x in w:
			if _at(x, y) != GRASS or roads.has(Vector2i(x, y)):
				continue
			for s in seeds:
				if Vector2(x, y).distance_to(s[0]) < s[1] * (0.75 + _rng.randf() * 0.5):
					_put(x, y, FOREST)
					break


## Street graph for cars: junctions, bends and ends, linked along roads.
func _graph() -> void:
	version += 1
	nodes.clear()
	links.clear()
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for p in roads:
		var seen := []
		for d in dirs:
			if roads.has(p + d):
				seen.append(d)
		if seen.is_empty() or (seen.size() == 2 and seen[0] == -seen[1]):
			continue
		nodes.append(p)
	var is_node := {}
	for p in nodes:
		is_node[p] = true
	for p in nodes:
		var out: Array[Vector2i] = []
		for d in dirs:
			var q: Vector2i = p + d
			if not roads.has(q):
				continue
			while not is_node.has(q) and roads.has(q + d):
				q += d
			if is_node.has(q) and q != p:
				out.append(q)
		links[p] = out
