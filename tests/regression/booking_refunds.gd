extends SceneTree
const Sim=preload("res://simulation/match.gd")
const Cases=preload("res://tests/support/market_cases.gd")
const F=preload("res://simulation/systems/finance.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL booking refunds: "+label)
func fixture(kind: String,delivered: bool):
	var sim=Sim.new();check(sim.initialize("booking-refund",42,Cases.FOUNDATIONS)=="","initialize")
	if kind=="organic":
		var c: Dictionary=sim._state.cities[1]
		c.buildings.append(sim._buildings.record(c.next_building_id,"biogas_facility",1,1,0,true));c.next_building_id+=1
	if kind=="electricity":
		var c: Dictionary=sim._state.cities[0]
		c.buildings.append(sim._buildings.record(c.next_building_id,"factory",0,1,0,true));c.next_building_id+=1
	var seller: int=2 if kind=="electricity" else 1
	sim._economy.market.book(sim._state,0,{"seller":seller,"type":kind,"rate":100000000 if kind=="electricity" else 10000000,"price":sim._balance.market.prices[kind].standard})
	if delivered:
		check(sim.step().status=="advanced","delivery step")
		check(sim.snapshot().contracts[0].delivered>0,"real service before cancellation")
	return sim
func refunds() -> void:
	for kind in ["electricity","recyclable","organic"]:
		for delivered in [false,true]:
			for party in ["buyer","seller"]:
				var sim=fixture(kind,delivered)
				var before: Dictionary=sim.snapshot();var k: Dictionary=before.contracts[0]
				check(before.cities[k.seller].finance.reserved["refund:0"].amount==k.booking_micro,"liability retained after any delivery")
				Cases.command(sim,k[party],"cancel_contract",{"id":0})
				check(sim.step().status=="advanced","cancellation advances")
				var after: Dictionary=sim.snapshot();var closed: Dictionary=after.contracts[0]
				check(closed.booking_refunded==(party=="seller"),"refund by actor")
				check(closed.paid==k.paid and closed.delivered==k.delivered,"completed service immutable")
				var rows: Array=after.market.ledger.filter(func(r):return r.kind=="booking_refund")
				check(rows.size()==(1 if party=="seller" else 0),"at most one refund")
				if party=="seller":
					check(rows[0].amount==k.booking_micro and rows[0].payer==k.seller and rows[0].recipient==k.buyer,"original amount and direction")
					check(after.cities[k.buyer].finance.totals.contract_income-before.cities[k.buyer].finance.totals.contract_income==k.booking_micro,"buyer credited exactly")
					check(after.cities[k.seller].finance.totals.contract_payments-before.cities[k.seller].finance.totals.contract_payments==k.booking_micro,"seller debited exactly")
				check(after.cities[k.seller].finance.reserved.is_empty(),"hold released at close")
				Cases.command(sim,k[party],"cancel_contract",{"id":0})
				check(sim.step().commands[0].status=="contract_unavailable","repeat rejected")
				check(sim.snapshot().market.ledger==after.market.ledger,"repeat creates no transfer")
		# Spend every unreserved micro-credit: the original fee still funds the refund.
		var sim=fixture(kind,true);var k: Dictionary=sim._state.contracts[0]
		var seller: Dictionary=sim._state.cities[k.seller]
		check(F.debit(seller,F.available(seller),"building_upkeep"),"spend available cash fixture")
		check(F.available(seller)==0 and seller.money_micro==k.booking_micro,"only refund liability remains")
		check(not F.debit(seller,1,"building_upkeep"),"cannot spend held fee")
		Cases.command(sim,k.seller,"cancel_contract",{"id":0})
		check(sim.step().status=="advanced" and sim.snapshot().contracts[0].booking_refunded,"refund with zero free liquidity")
		check(sim.snapshot().cities.all(func(c):return c.money_micro>=0),"nonnegative balances")
