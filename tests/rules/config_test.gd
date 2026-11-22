extends "res://tests/support/harness.gd"
## The live configuration loads exactly the B2.1 numbers, and malformed or
## inconsistent configurations are rejected rather than repaired.

## Audit §6 catalogue with residents counted at the 8,000 scale (jobs, homes and
## services doubled): [credits, materials, seconds, upkeep, jobs, power, primary capacity].
## Power is demand for consumers and generation for plants.
const CATALOGUE = {
	"residential_district": [[125, 9, 25, 4, 0, 0, 360], [235, 17, 43, 7, 0, 0, 760], [380, 28, 65, 11, 0, 0, 1340]],
	"factory": [[175, 12, 28, 22, 310, 26, 145], [315, 22, 48, 38, 570, 47, 265], [495, 36, 73, 61, 900, 75, 410]],
	"commercial_district": [[145, 8, 25, 14, 200, 14, 75], [260, 14, 43, 26, 370, 26, 137], [425, 23, 66, 43, 600, 42, 222]],
	"public_services_center": [[125, 8, 27, 8, 48, 9, 460], [220, 14, 44, 15, 80, 16, 940], [355, 24, 65, 25, 130, 25, 1520]],
	"park": [[95, 4, 20, 3, 0, 0, 0.24], [170, 7, 35, 5, 0, 0, 0.43], [280, 12, 53, 9, 0, 0, 0.72]],
	"collection_center": [[95, 5, 23, 7, 48, 7, 23], [175, 10, 39, 12, 84, 12, 45], [280, 17, 58, 19, 132, 19, 72]],
	"sorting_center": [[100, 7, 25, 9, 56, 11, 34], [190, 13, 42, 16, 102, 20, 63], [310, 22, 63, 26, 160, 32, 100]],
	"recycling_center": [[135, 10, 29, 11, 68, 14, 20], [245, 18, 47, 21, 124, 26, 39], [400, 31, 72, 35, 200, 43, 63]],
	"biogas_facility": [[140, 10, 29, 11, 40, 5, 12], [245, 18, 46, 20, 74, 9, 25], [405, 30, 70, 34, 120, 15, 42]],
	"landfill": [[90, 5, 21, 6, 28, 4, 28], [165, 9, 36, 10, 48, 7, 53], [270, 15, 55, 16, 78, 11, 86]],
	"fossil_power_plant": [[120, 7, 25, 15, 24, 90, 90], [220, 13, 43, 27, 42, 170, 170], [360, 22, 64, 43, 64, 275, 275]],
	"renewable_power_plant": [[205, 10, 32, 6, 20, 75, 75], [365, 18, 55, 11, 36, 145, 145], [590, 30, 83, 18, 58, 235, 235]],
}
const PRIMARY = {"residential_district": "housing", "factory": "income", "commercial_district": "income",
	"public_services_center": "services", "park": "cleanup", "collection_center": "collection",
	"sorting_center": "sorting", "recycling_center": "recycling", "biogas_facility": "biogas",
	"landfill": "landfill", "fossil_power_plant": "generation", "renewable_power_plant": "generation"}
## Audit §6 tier upgrades: [S->M credits, materials, seconds, M->L credits, materials, seconds].
const UPGRADES = {
	"residential_district": [119, 8, 33, 157, 11, 49], "factory": [152, 10, 36, 195, 14, 55],
	"commercial_district": [125, 6, 33, 179, 9, 50], "public_services_center": [103, 6, 33, 146, 10, 49],
	"park": [81, 3, 27, 119, 5, 40], "collection_center": [87, 5, 30, 114, 7, 44],
	"sorting_center": [98, 6, 32, 130, 9, 48], "recycling_center": [119, 8, 36, 168, 13, 54],
	"biogas_facility": [114, 8, 35, 173, 12, 53], "landfill": [81, 4, 27, 114, 6, 42],
	"fossil_power_plant": [108, 6, 33, 152, 9, 48], "renewable_power_plant": [173, 8, 42, 244, 12, 63],
}
## Audit §6 operating coefficients, S/M/L.
const COEFFICIENTS = {
	"factory": {"material_input": [7, 13, 20], "waste": [14, 25, 39], "emissions": [0.75, 1.35, 2.2]},
	"commercial_district": {"waste": [5, 9, 15], "emissions": [0.07, 0.12, 0.19]},
	"park": {"amenity": [1, 1.7, 2.6]},
	"collection_center": {"collection_reuse": [0.08, 0.1, 0.12]},
	"sorting_center": {"capture_recyclable": [0.8, 0.85, 0.9], "capture_organic": [0.75, 0.81, 0.86], "sorting_reuse": [0.16, 0.18, 0.2]},
	"recycling_center": {"recycling_yield": [0.8, 0.83, 0.86]},
	"biogas_facility": {"biogas_energy": [2.6, 2.8, 3], "biogas_residue": [0.2, 0.18, 0.15]},
	"fossil_power_plant": {"emissions": [0.95, 1.8, 2.9]},
}

