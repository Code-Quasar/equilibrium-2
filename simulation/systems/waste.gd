extends RefCounted
const A = preload("res://simulation/core/arithmetic.gd")
const Finance = preload("res://simulation/systems/finance.gd")
var b: Dictionary
var rules: Dictionary
var catalogue: RefCounted

func _init(balance: Dictionary, buildings: RefCounted) -> void:
	b = balance
	rules = b.local_simulation
	catalogue = buildings

func generate(city: Dictionary, source: String, key: String, rate: int, efficiency: int) -> void:
	rate = A.mul(rate, city.get("event_modifiers", {}).get(source + "_percent", 100), 100)
	for i in range(3):
		var percent: int = rules[source + "_" + ["R", "O", "X"][i] + "_percent"]
		# B1 rate/percentage products are integral micro-units/minute before conversion.
		var amount: int = A.carried(city, key + ":" + str(i), rate * percent, efficiency, 6000 * A.S)
		city.uncollected_micro[i] += amount
		city.mass_ledger_micro.generated += amount
		city.waste_totals.generated_by_source[source][i] += amount

func prepare(city: Dictionary) -> void:
	city.processing_budgets.clear()
	if city.has("contract_biogas"): city.contract_biogas.clear()
	city["disposed_this_tick"] = 0
	for building in ordered(city):
		var efficiency: int = A.efficiency(city, building)
		var d: Dictionary = catalogue.effects(building)
		if building.type not in ["recycling_center", "biogas_facility"]: continue
		var capacity: int = d.recycling_per_minute if building.type == "recycling_center" else d.treatment_per_minute
		var key: String = str(building.id)
		city.processing_budgets[key] = {"remaining": A.rate(city, "process:" + key, capacity * A.S, efficiency),
			"reuse_remaining": A.rate(city, "reuse:" + key, d.reuse_per_minute * A.S, efficiency)}

func household_collection(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var rate: int = rules.household_waste_micro_per_resident_minute * city.population
		if city.policy_active: rate = A.mul(rate, rules.policy_household_percent, 100)
		generate(city, "household", "household", rate, A.S)
		var capacity: int = A.rate(city, "base_collection", b.collection_units_per_minute * A.S)
		for building in ordered(city):
			var d: Dictionary = catalogue.effects(building)
			if d.collection_per_minute > 0:
				capacity += A.rate(city, "collection:" + str(building.id), d.collection_per_minute * A.S, A.efficiency(city, building))
		var amounts: Array = A.allocate(capacity, city.uncollected_micro)
		for i in range(3):
			city.uncollected_micro[i] -= amounts[i]
			city.sorted_micro[i] += amounts[i]
			city.waste_totals.collected += amounts[i]
	return ""

# Local and contracted processing share these budgets and yields.
# Contract orchestration and cross-city transfers belong to the market system.
func process(city: Dictionary, building: Dictionary, input_mass: int, organic: bool) -> Dictionary:
	var key: String = str(building.id)
	var budget: Dictionary = city.processing_budgets[key]
	var amount: int = mini(input_mass, budget.remaining)
	budget.remaining -= amount
	if organic:
		var sink: int = A.carried(city, "organic_yield:" + key, amount, rules.organic_sink_percent, 100)
		return {"input": amount, "output": sink, "rejects": amount - sink}
	var reuse: int = mini(amount, budget.reuse_remaining)
	budget.reuse_remaining -= reuse
	var recovered: int = A.carried(city, "reuse_yield:" + key, reuse, rules.reuse_yield_percent, 100)
	recovered += A.carried(city, "recycle_yield:" + key, amount - reuse, rules.recycle_yield_percent, 100)
	return {"input": amount, "output": recovered, "rejects": amount - recovered}

func local_processing(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var next_biogas: Dictionary = city.get("contract_biogas", {}).duplicate()
		for building in ordered(city):
			if building.type not in ["recycling_center", "biogas_facility"]: continue
			var organic: bool = building.type == "biogas_facility"
			var category: int = 1 if organic else 0
			var converted: Dictionary = process(city, building, city.sorted_micro[category], organic)
			city.sorted_micro[category] -= converted.input
			city.sorted_micro[2] += converted.rejects
			if organic:
				city.mass_ledger_micro.organic_sink += converted.output
				city.waste_totals.organic_processed += converted.input
				next_biogas[str(building.id)] = next_biogas.get(str(building.id), 0) + converted.input * 60 * rules.biogas_E_per_unit_minute
			else:
				city.materials_micro += converted.output
				city.mass_ledger_micro.recovered += converted.output
				city.waste_totals.recycled += converted.input
		city.biogas_pending = next_biogas
	return ""

func landfill(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var capacity: int = A.rate(city, "base_landfill", b.landfill_units_per_minute * A.S)
		for building in ordered(city):
			if building.type == "landfill":
				capacity += A.rate(city, "landfill:" + str(building.id), catalogue.effects(building).treatment_per_minute * A.S, A.efficiency(city, building))
		var affordable: int = A.divi(Finance.available(city) * A.S + city.disposal_prepaid_fraction, rules.landfill_price_micro)
		var amount: int = mini(mini(capacity, affordable), A.total(city.sorted_micro))
		if amount == 0: continue
		var numerator: int = amount * rules.landfill_price_micro - city.disposal_prepaid_fraction
		var charge: int = A.divi(numerator + A.S - 1, A.S)
		if not Finance.debit(city, charge, "landfill"): return "landfill_affordability"
		city.disposal_prepaid_fraction = charge * A.S - numerator
		city.disposed_this_tick = amount
		city.mass_ledger_micro.disposed += amount
		for category in [2, 1, 0]:
			var removed: int = mini(amount, city.sorted_micro[category])
			city.sorted_micro[category] -= removed
			amount -= removed
	return ""

func material_sales(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var amount: int = maxi(0, city.materials_micro - rules.material_reserve_micro)
		var income: int = A.carried(city, "material_sale", amount, rules.material_sale_price_micro, A.S)
		city.materials_micro -= amount
		city.materials_sold += amount
		if income > 0: Finance.credit(city, income, "material_sales")
	return ""

static func ordered(city: Dictionary) -> Array:
	var buildings: Array = city.buildings.duplicate()
	buildings.sort_custom(func(a, other): return a.id < other.id)
	return buildings
