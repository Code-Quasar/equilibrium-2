extends RefCounted
const Life = preload("res://simulation/interfaces/lifecycle.gd")
const Gateway = preload("res://server/command_gateway.gd")
const Bots = preload("res://server/bot_controller.gd")
const Scheduler = preload("res://server/tick_scheduler.gd")
const View = preload("res://simulation/projections/player_view.gd")
const Protocol = preload("res://shared/protocol_v1.gd")
var game = Life.new()
var gateway = Gateway.new(game)
var scheduler = Scheduler.new()
var bots: Array = []
var view_seq: int = 0
var failed: bool = false
var developer: bool = false                 # --dev-emergencies: fixed schedule, timeline log
var _logged: Dictionary = {}
func initialize(match_id: String, seed_value: int, bot_seats: Array, dev_emergencies: Array = []) -> String:
	bots = bot_seats.duplicate()
	developer = not dev_emergencies.is_empty()
	game.emergency_schedule = dev_emergencies.duplicate(true)
	var error: String = game.create(match_id,seed_value,bots)
	if error == "": Bots.draft(game,gateway,bots)
	return error
func draft_view() -> Dictionary:
	var available: Array = []
	for card in game.CARDS:
		if card not in game.draft.choices: available.append(card)
	return Protocol.message("draft_state",{"match_id":game.draft.match_id,"order":game.draft.order.duplicate(),"choices":game.draft.choices.duplicate(),"turn_seat":game.draft.order[game.draft.turn] if game.engine == null else -1,"available_foundations":available})
func view(seat: int) -> Dictionary:
	var state: Dictionary = game.snapshot()
	var result: Dictionary = View.project(state,seat,game.engine.build_options(seat),game.engine.emergency_view(seat))
	if developer: result.public.developer_mode = true
	result.merge({"match_id":state.match_id,"tick":state.tick,"view_seq":view_seq})
	return Protocol.message("player_view",result)
func step() -> Dictionary:
	if failed: return {"status":"session_failed"}
	if game.engine == null: return {"status":"draft_in_progress"}
	if game.snapshot().status == "finished": return {"status":"match_closed"}
	Bots.play(game,gateway,bots)
	var result: Dictionary = game.step()
	if result.status != "advanced":
		failed = true
		scheduler.stop()
		return result
	result.deliveries = gateway.complete(result)
	view_seq += 1
	if developer: _log_emergencies()
	if game.snapshot().status == "finished": scheduler.stop()
	return result
## Developer mode: the authoritative emergency timeline, scores and boosts, on the
## server's log, once per phase change.
func _log_emergencies() -> void:
	var state: Dictionary = game.snapshot()
	for ev in state.emergencies.events:
		var ph: String = game.engine.emergency_phase(ev)
		if _logged.get(ev.id, "") != ph:
			_logged[ev.id] = ph
			print("EMERGENCY tick=%d %s %s %s scores=%s result=%s boosts=%s" % [state.tick, ev.id, ev.type, ph,
				str(ev.players.map(func(p): return p.score)), str(ev.result), str(state.emergencies.boosts)])
