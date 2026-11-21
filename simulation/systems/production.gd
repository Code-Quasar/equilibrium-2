extends RefCounted
## Factory and commercial output. A building runs at the largest fraction, up to its
## power and staff share, whose material purchases and emission levy the treasury
## can pay this second. Factories use stocked materials before buying. Income, waste
## and emissions all scale with that same realized fraction.
const A = preload("res://simulation/core/arithmetic.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Materials = preload("res://simulation/systems/materials.gd")
const SOURCES = {"factory": "factory", "commercial_district": "commercial"}
var b: Dictionary
var catalogue: RefCounted
var waste: RefCounted

func _init(config: Dictionary, buildings: RefCounted, waste_system: RefCounted) -> void:
	b = config
	catalogue = buildings
	waste = waste_system

## Phase: production in electricity priority order, plot order within a type.
func run(state: Dictionary, _ctx: Dictionary) -> String:
	var effects: Dictionary = state.crisis.effects
	for city in state.cities:
		for building in Buildings.ordered(city, b.power_order):
			if not building.op.funded or not SOURCES.has(building.type):
				continue
			var t: Dictionary = catalogue.tier(building)
			var emission_rate: int = A.mul(t.emissions, effects.emission)
			var fraction: int = _affordable(city, building, t, emission_rate, building.op.fraction_micro)
			var materials: int = A.per_tick(building.carries, "material_input", t.material_input, fraction)
			var emitted: int = A.per_tick(building.carries, "emissions", emission_rate, fraction)
			if not Materials.consume(city, b, materials) or not Finance.debit(city, A.mul(emitted, b.economy.levy), "emissions_levy"):
				return "production_unaffordable"
			Finance.credit(city, A.per_tick(building.carries, "income", t.income, fraction), "building_income")
			var source: String = SOURCES[building.type]
			waste.generate(city, building.carries, source, A.mul(t.waste, effects[source]), fraction)
			building.op.fraction_micro = fraction
			building.op.emitted_micro = emitted
	return ""

func _cost(city: Dictionary, building: Dictionary, t: Dictionary, emission_rate: int, fraction: int) -> int:
	var materials: int = A.peek_tick(building.carries, "material_input", t.material_input, fraction)
	var emitted: int = A.peek_tick(building.carries, "emissions", emission_rate, fraction)
	return Materials.purchase_cost(city, b, materials) + A.mul(emitted, b.economy.levy)

## Largest fraction up to limit whose operating cost is payable; cost is monotone.
func _affordable(city: Dictionary, building: Dictionary, t: Dictionary, emission_rate: int, limit: int) -> int:
	var cash: int = Finance.available(city)
	if _cost(city, building, t, emission_rate, limit) <= cash:
		return limit
	var low: int = 0
	var high: int = limit
	while low < high:
		var middle: int = A.divi(low + high + 1, 2)
		if _cost(city, building, t, emission_rate, middle) <= cash:
			low = middle
		else:
			high = middle - 1
	return low
