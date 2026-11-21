extends SceneTree
## Screenshots of the screens that need no server: menu, address errors,
## How to Play (top and scrolled), Settings. Also checks address validation.
##
##   godot --path client/godot --script res://tests/menu_shots.gd -- /tmp/shots 1170x540

var app: Node
var step := 0
var t := 0.0
var out := "/tmp/shots"
var size := Vector2i(1170, 540)
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1:
		var p := args[1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(size)
	_check_addresses()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)


func _check_addresses() -> void:
	var good := ["192.168.1.20:9080", "localhost:9080", "my-server.example.org:443", "10.0.0.5", "[::1]:9080", "ws://10.0.0.5:9080"]
	var bad := ["", "192.168.1:9080", "300.1.1.1:9080", "host:99999", "host:abc", "ho st:1", "a/b:1", ":9080"]
	for a in good:
		if Settings.address_problem(a) != "":
			failures += 1
			print("FAIL should accept ", a, " -> ", Settings.address_problem(a))
	for a in bad:
		if Settings.address_problem(a) == "":
			failures += 1
			print("FAIL should reject ", a)
	Settings.secure = false
	_expect(Settings.address_to_url("10.0.0.5:9081"), "ws://10.0.0.5:9081")
	_expect(Settings.address_to_url("10.0.0.5"), "ws://10.0.0.5:9080")
	Settings.secure = true
	_expect(Settings.address_to_url("game.example.org:443"), "wss://game.example.org:443")
	Settings.secure = false
	_expect(Settings.url_to_address("ws://1.2.3.4:9080"), "1.2.3.4:9080")
	print("address checks: ", "ok" if failures == 0 else "%d failed" % failures)


func _expect(a: String, b: String) -> void:
	if a != b:
		failures += 1
		print("FAIL ", a, " != ", b)


func shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%dx%d.png" % [out, name, size.x, size.y])
	print("saved ", name)


func _find(n: Node, cls: String) -> Array:
	return n.find_children("*", cls, true, false)


func _process(delta: float) -> bool:
	t += delta
	if not ("screen" in app):
		print("FAIL app did not load")
		return true
	match step:
		0:
			if t > 2.5:
				shot("m1_menu")
				var f: LineEdit = _find(app.screen, "LineEdit")[0]
				f.text = "192.168.1:90x"
				f.text_submitted.emit(f.text)
				step += 1; t = 0
		1:
			if t > 0.5:
				shot("m2_bad_address")
				app._sub = "howto"
				app._show_menu()
				step += 1; t = 0
		2:
			if t > 1.5:
				shot("m3_howto")
				var sc: ScrollContainer = _find(app.screen, "ScrollContainer")[0]
				sc.scroll_vertical = 900
				step += 1; t = 0
		3:
			if t > 0.6:
				shot("m4_howto_scrolled")
				app._sub = ""
				app._show_menu()
				app._open_settings()
				step += 1; t = 0
		4:
			if t > 0.8:
				shot("m5_settings")
				app.root.visible = false
				app._menu_map.camera.size = 60.0
				step += 1; t = 0
		5:
			if t > 0.6:
				shot("m6_world")
				return true
	return false
