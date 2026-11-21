extends SceneTree
## One headless entry point; child Godot processes also verify clean-process replay.
func _initialize() -> void:
	for script in ["tests/regression/core.gd", "tests/regression/construction.gd", "tests/regression/resources.gd", "tests/regression/regional.gd", "tests/regression/integrity_insights.gd", "tests/regression/booking_refunds.gd", "tests/integration/openings.gd"]:
		var output: Array = []
		var code: int = execute(script, [], output)
		for block in output: print(block)
		if code != 0 or has_script_error(output):
			quit(1)
			return
	for scenario in ["construction", "resources", "services", "cancellation", "seller_refund"]:
		var forward: Array = []
		var reverse: Array = []
		var script: String = "tests/replay/" + scenario + ".gd"
		var a: int = execute(script, [], forward)
		var b: int = execute(script, ["reverse"], reverse)
		if a != 0 or b != 0 or has_script_error(forward) or has_script_error(reverse) or snapshot_line(forward) == "" or snapshot_line(forward) != snapshot_line(reverse):
			printerr("Cross-process replay failed: " + scenario)
			quit(1)
			return
		print("Cross-process %s replay: byte-identical canonical snapshots after 1200 ticks" % scenario)
	quit(0)

func execute(script: String, args: Array, output: Array) -> int:
	var options: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", "/tmp/equilibrium-" + script.get_file() + ".log", "--script", script]
	if not args.is_empty():
		options.append("--")
		options.append_array(PackedStringArray(args))
	return OS.execute(OS.get_executable_path(), options, output, true)

func has_script_error(output: Array) -> bool:
	return str(output).contains("SCRIPT ERROR") or str(output).contains("Parse Error") or str(output).contains("FAIL")

func snapshot_line(output: Array) -> String:
	for block in output:
		for line in str(block).split("\n"):
			if line.begins_with("{\"balance\":"):
				return line
	return ""
