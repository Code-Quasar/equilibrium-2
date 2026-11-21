extends SceneTree
const Sim=preload("res://simulation/match.gd")
const Cases=preload("res://tests/support/market_cases.gd")
func _initialize() -> void:
	var choices: Array=["commercial_district","recycling_center","renewable_power_plant","residential_district","public_services_center","recovery_hub","green_space","factory","landfill"]
	var evidence: Array=[]
	for owner in range(4):
		var feasible: Array=[]
		for i in range(choices.size()):
			for j in range(i+1,choices.size()):
				var sim=Sim.new()
				if sim.initialize("opening",42,Cases.FOUNDATIONS)!="":quit(1);return
				Cases.command(sim,owner,"construct",{"building_type":choices[i]},0)
				Cases.command(sim,owner,"construct",{"building_type":choices[j]},1)
				var result: Dictionary=sim.step()
				if result.status!="advanced":printerr(result);quit(1);return
				if result.commands.all(func(row):return row.status=="applied"):feasible.append([choices[i],choices[j]])
		if feasible.size()<2:printerr("FAIL fewer than two feasible opening pairs");quit(1);return
		evidence.append({"foundation":Cases.FOUNDATIONS[owner],"feasible_distinct_build_pairs":feasible})
	print(JSON.stringify(evidence))
	quit(0)
