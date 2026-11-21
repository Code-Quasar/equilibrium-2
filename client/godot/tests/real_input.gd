extends SceneTree
## Starts a match in the real app, then logs the input events that arrive and
## the camera, so real mouse input (from xdotool) can be checked.
var app: Node
var s: Session
var t := 0.0
var step := 0
var last := ""

class InputCounter extends Node:
	var counts := {}
	func _input(e: InputEvent) -> void:
		counts[e.get_class()] = counts.get(e.get_class(), 0) + 1

var logger := InputCounter.new()

func _initialize() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	root.add_child(logger)

func _process(d: float) -> bool:
	t += d
	if s == null and app.session != null:
		s = app.session
		s.store = "user://real_input.cfg"
		s._forget_seat()
	match step:
		0:
			if t > 0.5: s.create("ws://127.0.0.1:9081"); step = 1
		1:
			if s.phase == "lobby" and t > 1.0: s.set_ready(true); step = 2; t = 0
		2:
			if t > 0.5: s.start_match(); step = 3
		3:
			if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
				s.choose_foundation(s.draft["available_foundations"][0])
			if s.phase == "play" and t > 2.0:
				print("READY_FOR_INPUT")
				step = 4
				t = 0
		4:
			var cam: Camera3D = app.map.camera
			var line := "cam %s size %.2f events %s" % [cam.position.snapped(Vector3(0.01, 0.01, 0.01)), cam.size, logger.counts]
			if line != last:
				print(line)
				last = line
			if t > 25:
				quit()
	return false
