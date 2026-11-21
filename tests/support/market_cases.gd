extends RefCounted
const Sim=preload("res://simulation/match.gd")
const A=preload("res://simulation/core/arithmetic.gd")
const FOUNDATIONS=["industrial_legacy","circular_foundation","energy_pioneer","investment_district"]
static func command(sim,owner: int,kind: String,payload: Dictionary,offset: int=0) -> Dictionary:
	var s: Dictionary=sim.snapshot()
	var seq: int=s.tick*100+offset
	return sim.submit({"match_id":s.match_id,"player_id":owner,"command_seq":seq,"command_id":"%d:%d"%[owner,seq],"command_type":kind,"payload":payload,"server_received_tick":s.tick},owner)
static func run(check: Callable) -> void:
	var sim=Sim.new();check.call(sim.initialize("market-test",42,FOUNDATIONS)=="","market init")
	check.call(sim.step().status=="advanced","market first interval")
	check.call(command(sim,1,"publish_offer",{"type":"recyclable","rate":10000000,"price":1000000}).status=="queued","offer queued")
	var result: Dictionary=sim.step();check.call(result.status=="advanced",str(result))
	check.call(result.commands[0].status=="applied","valid standing offer")
	var offer: int=sim.snapshot().offers[0].id
	command(sim,0,"accept_quote",{"id":offer})
	result=sim.step();check.call(result.status=="advanced" and result.commands[0].status=="applied","accept treatment "+str(result))
	if result.status!="advanced" or result.commands[0].status!="applied":return
	for tick in range(20):
		result=sim.step();check.call(result.status=="advanced","treatment accounting "+str(result))
		if result.status!="advanced":return
	var state: Dictionary=sim.snapshot()
	check.call(state.contracts[0].delivered>0 and state.contracts[0].paid>0,"real recyclable settlement")
	check.call(state.cities[0].trade_mass.exports==state.cities[1].trade_mass.imports,"import/export mass")
	check.call(state.cities[1].mass_ledger_micro.recovered>0,"seller recovery")
	command(sim,0,"accept_quote",{"id":offer});result=sim.step()
	check.call(result.commands[0].status=="offer_unavailable","duplicate acceptance")
	for price in [599999,650000,1600001,0,-1]:
		command(sim,1,"publish_offer",{"type":"recyclable","rate":1000000,"price":price});result=sim.step()
		check.call(result.commands[0].status=="invalid_price","invalid price")
	command(sim,0,"construct",{"building_type":"recycling_center"});sim.step()
	for tick in range(35):sim.step()
	command(sim,2,"publish_offer",{"type":"electricity","rate":20000000,"price":300000});result=sim.step()
	check.call(result.commands[0].status=="applied","power offer")
	var power_offer: int=sim.snapshot().offers[-1].id
	command(sim,0,"accept_quote",{"id":power_offer});result=sim.step()
	check.call(result.status=="advanced" and result.commands[0].status=="applied","power accept "+str(result))
	state=sim.snapshot()
	check.call(state.cities[0].electricity.imports>0 and state.cities[2].electricity.exports>0,"actual power delivery")
	for tick in range(120):
		result=sim.step();check.call(result.status=="advanced","contract expiry accounting "+str(result))
		if result.status!="advanced":return
	check.call(sim.snapshot().contracts.all(func(k):return k.status!="active"),"contracts close")

static func adversarial(check: Callable) -> void:
	var sim=Sim.new();sim.initialize("refund",42,FOUNDATIONS);sim.step()
	command(sim,1,"publish_offer",{"type":"recyclable","rate":10000000,"price":1000000});sim.step()
	var id: int=sim.snapshot().offers[0].id
	command(sim,0,"accept_quote",{"id":id});command(sim,1,"disable",{"building_id":0})
	var result: Dictionary=sim.step()
	check.call(result.status=="advanced" and result.commands.all(func(r):return r.status=="applied"),"accept then disable canonical order")
	for i in range(14):
		result=sim.step();check.call(result.status=="advanced","refund tick "+str(result))
	var state: Dictionary=sim.snapshot()
	check.call(state.contracts[0].status=="zero_delivery" and state.contracts[0].refund_eligible,"continuous seller failure")
	check.call(state.market.ledger.any(func(row):return row.kind=="booking_refund"),"booking refund")
	check.call(state.market.cooldowns.values()[0]==state.tick+90,"90 second cooldown")
	check.call(state.cities[1].finance.reserved.is_empty(),"liability released")
	# Quote window checks operate on authoritative commands and simulation time.
	sim=Sim.new();sim.initialize("quotes",42,FOUNDATIONS);sim.step()
	command(sim,0,"request_quotes",{"type":"recyclable","rate":10000000});result=sim.step()
	check.call(result.commands[0].status=="applied","request quotes")
	var request: int=sim.snapshot().market.requests[0].id
	command(sim,1,"submit_quote",{"request_id":request,"type":"recyclable","rate":10000000,"price":1000000});result=sim.step()
	check.call(result.commands[0].status=="applied","submit quote")
	id=sim.snapshot().offers[0].id
	command(sim,0,"accept_quote",{"id":id});result=sim.step()
	check.call(result.commands[0].status=="selection_window_closed","early selection rejected")
	while sim.snapshot().tick<11:sim.step()
	command(sim,1,"submit_quote",{"request_id":request,"type":"recyclable","rate":10000000,"price":1000000});result=sim.step()
	check.call(result.commands[0].status=="quote_window_closed","late quote rejected")
	command(sim,0,"accept_quote",{"id":id});result=sim.step()
	check.call(result.commands[0].status=="applied","selection window acceptance")
	var contract_id: int=sim.snapshot().contracts[0].id
	command(sim,0,"renew_contract",{"id":contract_id});command(sim,1,"renew_contract",{"id":contract_id});result=sim.step()
	check.call(result.commands.all(func(r):return r.status=="applied"),"mutual renewal consent")
	while sim.snapshot().tick<104:
		result=sim.step()
		if result.status!="advanced":check.call(false,"renewal progression "+str(result));return
	check.call(sim.snapshot().contracts.size()==2,"fresh renewed contract")

