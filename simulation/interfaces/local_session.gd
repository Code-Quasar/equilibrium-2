extends RefCounted
const Life=preload("res://simulation/interfaces/lifecycle.gd")
const Canonical=preload("res://simulation/core/canonical.gd")
const Bot=preload("res://simulation/interfaces/local_bot.gd")
var game=Life.new()
var humans: int=4
var admin: bool=false
var active: int=-1
var seq: Array=[0,0,0,0]
var history: Array=[]
var replay: Array=[]
func initialize(seed_value: int,human_count: int,administrative: bool=false) -> String:
	if human_count not in [2,3,4]:return "human_seats_must_be_2_3_or_4"
	humans=human_count;admin=administrative
	var error: String=game.create("local-"+str(seed_value),seed_value)
	if error=="":script_draft()
	return error
func issue(owner: int,kind: String,payload: Dictionary) -> Dictionary:
	var state: Dictionary=game.snapshot();var tick: int=state.get("tick",0)
	var envelope: Dictionary={"match_id":state.match_id,"player_id":owner,"command_seq":seq[owner],"command_id":"local:%d:%d"%[owner,seq[owner]],"command_type":kind,"payload":payload,"server_received_tick":tick}
	seq[owner]+=1
	var result: Dictionary=game.submit(envelope,owner)
	replay.append({"envelope":envelope,"authenticated_player":owner,"admission":result.status})
	return result
func script_draft() -> void:
	while game.engine==null and game.draft.order[game.draft.turn]>=humans:
		var owner: int=game.draft.order[game.draft.turn]
		for card in Life.CARDS:
			if card not in game.draft.choices:
				issue(owner,"select_foundation",{"foundation":card});break
func advance(seconds: int) -> Dictionary:
	if seconds<1 or seconds>1200:return {"status":"invalid_seconds"}
	if game.engine==null:return {"status":"draft_in_progress"}
	var outcomes: Array=[]
	for i in range(seconds):
		var state: Dictionary=game.snapshot()
		if state.status=="finished":return {"status":"finished","commands":outcomes,"final_result":state.final_result}
		for owner in range(humans,4):
			var plan: Array=Bot.PLAN
			if state.tick%90==0 and Life.Sim.FullEconomy.A.divi(state.tick,90)<plan.size():
				@warning_ignore("integer_division")
				var index: int=state.tick/90
				issue(owner,"construct",{"building_type":plan[index]})
		var result: Dictionary=game.step()
		if result.status!="advanced":return result
		outcomes.append_array(result.commands);history.append_array(result.commands)
	return {"status":"advanced","commands":outcomes,"tick":game.snapshot().tick,"final_result":game.snapshot().final_result}
func select_seat(seat: int) -> Dictionary:
	if seat<0 or seat>=4 or (not admin and seat>=humans):return {"status":"seat_not_locally_controlled"}
	active=seat
	return {"status":"seat_selected","seat":active,"administrative":admin}
func choose_foundation(card: String) -> Dictionary:
	if active<0:return {"status":"select_seat_first"}
	var result: Dictionary=issue(active,"select_foundation",{"foundation":card})
	if game.engine==null:script_draft()
	return result
