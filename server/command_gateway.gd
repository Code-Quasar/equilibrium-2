extends RefCounted
const Canonical = preload("res://simulation/core/canonical.gd")
const Protocol = preload("res://shared/protocol_v1.gd")
const MAX_ACTIONS = 4096
var game: RefCounted
var sequences: Array = [0,0,0,0]
var records: Array = [{},{},{},{}]
var queued: Dictionary = {}

func _init(lifecycle: RefCounted) -> void:
	game = lifecycle

func issue(seat: int, action: String, kind: String, payload: Dictionary) -> Array:
	var identity: String = Canonical.encode({"kind":kind,"payload":payload})
	if records[seat].has(action):
		var old: Dictionary = records[seat][action]
		if old.identity != identity: return [ack(action,"admission","action_id_conflict")]
		return old.acks.duplicate(true)
	if records[seat].size() >= MAX_ACTIONS: return [ack(action,"admission","action_limit")]
	var snapshot: Dictionary = game.snapshot()
	var tick: int = snapshot.get("tick",0)
	var seq: int = sequences[seat]
	sequences[seat] += 1
	var command_id: String = "online:%d:%d" % [seat,seq]
	var envelope: Dictionary = {"match_id":snapshot.match_id,"player_id":seat,"command_seq":seq,"command_id":command_id,"command_type":kind,"payload":payload.duplicate(true),"server_received_tick":tick}
	var result: Dictionary = game.submit(envelope,seat)
	var messages: Array = [ack(action,"admission",result.status,tick)]
	if result.status == "applied": messages.append(ack(action,"execution","applied",tick,tick))
	records[seat][action] = {"identity":identity,"acks":messages.duplicate(true)}
	if result.status == "queued": queued[command_id] = {"seat":seat,"action":action,"receipt_tick":tick}
	return messages

func complete(result: Dictionary) -> Array:
	var deliveries: Array = []
	for outcome in result.get("commands",[]):
		if not queued.has(outcome.command_id): continue
		var q: Dictionary = queued[outcome.command_id]
		var message: Dictionary = ack(q.action,"execution",outcome.status,result.tick,result.tick-1)
		records[q.seat][q.action].acks.append(message)
		deliveries.append({"seat":q.seat,"message":message})
		queued.erase(outcome.command_id)
	return deliveries

func ack(action: String, phase: String, status: String, tick: int = -1, executed: int = -1) -> Dictionary:
	var body: Dictionary = {"action_id":action,"phase":phase,"status":status,"server_tick":game.snapshot().get("tick",0) if tick < 0 else tick}
	if executed >= 0: body.execution_tick = executed
	return Protocol.message("action_ack",body)
