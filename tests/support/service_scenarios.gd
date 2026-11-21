extends RefCounted
const Session=preload("res://simulation/interfaces/local_session.gd")
const Resources=preload("res://tests/support/resource_scenarios.gd")
const A=preload("res://simulation/core/arithmetic.gd")
const SCENARIOS=["industrial","circular","renewable","commerce","mixed","minimal","electricity_trade","recyclable_trade","organic_trade","competition","local2","local3","local4"]
static func plans(name: String,owner: int) -> Array:
	if name in Resources.PLANS:return Resources.PLANS[name]
	if name in ["electricity_trade","recyclable_trade","organic_trade","competition"]:
		if owner==0:return ["factory","recycling_center" if name=="electricity_trade" else "factory","recovery_hub","commercial_district","residential_district","public_services_center"]
		if owner==1:return Resources.PLANS.mixed
		if owner==2:return ["commercial_district","renewable_power_plant","recycling_center","public_services_center","residential_district","recovery_hub","biogas_facility"]
	return Resources.PLANS.mixed
static func run(name: String,seed_value: int,assignment: int=0,reverse: bool=false) -> Dictionary:
	var session=Session.new()
	var humans: int=int(name.substr(5)) if name.begins_with("local") else 4
	var error: String=session.initialize(seed_value,humans,true)
	if error!="":return {"error":error}
	while session.game.engine==null:
		var owner: int=session.game.draft.order[session.game.draft.turn]
		session.select_seat(owner)
		var card: String=session.game.CARDS[(owner+assignment)%4]
		if card in session.game.draft.choices:
			for candidate in session.game.CARDS:
				if candidate not in session.game.draft.choices:card=candidate;break
		var chosen: Dictionary=session.choose_foundation(card)
		if chosen.status!="applied":return {"error":str(chosen)}
	var sim=session.game.engine
	var snapshots: Array=[];var outcomes: Array=[]
	var stats: Array=[]
	for i in range(4):stats.append({"shortage_ticks":0,"waste_ticks":0,"unused_project_slot_seconds":0})
	var trading: bool=name in ["electricity_trade","recyclable_trade","organic_trade","competition"]
	var admitted: Array=[]
	for tick in range(1200):
		var state: Dictionary=sim.snapshot()
		var commands: Array=[]
		for owner in range(humans):
			var plan: Array=plans(name,owner)
			if tick%90==0 and A.divi(tick,90)<plan.size():commands.append({"owner":owner,"kind":"construct","payload":{"building_type":plan[A.divi(tick,90)]}})
		if trading and tick%30==0:
			var types: Array=(["electricity","recyclable"] if tick<600 else ["electricity","organic"]) if name=="competition" else [name.trim_suffix("_trade")]
			for kind in types:
				for seller in range(4):
					var spare: int=sim._economy.market.spare(state,seller,kind)
					if spare<5000000:continue
					var buyer_found: bool=false
					for buyer in range(4):
						if buyer!=seller and sim._economy.market.need(state,buyer,kind):buyer_found=true
					if buyer_found:
						commands.append({"owner":seller,"kind":"publish_offer","payload":{"type":kind,"rate":mini(10000000,spare),"price":sim._balance.market.prices[kind].standard}})
						break
		if trading and tick%30==1:
			for offer in state.offers:
				if offer.status!="open":continue
				if name=="competition" and offer.type==("organic" if tick<600 else "recyclable"):continue
				for buyer in range(4):
					if sim._economy.market.acceptance(state,buyer,offer)=="":
						commands.append({"owner":buyer,"kind":"accept_quote","payload":{"id":offer.id}});break
		# Assign sequences before reversing transport arrivals.
		var envelopes: Array=[]
		for command in commands:
			var owner: int=command.owner
			envelopes.append({"match_id":state.match_id,"player_id":owner,"command_seq":session.seq[owner],"command_id":"local:%d:%d"%[owner,session.seq[owner]],"command_type":command.kind,"payload":command.payload,"server_received_tick":tick})
			session.seq[owner]+=1
		if reverse:envelopes.reverse()
		for envelope in envelopes:
			var response: Dictionary=sim.submit(envelope,envelope.player_id)
			admitted.append({"envelope":envelope,"status":response.status})
			if response.status!="queued":return {"error":str(response)}
		var result: Dictionary=session.advance(1)
		if result.status!="advanced":return {"error":str(result),"tick":tick}
		outcomes.append_array(result.commands)
		state=sim.snapshot()
		for c in state.cities:
			if c.electricity.shortage>0:stats[c.city_id].shortage_ticks+=1
			if A.total(c.uncollected_micro+c.sorted_micro)>0:stats[c.city_id].waste_ticks+=1
			for slot in c.project_slots:
				if slot==null:stats[c.city_id].unused_project_slot_seconds+=1
		if state.tick in [1,80,120,330,390,465,600,660,750,870,930,1005,1020,1080,1140,1200] or (state.tick>=80 and state.tick%20==0):
			var snap: Dictionary=Resources.summarize(sim)
			snap["events"]=state.event_state;snap["rankings"]=sim.Migration.ranking(state)
			snapshots.append(snap)
	var final: Dictionary=sim.snapshot()
	return {"scenario":name,"seed":seed_value,"assignment":assignment,"humans":humans,"foundations":final.foundations,"draft":final.draft,
		"snapshots":snapshots,"statistics":stats,"command_results":outcomes,"admissions":admitted,"contracts":final.contracts,
		"settlements":final.market.ledger,"migration":final.transfer_ledger,"final_result":final.final_result,
		"canonical_sha256":sim.serialize().sha256_text(),"final_canonical":sim.serialize()}
