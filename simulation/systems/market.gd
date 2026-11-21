extends RefCounted
const A = preload("res://simulation/core/arithmetic.gd")
const F = preload("res://simulation/systems/finance.gd")
const Power = preload("res://simulation/systems/power.gd")
const Waste = preload("res://simulation/systems/waste.gd")
const KINDS = ["publish_offer","withdraw_offer","request_quotes","submit_quote","accept_quote","renew_contract","cancel_contract"]
var b: Dictionary
var catalogue: RefCounted
var waste: RefCounted
func _init(balance: Dictionary, buildings: RefCounted, processor: RefCounted) -> void:
	b=balance;catalogue=buildings;waste=processor
func initialize(state: Dictionary) -> void:
	state["market"]={"next_id":0,"requests":[],"cooldowns":{},"ledger":[],"notifications":[]}
	for c in state.cities:
		c["trade_mass"]={"imports":0,"exports":0}
		c["contract_biogas"]={}
func fresh(state: Dictionary) -> int:
	var id: int=state.market.next_id
	state.market.next_id+=1
	return id
static func find(items: Array, id: int) -> Dictionary:
	for item in items:
		if item.id==id:return item
	return {}
static func live(contract: Dictionary, tick: int) -> bool:
	return contract.status=="active" and tick>=contract.start_tick and tick<contract.end_tick
static func pair(buyer: int,seller: int,kind: String) -> String:
	return "%d:%d:%s"%[buyer,seller,kind]
func reserved(state: Dictionary, owner: int, kind: String, buying: bool=false) -> int:
	var amount: int=0
	for k in state.contracts:
		if live(k,state.tick) and k.type==kind and k["buyer" if buying else "seller"]==owner:amount+=k.rate
	return amount
func forecast(state: Dictionary, owner: int) -> Dictionary:
	var c: Dictionary=state.cities[owner].duplicate(true)
	var available: int=F.available(c)+A.divi(b.economy.municipal_income_micro_per_minute+c.population*b.economy.income_per_resident_micro_per_minute-b.economy.municipal_upkeep_micro_per_minute,60)
	var ordered: Array=c.buildings.duplicate()
	ordered.sort_custom(func(x,y):return x.created_tick<y.created_tick if x.created_tick!=y.created_tick else x.id<y.id)
	var jobs: int=b.base_jobs
	for plant in ordered:
		plant.funded=false
		if plant.status!="complete" or not plant.enabled:continue
		var upkeep: int=A.divi(catalogue.effects(plant).upkeep_micro_per_minute+59,60)
		if available<upkeep:continue
		available-=upkeep;plant.funded=true;jobs+=catalogue.effects(plant).jobs
	c.capacity.staffing_micro=mini(A.S,A.divi(c.population*A.S,jobs))
	var supply: int=c.get("event_modifiers",{}).get("municipal_E",b.municipal_generation_E)*A.S
	for plant in ordered:
		if plant.funded:
			supply+=A.mul(catalogue.effects(plant).generation_micro_E,c.capacity.staffing_micro)
			if plant.type=="biogas_facility":supply+=c.biogas_pending.get(str(plant.id),0)
	c.capacity.generation_micro_E=supply
	var municipal: int=b.municipal_base_demand_E*A.S+b.municipal_demand_per_resident_micro_E*c.population
	Power.allocate(c,catalogue,municipal,0,mini(reserved(state,owner,"electricity"),maxi(0,supply-municipal)))
	var generation: Array=[0,0]
	var processing: Array=[0,0]
	var household: int=b.local_simulation.household_waste_micro_per_resident_minute*c.population
	if c.reduce_waste and available>=A.divi(b.economy.policy_fee_micro_per_minute+59,60):household=A.mul(household,b.local_simulation.policy_household_percent,100)
	household=A.mul(household,c.get("event_modifiers",{}).get("household_percent",100),100)
	for category in range(2):generation[category]=A.mul(household,b.local_simulation["household_"+["R","O"][category]+"_percent"],100)
	for plant in ordered:
		var d: Dictionary=catalogue.effects(plant)
		var efficiency: int=A.efficiency(c,plant)
		if plant.type=="recycling_center":processing[0]+=A.mul(d.recycling_per_minute*A.S,efficiency)
		if plant.type=="biogas_facility":processing[1]+=A.mul(d.treatment_per_minute*A.S,efficiency)
		if d.waste_per_minute>0:
			var source: String="factory" if plant.type=="factory" else "commerce"
			var rate: int=A.mul(d.waste_per_minute*A.S,efficiency)
			if c.reduce_waste and available>=A.divi(b.economy.policy_fee_micro_per_minute+59,60):rate=A.mul(rate,b.local_simulation["policy_"+source+"_percent"],100)
			rate=A.mul(rate,c.get("event_modifiers",{}).get(source+"_percent",100),100)
			for category in range(2):generation[category]+=A.mul(rate,b.local_simulation[source+"_"+["R","O"][category]+"_percent"],100)
	return {"supply":supply,"demand":c.electricity.demand,"generation":generation,"processing":processing}
