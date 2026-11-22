extends RefCounted
## Physical waste flow. Every unit of mass sits in exactly one place: the street,
## the dedicated mixed buffer, a sorted stream, the disposal queue, or one of the
## sinks (recovered materials, digested organics, landfill, export).
##
##   street --dedicated collection--> mixed --sorting--> sorted recyclable --recycling--> materials
##     |          (salvage -> materials)       (reuse -> materials)          (rejects -> disposal)
##     |                                     --> sorted organic --biogas--> converted + next-tick E
##     |                                     --> misses -> disposal          (residue -> disposal)
##     +--municipal collection--> disposal --landfill--> landfilled  (then mixed as unsorted bypass)
##
## Each stage recovers only mass removed from the stage before it, so no unit is
## valued twice. Municipal collection never feeds sorting.
const A = preload("res://simulation/core/arithmetic.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Materials = preload("res://simulation/systems/materials.gd")
const Emergencies = preload("res://simulation/systems/emergencies.gd")
const R: int = 0
const O: int = 1
const X: int = 2
const FLOWS = ["generated", "collected", "salvaged", "municipal_collected", "sorted",
	"captured_recyclable", "captured_organic", "sorting_misses", "sorting_reuse", "overflow_to_disposal",
	"recycled", "recycled_materials", "recycling_rejects", "digested", "digested_converted",
	"digestion_residue", "landfilled", "landfilled_unsorted", "exported", "imported"]
var b: Dictionary
var catalogue: RefCounted

func _init(config: Dictionary, buildings: RefCounted) -> void:
	b = config
	catalogue = buildings

static func initialize(city: Dictionary) -> void:
	city["street_micro"] = [0, 0, 0]
	city["mixed_micro"] = [0, 0, 0]
	city["sorted_micro"] = [0, 0]
	city["disposal_micro"] = 0
	var flows: Dictionary = {}
	for key in FLOWS:
		flows[key] = 0
	city["waste"] = {"tick": flows, "totals": flows.duplicate()}
	city["processing"] = {"recyclable_capacity_micro": 0, "organic_capacity_micro": 0}

static func flow(city: Dictionary, key: String, amount: int) -> void:
	city.waste.tick[key] += amount
	city.waste.totals[key] += amount

static func recovered(city: Dictionary) -> int:
	var t: Dictionary = city.waste.totals
	return t.salvaged + t.sorting_reuse + t.recycled_materials

## Adds one source's waste for this second at its composition.
func generate(city: Dictionary, carries: Dictionary, source: String, rate: int, fraction: int) -> void:
	for i in range(3):
		var amount: int = A.per_tick(carries, "waste_%d" % i, A.mul(rate, b.waste.composition[source][i]), fraction)
		city.street_micro[i] += amount
		flow(city, "generated", amount)

## Phase: household waste, dedicated collection with salvage, municipal fallback,
## sorting with direct reuse, then this tick's treatment budgets.
func collect_and_sort(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		for key in FLOWS:
			city.waste.tick[key] = 0
		generate(city, city.carries, "household", A.mul(b.waste.household * city.population, state.crisis.effects.household), A.S)
		# An ECO EMERGENCIES boost raises a stage's own rate; it never adds waste.
		_collect(city, Emergencies.multiplier(state, city.city_id, "collection"))
		_municipal_collect(city)
		_sort(city, Emergencies.multiplier(state, city.city_id, "sorting"))
		_budget(city, Emergencies.multiplier(state, city.city_id, "recycling"))
	return ""

func _collect(city: Dictionary, boost: int = A.S) -> void:
	for center in Buildings.by_tile(city, "collection_center"):
		if not center.op.funded:
			continue
		var t: Dictionary = catalogue.tier(center)
		var capacity: int = A.per_tick(center.carries, "collection", A.mul(t.collection, boost), center.op.fraction_micro)
		var room: int = b.waste.mixed_cap - A.total(city.mixed_micro)
		var taken: Array = A.allocate(mini(capacity, room), city.street_micro)
		var salvage: int = A.carried(center.carries, "salvage", taken[R], t.collection_reuse, A.S)
		for i in range(3):
			city.street_micro[i] -= taken[i]
			city.mixed_micro[i] += taken[i]
		city.mixed_micro[R] -= salvage
		Materials.recover(city, salvage)
		flow(city, "collected", A.total(taken))
		flow(city, "salvaged", salvage)

func _municipal_collect(city: Dictionary) -> void:
	var capacity: int = A.per_tick(city.carries, "municipal_collection", b.city.collection)
	var taken: Array = A.allocate(capacity, city.street_micro)
	for i in range(3):
		city.street_micro[i] -= taken[i]
	city.disposal_micro += A.total(taken)
	flow(city, "municipal_collected", A.total(taken))

func _sort(city: Dictionary, boost: int = A.S) -> void:
	for sorter in Buildings.by_tile(city, "sorting_center"):
		if not sorter.op.funded:
			continue
		var t: Dictionary = catalogue.tier(sorter)
		var capacity: int = A.per_tick(sorter.carries, "sorting", A.mul(t.sorting, boost), sorter.op.fraction_micro)
		var taken: Array = A.allocate(capacity, city.mixed_micro)
		for i in range(3):
			city.mixed_micro[i] -= taken[i]
		var recyclable: int = A.carried(sorter.carries, "capture_recyclable", taken[R], t.capture_recyclable, A.S)
		var organic: int = A.carried(sorter.carries, "capture_organic", taken[O], t.capture_organic, A.S)
		var reuse: int = A.carried(sorter.carries, "reuse", recyclable, t.sorting_reuse, A.S)
		var misses: int = A.total(taken) - recyclable - organic
		Materials.recover(city, reuse)
		city.disposal_micro += misses
		_store(city, R, recyclable - reuse)
		_store(city, O, organic)
		flow(city, "sorted", A.total(taken))
		flow(city, "captured_recyclable", recyclable)
		flow(city, "captured_organic", organic)
		flow(city, "sorting_reuse", reuse)
		flow(city, "sorting_misses", misses)

## Sorted mass above a stream's cap goes to disposal, never back to be sorted again.
func _store(city: Dictionary, stream: int, amount: int) -> void:
	var kept: int = mini(amount, b.waste.sorted_cap[stream] - city.sorted_micro[stream])
	city.sorted_micro[stream] += kept
	city.disposal_micro += amount - kept
	flow(city, "overflow_to_disposal", amount - kept)

## Per-plant throughput for this second. Contracted imports and local stock share it.
func _budget(city: Dictionary, recycling_boost: int = A.S) -> void:
	var capacity: Dictionary = {"recycling_center": 0, "biogas_facility": 0}
	for kind in capacity:
		for plant in Buildings.by_tile(city, kind):
			if not plant.op.funded:
				continue
			var rate: int = A.mul(catalogue.tier(plant).recycling, recycling_boost) if kind == "recycling_center" else catalogue.tier(plant).biogas
			plant.op.budget_micro = A.per_tick(plant.carries, "throughput", rate, plant.op.fraction_micro)
			capacity[kind] += A.mul(rate, plant.op.fraction_micro)
	city.processing = {"recyclable_capacity_micro": capacity.recycling_center, "organic_capacity_micro": capacity.biogas_facility}

static func plant_kind(stream: int) -> String:
	return "recycling_center" if stream == R else "biogas_facility"

static func remaining_budget(city: Dictionary, stream: int) -> int:
	var amount: int = 0
	for plant in Buildings.by_tile(city, plant_kind(stream)):
		amount += plant.op.budget_micro
	return amount

## Treats amount of one sorted stream in plot order; returns the mass treated.
func treat(city: Dictionary, stream: int, amount: int) -> int:
	var treated: int = 0
	for plant in Buildings.by_tile(city, plant_kind(stream)):
		var input: int = mini(amount - treated, plant.op.budget_micro)
		if input <= 0:
			continue
		plant.op.budget_micro -= input
		treated += input
		var t: Dictionary = catalogue.tier(plant)
		if stream == R:
			var output: int = A.carried(plant.carries, "yield", input, t.recycling_yield, A.S)
			Materials.recover(city, output)
			city.disposal_micro += input - output
			flow(city, "recycled", input)
			flow(city, "recycled_materials", output)
			flow(city, "recycling_rejects", input - output)
		else:
			var residue: int = A.carried(plant.carries, "residue", input, t.biogas_residue, A.S)
			city.disposal_micro += residue
			# input is mass per second; E per (unit per minute) needs the minute rate.
			city.biogas_pending_micro_E += A.mul(60 * input, t.biogas_energy)
			flow(city, "digested", input)
			flow(city, "digested_converted", input - residue)
			flow(city, "digestion_residue", residue)
	return treated

## Phase: local sorted stock uses the throughput contracts left.
func treat_local(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		for stream in [R, O]:
			city.sorted_micro[stream] -= treat(city, stream, city.sorted_micro[stream])
	return ""

## Phase: landfill takes the disposal queue first, then unsorted mixed waste as a
## bypass, limited by capacity and by the fees the treasury can pay.
func landfill(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		var capacity: int = A.per_tick(city.carries, "municipal_landfill", b.city.landfill)
		for site in Buildings.by_tile(city, "landfill"):
			if site.op.funded:
				capacity += A.per_tick(site.carries, "landfill", catalogue.tier(site).landfill, site.op.fraction_micro)
		var amount: int = mini(capacity, city.disposal_micro + A.total(city.mixed_micro))
		amount = mini(amount, _affordable(city, amount))
		if amount == 0:
			continue
		Finance.debit(city, A.carried(city.carries, "landfill_fee", amount, b.economy.landfill_fee, A.S), "landfill_fees")
		var queued: int = mini(amount, city.disposal_micro)
		city.disposal_micro -= queued
		var bypass: Array = A.allocate(amount - queued, city.mixed_micro)
		for i in range(3):
			city.mixed_micro[i] -= bypass[i]
		flow(city, "landfilled", amount)
		flow(city, "landfilled_unsorted", amount - queued)
	return ""

## Largest disposal mass up to limit whose fee the city can pay now.
func _affordable(city: Dictionary, limit: int) -> int:
	var cash: int = Finance.available(city)
	var fee := func(units: int) -> int: return A.peek(city.carries, "landfill_fee", units, b.economy.landfill_fee, A.S)
	if fee.call(limit) <= cash:
		return limit
	var low: int = 0
	var high: int = limit
	while low < high:
		var middle: int = A.divi(low + high + 1, 2)
		if fee.call(middle) <= cash:
			low = middle
		else:
			high = middle - 1
	return low

func validate_city(city: Dictionary) -> String:
	for amount in city.street_micro + city.mixed_micro + city.sorted_micro + [city.disposal_micro, city.biogas_pending_micro_E]:
		if typeof(amount) != TYPE_INT or amount < 0:
			return "invalid_waste_inventory"
	if A.total(city.mixed_micro) > b.waste.mixed_cap or city.sorted_micro[R] > b.waste.sorted_cap[R] or city.sorted_micro[O] > b.waste.sorted_cap[O]:
		return "waste_inventory_cap"
	var t: Dictionary = city.waste.totals
	for value in t.values() + city.waste.tick.values():
		if typeof(value) != TYPE_INT or value < 0:
			return "invalid_waste_flow"
	var held: int = A.total(city.street_micro) + A.total(city.mixed_micro) + A.total(city.sorted_micro) + city.disposal_micro
	if t.generated + t.imported != held + recovered(city) + t.digested_converted + t.landfilled + t.exported:
		return "waste_mass_conservation"
	return ""
