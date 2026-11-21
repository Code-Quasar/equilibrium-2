extends SceneTree
const Scenario = preload("res://tests/support/resource_scenarios.gd")
func _initialize() -> void:
	var result: Dictionary = Scenario.run_scenario("circular",42,1200,"reverse" in OS.get_cmdline_user_args())
	if result.has("error"):
		printerr(result.error)
		quit(1)
		return
	print(result.final_canonical)
	quit(0)
