extends RefCounted
## Local IPC v1. Presentation queries never mutate authoritative state or RNG.
const Session=preload("res://simulation/interfaces/local_session.gd")
const Balance=preload("res://simulation/core/balance.gd")
const A=preload("res://simulation/core/arithmetic.gd")
const Insights=preload("res://simulation/projections/insights.gd")
var previous: Dictionary={}
var session=Session.new()
var balance: Dictionary=Balance.load_b1()
func initialize(seed_value: int, humans: int, admin: bool) -> String:
	return session.initialize(seed_value,humans,admin)
func request(raw: Variant) -> Dictionary:
	var result: Dictionary={"status":"invalid_request"}
	var id: Variant=null
	if raw is Dictionary:
		id=raw.get("id")
		if raw.get("v")!=1:result={"status":"unsupported_protocol"}
		elif typeof(id)!=TYPE_INT or id<0 or typeof(raw.get("op"))!=TYPE_STRING:pass
		else:result=dispatch(raw)
	result["v"]=1;result["id"]=id
	return result
func dispatch(p: Dictionary) -> Dictionary:
	match p.op:
		"snapshot":return view()
		"seat":
			if typeof(p.get("seat"))!=TYPE_INT:return {"status":"invalid_seat"}
			var seat: int=p.seat
			if seat<0 or seat>3 or (seat>=session.humans and not session.admin):return {"status":"seat_not_locally_controlled"}
			session.active=seat
			return {"status":"seat_selected","seat":seat}
		"command":
			if session.active<0:return {"status":"select_seat_first"}
			if typeof(p.get("player_id"))!=TYPE_INT or p.player_id!=session.active:return {"status":"unauthorized_player"}
			if typeof(p.get("kind"))!=TYPE_STRING or not p.get("payload") is Dictionary:return {"status":"invalid_command"}
			var result: Dictionary=session.issue(session.active,p.kind,p.payload)
			if session.game.engine==null:session.script_draft()
			return result
		"advance":
			if typeof(p.get("seconds"))!=TYPE_INT:return {"status":"invalid_seconds"}
			previous=session.game.snapshot() if session.game.engine!=null else {}
			return session.advance(p.seconds)
		"preview":
			if session.game.engine==null:return {"status":"draft_in_progress"}
			if session.active<0:return {"status":"select_seat_first"}
			if typeof(p.get("kind"))!=TYPE_STRING or not p.get("payload") is Dictionary:return {"status":"invalid_command"}
			var engine=session.game.engine
			var error: String=engine.preview(session.active,p.kind,p.payload)
			return {"status":"available" if error=="" else error}
		"replay":return {"status":"ok","seed":session.game.draft.seed,"humans":session.humans,"commands":session.replay,"tick":session.game.snapshot().get("tick",0),"canonical_sha256":session.game.engine.serialize().sha256_text() if session.game.engine!=null else ""}
		"quit":return {"status":"quit"}
	return {"status":"unknown_operation"}
func view() -> Dictionary:
	var state: Dictionary=session.game.snapshot()
	var result: Dictionary={"status":"ok","state":state,"draft":session.game.draft,"active":session.active,"humans":session.humans,"admin":session.admin,"balance":balance,"history":session.history,"rankings":[],"next_migration":null,"next_boundary":null,"details":[],"insights":[]}
	if session.game.engine==null:return result
	var engine=session.game.engine
	result.rankings=session.Life.Sim.Migration.ranking(state)
	for tick in range(balance.migration_first_second,balance.match_seconds+1,balance.migration_interval_seconds):
		if tick>state.tick:result.next_migration=tick;break
	var boundaries: Array=[balance.match_seconds]
	if result.next_migration!=null:boundaries.append(result.next_migration)
	for event in state.event_schedule:
		for key in ["warning","start","end"]:
			# Event phase applies on the interval starting at the boundary.
			if event[key]+1>state.tick:boundaries.append(event[key]+1)
	boundaries.sort();result.next_boundary=boundaries[0]
	for city in state.cities:
		var details: Dictionary={"power_sources":{"municipal":city.get("event_modifiers",{}).get("municipal_E",balance.municipal_generation_E)*A.S,"fossil":0,"renewable":0,"biogas":city.previous_biogas_micro_E},"collection_micro_per_minute":balance.collection_units_per_minute*A.S,"landfill_micro_per_minute":balance.landfill_units_per_minute*A.S,"buildings":{},"spare":{},"need":{},"forecast":engine._economy.market.forecast(state,city.city_id)}
		for plant in city.buildings:
			var effects: Dictionary=engine._buildings.effects(plant)
			details.buildings[str(plant.id)]=effects
			if plant.funded and plant.type in ["fossil_power_plant","renewable_power_plant"]:
				details.power_sources["fossil" if plant.type=="fossil_power_plant" else "renewable"]+=A.mul(effects.generation_micro_E,city.capacity.staffing_micro)
			details.collection_micro_per_minute+=A.mul(effects.collection_per_minute*A.S,A.efficiency(city,plant))
			if plant.type=="landfill":details.landfill_micro_per_minute+=A.mul(effects.treatment_per_minute*A.S,A.efficiency(city,plant))
		for kind in balance.market.prices:
			details.spare[kind]=engine._economy.market.spare(state,city.city_id,kind)
			details.need[kind]=engine._economy.market.need(state,city.city_id,kind)
		result.details.append(details)
		result.insights.append(Insights.city(state,city.city_id,balance,engine._buildings,previous))
	return result
