extends SceneTree
## Renders every road shape in every direction from straight above, to check
## that road pieces are turned to match their neighbours.
##   godot --path client/godot --script res://tests/roads_view.gd -- /tmp/roads.png
var map: CityMap
var t := 0.0
var out := "/tmp/roads.png"

func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	map = CityMap.new()
	map.art = Art.new()
	UI.art = map.art
	root.add_child(map)


func _setup() -> void:
	var L := CityLayout.new("roads-view")
	L.roads.clear()
	L.main_road.clear()
	L.placements.clear()
	for i in L.terrain.size():
		L.terrain[i] = CityLayout.GRASS
	# A plus, four T's, four bends, four ends and straights, spaced apart.
	var cells := []
	var c := Vector2i(10, 10)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		cells.append(c + d)
	for o in [Vector2i(16, 4), Vector2i(16, 10), Vector2i(16, 16), Vector2i(4, 16)]:
		cells.append(o)
	# T's: open side S, W, N, E
	for spec in [[Vector2i(22, 4), [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]], [Vector2i(22, 10), [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]],
			[Vector2i(22, 16), [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]], [Vector2i(22, 22), [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]]]:
		cells.append(spec[0])
		for d in spec[1]:
			cells.append(spec[0] + d)
	# Bends: S+E, N+E, N+W, S+W
	for spec in [[Vector2i(4, 4), [Vector2i(0, 1), Vector2i(1, 0)]], [Vector2i(4, 22), [Vector2i(0, -1), Vector2i(1, 0)]], [Vector2i(10, 22), [Vector2i(0, -1), Vector2i(-1, 0)]], [Vector2i(16, 22), [Vector2i(0, 1), Vector2i(-1, 0)]]]:
		cells.append(spec[0])
		for d in spec[1]:
			cells.append(spec[0] + d)
	for i in 5:
		cells.append(Vector2i(28, 2 + i))      # north-south straight
		cells.append(Vector2i(26 + i, 10))     # east-west straight
	for p in cells:
		L.roads[p] = true
		L.main_road[p] = true
	L._refresh()
	map.layout = L
	map.traffic.layout = L
	map._build_ground()
	map._build_roads()
	map.camera.rotation_degrees = Vector3(-90, 0, 0)
	map.camera.size = float(OS.get_environment("VIEW_SIZE") if OS.get_environment("VIEW_SIZE") != "" else "30")
	var cx := float(OS.get_environment("VIEW_X") if OS.get_environment("VIEW_X") != "" else "13")
	var cz := float(OS.get_environment("VIEW_Z") if OS.get_environment("VIEW_Z") != "" else "13")
	map.camera.position = Vector3(cx, 50, cz)
	DisplayServer.window_set_size(Vector2i(900, 900))

var done_setup := false

func _process(d: float) -> bool:
	if not done_setup:
		done_setup = true
		_setup()
	t += d
	if t > 1.5:
		root.get_texture().get_image().save_png(out)
		print("saved")
		quit()
	return false
