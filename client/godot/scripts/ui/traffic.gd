class_name Traffic
extends Node2D
## Cars driving the streets. How many there are follows the city's real
## population and its working job buildings (factories, shops, services) from
## the last player_view; cars head mostly toward those workplaces. They keep
## their distance and wait their turn at junctions, so busy streets jam.
## Traffic is scenery: the engine has no roads and congestion changes nothing
## in the game.

const GAP := 0.9            # cells between cars in a lane
const JUNCTION_GAP := 0.45  # seconds between cars crossing a junction
const COLORS := ["#e85d4a", "#3d9be9", "#f2b33d", "#f5f7f8", "#4caf7a", "#8e7cf0"]

var layout: CityLayout
var target := 0
var congestion := 0.0       # share of cars stopped, 0..1
var _cars: Array = []
var _junction_free := {}    # node -> time it may next be crossed
var _jobs: Array[Vector2i] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _version := -1


func _ready() -> void:
	_rng.seed = 2050


## Cars follow residents and working job buildings that are on the road network.
func set_demand(city: Dictionary, l: CityLayout) -> void:
	layout = l
	var jobs := 0
	_jobs.clear()
	for b in city.get("buildings", []):
		var t := int(b["tile"])
		if str(b["type"]) in ["factory", "commercial_district", "public_services_center"] and b.get("status", "") == "complete" and b.get("operational", false) and l.placements.has(t):
			jobs += 1
			var r := l.rect(t)
			_jobs.append(Vector2i(r.position.x - 1, r.position.y - 1))
	target = clampi(int(float(city.get("population", 0)) / 45.0) + jobs * 6, 6, 90)


func _process(delta: float) -> void:
	if layout == null or layout.nodes.is_empty():
		return
	if layout.version != _version:
		# The player redrew roads: keep only cars still on a street.
		_version = layout.version
		_cars = _cars.filter(func(c): return layout.links.has(c["from"]) and c["to"] in layout.links[c["from"]])
	_time += delta
	if _cars.size() < target and _rng.randf() < delta * 4.0:
		_spawn()
	var stopped := 0
	for car in _cars:
		_move(car, delta)
		if car["wait"] > 0.5:
			stopped += 1
	congestion = float(stopped) / maxf(_cars.size(), 1)
	# Too many cars: the ones that just arrived somewhere park and vanish.
	if _cars.size() > target:
		for i in range(_cars.size() - 1, -1, -1):
			if _cars[i]["d"] < 0.05:
				_cars.remove_at(i)
				break
	queue_redraw()


func _spawn() -> void:
	var a: Vector2i = layout.nodes[_rng.randi() % layout.nodes.size()]
	var nexts: Array = layout.links.get(a, [])
	if nexts.is_empty():
		return
	var b: Vector2i = nexts[_rng.randi() % nexts.size()]
	_cars.append({"from": a, "to": b, "d": 0.0, "speed": _rng.randf_range(2.2, 3.2), "wait": 0.0,
		"color": Color(COLORS[_rng.randi() % COLORS.size()])})


func _len(car: Dictionary) -> float:
	return Vector2(car["to"] - car["from"]).length()


func _move(car: Dictionary, delta: float) -> void:
	var length := _len(car)
	# Distance to the car ahead in the same lane.
	var room := INF
	for other in _cars:
		if other != car and other["from"] == car["from"] and other["to"] == car["to"] and other["d"] > car["d"]:
			room = minf(room, other["d"] - car["d"] - GAP)
	var step: float = car["speed"] * delta
	var move := clampf(minf(step, room), 0.0, step)
	if car["d"] + move >= length:
		# At the junction: cross only when it is free.
		var node: Vector2i = car["to"]
		if _time < float(_junction_free.get(node, 0.0)):
			car["d"] = length
			car["wait"] += delta
			return
		_junction_free[node] = _time + JUNCTION_GAP
		car["from"] = node
		car["to"] = _next(node, car)
		car["d"] = 0.0
		car["wait"] = 0.0
		return
	car["d"] += move
	car["wait"] = car["wait"] + delta if move < step * 0.3 else 0.0


## Mostly toward a workplace, sometimes anywhere, rarely straight back.
func _next(node: Vector2i, car: Dictionary) -> Vector2i:
	var options: Array = layout.links.get(node, []).duplicate()
	if options.is_empty():
		return car["from"]   # dead end: turn around
	if options.size() > 1:
		options.erase(car["from"])
	if not _jobs.is_empty() and _rng.randf() < 0.7:
		var goal: Vector2i = _jobs[_rng.randi() % _jobs.size()]
		options.sort_custom(func(a, b): return Vector2(a).distance_squared_to(Vector2(goal)) < Vector2(b).distance_squared_to(Vector2(goal)))
		return options[0]
	return options[_rng.randi() % options.size()]


func _draw() -> void:
	for car in _cars:
		var a := Vector2(car["from"]) + Vector2(0.5, 0.5)
		var b := Vector2(car["to"]) + Vector2(0.5, 0.5)
		var dir := (b - a).normalized()
		# Drive on the right half of the street.
		var lane := Vector2(-dir.y, dir.x) * 0.22
		var p := a + dir * float(car["d"]) + lane
		var c := CityMap.iso(p.x, p.y)
		var along := CityMap.iso(dir.x, dir.y) * 0.32
		var side := CityMap.iso(-dir.y, dir.x) * 0.16
		var body := PackedVector2Array([c - along - side, c + along - side, c + along + side, c - along + side])
		var col: Color = car["color"]
		draw_colored_polygon(body, col.darkened(0.25))
		var roof := PackedVector2Array()
		for v in body:
			roof.append(v + Vector2(0, -2.2))
		draw_colored_polygon(roof, col)
		if car["wait"] > 0.5:
			draw_circle(c - along + Vector2(0, -1.5), 0.9, Color("#ff3b2f"))
