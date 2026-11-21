extends RefCounted
const Sim=preload("res://simulation/match.gd")
const Random=preload("res://simulation/core/seeded_random.gd")
const Envelope=preload("res://simulation/core/command_envelope.gd")
const Canonical=preload("res://simulation/core/canonical.gd")
const CARDS=["industrial_legacy","circular_foundation","energy_pioneer","investment_district"]
var engine: RefCounted
var draft: Dictionary={}
func create(match_id: String,seed_value: int) -> String:
	if not draft.is_empty():return "already_initialized"
	if match_id.is_empty():return "invalid_match_id"
	var rng=Random.new(seed_value)
	var order: Array=[0,1,2,3]
	for i in range(3,0,-1):
		var j: int=rng.below(i+1);var temp: int=order[i];order[i]=order[j];order[j]=temp
	draft={"match_id":match_id,"seed":seed_value,"status":"draft","order":order,"choices":[null,null,null,null],"turn":0,"rng_state":rng.state,"results":{},"last_seq":[-1,-1,-1,-1]}
	if Sim.Balance.load_b1().get("allow_duplicate_foundations",false):draft["allow_duplicate_foundations"]=true
	return ""
func submit(command: Variant,authenticated_player: int) -> Dictionary:
	if engine!=null:return engine.submit(command,authenticated_player)
	if draft.is_empty():return {"status":"not_initialized"}
	var error: String=Envelope.validate(command,draft.match_id,0,authenticated_player)
	if error!="":return {"status":error}
	var identity: Dictionary=command.duplicate(true)
	identity.erase("server_received_tick")
	var fingerprint: String=Canonical.encode(identity)
	if draft.results.has(command.command_id):return {"status":"duplicate" if draft.results[command.command_id].fingerprint==fingerprint else "command_id_conflict"}
	if command.command_seq<=draft.last_seq[authenticated_player]:return {"status":"stale_sequence"}
	if command.command_type!="select_foundation":error="draft_in_progress"
	elif authenticated_player!=draft.order[draft.turn]:error="not_draft_turn"
	elif command.payload.size()!=1 or typeof(command.payload.get("foundation"))!=TYPE_STRING or command.payload.foundation not in CARDS:error="invalid_foundation"
	elif command.payload.foundation in draft.choices and not draft.get("allow_duplicate_foundations",false):error="foundation_taken"
	if error=="":
		draft.choices[authenticated_player]=command.payload.foundation;draft.turn+=1
	draft.last_seq[authenticated_player]=command.command_seq
	draft.results[command.command_id]={"status":"applied" if error=="" else error,"fingerprint":fingerprint}
	if draft.turn==4:
		engine=Sim.new()
		var initialized: String=engine.initialize(draft.match_id,draft.seed,draft.choices)
		if initialized!="":return {"status":initialized}
		draft.status="complete"
		engine._state["draft"]=draft.duplicate(true)
		engine._rng.state=draft.rng_state
		engine._state.last_command_seq=draft.last_seq.duplicate()
		for id in draft.results:engine._state.command_results[id]=draft.results[id].duplicate()
	return {"status":"applied" if error=="" else error}
func snapshot() -> Dictionary:
	return engine.snapshot() if engine!=null else draft.duplicate(true)
func step() -> Dictionary:
	return engine.step() if engine!=null else {"status":"draft_in_progress"}
