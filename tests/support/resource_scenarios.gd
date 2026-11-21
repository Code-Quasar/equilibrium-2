extends RefCounted
const Sim = preload("res://tests/support/resource_simulation.gd")
const A = preload("res://simulation/core/arithmetic.gd")
const FOUNDATIONS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
const PLANS = {
	"industrial": ["factory","renewable_power_plant","recovery_hub","factory","recycling_center","landfill"],
	"commerce": ["commercial_district","renewable_power_plant","commercial_district","recycling_center","commercial_district"],
	"circular": ["renewable_power_plant","residential_district","public_services_center","recycling_center","recycling_center","biogas_facility","recovery_hub"],
	"renewable": ["commercial_district","renewable_power_plant","factory","renewable_power_plant","recycling_center"],
	"fossil": ["commercial_district","fossil_power_plant","factory","fossil_power_plant","recycling_center"],
	"mixed": ["commercial_district","renewable_power_plant","recycling_center","residential_district","public_services_center","recovery_hub","biogas_facility"],
	"minimal": [],
	"prevention": ["factory","renewable_power_plant","recovery_hub","recycling_center","commercial_district"]}

static func summarize(sim) -> Dictionary:
	var state: Dictionary = sim.snapshot()
	var cities: Array = []
	for c in state.cities:
		cities.append({"city": c.city_id, "foundation": c.foundation, "population": c.population,
			"cash_micro": c.money_micro, "finance_micro": c.finance.totals,
			"waste_micro": c.mass_ledger_micro, "flows_micro": c.waste_totals,
			"uncollected_micro": c.uncollected_micro, "sorted_micro": c.sorted_micro,
			"materials_micro": c.materials_micro, "materials_sold_micro": c.materials_sold,
			"construction_materials_micro": c.finance.materials_spent,
			"electricity_micro_E": c.electricity, "reliability_micro": c.capacity.reliability_micro,
			"environment_micro": c.environment_micro, "satisfaction_micro": c.satisfaction_micro,
			"development_micro": c.development_micro, "capacity": c.capacity})
	return {"tick": state.tick, "cities": cities, "snapshot_sha256": sim.serialize().sha256_text()}

static func run_scenario(name: String, seed_value: int, ticks: int, reverse: bool = false) -> Dictionary:
	var sim = Sim.new()
	var error: String = sim.initialize("resource-" + name,seed_value,FOUNDATIONS)
	if error != "": return {"error":error}
	var snapshots: Array = []
	var outcomes: Array = []
	var plan: Array = PLANS[name]
	for tick in range(ticks):
		var commands: Array = []
		for owner in range(4):
			if tick % 90 == 0 and A.divi(tick,90) < plan.size():
				commands.append(envelope(name,owner,tick,0,"construct",{"building_type":plan[A.divi(tick,90)]}))
			if name == "prevention" and tick == 0:
				commands.append(envelope(name,owner,tick,1,"set_reduce_waste",{"enabled":true}))
		if reverse: commands.reverse()
		for command in commands:
			var admission: Dictionary = sim.submit(command,command.player_id)
			if admission.status != "queued": return {"error":admission.status}
		var result: Dictionary = sim.step()
		if result.status != "advanced": return {"error":str(result)}
		outcomes.append_array(result.commands)
		if tick + 1 in [120,600,ticks]: snapshots.append(summarize(sim))
	if ticks == 0: snapshots.append(summarize(sim))
	return {"scenario":name,"seed":seed_value,"ticks":ticks,"snapshots":snapshots,
		"command_results":outcomes,"reconciliation":"passed_after_every_phase",
		"final_canonical":sim.serialize(),"limitations":["no_migration","no_trade","no_events","not_competitive_balance"]}

static func envelope(name: String, owner: int, tick: int, offset: int, kind: String, payload: Dictionary) -> Dictionary:
	return {"match_id":"resource-"+name,"player_id":owner,"command_seq":tick*2+offset,
		"command_id":"%d:%d:%d"%[owner,tick,offset],"command_type":kind,"payload":payload,"server_received_tick":tick}
