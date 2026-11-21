extends RefCounted
const A = preload("res://simulation/core/arithmetic.gd")
var b: Dictionary
var catalogue: RefCounted
func _init(balance: Dictionary, buildings: RefCounted) -> void:
	b = balance
	catalogue = buildings

func update(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	var r: Dictionary = b.local_simulation
	for city in state.cities:
		var air_change: int = -A.rate(city, "natural_air", r.air_recovery_micro_per_minute)
		for building in city.buildings:
			var rate: int = catalogue.effects(building).air_micro_per_minute
			var delta: int = A.rate(city, "air:" + str(building.id), absi(rate), A.efficiency(city, building))
			air_change += delta if rate >= 0 else -delta
		city.air_micro = clampi(city.air_micro + air_change, 0, r.air_max_micro)
		var landfill_change: int = A.carried(city, "landfill_damage", city.disposed_this_tick, r.landfill_damage_per_unit_micro, A.S)
		landfill_change -= A.rate(city, "natural_landfill", r.landfill_recovery_micro_per_minute)
		city.landfill_damage_micro = clampi(city.landfill_damage_micro + landfill_change, 0, r.landfill_max_micro)
		var overflow: int = A.mul(A.total(city.uncollected_micro), city.get("event_modifiers", {}).get("uncollected_penalty_micro", r.uncollected_penalty_micro))
		overflow += A.mul(A.total(city.sorted_micro), r.sorted_penalty_micro)
		city["overflow_micro"] = mini(r.overflow_max_micro, overflow)
		# Keep event-adjusted air contribution distinct from the persistent stock.
		city["effective_air_micro"] = A.mul(city.air_micro, city.get("event_modifiers", {}).get("air_percent", 100), 100)
		city.environment_micro = clampi(100 * A.S - city.effective_air_micro - city.landfill_damage_micro - city.overflow_micro, 0, 100 * A.S)
		city.environment_status = "evaluated"
	return ""

static func satisfaction(city: Dictionary, weights: Dictionary) -> void:
	var denominator: int = maxi(1, city.population) * weights.capacity_requirement_percent
	var c: Dictionary = {
		"environment": A.divi(weights.environment_points * city.environment_micro, 100),
		"employment": A.divi(weights.employment_points * city.capacity.realized_jobs_micro, maxi(1, city.population)),
		"housing": A.divi(weights.housing_points * mini(denominator * A.S, city.capacity.housing * 100 * A.S), denominator),
		"services": A.divi(weights.services_points * mini(denominator * A.S, city.capacity.services_micro * 100), denominator),
		"power": A.mul(weights.power_points * A.S, city.electricity.delivered, city.electricity.demand) if city.electricity.demand > 0 else weights.power_points * A.S}
	city.satisfaction_components_micro = c
	city.satisfaction_micro = clampi(A.total(c.values()), 0, 100 * A.S)