func spare(state: Dictionary, owner: int, kind: String) -> int:
	var f: Dictionary=forecast(state,owner)
	if kind=="electricity":return maxi(0,f.supply-f.demand-reserved(state,owner,kind))
	var i: int=0 if kind=="recyclable" else 1
	return maxi(0,f.processing[i]-f.generation[i]-state.cities[owner].sorted_micro[i]*60-reserved(state,owner,kind))
func need(state: Dictionary, owner: int, kind: String) -> bool:
	var f: Dictionary=forecast(state,owner)
	if kind=="electricity":return f.demand-f.supply-reserved(state,owner,kind,true)>=b.market.minimum_need_micro
	var i: int=0 if kind=="recyclable" else 1
	return state.cities[owner].sorted_micro[i]>A.divi(f.processing[i],60) or f.generation[i]-f.processing[i]-reserved(state,owner,kind,true)>=b.market.minimum_need_micro
func terms(p: Dictionary) -> String:
	if typeof(p.get("type"))!=TYPE_STRING or not b.market.prices.has(p.type):return "invalid_service"
	if typeof(p.get("rate"))!=TYPE_INT or p.rate<=0 or p.rate>100000000000:return "invalid_rate"
	if typeof(p.get("price"))!=TYPE_INT:return "invalid_price"
	var prices: Dictionary=b.market.prices[p.type]
	if p.price<prices.minimum or p.price>prices.maximum or (p.price-prices.minimum)%prices.step!=0:return "invalid_price"
	return ""
func acceptance(state: Dictionary, buyer: int, offer: Dictionary) -> String:
	var seller: int=offer.seller
	if buyer==seller:return "self_contract"
	if state.tick+b.market.minimum_remaining>b.match_seconds:return "not_enough_time"
	if state.market.cooldowns.get(pair(buyer,seller,offer.type),0)>state.tick:return "contract_cooldown"
	var incoming: int=0;var outgoing: int=0
	for k in state.contracts:
		if not live(k,state.tick):continue
		if k.buyer==buyer:incoming+=1
		if k.seller==seller:outgoing+=1
		if k.buyer==buyer and k.seller==seller and k.type==offer.type:return "duplicate_contract"
	if incoming>=b.market.contract_limit or outgoing>=b.market.contract_limit:return "contract_limit"
	if F.available(state.cities[buyer])<b.market.booking_micro:return "insufficient_funds"
	if not need(state,buyer,offer.type):return "no_eligible_buyer_need"
	if spare(state,seller,offer.type)<offer.rate:return "insufficient_seller_capacity"
	return ""
