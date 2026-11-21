extends "res://tests/support/construction_simulation.gd"
const LocalEconomy = preload("res://simulation/systems/economy/local.gd")
const LocalValidation = preload("res://simulation/core/resource_invariants.gd")

func initialize(match_id: String, seed_value: int, foundations: Array) -> String:
	if not _state.is_empty(): return "already_initialized"
	var config: Dictionary = Balance.load_b1()
	var error: String = LocalValidation.config(config)
	if not error.is_empty(): return error
	error = super.initialize(match_id, seed_value, foundations)
	if not error.is_empty(): return error
	_state.scope = "resources"
	_state.schema_version = 1
	register_system("household_collection", "household_waste_collection", _economy.waste.household_collection)
	register_system("local_processing", "waste_processing", _economy.waste.local_processing)
	register_system("landfill", "waste_disposal", _economy.waste.landfill)
	register_system("material_sales", "recovered_material_sales", _economy.waste.material_sales)
	register_system("environment", "environment_update", _economy.environment.update)
	return _validate_state(_state)

func _make_economy() -> RefCounted:
	return LocalEconomy.new(_balance, _buildings)

func _validate_state(state: Dictionary) -> String:
	var error: String = super._validate_state(state)
	if not error.is_empty() or state.get("scope") not in ["resources", "complete"]: return error
	for c in state.cities:
		error = LocalValidation.city(c, _balance.local_simulation, state.scope == "complete")
		if not error.is_empty(): return error
	return ""