func _initialize() -> void:
	var c: Dictionary = Balance.load_config()
	check(not c.is_empty(), "live configuration loads")
	if c.is_empty():
		finish("Configuration")
		return
	catalogue(c)
	baseline(c)
	malformed()
	finish("Configuration")

static func micro(value: float) -> int:
	return int(round(value * 1000000.0))

func catalogue(c: Dictionary) -> void:
	eq(c.buildings.keys().size(), 12, "twelve building types")
	for kind in CATALOGUE:
		for i in range(3):
			var size: String = Balance.SIZES[i]
			var row: Array = CATALOGUE[kind][i]
			var t: Dictionary = c.buildings[kind][size]
			var label: String = kind + " " + size
			eq([t.credits, t.materials, t.seconds, t.upkeep], [micro(row[0]), micro(row[1]), row[2], micro(row[3])], label + " price, time, upkeep")
			eq(t.jobs, row[4], label + " jobs")
			eq(t.generation if t.generation > 0 else t.demand, micro(row[5]), label + " power")
			var primary: Variant = t[PRIMARY[kind]]
			eq(primary, row[6] if kind in ["residential_district", "public_services_center"] else micro(row[6]), label + " primary capacity")
			for field in COEFFICIENTS.get(kind, {}):
				eq(t[field], micro(COEFFICIENTS[kind][field][i]), label + " " + field)
		var up: Array = UPGRADES[kind]
		eq([c.buildings[kind].M.upgrade.credits, c.buildings[kind].M.upgrade.materials, c.buildings[kind].M.upgrade.seconds], [micro(up[0]), micro(up[1]), up[2]], kind + " S->M upgrade")
		eq([c.buildings[kind].L.upgrade.credits, c.buildings[kind].L.upgrade.materials, c.buildings[kind].L.upgrade.seconds], [micro(up[3]), micro(up[4]), up[5]], kind + " M->L upgrade")
	eq(c.buildings.sorting_center.requires, ["collection_center"], "sorting requires collection")
	eq(c.buildings.recycling_center.requires, ["collection_center", "sorting_center"], "recycling requires the chain")
	eq(c.buildings.biogas_facility.requires, ["collection_center", "sorting_center"], "biogas requires the chain")
	for kind in ["residential_district", "factory", "landfill", "park", "collection_center"]:
		eq(c.buildings[kind].requires, [], kind + " has no prerequisite")

