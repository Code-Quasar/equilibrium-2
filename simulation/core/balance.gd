extends RefCounted
## Loads the B2.1 ruleset into the engine's integer form.
## The file states natural units (credits, units per minute, fractions); every
## non-count quantity here becomes micro-units. Counts stay integers: seconds,
## ticks, residents, housing, service capacity and job slots.
const A = preload("res://simulation/core/arithmetic.gd")
const PATH = "res://config/balance/B2_1.json"
const TYPES = ["residential_district", "factory", "commercial_district", "public_services_center",
	"park", "collection_center", "sorting_center", "recycling_center", "biogas_facility",
	"landfill", "fossil_power_plant", "renewable_power_plant"]
const FOUNDATIONS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
const SIZES = ["S", "M", "L"]
const SOURCES = {"household": "household_composition", "factory": "factory_composition", "commercial": "commercial_composition"}
const CATEGORIES = ["recyclable", "organic", "residual"]
const MICRO = 0
const COUNT = 1
const FRACTION = 2
## Tier file key -> [engine key, kind]. Optional keys default to zero.
const TIER_FIELDS = {
	"construction_credits": ["credits", MICRO],
	"construction_materials": ["materials", MICRO],
	"construction_seconds": ["seconds", COUNT],
	"maintenance_credits_per_min": ["upkeep", MICRO],
	"housing_capacity": ["housing", COUNT],
	"service_capacity": ["services", COUNT],
	"job_slots": ["jobs", COUNT],
	"gross_income_credits_per_min": ["income", MICRO],
	"factory_materials_consumed_per_min": ["material_input", MICRO],
	"waste_generated_per_min": ["waste", MICRO],
	"power_generated_capacity": ["generation", MICRO],
	"power_demand_capacity": ["demand", MICRO],
	"air_emissions_points_per_min": ["emissions", MICRO],
	"air_cleanup_points_per_min": ["cleanup", MICRO],
	"park_amenity_points": ["amenity", MICRO],
	"collection_waste_per_min": ["collection", MICRO],
	"sorting_waste_per_min": ["sorting", MICRO],
	"recycling_waste_per_min": ["recycling", MICRO],
	"biogas_organic_waste_per_min": ["biogas", MICRO],
	"landfill_waste_per_min": ["landfill", MICRO],
	"collection_direct_reuse_fraction": ["collection_reuse", FRACTION],
	"sort_capture_recyclable": ["capture_recyclable", FRACTION],
	"sort_capture_organic": ["capture_organic", FRACTION],
	"sorting_direct_reuse_fraction": ["sorting_reuse", FRACTION],
	"material_yield_fraction": ["recycling_yield", FRACTION],
	"biogas_energy_capacity_per_organic_unit_per_min": ["biogas_energy", MICRO],
	"biogas_residue_fraction": ["biogas_residue", FRACTION],
}
const TIER_REQUIRED = ["construction_credits", "construction_materials", "construction_seconds", "maintenance_credits_per_min"]
const CRISIS_MULTIPLIERS = {
	"emission_multiplier": "emission",
	"air_natural_decay_multiplier": "air_decay",
	"household_waste_multiplier": "household",
	"factory_waste_multiplier": "factory",
	"commerce_waste_multiplier": "commercial",
	"municipal_baseline_grid_output_multiplier": "municipal_power",
}
## Technical bound keeping every fixed-point product inside int64.
const LIMIT: int = 1000000000000

