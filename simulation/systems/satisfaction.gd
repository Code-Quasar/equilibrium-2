extends RefCounted
## Capacities and the single Satisfaction score used by migration:
##   35 * Environment/100 + 20 * min(1, J/P) + 15 * min(1, H/(1.15 P))
##   + 15 * reliability + 15 * min(1, V/(1.15 P)), clamped to 0..100.
## Housing H is also the hard cap on arrivals.
const A = preload("res://simulation/core/arithmetic.gd")
var b: Dictionary
var catalogue: RefCounted
var operations: RefCounted

func _init(config: Dictionary, buildings: RefCounted, operation: RefCounted) -> void:
	b = config
	catalogue = buildings
	operations = operation

## Phase: operating capacities and Satisfaction from this second's results.
func update(state: Dictionary, _ctx: Dictionary) -> String:
	var w: Dictionary = b.satisfaction
	for city in state.cities:
		var housing: int = 0
		var services: int = A.mul(b.city.services * A.S, operations.municipal_service_fraction(city))
		for building in city.buildings:
			if building.op.funded:
				var t: Dictionary = catalogue.tier(building)
				housing += t.housing
				services += t.services * building.op.fraction_micro
		var employed: int = city.employment.municipal + city.employment.buildings
		city.capacity = {"housing": housing, "services_micro": services, "employed": employed}
		var population: int = maxi(1, city.population)
		var components: Dictionary = {
			"environment": A.mul(w.environment * city.environment_micro, 1, 100),
			"employment": w.employment * mini(A.S, A.mul(employed, A.S, population)),
			"housing": w.housing * mini(A.S, A.mul(housing * A.S, A.S, w.housing_slack * population)),
			"power": w.power * city.power.reliability_micro,
			"services": w.services * mini(A.S, A.mul(services, A.S, w.services_slack * population)),
		}
		city.satisfaction_components_micro = components
		city.satisfaction_micro = clampi(A.total(components.values()), 0, 100 * A.S)
	return ""
