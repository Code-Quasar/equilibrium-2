extends RefCounted
const Canonical = preload("res://simulation/core/canonical.gd")

static func create(match_id: String, seed_value: int, foundations: Array, b: Dictionary) -> Dictionary:
	if match_id.is_empty() or foundations.size() != 4:
		return {}
	var chosen: Array = []
	for foundation in foundations:
		if typeof(foundation) != TYPE_STRING or not b.foundations.has(foundation) or (foundation in chosen and not b.get("allow_duplicate_foundations", false)):
			return {}
		chosen.append(foundation)
	var cities: Array = []
	for id in range(4):
		var package: Dictionary = b.foundations[foundations[id]]
		var buildings: Array = []
		if not package.building.is_empty():
			buildings.append({"id": 0, "type": package.building, "level": 1,
				"tile": 0, "completed_tick": 0, "enabled": true, "money_paid_micro": 0})
		cities.append({
			"city_id": id, "player_id": id, "foundation": foundations[id],
			"population": b.population_per_city, "founding_population": b.founding_population_per_city,
			"money_micro": package.money * b.micro_units, "materials_micro": b.initial_materials,
			"uncollected_micro": [b.initial_waste, b.initial_waste, b.initial_waste],
			"sorted_micro": [b.initial_waste, b.initial_waste, b.initial_waste],
			"buildings": buildings, "next_building_id": buildings.size(), "project_slots": [null, null],
			"baseline": {"housing": b.housing, "service_capacity": b.service_capacity,
				"jobs": b.base_jobs, "generation_micro_E": b.municipal_generation_E * b.micro_units,
				"demand_micro_E": b.municipal_base_demand_E * b.micro_units + b.municipal_demand_per_resident_micro_E * b.population_per_city,
				"collection_micro_per_minute": b.collection_units_per_minute * b.micro_units,
				"landfill_micro_per_minute": b.landfill_units_per_minute * b.micro_units},
			"air_micro": b.initial_air * b.micro_units,
			"landfill_damage_micro": b.initial_landfill_damage * b.micro_units,
			"environment_micro": b.initial_environment * b.micro_units,
			# Operational systems populate these derived scores during match setup and ticks.
			"satisfaction_micro": null, "development_micro": null,
			"previous_biogas_micro_E": 0, "reduce_waste": false,
			"rate_carries": {}, "cooldowns": {}, "contract_reservations": [],
			"incoming_contract_ids": [], "outgoing_contract_ids": [],
			"mass_ledger_micro": {"generated": 0, "recovered": 0, "disposed": 0, "organic_sink": 0}
		})
	return {"schema_version": 1, "scope": "core", "match_id": match_id,
		"seed": seed_value, "tick": 0, "status": "running", "cities": cities,
		"foundations": foundations.duplicate(), "contracts": [], "offers": [],
		"event_schedule": [], "transfer_ledger": [], "final_result": null,
		"last_command_seq": [-1, -1, -1, -1], "command_results": {}, "applied_command_ids": []}

static func validate(state: Dictionary) -> String:
	if not Canonical.supports(state):
		return "non_integer_or_non_serializable_state"
	if state.cities.size() != 4:
		return "city_count"
	var total: int = 0
	var mass_generated: int = 0
	var mass_accounted: int = 0
	for id in range(4):
		var city: Dictionary = state.cities[id]
		if city.city_id != id or city.player_id != id:
			return "city_identity"
		if typeof(city.population) != TYPE_INT or city.population < 500 or city.founding_population != 500:
			return "population_bounds"
		total += city.population
		for field in ["money_micro", "materials_micro", "previous_biogas_micro_E", "air_micro", "landfill_damage_micro"]:
			if typeof(city[field]) != TYPE_INT or city[field] < 0:
				return "negative_or_invalid_resource"
		for field in ["uncollected_micro", "sorted_micro"]:
			if city[field].size() != 3:
				return "waste_categories"
			for amount in city[field]:
				if typeof(amount) != TYPE_INT or amount < 0:
					return "negative_or_invalid_resource"
		for field in ["environment_micro", "satisfaction_micro", "development_micro"]:
			if city[field] != null and (typeof(city[field]) != TYPE_INT or city[field] < 0 or city[field] > 100000000):
				return "score_bounds"
		for amount in city.mass_ledger_micro.values():
			if typeof(amount) != TYPE_INT or amount < 0:
				return "invalid_mass_ledger"
		mass_generated += city.mass_ledger_micro.generated
		mass_accounted += city.mass_ledger_micro.recovered + city.mass_ledger_micro.disposed + city.mass_ledger_micro.organic_sink
		for amount in city.uncollected_micro + city.sorted_micro:
			mass_accounted += amount
		for carry in city.rate_carries.values():
			if typeof(carry) != TYPE_INT or carry < 0 or carry >= 60:
				return "invalid_rate_carry"
		if city.project_slots.size() != 2 or city.buildings.size() > 36:
			return "construction_bounds"
	if total != 4000:
		return "population_conservation"
	if mass_generated != mass_accounted:
		return "waste_conservation"
	if typeof(state.tick) != TYPE_INT or state.tick < 0 or state.tick > 1200:
		return "time_bounds"
	if state.status != ("finished" if state.tick == 1200 else "running"):
		return "status_time_mismatch"
	return ""
