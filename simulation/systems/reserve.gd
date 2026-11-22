extends RefCounted
## The natural-resource reserve: a fixed stock per city that only goes down.
## Every second it is drawn by
##   - residents, always, cut by up to max_cut by the city's circularity
##     (materials recovered / waste generated, since the start);
##   - delivered electricity, in the share not made by renewable plants or biogas;
##   - raw materials bought from outside (construction and factories), one for one.
## Renewable power and good recycling slow the decline; nothing reverses it.
## A city whose reserve reaches zero is eliminated: it can no longer act, its
## Satisfaction is zero so residents leave, and it ranks below every survivor.
const A = preload("res://simulation/core/arithmetic.gd")
const Waste = preload("res://simulation/systems/waste.gd")
const PARTS = ["residents", "power", "materials"]
var b: Dictionary
var catalogue: RefCounted

func _init(config: Dictionary, buildings: RefCounted) -> void:
	b = config
	catalogue = buildings

static func initialize(city: Dictionary, amount: int) -> void:
	var parts: Dictionary = {}
	for key in PARTS:
		parts[key] = 0
	city["status"] = "active"
	city["eliminated_tick"] = -1
	city["reserve"] = {"units_micro": amount, "initial_micro": amount, "drawn_micro": 0,
		"purchased_seen_micro": 0, "circularity_micro": 0, "renewable_share_micro": 0,
		"tick": parts, "totals": parts.duplicate()}

static func eliminated(city: Dictionary) -> bool:
	return city.get("status", "active") == "eliminated"

## Recovered over generated waste mass since the start, 0..1.
static func circularity(city: Dictionary) -> int:
	var generated: int = city.waste.totals.generated
	return mini(A.S, A.mul(Waste.recovered(city), A.S, generated)) if generated > 0 else 0

## Share of this second's own generation made by renewable plants and biogas, 0..1.
func renewable_share(city: Dictionary) -> int:
	var own: int = city.power.municipal_micro_E + city.power.plants_micro_E + city.power.biogas_micro_E
	if own <= 0:
		return 0
	var clean: int = city.power.biogas_micro_E
	for building in city.buildings:
		if building.type == "renewable_power_plant" and building.op.funded:
			clean += catalogue.tier(building).generation
	return mini(A.S, A.mul(clean, A.S, own))

## Phase: this second's draw for every active city, then elimination at zero.
func draw(state: Dictionary, ctx: Dictionary) -> String:
	var r: Dictionary = b.reserve
	for city in state.cities:
		var res: Dictionary = city.reserve
		for key in PARTS:
			res.tick[key] = 0
		if eliminated(city):
			continue
		var c: int = circularity(city)
		var share: int = renewable_share(city)
		res.circularity_micro = c
		res.renewable_share_micro = share
		var resident_rate: int = A.mul(city.population * r.per_resident, A.S - A.mul(r.max_cut, c))
		var delivered: int = city.power.municipal_delivered_micro_E + city.power.buildings_delivered_micro_E
		var power_rate: int = A.mul(A.mul(delivered, A.S - share), r.per_power)
		var purchased: int = city.materials.purchased - res.purchased_seen_micro
		res.purchased_seen_micro = city.materials.purchased
		var wanted: Dictionary = {
			"residents": A.per_tick(city.carries, "reserve_residents", resident_rate),
			"power": A.per_tick(city.carries, "reserve_power", power_rate),
			"materials": A.mul(purchased, r.per_material),
		}
		for key in PARTS:
			var taken: int = mini(wanted[key], res.units_micro)
			res.units_micro -= taken
			res.drawn_micro += taken
			res.tick[key] += taken
			res.totals[key] += taken
		if res.units_micro <= 0:
			city.status = "eliminated"
			city.eliminated_tick = ctx.end_tick
	return ""

## Stock equals the opening stock minus everything drawn, and never goes below zero.
static func validate(city: Dictionary) -> String:
	var res: Dictionary = city.get("reserve", {})
	if res.is_empty() or typeof(res.units_micro) != TYPE_INT or res.units_micro < 0:
		return "invalid_reserve"
	if res.units_micro != res.initial_micro - res.drawn_micro or A.total(res.totals.values()) != res.drawn_micro:
		return "reserve_conservation"
	if eliminated(city) != (res.units_micro == 0 and city.eliminated_tick >= 0):
		return "elimination_state"
	return ""
