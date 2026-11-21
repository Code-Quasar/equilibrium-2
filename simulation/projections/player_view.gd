extends RefCounted
## Recursive network allowlist. No mutable engine reference or internal ledger escapes.
const Finance = preload("res://simulation/systems/finance.gd")
const Migration = preload("res://simulation/systems/migration.gd")
static func scalar(value: Variant) -> bool:
	return typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING]

static func pick(source: Dictionary, keys: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in keys:
		if source.has(key) and scalar(source[key]): result[key] = source[key]
	return result

static func integers(source: Variant) -> Array:
	var result: Array = []
	if typeof(source) != TYPE_ARRAY: return result
	for value in source:
		if typeof(value) == TYPE_INT: result.append(value)
	return result

static func strings(source: Variant) -> Array:
	var result: Array = []
	if typeof(source) != TYPE_ARRAY: return result
	for value in source:
		if typeof(value) == TYPE_STRING: result.append(value)
	return result

static func events(source: Dictionary) -> Dictionary:
	return {
		"active":strings(source.get("active",[])),
		"warnings":strings(source.get("warnings",[])),
		"interval_start":source.get("interval_start",0) if typeof(source.get("interval_start"))==TYPE_INT else 0
	}

## What anyone could see looking at a rival city: which buildings stand where,
## at what level, finished or not. Nothing about money, power, staffing,
## projects or whether a building is switched off.
static func skyline(city: Dictionary) -> Array:
	var result: Array = []
	for b in city.get("buildings",[]):
		result.append(pick(b,["type","tile","level","status"]))
	return result

static func project(state: Dictionary, seat: int) -> Dictionary:
	assert(seat >= 0 and seat < 4)
	var rankings: Array = []
	for row in Migration.ranking(state):
		rankings.append(pick(row,["rank","city_id","population","satisfaction_micro","environment_micro","development_micro"]))
	var public: Dictionary = {"match_id":state.match_id,"tick":state.tick,"phase":state.status,"duration_ticks":1200,"foundations":strings(state.foundations),"rankings":rankings,"events":events(state.event_state)}
	var opponents: Array = []
	for c in state.cities:
		if c.city_id != seat:
			var other: Dictionary = pick(c,["city_id","foundation","population","satisfaction_micro","environment_micro","development_micro"])
			other.buildings = skyline(c)
			opponents.append(other)
	var city: Dictionary = state.cities[seat]
	var own: Dictionary = pick(city,["city_id","foundation","population","money_micro","materials_micro","uncollected_micro","sorted_micro","environment_micro","air_micro","effective_air_micro","landfill_damage_micro","overflow_micro","satisfaction_micro","development_micro","reduce_waste","policy_active","policy_change_at","previous_biogas_micro_E","disposed_this_tick"])
	own.uncollected_micro = integers(city.get("uncollected_micro",[]))
	own.sorted_micro = integers(city.get("sorted_micro",[]))
	own.available_money_micro = Finance.available(city)
	own.buildings = []
	for b in city.buildings:
		own.buildings.append(pick(b,["id","type","tile","level","status","created_tick","completed_tick","enabled","funded","operational","power_factor_micro","reactivate_at","money_paid_micro","materials_paid_micro","power_requested_micro_E","power_delivered_micro_E"]))
	own.projects = []
	for p in city.project_slots:
		own.projects.append(null if p == null else pick(p,["building_id","kind","complete_tick","cash_paid","materials_paid"]))
	own.capacity = pick(city.capacity,["housing","services_micro","potential_jobs","realized_jobs_micro","staffing_micro","generation_micro_E","demand_micro_E","power_status","reliability_micro"])
	own.electricity = pick(city.electricity,["supply","demand","delivered","unused","shortage","imports","exports","municipal_requested","municipal_delivered","biogas_available"])
	own.satisfaction_components_micro = pick(city.satisfaction_components_micro,["housing","employment","services","power","environment"])
	own.waste_totals = pick(city.waste_totals,["collected","recycled","organic_processed"])
	own.waste_totals.generated_by_source = {}
	for source in ["household","factory","commerce"]:
		own.waste_totals.generated_by_source[source] = integers(city.waste_totals.get("generated_by_source",{}).get(source,[]))
	own.materials_spent_micro = city.finance.materials_spent
	own.recovered_micro = city.mass_ledger_micro.recovered
	own.disposed_micro = city.mass_ledger_micro.disposed
	own.organic_sink_micro = city.mass_ledger_micro.organic_sink
	own.contracts = []
	var market: Dictionary = {"offers":[],"requests":[],"contracts":[]}
	for o in state.offers:
		if o.status == "open": market.offers.append(pick(o,["id","seller","type","rate","price","status","request_id"]))
	for r in state.market.requests:
		if r.status == "open": market.requests.append(pick(r,["id","buyer","type","rate","status","quote_until","select_until"]))
	for k in state.contracts:
		var terms: Dictionary = pick(k,["id","buyer","seller","type","rate","price","start_tick","end_tick","status"])
		if k.status == "active": market.contracts.append(terms.duplicate(true))
		if seat in [k.buyer,k.seller]:
			terms.merge(pick(k,["delivered","paid","last_delivery","booking_micro","booking_refunded","closed_tick"]))
			terms.renewals = integers(k.get("renewals",[]))
			own.contracts.append(terms)
	var notifications: Array = []
	for n in state.market.notifications:
		for k in state.contracts:
			if k.id == n.contract and seat in [k.buyer,k.seller]:
				notifications.append(pick(n,["time","contract","kind","actor","result"]))
	var final: Variant = null
	if state.final_result != null:
		final = pick(state.final_result,["duration","canonical_sha256"])
		final.winners = integers(state.final_result.get("winners",[]))
		final.rankings = rankings.duplicate(true)
	return {"public":public,"own_city":own,"opponents":opponents,"marketplace":market,"notifications":notifications,"final_result":final}