func edges() -> void:
	for party in ["buyer","seller"]:
		var sim=fixture("recyclable",true);var k: Dictionary=sim._state.contracts[0]
		k.end_tick=sim._state.tick+1
		Cases.command(sim,k.buyer,"renew_contract",{"id":0},0)
		Cases.command(sim,k.seller,"renew_contract",{"id":0},0)
		Cases.command(sim,k[party],"cancel_contract",{"id":0},1)
		check(sim.step().status=="advanced","renewal/last interval conflict")
		check(sim.snapshot().contracts[0].status=="cancelled" and sim.snapshot().contracts[0].booking_refunded==(party=="seller"),"cancellation precedes expiry and renewal")
		sim.step();check(sim.snapshot().contracts.size()==1,"cancelled consent cannot renew")
	var sim=fixture("recyclable",true);sim._state.contracts[0].end_tick=2
	check(sim.step().status=="advanced","natural expiry")
	check(sim.snapshot().contracts[0].status=="expired" and not sim.snapshot().contracts[0].booking_refunded,"natural expiry retains fee")
	Cases.command(sim,1,"cancel_contract",{"id":0})
	check(sim.step().commands[0].status=="contract_unavailable","expired refund rejected")
	# Simultaneous participant requests use the ordinary stable player order.
	var a=fixture("recyclable",true);var b=fixture("recyclable",true)
	for current in [a,b]:
		for owner in ([0,1] if current==a else [1,0]):Cases.command(current,owner,"cancel_contract",{"id":0})
		var result: Dictionary=current.step()
		check(result.commands.filter(func(r):return r.status=="applied").size()==1,"one cancellation wins")
		check(not current.snapshot().contracts[0].booking_refunded,"buyer wins canonical tie")
	check(a.serialize()==b.serialize(),"simultaneous arrival reversal stable")
	# Continuous seller inability still refunds once at the existing 15-second boundary.
	sim=fixture("recyclable",false);sim._state.cities[1].buildings[0].enabled=false
	for i in range(15):check(sim.step().status=="advanced","zero-service interval")
	var state: Dictionary=sim.snapshot()
	check(state.contracts[0].status=="zero_delivery" and state.contracts[0].booking_refunded,"zero-delivery refund")
	check(state.market.ledger.filter(func(r):return r.kind=="booking_refund").size()==1,"one auto refund")
	check(state.market.cooldowns["0:1:recyclable"]==105,"existing cooldown retained")
	Cases.command(sim,1,"cancel_contract",{"id":0})
	check(sim.step().commands[0].status=="contract_unavailable","no refund after auto close")
	check(sim.snapshot().market.ledger==state.market.ledger,"no second refund")
	# A fresh natural renewal gets its own fee/hold; cancellation never reverses the old term.
	sim=fixture("recyclable",true);sim._state.contracts[0].end_tick=2
	Cases.command(sim,0,"renew_contract",{"id":0});Cases.command(sim,1,"renew_contract",{"id":0});sim.step();sim.step()
	state=sim.snapshot();check(state.contracts.size()==2,"natural renewal creates fresh term")
	if state.contracts.size()==2:
		Cases.command(sim,1,"cancel_contract",{"id":state.contracts[1].id});sim.step()
		state=sim.snapshot()
		check(not state.contracts[0].booking_refunded and state.contracts[1].booking_refunded,"only renewed booking refunded")
func multiple_liabilities() -> void:
	var sim=fixture("recyclable",true)
	sim._economy.market.book(sim._state,3,{"seller":1,"type":"recyclable","rate":5000000,"price":1000000})
	var seller: Dictionary=sim._state.cities[1]
	check(F.debit(seller,F.available(seller),"building_upkeep"),"spend only free cash with two holds")
	check(seller.money_micro==10000000,"two original booking fees remain held")
	Cases.command(sim,1,"cancel_contract",{"id":0},0)
	Cases.command(sim,1,"cancel_contract",{"id":1},1)
	var result: Dictionary=sim.step()
	check(result.status=="advanced" and result.commands.all(func(r):return r.status=="applied"),"two funded cancellations in one tick")
	var state: Dictionary=sim.snapshot()
	check(state.contracts.all(func(k):return k.booking_refunded),"both original fees refunded")
	check(state.market.ledger.filter(func(r):return r.kind=="booking_refund").size()==2,"one refund per contract")
	check(state.cities[1].finance.reserved.is_empty() and state.cities[1].money_micro>=0,"no cross-contract liability leak")
func _initialize() -> void:
	refunds();edges();multiple_liabilities()
	print("Booking refunds: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