func validate(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary=command.payload;var kind: String=command.command_type;var owner: int=command.player_id
	if kind in ["publish_offer","submit_quote"]:
		if p.size()!=(4 if kind=="submit_quote" else 3):return "invalid_payload"
		var error: String=terms(p)
		if error!="":return error
		if spare(state,owner,p.type)<p.rate:return "insufficient_seller_capacity"
		if kind=="submit_quote":
			if typeof(p.get("request_id"))!=TYPE_INT:return "invalid_payload"
			var request: Dictionary=find(state.market.requests,p.request_id)
			if request.is_empty() or request.status!="open" or state.tick>=request.quote_until:return "quote_window_closed"
			if request.buyer==owner or request.type!=p.type or p.rate>request.rate:return "invalid_quote"
		return ""
	if kind=="request_quotes":
		if p.size()!=2 or typeof(p.get("type"))!=TYPE_STRING or not b.market.prices.has(p.type) or typeof(p.get("rate"))!=TYPE_INT or p.rate<=0 or p.rate>100000000000:return "invalid_payload"
		return "" if need(state,owner,p.type) else "no_eligible_buyer_need"
	if p.size()!=1 or typeof(p.get("id"))!=TYPE_INT:return "invalid_payload"
	if kind in ["withdraw_offer","accept_quote"]:
		var offer: Dictionary=find(state.offers,p.id)
		if offer.is_empty() or offer.status!="open":return "offer_unavailable"
		if kind=="withdraw_offer":return "" if offer.seller==owner else "offer_not_owned"
		if offer.request_id>=0:
			var request: Dictionary=find(state.market.requests,offer.request_id)
			if request.buyer!=owner:return "request_not_owned"
			if request.status!="open" or state.tick<request.quote_until or state.tick>=request.select_until:return "selection_window_closed"
		return acceptance(state,owner,offer)
	if kind in ["renew_contract","cancel_contract"]:
		var contract: Dictionary=find(state.contracts,p.id)
		if contract.is_empty() or not live(contract,state.tick):return "contract_unavailable"
		if owner not in [contract.buyer,contract.seller]:return "contract_not_owned"
		if kind=="renew_contract" and owner in contract.renewals:return "already_agreed"
		return ""
	return "unsupported_command"
func execute(state: Dictionary, command: Dictionary, _rng: RefCounted) -> String:
	var error: String=validate(state,command)
	if error!="":return error
	var p: Dictionary=command.payload;var kind: String=command.command_type;var owner: int=command.player_id
	if kind in ["publish_offer","submit_quote"]:
		state.offers.append({"id":fresh(state),"seller":owner,"type":p.type,"rate":p.rate,"price":p.price,"status":"open","request_id":p.get("request_id",-1)})
	elif kind=="request_quotes":
		state.market.requests.append({"id":fresh(state),"buyer":owner,"type":p.type,"rate":p.rate,"status":"open","quote_until":state.tick+b.market.quote_seconds,"select_until":state.tick+b.market.quote_seconds+b.market.selection_seconds})
	elif kind=="withdraw_offer":find(state.offers,p.id).status="withdrawn"
	elif kind=="accept_quote":
		var offer: Dictionary=find(state.offers,p.id)
		book(state,owner,offer)
		offer.status="accepted"
		if offer.request_id>=0:find(state.market.requests,offer.request_id).status="accepted"
	elif kind=="renew_contract":find(state.contracts,p.id).renewals.append(owner)
	elif kind=="cancel_contract":
		var contract: Dictionary=find(state.contracts,p.id)
		if owner==contract.seller:
			var refund_error: String=refund_booking(state,contract,state.tick+1)
			if refund_error!="":return refund_error
		close(state,contract,"cancelled",state.tick)
		F.release(state.cities[contract.buyer],"service:"+str(contract.id))
		contract.renewals.clear()
		state.market.notifications.append({"time":state.tick+1,"contract":contract.id,"kind":"contract_cancelled","actor":owner,"participants":[contract.buyer,contract.seller]})
	return ""
func book(state: Dictionary, buyer: int, offer: Dictionary) -> void:
	var id: int=fresh(state)
	var seller: int=offer.seller
	F.debit(state.cities[buyer],b.market.booking_micro,"contract_payments",id)
	F.credit(state.cities[seller],b.market.booking_micro,"contract_income",id)
	# Seller cancellation refunds the original booking once, even after partial service.
	F.reserve(state.cities[seller],"refund:"+str(id),b.market.booking_micro,state.tick)
	state.market.ledger.append({"tick":state.tick,"contract":id,"kind":"booking","payer":buyer,"recipient":seller,"amount":b.market.booking_micro})
	state.contracts.append({"id":id,"buyer":buyer,"seller":seller,"type":offer.type,"rate":offer.rate,"price":offer.price,
		"start_tick":state.tick,"end_tick":mini(state.tick+b.market.duration,b.match_seconds),"status":"active",
		"booking_micro":b.market.booking_micro,"booking_refunded":false,"zero_seconds":0,"refund_eligible":true,"prepaid":0,"rate_carry":0,"delivered":0,"paid":0,"last_delivery":0,"last_valid_request":false,"last_seller_capacity":0,"renewals":[],"warned":false})
	state.cities[buyer].incoming_contract_ids.append(id)
	state.cities[seller].outgoing_contract_ids.append(id)
func reserve_cash(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for k in state.contracts:
		if not live(k,state.tick):continue
		k.last_delivery=0;k.last_valid_request=false;k.last_seller_capacity=0
		var denominator: int=60*A.S
		var charge: int=A.divi(k.rate*k.price+denominator-1,denominator)
		if k.type!="electricity":charge=A.divi(A.divi(k.rate+59,60)*k.price+A.S-1,A.S)
		F.reserve(state.cities[k.buyer],"service:"+str(k.id),mini(charge,F.available(state.cities[k.buyer])),state.tick)
	return ""
func affordable(state: Dictionary,k: Dictionary,denominator: int) -> int:
	var amount: int=state.cities[k.buyer].finance.reserved.get("service:"+str(k.id),{"amount":0}).amount
	return A.divi(amount*denominator+k.prepaid,k.price)
func pay(state: Dictionary,k: Dictionary,quantity: int,denominator: int) -> String:
	if quantity<=0:return ""
	var numerator: int=quantity*k.price-k.prepaid
	var charge: int=A.divi(numerator+denominator-1,denominator)
	if not F.consume_reserved(state.cities[k.buyer],"service:"+str(k.id),charge):return "contract_payment_failed"
	F.credit(state.cities[k.seller],charge,"contract_income",k.id)
	k.prepaid=charge*denominator-numerator;k.paid+=charge;k.delivered+=quantity;k.last_delivery+=quantity
	state.market.ledger.append({"tick":state.tick,"contract":k.id,"kind":k.type,"payer":k.buyer,"recipient":k.seller,"quantity":quantity,"amount":charge})
	return ""
func power(state: Dictionary) -> String:
	var imports: Array=[0,0,0,0];var exports: Array=[0,0,0,0]
	for k in state.contracts:
		if not live(k,state.tick) or k.type!="electricity":continue
		var buyer: Dictionary=state.cities[k.buyer];var seller: Dictionary=state.cities[k.seller]
		var domestic: int=b.municipal_base_demand_E*A.S+b.municipal_demand_per_resident_micro_E*seller.population
		var available: int=maxi(0,seller.capacity.generation_micro_E-domestic-exports[k.seller])
		var deficit: int=maxi(0,buyer.capacity.demand_micro_E-buyer.capacity.generation_micro_E+exports[k.buyer]-imports[k.buyer])
		var funds: int=affordable(state,k,60*A.S)
		k.last_valid_request=deficit>0 and funds>0;k.last_seller_capacity=available
		var quantity: int=mini(k.rate,mini(available,mini(deficit,funds)))
		var error: String=pay(state,k,quantity,60*A.S)
		if error!="":return error
		imports[k.buyer]+=quantity;exports[k.seller]+=quantity
	for c in state.cities:
		Power.allocate(c,catalogue,b.municipal_base_demand_E*A.S+b.municipal_demand_per_resident_micro_E*c.population,imports[c.city_id],exports[c.city_id])
		waste.prepare(c)
	return ""
func processing_capacity(city: Dictionary,organic: bool) -> int:
	var amount: int=0
	for plant in Waste.ordered(city):
		if plant.type==("biogas_facility" if organic else "recycling_center"):amount+=city.processing_budgets.get(str(plant.id),{"remaining":0}).remaining
	return amount
func process_contracts(state: Dictionary,_ctx: Dictionary,_rng: RefCounted) -> String:
	for k in state.contracts:
		if not live(k,state.tick) or k.type=="electricity":continue
		var buyer: Dictionary=state.cities[k.buyer];var seller: Dictionary=state.cities[k.seller]
		var organic: bool=k.type=="organic";var category: int=1 if organic else 0
		var surplus: int=maxi(0,buyer.sorted_micro[category]-processing_capacity(buyer,organic))
		var available: int=processing_capacity(seller,organic)
		var funds: int=affordable(state,k,A.S)
		k.last_valid_request=surplus>0 and funds>0;k.last_seller_capacity=available
		var numerator: int=k.rate+k.rate_carry
		var capacity: int=A.divi(numerator,60);k.rate_carry=numerator%60
		var quantity: int=mini(capacity,mini(surplus,mini(available,funds)))
		var error: String=pay(state,k,quantity,A.S)
		if error!="":return error
		buyer.sorted_micro[category]-=quantity;buyer.trade_mass.exports+=quantity;seller.trade_mass.imports+=quantity
		var left: int=quantity
		for plant in Waste.ordered(seller):
			if plant.type!=("biogas_facility" if organic else "recycling_center"):continue
			var converted: Dictionary=waste.process(seller,plant,left,organic)
			left-=converted.input;seller.sorted_micro[2]+=converted.rejects
			if organic:
				seller.mass_ledger_micro.organic_sink+=converted.output;seller.waste_totals.organic_processed+=converted.input
				seller.contract_biogas[str(plant.id)]=seller.contract_biogas.get(str(plant.id),0)+converted.input*60*b.local_simulation.biogas_E_per_unit_minute
			else:
				seller.materials_micro+=converted.output;seller.mass_ledger_micro.recovered+=converted.output;seller.waste_totals.recycled+=converted.input
		if left!=0:return "unprocessed_import"
	return ""
func refund_booking(state: Dictionary,k: Dictionary,time: int) -> String:
	if k.booking_refunded:return "booking_already_refunded"
	var seller: Dictionary=state.cities[k.seller]
	var hold: String="refund:"+str(k.id)
	if seller.finance.reserved.get(hold,{}).get("amount",-1)!=k.booking_micro:return "refund_liability_unfunded"
	F.release(seller,hold)
	if not F.debit(seller,k.booking_micro,"contract_payments",k.id):return "refund_liability_unfunded"
	F.credit(state.cities[k.buyer],k.booking_micro,"contract_income",k.id)
	k.booking_refunded=true
	state.market.ledger.append({"tick":time,"contract":k.id,"kind":"booking_refund","payer":k.seller,"recipient":k.buyer,"amount":k.booking_micro})
	return ""
func close(state: Dictionary,k: Dictionary,status: String,time: int) -> void:
	k.status=status;k["closed_tick"]=time
	state.cities[k.buyer].incoming_contract_ids.erase(k.id)
	state.cities[k.seller].outgoing_contract_ids.erase(k.id)
	F.release(state.cities[k.seller],"refund:"+str(k.id))
func expiry(state: Dictionary,ctx: Dictionary,_rng: RefCounted) -> String:
	var renew: Array=[]
	for k in state.contracts:
		if k.status!="active":continue
		if k.last_delivery==0:k.zero_seconds+=1
		else:k.zero_seconds=0
		k.refund_eligible=k.refund_eligible and k.last_valid_request and k.last_seller_capacity==0 and k.last_delivery==0
		if k.zero_seconds>=b.market.zero_seconds:
			if k.refund_eligible:
				var error: String=refund_booking(state,k,ctx.end_tick)
				if error!="":return error
			close(state,k,"zero_delivery",ctx.end_tick)
			state.market.cooldowns[pair(k.buyer,k.seller,k.type)]=ctx.end_tick+b.market.cooldown
		elif ctx.end_tick>=k.end_tick:
			close(state,k,"expired",ctx.end_tick)
			if k.renewals.size()==2:renew.append(k.id)
		elif ctx.end_tick>=k.end_tick-b.market.expiry_warning and not k.warned:
			k.warned=true;state.market.notifications.append({"time":ctx.end_tick,"contract":k.id,"kind":"expiry_warning"})
	for id in renew:state.market.notifications.append({"time":ctx.end_tick,"contract":id,"kind":"renewal_due"})
	for request in state.market.requests:
		if request.status=="open" and ctx.end_tick>=request.select_until:request.status="expired"
	return ""
func renew_due(state: Dictionary,_ctx: Dictionary,_rng: RefCounted) -> String:
	for note in state.market.notifications:
		if note.kind!="renewal_due" or note.time!=state.tick:continue
		var old: Dictionary=find(state.contracts,note.contract)
		var error: String=acceptance(state,old.buyer,old)
		if error=="":book(state,old.buyer,old)
		note["result"]="renewed" if error=="" else error
	return ""

func invariant(state: Dictionary) -> String:
	var imports: int=0;var exports: int=0;var credits: int=0;var debits: int=0
	var power_in: int=0;var power_out: int=0
	for c in state.cities:
		imports+=c.trade_mass.imports;exports+=c.trade_mass.exports
		credits+=c.finance.totals.contract_income;debits+=c.finance.totals.contract_payments
		power_in+=c.electricity.imports;power_out+=c.electricity.exports
	if imports!=exports:return "trade_mass_conservation"
	if credits!=debits:return "trade_cash_conservation"
	if power_in!=power_out:return "regional_power_conservation"
	var ids: Array=[];var pairs: Array=[]
	var incoming: Array=[0,0,0,0];var outgoing: Array=[0,0,0,0]
	for k in state.contracts:
		if k.id in ids or k.buyer==k.seller or k.rate<=0:return "contract_identity"
		ids.append(k.id)
		var denominator: int=60*A.S if k.type=="electricity" else A.S
		if k.prepaid<0 or k.prepaid>=denominator or k.paid*denominator!=k.delivered*k.price+k.prepaid:return "usage_charge_conservation"
		var hold: Dictionary=state.cities[k.seller].finance.reserved.get("refund:"+str(k.id),{})
		if typeof(k.get("booking_micro"))!=TYPE_INT or k.booking_micro<0 or typeof(k.get("booking_refunded"))!=TYPE_BOOL:return "booking_state"
		if k.status=="active":
			if k.booking_refunded or hold.get("amount",-1)!=k.booking_micro:return "booking_liability"
		elif not hold.is_empty():return "closed_booking_liability"
		if k.status=="active":
			var key: String=pair(k.buyer,k.seller,k.type)
			if key in pairs:return "duplicate_contract"
			pairs.append(key);incoming[k.buyer]+=1;outgoing[k.seller]+=1
	for i in range(4):
		if incoming[i]>b.market.contract_limit or outgoing[i]>b.market.contract_limit:return "contract_count"
		if incoming[i]!=state.cities[i].incoming_contract_ids.size() or outgoing[i]!=state.cities[i].outgoing_contract_ids.size():return "contract_references"
	return ""
