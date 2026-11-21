extends SceneTree
const Sim=preload("res://simulation/match.gd")
const Cases=preload("res://tests/support/market_cases.gd")
var checks: int=0
var failures: int=0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL integrity: "+message)
func fixture(kind: String):
	var sim=Sim.new()
	check(sim.initialize("integrity-cancel",42,Cases.FOUNDATIONS)=="","initialize")
	# Trusted fixture bypasses booking eligibility only, never allocation/settlement.
	if kind=="organic":
		var c: Dictionary=sim._state.cities[1]
		c.buildings.append(sim._buildings.record(c.next_building_id,"biogas_facility",1,1,0,true));c.next_building_id+=1
	if kind=="electricity":
		var c: Dictionary=sim._state.cities[0]
		c.buildings.append(sim._buildings.record(c.next_building_id,"factory",0,1,0,true));c.next_building_id+=1
	var seller: int=2 if kind=="electricity" else 1
	sim._economy.market.book(sim._state,0,{"seller":seller,"type":kind,"rate":100000000 if kind=="electricity" else 10000000,"price":sim._balance.market.prices[kind].standard})
	check(sim.step().status=="advanced","first delivery")
	return sim
func cancellation() -> void:
	for kind in ["electricity","recyclable","organic"]:
		for party in ["buyer","seller"]:
			var sim=fixture(kind)
			var before: Dictionary=sim.snapshot()
			var k: Dictionary=before.contracts[0]
			check(k.delivered>0 and (kind!="electricity" or k.delivered<k.rate),"actual partial settlement before cancellation")
			check(Cases.command(sim,k[party],"cancel_contract",{"id":k.id}).status=="queued","cancel admitted")
			check(sim.snapshot().contracts[0].status=="active","not cancelled before tick")
			var result: Dictionary=sim.step()
			check(result.status=="advanced" and result.commands[0].status=="applied","cancel executes "+str(result))
			var after: Dictionary=sim.snapshot()
			check(after.tick==before.tick+1 and after.contracts[0].status=="cancelled","next tick inactive")
			check(after.contracts[0].paid==k.paid and after.contracts[0].delivered==k.delivered,"no new delivery or charge")
			# Seller cancellation refunds the original booking exactly once.
			var expected: Array=before.market.ledger.duplicate(true)
			if party=="seller":expected.append({"tick":after.tick,"contract":k.id,"kind":"booking_refund","payer":k.seller,"recipient":k.buyer,"amount":k.booking_micro})
			check(after.market.ledger==expected,"exact cancellation ledger; no fee or double settlement")
			check(after.market.notifications[-1].participants==[k.buyer,k.seller],"both participants notified")
			check(after.market.notifications[-1].time==after.tick,"notification publication time")
			check(after.cities[k.buyer].incoming_contract_ids.is_empty() and after.cities[k.seller].outgoing_contract_ids.is_empty(),"capacity released")
			check(not after.cities[k.seller].finance.reserved.has("refund:"+str(k.id)),"contingent hold released")
			Cases.command(sim,k[party],"cancel_contract",{"id":k.id});result=sim.step()
			check(result.commands[0].status=="contract_unavailable","repeat rejected")
	var a=fixture("recyclable");var b=fixture("recyclable")
	for sim in [a,b]:
		var owners: Array=[0,1] if sim==a else [1,0]
		for owner in owners:Cases.command(sim,owner,"cancel_contract",{"id":0})
		var result: Dictionary=sim.step()
		check(result.commands.filter(func(row):return row.status=="applied").size()==1,"simultaneous cancel once")
	check(a.serialize()==b.serialize(),"arrival order does not affect cancel replay")
	var sim=fixture("recyclable")
	for payload in [{"id":true},{"id":"0"},{"id":0,"extra":1},{"id":-1}]:
		Cases.command(sim,0,"cancel_contract",payload);var result: Dictionary=sim.step()
		check(result.commands[0].status in ["invalid_payload","contract_unavailable"],"malformed cancel rejected")
	Cases.command(sim,3,"cancel_contract",{"id":0});check(sim.step().commands[0].status=="contract_not_owned","outsider rejected")
	# Expiry and event fixtures preserve the ordinary phase ordering.
	for tick in [389,659,929,1079]:
		sim=fixture("recyclable");sim._state.tick=tick
		sim._state.contracts[0].end_tick=tick+1
		sim._state.market.cooldowns["0:1:organic"]=tick+90
		Cases.command(sim,0,"cancel_contract",{"id":0})
		check(sim.step().status=="advanced","cancel at event/expiry boundary")
		check(sim.snapshot().contracts[0].status=="cancelled","cancel before final possible service")
		check(sim.snapshot().market.cooldowns["0:1:organic"]==tick+90,"existing cooldown preserved")
	sim=fixture("recyclable");sim._state.contracts[0].end_tick=2;sim.step()
	Cases.command(sim,0,"cancel_contract",{"id":0})
	check(sim.step().commands[0].status=="contract_unavailable","already expired cancellation rejected")
