extends SceneTree
## A scripted 1,200-tick match touching construction, upgrades, both contract kinds,
## material sales, disabling and demolition. With "reverse", each tick's commands
## are submitted in reverse order; the engine's ordering must make that irrelevant.
## Prints the canonical serialization for byte comparison across processes.
const Sim = preload("res://simulation/match.gd")
const SCRIPT = {
	0: [[0, "construct", {"building_type": "residential_district", "size": "S"}], [1, "construct", {"building_type": "recycling_center", "size": "S"}],
		[2, "construct", {"building_type": "collection_center", "size": "S"}], [3, "construct", {"building_type": "commercial_district", "size": "S"}]],
	5: [[2, "publish_offer", {"type": "electricity", "rate": 10000000}]],
	6: [[0, "accept_offer", {"id": 0, "duration": 180}]],
	30: [[1, "upgrade", {"building_id": 0}], [3, "construct", {"building_type": "collection_center", "size": "S"}]],
	40: [[3, "construct", {"building_type": "factory", "size": "S"}]],
	60: [[3, "construct", {"building_type": "sorting_center", "size": "S"}], [2, "construct", {"building_type": "sorting_center", "size": "M"}]],
	90: [[1, "publish_offer", {"type": "recyclable", "rate": 5000000}]],
	91: [[3, "accept_offer", {"id": 2, "duration": 240}]],
	120: [[0, "construct", {"building_type": "landfill", "size": "M"}], [2, "construct", {"building_type": "fossil_power_plant", "size": "S"}]],
	200: [[1, "sell_materials", {"amount": 2000000}], [0, "construct", {"building_type": "park", "size": "S"}]],
	250: [[2, "disable", {"building_id": 0}]],
	270: [[2, "enable", {"building_id": 0}]],
	300: [[0, "cancel_contract", {"id": 1}], [1, "construct", {"building_type": "biogas_facility", "size": "S"}]],
	400: [[3, "upgrade", {"building_id": 2}], [0, "construct", {"building_type": "public_services_center", "size": "M"}]],
	500: [[1, "construct", {"building_type": "residential_district", "size": "M"}], [2, "cancel_project", {"building_id": 3}]],
	600: [[0, "demolish", {"building_id": 1}], [3, "construct", {"building_type": "renewable_power_plant", "size": "S"}]],
}

func _initialize() -> void:
	var reverse: bool = "reverse" in OS.get_cmdline_user_args()
	var m = Sim.new()
	var error: String = m.initialize("replay", 2050, ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"])
	if not error.is_empty():
		printerr(error)
		quit(1)
		return
	var sequence: Array = [0, 0, 0, 0]
	for tick in range(1200):
		var commands: Array = SCRIPT.get(tick, []).duplicate()
		if reverse:
			commands.reverse()
		for command in commands:
			var seat: int = command[0]
			var admitted: Dictionary = m.submit({"match_id": "replay", "player_id": seat, "command_seq": sequence[seat],
				"command_id": "replay:%d:%d" % [seat, sequence[seat]], "command_type": command[1], "payload": command[2],
				"server_received_tick": tick}, seat)
			sequence[seat] += 1
			if admitted.status != "queued":
				printerr("admission " + admitted.status)
				quit(1)
				return
		var result: Dictionary = m.step(false)
		if result.status != "advanced":
			printerr(str(result))
			quit(1)
			return
	print("CANONICAL " + m.serialize())
	quit(0)
