extends "res://simulation/core/engine.gd"
const Buildings = preload("res://simulation/systems/buildings.gd")
const Economy = preload("res://simulation/systems/economy/municipal.gd")
const Finance = preload("res://simulation/systems/finance.gd")
var _buildings: RefCounted
var _economy: RefCounted

func initialize(match_id: String, seed_value: int, foundations: Array) -> String:
	var error: String = super.initialize(match_id, seed_value, foundations)
	if not error.is_empty():
		return error
	_buildings = Buildings.new(_balance)
	_economy = _make_economy()
	_state.scope = "construction"
	_state.schema_version = 1
	for city in _state.cities:
		for i in range(city.buildings.size()):
			var old: Dictionary = city.buildings[i]
			city.buildings[i] = _buildings.record(old.id, old.type, city.city_id, old.tile, 0, true)
		_economy.initialize_city(city)
	for kind in ["construct", "upgrade", "disable", "enable", "demolish", "cancel_project", "set_reduce_waste"]:
		register_command(kind, _buildings.validate_command, _buildings.execute_command)
	register_system("construction_completion", "construction_projects", _buildings.complete_projects)
	register_system("municipal_finances", "municipal_budget", _economy.municipal)
	register_system("facility_funding", "facility_operations", _economy.fund)
	register_system("workforce_generation", "workforce_dispatch", _economy.workforce)
	register_system("power_allocation_settlement", "power_dependencies", _economy.power_dependency)
	register_system("production", "building_production", _economy.production)
	register_system("scores_development", "city_progression", _economy.scores)
	register_system("contract_expiry", "reservation_release", _economy.release_reservations)
	return _validate_state(_state)

func _validate_state(state: Dictionary) -> String:
	var error: String = super._validate_state(state)
	if not error.is_empty() or state.get("scope") not in ["construction", "resources", "complete"]:
		return error
	for city in state.cities:
		error = Finance.validate(city)
		if error.is_empty():
			error = _buildings.validate_city(city)
		if not error.is_empty():
			return error
		for key in ["housing", "services_micro", "potential_jobs", "realized_jobs_micro", "staffing_micro", "generation_micro_E", "demand_micro_E"]:
			if typeof(city.capacity[key]) != TYPE_INT or city.capacity[key] < 0:
				return "invalid_capacity"
	return ""

func _make_economy() -> RefCounted:
	return Economy.new(_balance, _buildings)