func cancellation_edges() -> void:
	var sim=Sim.new();sim.initialize("zero-service-cancel",17,Cases.FOUNDATIONS)
	sim._economy.market.book(sim._state,0,{"seller":1,"type":"recyclable","rate":5000000,"price":1000000})
	Cases.command(sim,0,"renew_contract",{"id":0},0)
	Cases.command(sim,0,"cancel_contract",{"id":0},1)
	var result: Dictionary=sim.step()
	check(result.status=="advanced" and result.commands.all(func(r):return r.status=="applied"),"same-tick renewal then cancel")
	var state: Dictionary=sim.snapshot()
	check(state.contracts[0].delivered==0 and state.contracts[0].paid==0,"cancel before first delivery")
	check(state.contracts[0].renewals.is_empty(),"cancel clears renewal consent")
	check(state.market.notifications.filter(func(n):return n.kind=="contract_cancelled").size()==1,"single cancellation event")
	for i in range(16):check(sim.step().status=="advanced","cancelled contract stays closed")
	check(sim.snapshot().contracts.size()==1 and sim.snapshot().market.ledger.size()==1,"no renewal or late refund after voluntary cancel")
	var protocol=preload("res://simulation/interfaces/local_protocol.gd").new()
	protocol.initialize(17,4,false)
	sim=Sim.new();sim.initialize("closed-preview",17,Cases.FOUNDATIONS)
	sim._state.tick=1199
	check(sim.step().status=="advanced","final tick fixture")
	protocol.session.game.engine=sim;protocol.session.active=0
	check(protocol.dispatch({"op":"preview","kind":"disable","payload":{"building_id":0}}).status=="match_closed","finished preview cannot promise an action")
func insights() -> void:
	var sim=fixture("recyclable")
	var before: Dictionary=sim.snapshot()
	for i in range(80):check(sim.step().status=="advanced","insights progress")
	var canonical: String=sim.serialize()
	var I=preload("res://simulation/projections/insights.gd")
	for owner in range(4):
		var first: Dictionary=I.city(sim.snapshot(),owner,sim._balance,sim._buildings,before)
		check(first==I.city(sim.snapshot(),owner,sim._balance,sim._buildings,before),"deterministic insights")
		check(first.environment.air_micro==sim.snapshot().cities[owner].air_micro,"exact exposure")
		for row in first.conditions:
			check(row.has("measurements") and row.has("relation") and row.has("possible_actions"),"machine readable evidence")
	check(sim.serialize()==canonical,"insights cannot change canonical state or RNG")
	var state: Dictionary=sim.snapshot()
	var c: Dictionary=state.cities[0]
	c.uncollected_micro=[1000000,0,0];c.sorted_micro=[1000000,1000000,0]
	c.electricity.shortage=1;c.capacity.housing=1;c.capacity.services_micro=1
	c.capacity.staffing_micro=500000;c.buildings[0].power_factor_micro=500000
	var rows: Array=I.city(state,0,sim._balance,sim._buildings,before).conditions
	for id in ["collection_overload","recycling_capacity","organic_capacity","electricity_shortage","building_power_constraint","building_staffing_constraint","housing_shortage","services_shortage","industrial_pollution"]:
		check(rows.any(func(r):return r.condition==id),"supported condition "+id)
	c.capacity.realized_jobs_micro=1
	state.transfer_ledger=[{"time":80,"before":[1000,1000,1000,1000],"after":[999,1001,1000,1000],"satisfaction_micro":[70000000,80000000,80000000,80000000]}]
	state.contracts[0].status="active";state.contracts[0].last_delivery=0
	rows=I.city(state,0,sim._balance,sim._buildings,before).conditions
	for id in ["employment_shortage","landfill_pressure","population_decline","contract_under_delivery"]:
		check(rows.any(func(r):return r.condition==id),"supported condition "+id)
	# At a migration publication, score constraints must use the pre-pulse population.
	var pulse: Dictionary=sim.snapshot()
	pulse.tick=80;pulse.cities[3].population=1060
	pulse.transfer_ledger=[{"time":80,"before":[1000,1000,1000,1000],"after":[980,980,980,1060],"satisfaction_micro":[80000000,80000000,80000000,80000000]}]
	pulse.cities[3].capacity.housing=1200;pulse.cities[3].capacity.services_micro=1200000000;pulse.cities[3].capacity.realized_jobs_micro=1000000000
	var projected: Array=I.city(pulse,3,sim._balance,sim._buildings).conditions
	check(not projected.any(func(r):return r.condition in ["housing_shortage","services_shortage","employment_shortage"]),"no false scored shortage immediately after arrivals")
	pulse.tick=81
	projected=I.city(pulse,3,sim._balance,sim._buildings).conditions
	check(projected.any(func(r):return r.condition=="housing_shortage"),"following interval uses current population")
	var old: Dictionary=state.duplicate(true);old.tick-=1;old.cities[0].environment_micro-=1
	check(I.city(state,0,sim._balance,sim._buildings,old).conditions.any(func(r):return r.condition=="environmental_recovery"),"measured recovery")
	old.match_id="another-match"
	check(not I.city(state,0,sim._balance,sim._buildings,old).conditions.any(func(r):return r.condition=="environmental_recovery"),"no trend from another match")
