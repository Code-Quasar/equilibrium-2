extends SceneTree
## Runs every engine and server suite in its own Godot process, then replays a
## scripted full match in two processes with reversed submission order and
## requires byte-identical canonical state.
const SUITES = ["tests/rules/config_test.gd", "tests/rules/construction_test.gd", "tests/rules/waste_test.gd",
	"tests/rules/economy_test.gd", "tests/rules/migration_test.gd", "tests/rules/market_test.gd", "tests/rules/emergencies_test.gd",
	"tests/integration/online_foundation.gd", "tests/integration/online_emergencies.gd", "tests/integration/online_completion.gd"]

func _initialize() -> void:
	var failed: bool = false
	for script in SUITES:
		var output: Array = []
		var code: int = run(script, [], output)
		var text: String = "".join(output)
		var summary: PackedStringArray = text.strip_edges().split("\n")
		print(summary[summary.size() - 1])
		if code != 0 or text.contains("SCRIPT ERROR") or text.contains("Parse Error") or text.contains("FAIL"):
			printerr(text)
			failed = true
	var forward: Array = []
	var reverse: Array = []
	var ok: bool = run("tests/replay/scenario.gd", [], forward) == 0 and run("tests/replay/scenario.gd", ["reverse"], reverse) == 0
	var a: String = canonical(forward)
	if ok and not a.is_empty() and a == canonical(reverse):
		print("Cross-process replay: byte-identical canonical state after 1200 ticks (%s)" % a.sha256_text())
	else:
		printerr("Cross-process replay differs or failed")
		failed = true
	quit(1 if failed else 0)

func run(script: String, args: Array, output: Array) -> int:
	var options: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path("user://" + script.get_file() + ".log"), "--script", script]
	if not args.is_empty():
		options.append("--")
		options.append_array(PackedStringArray(args))
	return OS.execute(OS.get_executable_path(), options, output, true)

func canonical(output: Array) -> String:
	for block in output:
		for line in str(block).split("\n"):
			if line.begins_with("CANONICAL "):
				return line
	return ""