static func organic_and_edges(check: Callable) -> void:
	var sim=Sim.new();sim.initialize("organic-unit",42,FOUNDATIONS)
	# Trusted fixture supplies a completed plant; production requires upkeep, staff, power and waste.
	var c: Dictionary=sim._state.cities[1]
	c.buildings.append(sim._buildings.record(c.next_building_id,"biogas_facility",1,1,0,true));c.next_building_id+=1
	check.call(sim.step().status=="advanced","organic fixture funded")
	command(sim,1,"publish_offer",{"type":"organic","rate":10000000,"price":800000});var result: Dictionary=sim.step()
	check.call(result.commands[0].status=="applied","organic offer")
	command(sim,0,"accept_quote",{"id":sim.snapshot().offers[0].id});result=sim.step()
	check.call(result.status=="advanced" and result.commands[0].status=="applied","organic acceptance")
	var state: Dictionary=sim.snapshot();var seller: Dictionary=state.cities[1]
	check.call(state.contracts[0].delivered>0 and seller.mass_ledger_micro.organic_sink>0,"organic actual conversion")
	check.call(seller.biogas_pending.get("1",0)>0,"imported organic next power")
	check.call(seller.trade_mass.imports==state.cities[0].trade_mass.exports,"organic ownership conservation")
	for type in ["recyclable","organic","electricity"]:
		var bounds: Dictionary=sim._balance.market.prices[type]
		for price in [bounds.minimum,bounds.maximum,bounds.standard]:check.call(sim._economy.market.terms({"type":type,"rate":1000000,"price":price})=="","price endpoint")
		for price in [bounds.minimum-1,bounds.maximum+1,bounds.minimum+1]:check.call(sim._economy.market.terms({"type":type,"rate":1000000,"price":price})=="invalid_price","price invalid step")
	check.call(sim._economy.market.terms({"type":"materials","rate":1000000,"price":1000000})=="invalid_service","no material trading")
	check.call(sim._economy.market.acceptance(state,1,{"seller":1,"type":"organic","rate":1000000,"price":800000})=="self_contract","no self trade")
	state.tick=1181
	check.call(sim._economy.market.acceptance(state,0,{"seller":1,"type":"organic","rate":1000000,"price":800000})=="not_enough_time","late contract forbidden")
	# Two buyers may not accept the same standing offer or reserve the same spare capacity twice.
	sim=Sim.new();sim.initialize("contended",42,FOUNDATIONS);sim.step()
	command(sim,1,"publish_offer",{"type":"recyclable","rate":17000000,"price":1000000});sim.step()
	var id: int=sim.snapshot().offers[0].id
	command(sim,0,"accept_quote",{"id":id});command(sim,3,"accept_quote",{"id":id});result=sim.step()
	check.call(result.commands.filter(func(r):return r.status=="applied").size()==1,"simultaneous acceptance single winner")
	check.call(sim.snapshot().contracts.size()==1,"no duplicate booking")
	# Stop buyer provision while preserving seller availability: booking is retained.
	var k: Dictionary=sim._state.contracts[0]
	var buyer: Dictionary=sim._state.cities[k.buyer]
	buyer.buildings.append(sim._buildings.record(buyer.next_building_id,"recycling_center",buyer.city_id,10,sim._state.tick,true));buyer.next_building_id+=1
	buyer.buildings.append(sim._buildings.record(buyer.next_building_id,"renewable_power_plant",buyer.city_id,11,sim._state.tick,true));buyer.next_building_id+=1
	for i in range(15):
		result=sim.step();check.call(result.status=="advanced","buyer withdrawal accounting")
	check.call(sim.snapshot().contracts[0].status=="zero_delivery","buyer zero release")
	check.call(not sim.snapshot().market.ledger.any(func(row):return row.kind=="booking_refund"),"booking retained after buyer shortage")
