extends SceneTree
const Sim = preload("res://tests/support/construction_simulation.gd")
const FOUNDATIONS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
func _initialize() -> void:
	var sim = Sim.new()
	if sim.initialize("cross-process",42,FOUNDATIONS) != "":
		quit(1)
		return
	var reverse: bool = "reverse" in OS.get_cmdline_user_args()
	for tick in range(1200):
		var commands: Array = []
		if tick in [0,40,50,60,80,100,140,150,200]:
			for owner in range(4):
				var kind: String = "construct"
				var payload: Dictionary = {"building_type": "residential_district"}
				match tick:
					40:
						kind = "disable"
						payload = {"building_id":0}
					50:
						kind = "enable"
						payload = {"building_id":0}
					60:
						payload = {"building_type":"renewable_power_plant"}
					80:
						kind = "set_reduce_waste"
						payload = {"enabled":true}
					100:
						kind = "upgrade"
						payload = {"building_id":0}
					140:
						kind = "set_reduce_waste"
						payload = {"enabled":false}
					150:
						payload = {"building_type":"commercial_district"}
					200:
						kind = "demolish"
						payload = {"building_id":0}
				commands.append({"match_id":"cross-process","player_id":owner,"command_seq":tick,
					"command_id":"%d:%d" % [owner,tick],"command_type":kind,
					"payload":payload,"server_received_tick":tick})
		if reverse: commands.reverse()
		for command in commands:
			if sim.submit(command,command.player_id).status != "queued":
				quit(1)
				return
		if sim.step().status != "advanced":
			quit(1)
			return
	print(sim.serialize())
	quit(0)
