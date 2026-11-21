extends "res://simulation/core/engine.gd"
## Authoritative complete match.
## Systems mutate only the transaction candidate supplied by the core engine.
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const FullEconomy = preload("res://simulation/systems/economy/regional.gd")
const LocalValidation = preload("res://simulation/core/resource_invariants.gd")
const RegionalConfig = preload("res://simulation/core/regional_config.gd")
const Events = preload("res://simulation/systems/events.gd")
const Migration = preload("res://simulation/systems/migration.gd")
var _buildings: RefCounted
var _economy: RefCounted

func initialize(match_id: String, seed_value: int, foundations: Array) -> String:
	var error: String = RegionalConfig.validate(Balance.load_b1())
	if not error.is_empty(): return error
	if not _state.is_empty(): return "already_initialized"
	error = LocalValidation.config(Balance.load_b1())
	if not error.is_empty(): return error
	error = super.initialize(match_id, seed_value, foundations)
	if not error.is_empty(): return error
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
	error = _validate_state(_state)
	if not error.is_empty(): return error
	_state.scope = "resources"
	register_system("household_collection", "household_waste_collection", _economy.waste.household_collection)
	register_system("local_processing", "waste_processing", _economy.waste.local_processing)
	register_system("landfill", "waste_disposal", _economy.waste.landfill)
	register_system("material_sales", "recovered_material_sales", _economy.waste.material_sales)
	register_system("environment", "environment_update", _economy.environment.update)
	error = _validate_state(_state)
	if not error.is_empty(): return error
	_state.scope = "complete"
	_economy.market.initialize(_state)
	for kind in _economy.market.KINDS:
		register_command(kind, _economy.market.validate, _economy.market.execute)
	register_system("facility_funding", "contract_cash_reservations", _economy.market.reserve_cash)
	register_system("contracted_processing", "contract_service", _economy.market.process_contracts)
	register_system("contract_expiry", "contract_closure", _economy.market.expiry)
	register_system("construction_completion", "service_renewal", _economy.market.renew_due)
	_state.event_schedule = _balance.events.duplicate(true)
	Events.apply(_state, _state.event_schedule, _balance)
	register_system("event_boundaries", "event_state", _events)
	register_system("migration", "population_migration", _migration)
	return _validate_state(_state)

func _migration(state: Dictionary, ctx: Dictionary, _random: RefCounted) -> String:
	if ctx.end_tick >= _balance.migration_first_second and ctx.end_tick % _balance.migration_interval_seconds == 0:
		state.transfer_ledger.append(Migration.pulse(state, _balance.migration))
	return ""

func step(validate_each_phase: bool = true) -> Dictionary:
	var result: Dictionary = super.step(validate_each_phase)
	if result.status == "advanced" and _state.status == "finished":
		var ranks: Array = Migration.ranking(_state)
		var winners: Array = []
		for row in ranks:
			if row.rank == 1: winners.append(row.city_id)
		_state.final_result = {"rankings": ranks, "winners": winners, "duration": _state.tick}
		# Hash the final canonical payload with the hash field absent (no self-reference).
		_state.final_result["canonical_sha256"] = serialize().sha256_text()
	return result

func _events(state: Dictionary, _ctx: Dictionary, _random: RefCounted) -> String:
	Events.apply(state, state.event_schedule, _balance)
	return ""

func _make_economy() -> RefCounted:
	return FullEconomy.new(_balance,_buildings)

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
	if state.get("scope") in ["resources", "complete"]:
		for city in state.cities:
			error = LocalValidation.city(city, _balance.local_simulation, state.scope == "complete")
			if not error.is_empty(): return error
	if state.get("scope") == "complete": return _economy.market.invariant(state)
	return ""
