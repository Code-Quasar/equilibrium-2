extends RefCounted
## Municipal budget and per-tick building operation: funding, electricity and staffing.
## Each completed building ends with op.fraction_micro = min(power share, staff share);
## output systems scale nameplate capacity by it, and feedstock or cash may lower it.
const A = preload("res://simulation/core/arithmetic.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
var b: Dictionary
var catalogue: RefCounted

func _init(config: Dictionary, buildings: RefCounted) -> void:
	b = config
	catalogue = buildings

## Phase: population taxes arrive, then municipal upkeep is paid. Upkeep the
## treasury cannot cover is recorded as unpaid; there is no municipal debt.
func municipal(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		Finance.credit(city, A.per_tick(city.carries, "taxes", b.economy.tax * city.population), "taxes")
		var due: int = A.per_tick(city.carries, "municipal_upkeep", b.city.upkeep)
		var paid: int = mini(due, Finance.available(city))
		Finance.debit(city, paid, "municipal_upkeep")
		city.finance.unpaid_municipal_upkeep += due - paid
	return ""

## Phase: enabled buildings pay full upkeep, homes first, then in staffing priority
## order, plot order within a type. A fossil plant's emission levy is part of its
## operating cost. Disabled buildings, and enabled ones that cannot pay in full, pay
## standby upkeep if they can.
func fund(state: Dictionary, _ctx: Dictionary) -> String:
	var emission: int = state.crisis.effects.emission
	var order: Array = ["residential_district"] + b.staffing_order
	for city in state.cities:
		for building in Buildings.ordered(city, order):
			building.op = Buildings.idle()
			if building.status != "complete":
				continue
			var t: Dictionary = catalogue.tier(building)
			if building.enabled:
				var upkeep: int = A.peek_tick(building.carries, "upkeep", t.upkeep)
				var emitted: int = A.peek_tick(building.carries, "emissions", A.mul(t.emissions, emission)) if t.generation > 0 else 0
				var levy: int = A.mul(emitted, b.economy.levy)
				if Finance.available(city) >= upkeep + levy:
					Finance.debit(city, A.per_tick(building.carries, "upkeep", t.upkeep), "building_upkeep")
					if t.generation > 0:
						A.per_tick(building.carries, "emissions", A.mul(t.emissions, emission))
						Finance.debit(city, levy, "emissions_levy")
						building.op.emitted_micro = emitted
					building.op.funded = true
					continue
			var standby_rate: int = A.mul(t.upkeep, b.economy.standby)
			if Finance.available(city) >= A.peek_tick(building.carries, "standby", standby_rate):
				Finance.debit(city, A.per_tick(building.carries, "standby", standby_rate), "standby_upkeep")
	return ""

## Phase: own generation and domestic requests. Biogas power comes only from organic
## waste processed during the previous tick.
func measure(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		var plants: int = 0
		var requested: int = 0
		for building in city.buildings:
			if not building.op.funded:
				continue
			var t: Dictionary = catalogue.tier(building)
			plants += t.generation
			building.op.requested_micro_E = t.demand
			requested += t.demand
		city.power = {"municipal_micro_E": A.mul(b.city.generation, state.crisis.effects.municipal_power),
			"plants_micro_E": plants, "biogas_micro_E": city.biogas_pending_micro_E,
			"imports_micro_E": 0, "exports_micro_E": 0,
			"municipal_requested_micro_E": b.city.base_demand + b.city.demand_per_resident * city.population,
			"municipal_delivered_micro_E": 0, "buildings_requested_micro_E": requested,
			"buildings_delivered_micro_E": 0, "unused_micro_E": 0, "reliability_micro": A.S}
		city.power.unused_micro_E = own_generation(city)
		city.biogas_pending_micro_E = 0
	return ""

static func own_generation(city: Dictionary) -> int:
	return city.power.municipal_micro_E + city.power.plants_micro_E + city.power.biogas_micro_E

static func domestic_request(city: Dictionary) -> int:
	return city.power.municipal_requested_micro_E + city.power.buildings_requested_micro_E

## Phase: municipal demand first, then building classes in priority order, prorated
## within a class by request with plot order owning exact remainders.
func allocate(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		var p: Dictionary = city.power
		var remaining: int = own_generation(city) + p.imports_micro_E - p.exports_micro_E
		p.municipal_delivered_micro_E = mini(remaining, p.municipal_requested_micro_E)
		remaining -= p.municipal_delivered_micro_E
		for building in city.buildings:
			if building.op.funded and building.op.requested_micro_E == 0:
				building.op.power_micro = A.S
		for kind in b.power_order:
			var loads: Array = Buildings.by_tile(city, kind).filter(func(x): return x.op.funded and x.op.requested_micro_E > 0)
			var shares: Array = A.allocate(remaining, loads.map(func(x): return x.op.requested_micro_E))
			for i in range(loads.size()):
				var op: Dictionary = loads[i].op
				op.delivered_micro_E = shares[i]
				op.power_micro = A.mul(shares[i], A.S, op.requested_micro_E)
				p.buildings_delivered_micro_E += shares[i]
				remaining -= shares[i]
		p.unused_micro_E = remaining
		var requested: int = domestic_request(city)
		var delivered: int = p.municipal_delivered_micro_E + p.buildings_delivered_micro_E
		p.reliability_micro = A.mul(delivered, A.S, requested) if requested > 0 else A.S
	return ""

## Phase: the first residents fill municipal jobs; the rest staff powered, funded
## buildings in priority order. Unpowered buildings employ nobody.
func staff(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		var municipal: int = mini(city.population, b.city.municipal_jobs)
		var pool: int = city.population - municipal
		for building in Buildings.ordered(city, b.staffing_order):
			var op: Dictionary = building.op
			if not op.funded:
				continue
			var jobs: int = catalogue.tier(building).jobs
			if jobs == 0:
				op.staff_micro = A.S
			elif op.power_micro > 0:
				op.workers = mini(jobs, pool)
				pool -= op.workers
				op.staff_micro = A.mul(op.workers, A.S, jobs)
			op.fraction_micro = mini(op.power_micro, op.staff_micro)
		city.employment = {"municipal": municipal, "buildings": city.population - municipal - pool}
	return ""

## Share of the municipal service baseline that operates: staffed by the first
## residents and powered by the municipal allocation.
func municipal_service_fraction(city: Dictionary) -> int:
	var staffing: int = mini(A.S, A.mul(city.population, A.S, b.city.municipal_jobs))
	var p: Dictionary = city.power
	var powered: int = A.mul(p.municipal_delivered_micro_E, A.S, p.municipal_requested_micro_E) if p.municipal_requested_micro_E > 0 else A.S
	return A.mul(staffing, powered)

static func validate_power(city: Dictionary) -> String:
	var p: Dictionary = city.power
	for value in p.values():
		if typeof(value) != TYPE_INT or value < 0:
			return "invalid_power_record"
	if p.municipal_delivered_micro_E > p.municipal_requested_micro_E or p.buildings_delivered_micro_E > p.buildings_requested_micro_E:
		return "power_overallocation"
	if p.exports_micro_E > own_generation(city):
		return "exports_exceed_own_generation"
	if own_generation(city) + p.imports_micro_E != p.municipal_delivered_micro_E + p.buildings_delivered_micro_E + p.exports_micro_E + p.unused_micro_E:
		return "power_conservation"
	return ""
