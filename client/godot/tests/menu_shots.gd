extends SceneTree
## Screenshots of the screens that need no server: menu, address errors,
## How to Play (top and scrolled), Settings. Also checks address validation and
## the address boxes: numbers only, automatic jumps, paste, cursor movement.
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


## The address boxes on the menu, driven as typing would drive them.
func _check_address_field() -> void:
	var af: AddressField = _find(app.screen, "AddressField")[0]
	var p := af.parts
	p[0].grab_focus()
	p[0].text = "192"
	p[0].text_changed.emit("192")
	_expect(str(p[1].has_focus()), "true")             # three digits jump on
	p[1].text = "16a8"
	p[1].text_changed.emit("16a8")
	_expect(p[1].text, "168")                         # letters are dropped
	p[1].text = "168."
	p[1].text_changed.emit("168.")
	_expect(p[1].text, "168")                         # "." is drawn, not typed...
	_expect(str(p[2].has_focus()), "true")             # ...and moves on
	p[2].text = "10.0.0.5:9081"
	p[2].text_changed.emit(p[2].text)                 # a pasted address fills every box
	_expect(af.address(), "10.0.0.5:9081")
	_expect(af.problem(), "")
	p[4].text = "99999"
	_expect(str(af.validate()), "false")              # port out of range
	p[4].text = "80x"
	p[4].text_changed.emit("80x")
	_expect(p[4].text, "80")                          # port: numbers only
	p[3].text = "300"
	_expect(af.problem(), "Each IP number is 0 to 255")
	# The caret moves both ways inside a box.
	p[3].text = "123"
	var left := InputEventKey.new(); left.keycode = KEY_LEFT; left.pressed = true
	p[3].grab_focus()
	p[3].deselect()                                   # focusing selects the number; tap again to place the caret
	p[3].caret_column = 3
	p[3].get_viewport().push_input(left)
	_expect(str(p[3].caret_column), "2")
	var right := InputEventKey.new(); right.keycode = KEY_RIGHT; right.pressed = true
	p[3].get_viewport().push_input(right)
	_expect(str(p[3].caret_column), "3")
	# A clean field again, then an invalid one for the screenshot.
	af.set_address("192.168.1.20:9080")
	_expect(af.problem(), "")
	p[2].text = ""
	af.validate()
	print("address field checks: ", "ok" if failures == 0 else "%d failed" % failures)


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
				_check_address_field()
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
