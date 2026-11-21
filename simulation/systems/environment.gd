extends RefCounted
## Environment = clamp(100 - air - landfill damage - untreated pressure + min(cap, park amenity), 0, 100).
## Air and landfill damage are persistent stocks; pressure is recomputed from the waste
## physically present this second. Parks clean air only and cannot offset landfill
## damage or street waste.
const A = preload("res://simulation/core/arithmetic.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
var b: Dictionary
var catalogue: RefCounted

func _init(config: Dictionary, buildings: RefCounted) -> void:
	b = config
	catalogue = buildings

## Phase: update stocks from this second's emissions, cleanup and disposal.
func update(state: Dictionary, _ctx: Dictionary) -> String:
	var e: Dictionary = b.environment
	for city in state.cities:
		var emitted: int = 0
		var cleanup: int = A.per_tick(city.carries, "air_decay", A.mul(e.air_decay, state.crisis.effects.air_decay))
		var amenity: int = 0
		for building in city.buildings:
			emitted += building.op.emitted_micro
			if building.type == "park" and building.op.funded:
				var t: Dictionary = catalogue.tier(building)
				cleanup += A.per_tick(building.carries, "cleanup", t.cleanup, building.op.fraction_micro)
				amenity += A.mul(t.amenity, building.op.fraction_micro)
		city.air_micro = clampi(city.air_micro + emitted - cleanup, 0, e.air_cap)
		var damage: int = A.carried(city.carries, "landfill_damage", city.waste.tick.landfilled, e.landfill_damage, A.S)
		city.landfill_damage_micro = mini(city.landfill_damage_micro + damage, e.landfill_cap)
		var stored: int = A.total(city.sorted_micro) + city.disposal_micro
		city.pressure_micro = mini(e.pressure_cap, A.mul(A.total(city.street_micro), e.pressure_street)
			+ A.mul(A.total(city.mixed_micro), e.pressure_mixed) + A.mul(stored, e.pressure_stored))
		city.amenity_micro = mini(amenity, e.amenity_cap)
		city.environment_micro = clampi(100 * A.S - city.air_micro - city.landfill_damage_micro - city.pressure_micro + city.amenity_micro, 0, 100 * A.S)
	return ""

func validate_city(city: Dictionary) -> String:
	var e: Dictionary = b.environment
	if city.air_micro < 0 or city.air_micro > e.air_cap or city.landfill_damage_micro < 0 or city.landfill_damage_micro > e.landfill_cap:
		return "environment_stock_bounds"
	if city.pressure_micro < 0 or city.pressure_micro > e.pressure_cap or city.amenity_micro < 0 or city.amenity_micro > e.amenity_cap:
		return "environment_term_bounds"
	if city.environment_micro < 0 or city.environment_micro > 100 * A.S:
		return "score_bounds"
	return ""