func chains_and_stress() -> void:
	var dirty=Sim.new();var corrected=Sim.new()
	for sim in [dirty,corrected]:check(sim.initialize("insight-chains",17,Cases.FOUNDATIONS)=="","chain init")
	Cases.command(corrected,0,"disable",{"building_id":0})
	for tick in range(120):
		for sim in [dirty,corrected]:check(sim.step().status=="advanced","industrial chain invariants")
	var d: Dictionary=dirty.snapshot().cities[0];var c: Dictionary=corrected.snapshot().cities[0]
	check(c.air_micro<d.air_micro,"stopping actual industrial operation lowers air pressure")
	check(c.mass_ledger_micro.generated<d.mass_ledger_micro.generated,"stopping factory lowers actual waste")
	check(c.environment_micro>d.environment_micro,"environment improves after intervention")
	check(c.satisfaction_components_micro.environment>d.satisfaction_components_micro.environment,"environment affects satisfaction component")
	# Total Satisfaction and migration are intentionally unasserted because disabling industry removes jobs.
	var sim=Sim.new();sim.initialize("extreme-state",43,Cases.FOUNDATIONS)
	var city: Dictionary=sim._state.cities[3]
	city.finance.initial_cash=1;city.money_micro=1
	city.air_micro=40000000;city.landfill_damage_micro=35000000
	city.sorted_micro[2]=1000000000000
	city.mass_ledger_micro.generated=1000000000000
	city.waste_totals.generated_by_source.household[2]=1000000000000
	city.waste_totals.collected=1000000000000
	for tick in range(80):check(sim.step().status=="advanced","extreme stock near-zero cash conserves resources")
	check(sim.snapshot().cities[3].money_micro>1,"municipal income prevents permanent cash softlock")
	check(sim.snapshot().cities.all(func(x):return x.population>=500),"founders protected under extreme pollution")
	# Full grid: trusted completed stock, then normal validated command must reject.
	sim=Sim.new();sim.initialize("full-grid",43,Cases.FOUNDATIONS)
	city=sim._state.cities[3]
	for tile in range(36):
		city.buildings.append(sim._buildings.record(city.next_building_id,"green_space",3,tile,0,true));city.next_building_id+=1
	Cases.command(sim,3,"construct",{"building_type":"factory"})
	var result: Dictionary=sim.step()
	check(result.status=="advanced" and result.commands[0].status!="applied","full grid rejects construction without corruption")
	check(sim.snapshot().cities[3].buildings.size()==36,"no overlapping tile")
func event_defaults() -> void:
	var sim=Sim.new();sim.initialize("event-defaults",17,Cases.FOUNDATIONS)
	var state: Dictionary=sim.snapshot()
	var balance: Dictionary=sim._balance.duplicate(true)
	balance.municipal_generation_E=137
	balance.local_simulation.uncollected_penalty_micro=170000
	Sim.Events.apply(state,[],balance)
	check(state.cities.all(func(c):return c.event_modifiers.municipal_E==137 and c.event_modifiers.uncollected_penalty_micro==170000),"event defaults use supplied balance")
	state.tick=930;Sim.Events.apply(state,state.event_schedule,balance)
	check(state.cities[0].event_modifiers.municipal_E==100,"active event overrides configured default")
	state.tick=1005;Sim.Events.apply(state,state.event_schedule,balance)
	check(state.cities[0].event_modifiers.municipal_E==137,"expiry restores configured default")
func _initialize() -> void:
	cancellation()
	cancellation_edges()
	insights()
	chains_and_stress()
	event_defaults()
	print("Integrity and insights: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
