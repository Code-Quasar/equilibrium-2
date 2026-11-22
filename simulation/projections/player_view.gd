extends RefCounted
## What one seat may see. Every field is copied from an explicit allowlist, so no
## engine reference, carry, escrow handle or rival's private figure can escape.
const Finance = preload("res://simulation/systems/finance.gd")
const Migration = preload("res://simulation/systems/migration.gd")
const CITY = ["city_id", "foundation", "population", "money_micro", "materials_micro", "street_micro",
	"mixed_micro", "sorted_micro", "disposal_micro", "air_micro", "landfill_damage_micro", "pressure_micro",
	"amenity_micro", "environment_micro", "satisfaction_micro", "biogas_pending_micro_E", "status", "eliminated_tick"]
const BUILDING = ["id", "type", "size", "tile", "status", "enabled", "reactivate_at", "created_tick", "completed_tick"]
const OPERATION = ["funded", "requested_micro_E", "delivered_micro_E", "power_micro", "workers", "staff_micro",
	"fraction_micro", "emitted_micro"]
const PROJECT = ["building_id", "kind", "target_size", "complete_tick", "credits_paid", "materials_paid"]
const OFFER = ["id", "seller", "type", "rate_micro", "price_micro", "created_tick"]
const CONTRACT = ["id", "buyer", "seller", "type", "rate_micro", "price_micro", "start_tick", "end_tick", "status"]
const CONTRACT_DETAIL = ["escrow_micro", "delivered_micro", "paid_micro", "last_delivery_micro", "closed_tick"]
const RANKING = ["rank", "city_id", "eliminated", "population", "satisfaction_micro", "environment_micro"]

static func allowed(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			return value.all(func(item): return typeof(item) == TYPE_INT)
	return false

static func pick(source: Variant, keys: Array) -> Dictionary:
	var result: Dictionary = {}
	if source is Dictionary:
		for key in keys:
			if source.has(key) and allowed(source[key]):
				result[key] = source[key].duplicate() if source[key] is Array else source[key]
	return result

static func picks(source: Variant, keys: Array) -> Array:
	return source.map(func(item): return pick(item, keys)) if source is Array else []

static func scalars(source: Variant) -> Dictionary:
	return pick(source, source.keys() if source is Dictionary else [])

static func strings(source: Variant) -> Array:
	return source.filter(func(item): return typeof(item) == TYPE_STRING) if source is Array else []

## options: the engine's build_options for this seat.
static func project(state: Dictionary, seat: int, options: Dictionary = {}) -> Dictionary:
	assert(seat >= 0 and seat < 4)
	var rankings: Array = picks(Migration.ranking(state), RANKING)
	var crisis: Dictionary = state.get("crisis", {})
	var public: Dictionary = {"match_id": state.match_id, "tick": state.tick, "phase": state.status,
		"duration_ticks": 1200, "foundations": strings(state.foundations), "rankings": rankings,
		"crisis": {"announced": strings(crisis.get("announced")), "active": strings(crisis.get("active"))}}
	var opponents: Array = []
	for c in state.cities:
		if c.city_id != seat:
			var rival: Dictionary = pick(c, ["city_id", "foundation", "population", "satisfaction_micro", "environment_micro", "status", "eliminated_tick"])
			# A rival's skyline is public; its operation, money and projects are not.
			rival.buildings = picks(c.buildings, ["type", "size", "tile", "status"])
			opponents.append(rival)
	var city: Dictionary = state.cities[seat]
	var own: Dictionary = pick(city, CITY)
	own.available_money_micro = Finance.available(city)
	own.satisfaction_components_micro = scalars(city.satisfaction_components_micro)
	own.capacity = scalars(city.capacity)
	own.employment = scalars(city.employment)
	own.power = scalars(city.power)
	own.processing = scalars(city.processing)
	own.finance = {"tick": scalars(city.finance.tick), "totals": scalars(city.finance.totals),
		"unpaid_municipal_upkeep_micro": city.finance.unpaid_municipal_upkeep}
	own.materials = scalars(city.materials)
	own.reserve = {"units_micro": city.reserve.units_micro, "initial_micro": city.reserve.initial_micro,
		"circularity_micro": city.reserve.circularity_micro, "renewable_share_micro": city.reserve.renewable_share_micro,
		"tick": scalars(city.reserve.tick), "totals": scalars(city.reserve.totals)}
	own.waste = {"tick": scalars(city.waste.tick), "totals": scalars(city.waste.totals)}
	own.buildings = []
	for building in city.buildings:
		var row: Dictionary = pick(building, BUILDING)
		row.op = pick(building.op, OPERATION)
		own.buildings.append(row)
	own.projects = city.projects.map(func(p): return null if p == null else pick(p, PROJECT))
	own.build_options = {}
	for kind in options:
		own.build_options[kind] = scalars(options[kind])
	own.contracts = []
	var market: Dictionary = {"offers": picks(state.market.offers, OFFER), "contracts": []}
	for k in state.market.contracts:
		if k.status == "active":
			market.contracts.append(pick(k, CONTRACT))
		if seat in [k.buyer, k.seller]:
			own.contracts.append(pick(k, CONTRACT + CONTRACT_DETAIL))
	var final: Variant = null
	if state.final_result != null:
		final = pick(state.final_result, ["duration", "canonical_sha256"])
		final.winners = state.final_result.winners.filter(func(id): return typeof(id) == TYPE_INT)
		final.rankings = rankings.duplicate(true)
	return {"public": public, "own_city": own, "opponents": opponents, "marketplace": market, "final_result": final}
