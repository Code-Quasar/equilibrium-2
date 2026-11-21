extends RefCounted
## Initial authoritative state and the invariants that hold after every phase.
const A = preload("res://simulation/core/arithmetic.gd")
const Balance = preload("res://simulation/core/balance.gd")
const Canonical = preload("res://simulation/core/canonical.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Materials = preload("res://simulation/systems/materials.gd")
const Waste = preload("res://simulation/systems/waste.gd")
const Market = preload("res://simulation/systems/market.gd")

## Foundations are one unique card per seat, in seat order.
static func create(match_id: String, seed_value: int, foundations: Array, b: Dictionary) -> Dictionary:
	if match_id.is_empty() or foundations.size() != b.players:
		return {}
	for foundation in foundations:
		if typeof(foundation) != TYPE_STRING or not b.foundations.has(foundation) or foundations.count(foundation) != 1:
			return {}
	var cities: Array = []
	for id in range(b.players):
		var package: Dictionary = b.foundations[foundations[id]]
		var city: Dictionary = {"city_id": id, "player_id": id, "foundation": foundations[id],
			"population": b.initial_residents, "buildings": [], "projects": [], "next_building_id": 0,
			"air_micro": b.city.air, "landfill_damage_micro": b.city.landfill_damage, "pressure_micro": 0,
			"amenity_micro": 0, "environment_micro": 100 * A.S - b.city.air - b.city.landfill_damage,
			"satisfaction_micro": null, "satisfaction_components_micro": {},
			"capacity": {"housing": b.city.housing, "services_micro": b.city.services * A.S, "employed": 0},
			"employment": {"municipal": 0, "buildings": 0}, "power": {}, "biogas_pending_micro_E": 0, "carries": {}}
		city.projects.resize(b.construction.slots)
		Finance.initialize(city, package.credits)
		Materials.initialize(city, b.city.materials + package.materials)
		Waste.initialize(city)
		for key in ["municipal_micro_E", "plants_micro_E", "biogas_micro_E", "imports_micro_E", "exports_micro_E",
				"municipal_requested_micro_E", "municipal_delivered_micro_E", "buildings_requested_micro_E",
				"buildings_delivered_micro_E", "unused_micro_E"]:
			city.power[key] = 0
		city.power["reliability_micro"] = A.S
		for start in package.buildings:
			city.buildings.append(Buildings.record(city.next_building_id, start.type, start.size, city.next_building_id, 0, true))
			city.next_building_id += 1
		cities.append(city)
	var state: Dictionary = {"match_id": match_id, "seed": seed_value, "tick": 0, "status": "running",
		"foundations": foundations.duplicate(), "cities": cities, "crisis": {}, "migrations": [],
		"final_result": null, "last_command_seq": [-1, -1, -1, -1], "command_results": {}}
	Market.initialize(state)
	return state

static func validate(state: Dictionary, b: Dictionary) -> String:
	if not Canonical.supports(state):
		return "non_integer_or_non_serializable_state"
	if typeof(state.tick) != TYPE_INT or state.tick < 0 or state.tick > b.duration:
		return "time_bounds"
	if state.status != ("finished" if state.tick == b.duration else "running"):
		return "status_time_mismatch"
	if state.cities.size() != b.players:
		return "city_count"
	var residents: int = 0
	for id in range(b.players):
		var city: Dictionary = state.cities[id]
		if city.city_id != id or city.player_id != id:
			return "city_identity"
		if typeof(city.population) != TYPE_INT or city.population < b.migration.source_min:
			return "population_bounds"
		residents += city.population
		if city.satisfaction_micro != null and (typeof(city.satisfaction_micro) != TYPE_INT or city.satisfaction_micro < 0 or city.satisfaction_micro > 100 * A.S):
			return "score_bounds"
		for carry in city.carries.values():
			if typeof(carry) != TYPE_INT or carry < 0:
				return "invalid_carry"
		var error: String = Finance.validate(city)
		if error.is_empty():
			error = Materials.validate(city, Waste.recovered(city))
		if not error.is_empty():
			return error
	if residents != b.residents:
		return "population_conservation"
	return ""