static func load_config(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var result: Dictionary = normalize(parsed)
	return result.config if result.error.is_empty() else {}

## Returns {"error": "", "config": {...}} or {"error": reason, "config": {}}.
static func normalize(raw: Dictionary) -> Dictionary:
	var r := Reader.new()
	var c: Dictionary = r.build(raw)
	if r.error.is_empty():
		r.error = _consistency(c)
	return {"error": r.error, "config": c if r.error.is_empty() else {}}

static func _consistency(c: Dictionary) -> String:
	if c.players != 4 or c.duration != 1200 or c.residents != 4000 or c.initial_residents != 1000 or c.tiles != 36 or c.construction.slots != 2:
		return "unsupported_structural_constants"
	var s: Dictionary = c.satisfaction
	if s.environment + s.employment + s.housing + s.power + s.services != 100:
		return "satisfaction_weights_must_sum_to_100"
	var m: Dictionary = c.migration
	if m.interval <= 0 or m.first <= 0 or m.first > m.last or m.last > c.duration or m.first % m.interval != 0 or (m.last - m.first) % m.interval != 0:
		return "invalid_migration_schedule"
	if m.source_max < 1 or m.target_max < 1 or m.source_min < 1 or m.source_min > c.initial_residents:
		return "invalid_migration_limits"
	for source in c.waste.composition:
		if A.total(c.waste.composition[source]) != A.S:
			return "waste_composition_must_sum_to_1"
	if c.economy.sell_price <= 0 or c.economy.buy_price <= c.economy.sell_price:
		return "material_price_arbitrage"
	if c.economy.landfill_fee <= 0 or c.economy.material_cap <= 0 or c.waste.mixed_cap <= 0 or c.waste.sorted_cap.has(0):
		return "invalid_economy"
	if c.construction.reactivation_cooldown < 1:
		return "invalid_reactivation_cooldown"
	if c.city.air > c.environment.air_cap or c.city.landfill_damage > c.environment.landfill_cap:
		return "invalid_initial_environment"
	var mk: Dictionary = c.market
	if mk.min_duration < 1 or mk.min_duration > mk.default_duration or mk.default_duration > mk.max_duration or mk.max_duration > c.duration:
		return "invalid_contract_duration"
	if mk.max_offers < 1 or mk.max_contracts < 1 or mk.electricity_max <= 0 or mk.prices.values().has(0):
		return "invalid_market"
	var ids: Array = []
	for crisis in c.crises:
		if crisis.id in ids:
			return "duplicate_crisis"
		ids.append(crisis.id)
		if crisis.announce > crisis.start or crisis.start > crisis.end or crisis.end > c.duration:
			return "invalid_crisis_schedule"
		var neutral: bool = true
		for key in CRISIS_MULTIPLIERS.values():
			if crisis[key] <= 0:
				return "invalid_crisis_multiplier"
			neutral = neutral and crisis[key] == A.S
		if crisis.start == crisis.end and not neutral:
			return "empty_crisis_with_effect"
	for kind in TYPES:
		var item: Dictionary = c.buildings[kind]
		for required in item.requires:
			if required == kind or not c.buildings.has(required):
				return "invalid_prerequisite"
			for transitive in c.buildings[required].requires:
				if transitive not in item.requires:
					return "prerequisites_must_be_transitively_explicit"
		for size in SIZES:
			var t: Dictionary = item[size]
			if t.credits <= 0 or t.seconds <= 0 or t.seconds >= c.duration or t.upkeep <= 0:
				return "invalid_building_tier"
			if t.generation > 0 and t.demand > 0:
				return "generator_with_demand"
			if size != "S" and (t.upgrade.credits <= 0 or t.upgrade.seconds <= 0 or t.upgrade.seconds >= c.duration):
				return "invalid_upgrade"
	for order in [c.staffing_order, c.power_order]:
		for kind in order:
			if kind not in TYPES or order.count(kind) != 1:
				return "invalid_priority_order"
	for kind in TYPES:
		for size in SIZES:
			if c.buildings[kind][size].jobs > 0 and kind not in c.staffing_order:
				return "staffed_type_missing_from_staffing_order"
			if c.buildings[kind][size].demand > 0 and kind not in c.power_order:
				return "powered_type_missing_from_power_order"
	for id in FOUNDATIONS:
		var owned: Array = []
		var package: Dictionary = c.foundations[id]
		if package.buildings.size() > c.tiles:
			return "foundation_exceeds_grid"
		for start in package.buildings:
			for required in c.buildings[start.type].requires:
				if required not in owned:
					return "foundation_violates_prerequisites"
			owned.append(start.type)
	return ""

## Field reader that records the first error and never throws.
class Reader:
	var error: String = ""

	func fail(reason: String) -> void:
		if error.is_empty():
			error = reason

	func section(raw: Variant, key: String) -> Dictionary:
		var value: Variant = raw.get(key) if raw is Dictionary else null
		if not value is Dictionary:
			fail("missing_" + key)
			return {}
		return value

	func number(raw: Dictionary, key: String, kind: int, optional: bool = false) -> int:
		if not raw.has(key):
			if not optional:
				fail("missing_" + key)
			return 0
		var value: Variant = raw[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			fail("invalid_" + key)
			return 0
		if kind == COUNT:
			if float(value) != floor(float(value)) or float(value) > float(LIMIT):
				fail("invalid_" + key)
				return 0
			return int(value)
		var scaled: float = float(value) * float(A.S)
		var rounded: float = round(scaled)
		if absf(scaled - rounded) > 0.001 or rounded > float(LIMIT) or (kind == FRACTION and rounded > float(A.S)):
			fail("invalid_" + key)
			return 0
		return int(rounded)

	func types(value: Variant, key: String) -> Array:
		if not value is Array:
			fail("invalid_" + key)
			return []
		for item in value:
			if typeof(item) != TYPE_STRING or item not in TYPES:
				fail("invalid_" + key)
				return []
		return value.duplicate()

	func exact_keys(raw: Dictionary, allowed: Array, label: String) -> void:
		for key in raw:
			if key not in allowed:
				fail("unknown_field_" + label + "." + str(key))

	func build(raw: Dictionary) -> Dictionary:
		if raw.get("version") != "B2.1":
			fail("unsupported_version")
		var game: Dictionary = section(raw, "match")
		var world: Dictionary = section(raw, "world")
		var city: Dictionary = section(raw, "baseline_city")
		var sat: Dictionary = section(raw, "satisfaction")
		var weights: Dictionary = section(sat, "weights_points")
		var mig: Dictionary = section(raw, "migration")
		var eco: Dictionary = section(raw, "economy")
		var con: Dictionary = section(raw, "construction")
		var waste: Dictionary = section(raw, "waste")
		var env: Dictionary = section(raw, "environment")
		var pressure: Dictionary = section(env, "untreated_pressure")
		var market: Dictionary = section(raw, "market")
		var prices: Dictionary = section(market, "prices")
		if not error.is_empty():
			return {}
		if number(game, "tick_seconds", COUNT) != 1:
			fail("unsupported_tick_seconds")
		var c: Dictionary = {
			"version": "B2.1",
			"players": number(game, "players", COUNT),
			"duration": number(game, "duration_seconds", COUNT),
			"residents": number(game, "total_residents", COUNT),
			"initial_residents": number(game, "initial_residents_per_city", COUNT),
			"tiles": number(world, "building_grid_width", COUNT) * number(world, "building_grid_height", COUNT),
			"city": {
				"housing": number(city, "starting_housing_capacity", COUNT),
				"services": number(city, "starting_service_capacity", COUNT),
				"municipal_jobs": number(city, "starting_municipal_job_slots", COUNT),
				"materials": number(city, "starting_materials", MICRO),
				"air": number(city, "starting_air_burden", MICRO),
				"landfill_damage": number(city, "starting_landfill_damage", MICRO),
				"generation": number(city, "municipal_electricity_generation_capacity", MICRO),
				"base_demand": number(city, "municipal_base_electricity_demand", MICRO),
				"demand_per_resident": number(city, "municipal_electricity_per_resident", MICRO),
				"collection": number(city, "municipal_waste_collection_capacity_per_min", MICRO),
				"landfill": number(city, "municipal_landfill_capacity_per_min", MICRO),
				"upkeep": number(city, "municipal_upkeep_credits_per_min", MICRO),
			},
			"satisfaction": {
				"environment": number(weights, "environment", COUNT),
				"employment": number(weights, "realized_employment", COUNT),
				"housing": number(weights, "housing_slack", COUNT),
				"power": number(weights, "electricity_reliability", COUNT),
				"services": number(weights, "effective_services", COUNT),
				"housing_slack": number(sat, "housing_satisfaction_slack_multiplier", MICRO),
				"services_slack": number(sat, "services_satisfaction_slack_multiplier", MICRO),
			},
			"migration": {
				"first": number(mig, "first_event_tick", COUNT),
				"last": number(mig, "last_event_tick", COUNT),
				"interval": number(mig, "event_interval_seconds", COUNT),
				"min_gap": number(mig, "min_satisfaction_gap_points", MICRO),
				"per_gap_point": number(mig, "migration_per_gap_point", MICRO),
				"source_max": number(mig, "migration_per_source_per_event_max", COUNT),
				"target_max": number(mig, "migration_per_target_per_event_max", COUNT),
				"source_min": number(mig, "source_min_residents", COUNT),
			},
			"staffing_order": types(section(raw, "employment").get("staffing_priority_order"), "staffing_priority_order"),
			"power_order": types(section(raw, "electricity").get("allocation_priority"), "allocation_priority"),
			"economy": {
				"tax": number(eco, "population_tax_credits_per_resident_per_min", MICRO),
				"buy_price": number(eco, "external_virgin_material_buy_price_credits_per_unit", MICRO),
				"sell_price": number(eco, "external_material_sell_price_credits_per_unit", MICRO),
				"material_cap": number(eco, "material_inventory_capacity_units", MICRO),
				"landfill_fee": number(eco, "landfill_fee_credits_per_waste_unit", MICRO),
				"levy": number(eco, "emissions_levy_credits_per_air_point_emitted", MICRO),
				"standby": number(eco, "standby_upkeep_fraction", FRACTION),
			},
			"construction": {
				"slots": number(con, "simultaneous_projects_max", COUNT),
				"cancel_refund": number(con, "cancel_project_refund_fraction_of_base_credits", FRACTION),
				"cancel_materials_refund": number(con, "cancel_project_materials_refund_fraction", FRACTION),
				"demolition_refund": number(con, "demolition_refund_fraction_of_base_credits", FRACTION),
				"reactivation_cooldown": number(con, "reactivation_cooldown_seconds", COUNT),
			},
			"waste": {
				"household": number(waste, "household_waste_per_resident_per_min", MICRO),
				"composition": {},
				"mixed_cap": number(waste, "mixed_inventory_cap", MICRO),
				"sorted_cap": [number(waste, "sorted_recyclable_inventory_cap", MICRO), number(waste, "sorted_organic_inventory_cap", MICRO)],
			},
			"environment": {
				"air_cap": number(env, "air_burden_cap", MICRO),
				"landfill_cap": number(env, "landfill_damage_cap", MICRO),
				"air_decay": number(env, "natural_air_decay_points_per_min", MICRO),
				"landfill_damage": number(env, "landfill_damage_points_per_waste_mass", MICRO),
				"amenity_cap": number(env, "park_amenity_cap_points", MICRO),
				"pressure_street": number(pressure, "uncollected_street", MICRO),
				"pressure_mixed": number(pressure, "collected_mixed", MICRO),
				"pressure_stored": number(pressure, "sorted_and_residual", MICRO),
				"pressure_cap": number(pressure, "cap", MICRO),
			},
			"crises": [],
			"market": {
				"max_offers": number(market, "max_open_offers_per_city", COUNT),
				"max_contracts": number(market, "max_active_contracts_per_buyer", COUNT),
				"min_duration": number(market, "min_duration_seconds", COUNT),
				"default_duration": number(market, "default_duration_seconds", COUNT),
				"max_duration": number(market, "max_duration_seconds", COUNT),
				"electricity_max": number(market, "electricity_capacity_units_per_contract_max", MICRO),
				"prices": {
					"electricity": number(prices, "electricity_credits_per_capacity_minute", MICRO),
					"recyclable": number(prices, "recyclable_treatment_credits_per_waste_unit", MICRO),
					"organic": number(prices, "organic_treatment_credits_per_waste_unit", MICRO),
				},
			},
			"buildings": {},
			"foundations": {},
		}
		for source in SOURCES:
			var mix: Dictionary = section(waste, SOURCES[source])
			c.waste.composition[source] = []
			for category in CATEGORIES:
				c.waste.composition[source].append(number(mix, category, FRACTION))
		c.crises = crises(raw.get("crises"))
		c.buildings = buildings(section(raw, "buildings"))
		c.foundations = foundations(section(raw, "foundations"))
		return c

	func crises(value: Variant) -> Array:
		var result: Array = []
		if not value is Array:
			fail("invalid_crises")
			return result
		for raw in value:
			if not raw is Dictionary or typeof(raw.get("id")) != TYPE_STRING or raw.id.is_empty():
				fail("invalid_crisis")
				return result
			exact_keys(raw, ["id", "announce_tick", "start_tick", "end_tick_exclusive"] + CRISIS_MULTIPLIERS.keys(), "crisis")
			var crisis: Dictionary = {"id": raw.id, "announce": number(raw, "announce_tick", COUNT),
				"start": number(raw, "start_tick", COUNT), "end": number(raw, "end_tick_exclusive", COUNT)}
			for key in CRISIS_MULTIPLIERS:
				crisis[CRISIS_MULTIPLIERS[key]] = number(raw, key, MICRO) if raw.has(key) else A.S
			result.append(crisis)
		return result

	func buildings(raw: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		exact_keys(raw, TYPES, "buildings")
		for kind in TYPES:
			var item: Dictionary = section(raw, kind)
			exact_keys(item, ["required_completed_buildings"] + SIZES, kind)
			var entry: Dictionary = {"requires": types(item.get("required_completed_buildings"), kind + ".required_completed_buildings")}
			for size in SIZES:
				entry[size] = tier(section(item, size), kind, size)
			result[kind] = entry
		return result

	func tier(raw: Dictionary, kind: String, size: String) -> Dictionary:
		var upgrade_key: String = {"S": "", "M": "upgrade_from_S", "L": "upgrade_from_M"}[size]
		exact_keys(raw, TIER_FIELDS.keys() + ([upgrade_key] if upgrade_key else []), kind + "." + size)
		var result: Dictionary = {}
		for key in TIER_FIELDS:
			result[TIER_FIELDS[key][0]] = number(raw, key, TIER_FIELDS[key][1], key not in TIER_REQUIRED)
		if upgrade_key:
			var up: Dictionary = section(raw, upgrade_key)
			exact_keys(up, ["additional_credits", "additional_materials", "seconds"], kind + "." + upgrade_key)
			result["upgrade"] = {"credits": number(up, "additional_credits", MICRO),
				"materials": number(up, "additional_materials", MICRO), "seconds": number(up, "seconds", COUNT)}
		return result

	func foundations(raw: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		exact_keys(raw, FOUNDATIONS, "foundations")
		for id in FOUNDATIONS:
			var item: Dictionary = section(raw, id)
			exact_keys(item, ["starting_buildings", "starting_cash_credits", "starting_materials_units"], id)
			var package: Dictionary = {"buildings": [], "credits": number(item, "starting_cash_credits", MICRO),
				"materials": number(item, "starting_materials_units", MICRO)}
			if not item.get("starting_buildings") is Array:
				fail("invalid_starting_buildings")
				continue
			for start in item.starting_buildings:
				if not start is Dictionary or start.size() != 2 or start.get("id") not in TYPES or start.get("tier") not in SIZES:
					fail("invalid_starting_building")
					break
				package.buildings.append({"type": start.id, "size": start.tier})
			result[id] = package
		return result
