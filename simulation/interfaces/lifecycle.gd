extends RefCounted
## Foundation draft, then the match. Human seats pick a unique Foundation first, in
## a seeded random order; bot seats follow, also in seeded order, from what is left.
## The fourth pick creates the authoritative match.
const Sim = preload("res://simulation/match.gd")
const Random = preload("res://simulation/core/seeded_random.gd")
const Envelope = preload("res://simulation/core/command_envelope.gd")
const CARDS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
var engine: RefCounted
var draft: Dictionary = {}
var emergency_schedule: Array = []          # server developer mode only

func create(match_id: String, seed_value: int, bot_seats: Array = []) -> String:
	if not draft.is_empty():
		return "already_initialized"
	if match_id.is_empty():
		return "invalid_match_id"
	var rng = Random.new(seed_value)
	var order: Array = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j: int = rng.below(i + 1)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	order = order.filter(func(seat): return seat not in bot_seats) + order.filter(func(seat): return seat in bot_seats)
	draft = {"match_id": match_id, "seed": seed_value, "status": "draft", "order": order,
		"choices": [null, null, null, null], "turn": 0, "results": {}, "last_seq": [-1, -1, -1, -1]}
	return ""

func submit(command: Variant, authenticated_player: int) -> Dictionary:
	if engine != null:
		return engine.submit(command, authenticated_player)
	if draft.is_empty():
		return {"status": "not_initialized"}
	var error: String = Envelope.validate(command, draft.match_id, 0, authenticated_player)
	if not error.is_empty():
		return {"status": error}
	var fingerprint: String = Sim._fingerprint(command)
	if draft.results.has(command.command_id):
		return {"status": "duplicate" if draft.results[command.command_id].fingerprint == fingerprint else "command_id_conflict"}
	if command.command_seq <= draft.last_seq[authenticated_player]:
		return {"status": "stale_sequence"}
	var card: Variant = command.payload.get("foundation")
	if command.command_type != "select_foundation":
		error = "draft_in_progress"
	elif authenticated_player != draft.order[draft.turn]:
		error = "not_draft_turn"
	elif command.payload.size() != 1 or typeof(card) != TYPE_STRING or card not in CARDS:
		error = "invalid_foundation"
	elif card in draft.choices:
		error = "foundation_taken"
	if error.is_empty():
		draft.choices[authenticated_player] = card
		draft.turn += 1
	draft.last_seq[authenticated_player] = command.command_seq
	draft.results[command.command_id] = {"status": "applied" if error.is_empty() else error, "fingerprint": fingerprint}
	if draft.turn == 4:
		engine = Sim.new()
		var initialized: String = engine.initialize(draft.match_id, draft.seed, draft.choices, emergency_schedule)
		if not initialized.is_empty():
			return {"status": initialized}
		draft.status = "complete"
		# Draft receipts and sequences carry into the match's idempotency record.
		engine._state.last_command_seq = draft.last_seq.duplicate()
		for id in draft.results:
			engine._state.command_results[id] = draft.results[id].duplicate()
	return {"status": "applied" if error.is_empty() else error}

func snapshot() -> Dictionary:
	return engine.snapshot() if engine != null else draft.duplicate(true)

func step() -> Dictionary:
	return engine.step() if engine != null else {"status": "draft_in_progress"}
