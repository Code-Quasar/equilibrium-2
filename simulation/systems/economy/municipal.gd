extends RefCounted
const Finance = preload("res://simulation/systems/finance.gd")
const Fixed = preload("res://simulation/core/fixed_point.gd")
const SCALE: int = 1000000
var balance: Dictionary
var catalogue: RefCounted

func _init(config: Dictionary, buildings: RefCounted) -> void:
	balance = config.duplicate(true)
	catalogue = buildings

static func divi(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	var result: int = numerator / denominator
	return result

func initialize_city(city: Dictionary) -> void:
	Finance.initialize(city)
	city["policy_change_at"] = 0
	city["policy_active"] = false
	city["policy_failures"] = 0
	city["development_micro"] = 0
	city["environment_status"] = "initial_stocks_pending_evaluation"
	city["score_evaluated_tick"] = null
	city["satisfaction_components_micro"] = {}
	city["preview_neutral_satisfaction_micro"] = balance.neutral_satisfaction_micro
	city["capacity"] = {"housing": balance.housing, "services_micro": balance.service_capacity * SCALE,
		"potential_jobs": balance.base_jobs, "realized_jobs_micro": balance.base_jobs * SCALE,
		"staffing_micro": SCALE, "generation_micro_E": balance.municipal_generation_E * SCALE,
		"demand_micro_E": city.baseline.demand_micro_E, "power_status": "unevaluated"}
	city["peaks"] = {"housing": balance.housing, "services_micro": balance.service_capacity * SCALE,
		"jobs_micro": balance.base_jobs * SCALE, "generation_micro_E": balance.municipal_generation_E * SCALE}
	city["operation_totals"] = {"eligible_ticks": 0, "funded_ticks": 0, "operational_ticks": 0,
		"productive_ticks": 0, "funding_failures": 0, "power_pending_ticks": 0}

func municipal(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var income: int = balance.economy.municipal_income_micro_per_minute + city.population * balance.economy.income_per_resident_micro_per_minute
		Finance.rate(city, "municipal_income", income, "municipal_income", true)
		if not Finance.rate(city, "municipal_upkeep", balance.economy.municipal_upkeep_micro_per_minute, "municipal_upkeep", false):
			return "mandatory_upkeep_unfunded"
	return ""

func fund(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var ordered: Array = city.buildings.duplicate()
		ordered.sort_custom(func(a, b): return a.created_tick < b.created_tick if a.created_tick != b.created_tick else a.id < b.id)
		for building in ordered:
			if building.status != "complete" or not building.enabled:
				continue
			building.eligible_ticks += 1
			city.operation_totals.eligible_ticks += 1
			var amount: Dictionary = Fixed.per_second(catalogue.effects(building).upkeep_micro_per_minute, building.upkeep_carry)
			if Finance.debit(city, amount.amount, "building_upkeep", building.id):
				building.upkeep_carry = amount.carry
				building.funded = true
				building.funded_ticks += 1
				city.operation_totals.funded_ticks += 1
			else:
				building.funding_failures += 1
				city.operation_totals.funding_failures += 1
		city["policy_active"] = false
		if city.reduce_waste:
			city["policy_active"] = Finance.rate(city, "policy_fee", balance.economy.policy_fee_micro_per_minute, "policy", false)
			if not city.policy_active:
				city.policy_failures += 1
	return ""

func workforce(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var jobs: int = balance.base_jobs
		for building in city.buildings:
			if building.funded:
				jobs += catalogue.effects(building).jobs
		var staffing: int = mini(SCALE, divi(city.population * SCALE, maxi(1, jobs)))
		var supply: int = city.get("event_modifiers", {}).get("municipal_E", balance.municipal_generation_E) * SCALE
		var demand: int = balance.municipal_base_demand_E * SCALE + balance.municipal_demand_per_resident_micro_E * city.population
		for building in city.buildings:
			if building.funded:
				var d: Dictionary = catalogue.effects(building)
				supply += divi(d.generation_micro_E * staffing, SCALE)
				# Round requested power upward, supply downward: sufficiency cannot overpromise.
				demand += divi(d.demand_micro_E * staffing + SCALE - 1, SCALE)
		city.capacity["potential_jobs"] = jobs
		city.capacity["staffing_micro"] = staffing
		city.capacity["generation_micro_E"] = supply
		city.capacity["demand_micro_E"] = demand
	return ""

func power_dependency(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var sufficient: bool = city.capacity.generation_micro_E >= city.capacity.demand_micro_E
		city.capacity["power_status"] = "all_loads_supplied" if sufficient else "awaiting_detailed_allocation"
		if not sufficient:
			city.operation_totals.power_pending_ticks += 1
		for building in city.buildings:
			if not building.funded:
				continue
			var d: Dictionary = catalogue.effects(building)
			# Powered operation requires proven capacity.
			building.power_factor_micro = SCALE if d.demand_micro_E == 0 or sufficient else null
			building.operational = building.power_factor_micro == SCALE
			if building.operational:
				building.operational_ticks += 1
				city.operation_totals.operational_ticks += 1
	return ""

func production(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		for building in city.buildings:
			if not building.operational:
				continue
			var rate: int = catalogue.effects(building).income_micro_per_minute
			if rate == 0:
				continue
			if city.policy_active:
				var percent: int = balance.economy.policy_factory_income_percent if building.type == "factory" else balance.economy.policy_commerce_income_percent
				# Catalogue validation ensures this is exact for B1 monetary rates.
				rate = divi(rate * percent, 100)
			var numerator: int = rate * city.capacity.staffing_micro + building.income_carry
			var income: int = divi(numerator, 60 * SCALE)
			building.income_carry = numerator % (60 * SCALE)
			Finance.credit(city, income, "building_income", building.id)
			building.productive = true
			building.productive_ticks += 1
			city.operation_totals.productive_ticks += 1
	return ""

func scores(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		var housing: int = balance.housing
		var services: int = balance.service_capacity * SCALE
		var jobs: int = balance.base_jobs * SCALE
		for building in city.buildings:
			if not building.operational:
				continue
			var d: Dictionary = catalogue.effects(building)
			housing += d.housing
			services += d.services * building.power_factor_micro
			jobs += divi(d.jobs * city.capacity.staffing_micro * building.power_factor_micro, SCALE)
		jobs = mini(jobs, city.population * SCALE)
		city.capacity["housing"] = housing
		city.capacity["services_micro"] = services
		city.capacity["realized_jobs_micro"] = jobs
		city.peaks.housing = maxi(city.peaks.housing, housing)
		city.peaks.services_micro = maxi(city.peaks.services_micro, services)
		city.peaks.jobs_micro = maxi(city.peaks.jobs_micro, jobs)
		city.peaks.generation_micro_E = maxi(city.peaks.generation_micro_E, city.capacity.generation_micro_E)
		var dev: Dictionary = balance.development
		var score: int = capability(city.peaks.housing - balance.housing, dev.housing_span, dev.housing_points)
		score += capability(city.peaks.services_micro - balance.service_capacity * SCALE, dev.services_span * SCALE, dev.services_points)
		score += capability(city.peaks.jobs_micro - balance.base_jobs * SCALE, dev.jobs_span * SCALE, dev.jobs_points)
		score += capability(city.peaks.generation_micro_E - balance.municipal_generation_E * SCALE, dev.energy_span_E * SCALE, dev.energy_points)
		# Circular capability only credits mass actually recovered or treated.
		score += capability(city.mass_ledger_micro.recovered + city.mass_ledger_micro.organic_sink, dev.circular_span * SCALE, dev.circular_points)
		city["development_micro"] = maxi(city.development_micro, mini(dev.maximum_points * SCALE, divi(score + 5000, 10000) * 10000))
		var weights: Dictionary = balance.satisfaction
		var denominator: int = city.population * weights.capacity_requirement_percent
		var resolved: bool = city.capacity["power_status"] == "all_loads_supplied"
		city["satisfaction_components_micro"] = {
			"housing": weights.housing_points * mini(SCALE, divi(housing * SCALE * 100, denominator)),
			"employment": divi(weights.employment_points * jobs, city.population) if resolved else null,
			"services": weights.services_points * mini(SCALE, divi(services * 100, denominator)) if resolved else null,
			"power": weights.power_points * SCALE if resolved else null,
			"environment": null}
		city["score_evaluated_tick"] = state.tick + 1
		city["satisfaction_micro"] = null
	return ""

static func capability(excess: int, span: int, points: int) -> int:
	return divi(points * SCALE * clampi(excess, 0, span), span)

func release_reservations(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		# Tick-local holds never leak into the next municipal payment interval.
		for id in city.finance.reserved.keys():
			if not str(id).begins_with("refund:"): city.finance.reserved.erase(id)
	return ""
