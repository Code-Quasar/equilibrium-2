extends RefCounted
const TYPES = ["residential_district", "factory", "commercial_district", "public_services_center", "recovery_hub", "recycling_center", "biogas_facility", "landfill", "fossil_power_plant", "renewable_power_plant", "green_space"]
const ROOT_INTS = ["match_seconds", "tick_seconds", "city_count", "regional_population", "population_per_city", "founding_population_per_city", "micro_units", "housing", "service_capacity", "base_jobs", "municipal_generation_E", "municipal_base_demand_E", "municipal_demand_per_resident_micro_E", "collection_units_per_minute", "landfill_units_per_minute", "initial_materials", "initial_waste", "initial_air", "initial_landfill_damage", "initial_environment", "neutral_satisfaction_micro", "construction_slots", "grid_width", "grid_height", "migration_first_second", "migration_interval_seconds"]
const EFFECTS = ["cost_micro", "duration_seconds", "upkeep_micro_per_minute", "jobs", "demand_micro_E", "generation_micro_E", "income_micro_per_minute", "air_micro_per_minute", "housing", "services", "collection_per_minute", "recycling_per_minute", "reuse_per_minute", "treatment_per_minute", "waste_per_minute"]
const ECONOMY = ["municipal_income_micro_per_minute", "income_per_resident_micro_per_minute", "municipal_upkeep_micro_per_minute", "material_discount_percent", "cancel_refund_percent", "demolition_refund_micro", "reactivation_cooldown_seconds", "policy_cooldown_seconds", "policy_fee_micro_per_minute", "policy_factory_income_percent", "policy_commerce_income_percent"]
const DEVELOPMENT = ["housing_points", "housing_span", "services_points", "services_span", "jobs_points", "jobs_span", "energy_points", "energy_span_E", "circular_points", "circular_span", "maximum_points"]
const SATISFACTION = ["environment_points", "employment_points", "housing_points", "power_points", "services_points", "capacity_requirement_percent"]

static func load_b1(path: String = "res://config/balance/B1.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var converted: Variant = _integers(parsed)
	if not converted is Dictionary or not validate(converted).is_empty():
		return {}
	return converted

static func _integers(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _integers(value[key])
		return result
	if value is Array:
		return value.map(func(item): return _integers(item))
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value) or value != floor(value) or abs(value) > 9007199254740991.0:
			return null
		return int(value)
	return value

static func fields(value: Variant, keys: Array, signed: String = "") -> bool:
	if not value is Dictionary:
		return false
	for key in keys:
		if not value.has(key) or typeof(value[key]) != TYPE_INT:
			return false
		# Technical overflow guard, not a tunable balance limit.
		if absi(value[key]) > 1000000000 or (key != signed and value[key] < 0):
			return false
	return true

static func validate(b: Dictionary) -> String:
	if b.has("allow_duplicate_foundations") and typeof(b.allow_duplicate_foundations) != TYPE_BOOL:
		return "invalid_duplicate_foundation_flag"
	if not fields(b, ROOT_INTS):
		return "invalid_baseline"
	if b.city_count != 4 or b.match_seconds != 1200 or b.tick_seconds != 1 or b.micro_units != 1000000 or b.construction_slots != 2 or b.grid_width != 6 or b.grid_height != 6:
		return "unsupported_structural_constants"
	if b.population_per_city != 1000 or b.founding_population_per_city != 500 or b.regional_population != 4000:
		return "inconsistent_population"
	for section in ["foundations", "buildings", "economy", "development", "satisfaction"]:
		if not b.get(section) is Dictionary:
			return "missing_" + section
	if b.foundations.size() != 4 or b.buildings.size() != 11:
		return "catalogue_size"
	var packages: Dictionary = {"industrial_legacy": "factory", "circular_foundation": "recycling_center", "energy_pioneer": "renewable_power_plant", "investment_district": ""}
	for key in packages:
		if not fields(b.foundations.get(key), ["money"]) or b.foundations[key].get("building") != packages[key]:
			return "invalid_foundation"
	for kind in TYPES:
		var item: Variant = b.buildings.get(kind)
		if not fields(item, ["build_unlock_micro", "upgrade_unlock_micro"]):
			return "invalid_unlock"
		if item.build_unlock_micro > 100000000 or item.upgrade_unlock_micro > 100000000:
			return "invalid_unlock"
		for level in ["l1", "upgrade_delta"]:
			if not fields(item.get(level), EFFECTS, "air_micro_per_minute"):
				return "invalid_building"
			var d: Dictionary = item[level]
			if d.duration_seconds <= 0 or d.duration_seconds >= b.match_seconds or d.cost_micro <= 0 or d.upkeep_micro_per_minute <= 0 or d.reuse_per_minute > d.recycling_per_minute:
				return "inconsistent_building"
			if d.generation_micro_E > 0 and d.demand_micro_E > 0:
				return "generator_requires_power"
			# Keep all fixed-point products inside int64, including score numerators.
			for key in ["jobs", "housing", "services", "collection_per_minute", "recycling_per_minute", "reuse_per_minute", "treatment_per_minute", "waste_per_minute"]:
				if d[key] > 1000:
					return "capacity_exceeds_arithmetic_bound"
			if d.income_micro_per_minute % 100 != 0:
				return "income_policy_precision"
	if not fields(b.economy, ECONOMY) or not fields(b.development, DEVELOPMENT) or not fields(b.satisfaction, SATISFACTION):
		return "invalid_economic_schema"
	for key in ["material_discount_percent", "cancel_refund_percent", "policy_factory_income_percent", "policy_commerce_income_percent"]:
		if b.economy[key] > 100:
			return "invalid_percentage"
	if b.economy.demolition_refund_micro != 0 or b.economy.reactivation_cooldown_seconds <= 0 or b.economy.policy_cooldown_seconds <= 0:
		return "invalid_lifecycle"
	if b.economy.municipal_income_micro_per_minute + b.economy.income_per_resident_micro_per_minute * b.founding_population_per_city <= b.economy.municipal_upkeep_micro_per_minute:
		return "municipal_softlock"
	for key in ["housing_span", "services_span", "jobs_span", "energy_span_E", "circular_span"]:
		if b.development[key] <= 0:
			return "invalid_development_span"
	if b.satisfaction.capacity_requirement_percent <= 0 or b.development.maximum_points != 100:
		return "invalid_scores"
	var dev_total: int = 0
	for key in ["housing_points", "services_points", "jobs_points", "energy_points", "circular_points"]:
		if b.development[key] > 100:
			return "invalid_score_weight"
		dev_total += b.development[key]
	var satisfaction_total: int = 0
	for key in ["environment_points", "employment_points", "housing_points", "power_points", "services_points"]:
		if b.satisfaction[key] > 100:
			return "invalid_score_weight"
		satisfaction_total += b.satisfaction[key]
	if dev_total != 100 or satisfaction_total != 100:
		return "score_weights_must_sum_to_100"
	if b.initial_environment > 100 or b.initial_air > 40 or b.initial_landfill_damage > 35 or b.initial_environment != 100 - b.initial_air - b.initial_landfill_damage:
		return "invalid_initial_environment"
	return ""