func baseline(c: Dictionary) -> void:
	eq([c.residents, c.initial_residents], [8000, 2000], "8,000 residents, 2,000 per city")
	eq(c.city.buildings, [{"type": "residential_district", "size": "M"}, {"type": "residential_district", "size": "M"}, {"type": "residential_district", "size": "M"}], "three Medium Residential Districts")
	eq([c.city.services, c.city.municipal_jobs], [2300, 1000], "baseline capacities")
	eq([c.city.generation, c.city.base_demand, c.city.demand_per_resident], [100 * U, 43 * U, 10000], "municipal electricity")
	eq([c.city.collection, c.city.landfill, c.city.upkeep], [40 * U, 38 * U, 31 * U], "municipal waste and upkeep")
	eq([c.city.air, c.city.landfill_damage, c.city.materials], [3 * U, 1 * U, 30 * U], "starting stocks")
	eq([c.economy.tax, c.economy.buy_price, c.economy.sell_price, c.economy.material_cap, c.economy.landfill_fee, c.economy.levy],
		[55000, 6 * U, 2 * U, 500 * U, 850000, 2 * U], "economy prices")
	eq(c.waste.composition.household, [500000, 300000, 200000], "household composition")
	eq(c.waste.household, 15000, "household waste per resident")
	eq(c.migration, {"first": 80, "last": 1180, "interval": 20, "min_gap": 750000, "per_gap_point": 8 * U,
		"source_max": 60, "target_max": 150, "source_min": 700}, "migration rule")
	eq(c.foundations.industrial_legacy, {"buildings": [{"type": "factory", "size": "S"}], "credits": 413 * U, "materials": 0}, "Industrial Legacy")
	eq(c.foundations.circular_foundation, {"buildings": [{"type": "collection_center", "size": "S"}, {"type": "sorting_center", "size": "S"}], "credits": 393 * U, "materials": 0}, "Circular Foundation")
	eq(c.foundations.energy_pioneer, {"buildings": [{"type": "renewable_power_plant", "size": "S"}], "credits": 395 * U, "materials": 0}, "Energy Pioneer")
	eq(c.foundations.investment_district, {"buildings": [], "credits": 660 * U, "materials": 0}, "Investment District")
	eq(c.crises.map(func(x): return [x.id, x.announce, x.start, x.end]),
		[["smog_alert", 255, 300, 390], ["waste_surge", 555, 600, 690], ["power_shortage", 855, 900, 990], ["equilibrium_2050", 1140, 1200, 1200]], "crisis schedule")
	eq(c.market.prices, {"electricity": 220000, "recyclable": 750000, "organic": 700000}, "contract prices")

func rejects(mutate: Callable, label: String) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Balance.PATH))
	mutate.call(raw)
	check(not Balance.normalize(raw).error.is_empty(), "rejects " + label)

func malformed() -> void:
	rejects(func(r): r.version = "B1", "another version")
	rejects(func(r): r.erase("economy"), "missing section")
	rejects(func(r): r.economy.landfill_fee_credits_per_waste_unit = -1, "negative value")
	rejects(func(r): r.buildings.collection_center.S.collection_direct_reuse_fraction = 1.5, "fraction above one")
	rejects(func(r): r.buildings.factory.S.construction_seconds = 28.5, "fractional count")
	rejects(func(r): r.buildings.factory.S["typo_field"] = 1, "unknown tier field")
	rejects(func(r): r.buildings.factory.S.erase("construction_credits"), "missing required tier field")
	rejects(func(r): r.waste.household_composition.organic = 0.31, "composition not summing to one")
	rejects(func(r): r.buildings.collection_center.required_completed_buildings = ["recycling_center"], "prerequisite cycle")
	rejects(func(r): r.buildings.recycling_center.required_completed_buildings = ["sorting_center"], "implicit transitive prerequisite")
	rejects(func(r): r.foundations.circular_foundation.starting_buildings = [{"id": "sorting_center", "tier": "S"}], "Foundation skipping a prerequisite")
	rejects(func(r): r.foundations.circular_foundation.starting_buildings = [{"id": "recycling_center", "tier": "S"}, {"id": "collection_center", "tier": "S"}, {"id": "sorting_center", "tier": "S"}], "Foundation out of chain order")
	rejects(func(r): r.economy.external_material_sell_price_credits_per_unit = 6, "buy/sell arbitrage")
	rejects(func(r): r.buildings.fossil_power_plant.S["power_demand_capacity"] = 1, "generator with demand")
	rejects(func(r): r.crises[1].id = "smog_alert", "duplicate crisis")
	rejects(func(r): r.crises[3]["emission_multiplier"] = 2, "empty crisis with an effect")
	rejects(func(r): r.match.players = 3, "unsupported player count")
	rejects(func(r): r.buildings.erase("park"), "missing building type")
	rejects(func(r): r.employment.staffing_priority_order.erase("factory"), "staffed type missing from staffing order")
	rejects(func(r): r.market.min_duration_seconds = 400, "contract durations out of order")
	rejects(func(r): r.baseline_city.starting_buildings = [{"id": "residential_district", "tier": "S"}], "starting homes below the starting residents")
	rejects(func(r): r.baseline_city.starting_buildings = [{"id": "sorting_center", "tier": "S"}], "baseline building skipping a prerequisite")
