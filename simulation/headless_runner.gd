extends SceneTree
## Runs a match without commands and prints the canonical state.
## Usage: -- [seed] [ticks 0..1200]
const Sim = preload("res://simulation/match.gd")

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 2 or Array(arguments).any(func(a): return not a.is_valid_int()):
		_fail("Usage: -- [seed_integer] [ticks_0_to_1200]")
		return
	var seed_value: int = int(arguments[0]) if arguments.size() > 0 else 0
	var ticks: int = int(arguments[1]) if arguments.size() > 1 else 1200
	if ticks < 0 or ticks > 1200:
		_fail("Ticks must be between 0 and 1200")
		return
	var simulation = Sim.new()
	var error: String = simulation.initialize("headless", seed_value, ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"])
	if not error.is_empty():
		_fail(error)
		return
	for _tick in range(ticks):
		var result: Dictionary = simulation.step(false)
		if result.status != "advanced":
			_fail(str(result))
			return
	print(simulation.serialize())
	quit(0)

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
