extends RefCounted
const Balance = preload("res://simulation/core/balance.gd")
const State = preload("res://simulation/core/match_state.gd")
const Random = preload("res://simulation/core/seeded_random.gd")
const Envelope = preload("res://simulation/core/command_envelope.gd")
const Pipeline = preload("res://simulation/core/pipeline.gd")
const Canonical = preload("res://simulation/core/canonical.gd")

var _state: Dictionary = {}
var _pending: Array = []
var _handlers: Dictionary = {}
var _pipeline = Pipeline.new()
var _rng = Random.new()
var _balance: Dictionary = {}
var _started: bool = false
var _stepping: bool = false

func initialize(match_id: String, seed_value: int, foundations: Array) -> String:
	if not _state.is_empty():
		return "already_initialized"
	_balance = Balance.load_b1()
	if _balance.is_empty():
		return "invalid_balance"
	_state = State.create(match_id, seed_value, foundations, _balance)
	if _state.is_empty():
		return "invalid_match_setup"
	_rng = Random.new(seed_value)
	return _validate_state(_state)

func register_command(kind: String, validate: Callable, execute: Callable) -> bool:
	if _started or _stepping or _handlers.has(kind) or kind.is_empty() or not validate.is_valid() or not execute.is_valid():
		return false
	_handlers[kind] = {"validate": validate, "execute": execute}
	return true

func register_system(phase: String, system_id: String, execute: Callable) -> bool:
	return not _started and not _stepping and _pipeline.register_system(phase, system_id, execute)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func serialize() -> String:
	var pending: Array = _pending.duplicate(true)
	if not _state.is_empty():
		pending.sort_custom(func(a, b): return Envelope.before(a, b, _state.seed))
	var commands: Array = _handlers.keys()
	commands.sort()
	return Canonical.encode({"state": _state, "pending_commands": pending,
		"rng_algorithm": "park_miller_16807_v1", "rng_state": _rng.state,
		"balance": _balance, "systems": _pipeline.manifest(),
		"command_types": commands, "started": _started})

## Read-only command preview. Admission and execution still revalidate independently.
func preview(player_id: int, kind: String, payload: Dictionary) -> String:
	if _state.is_empty():
		return "not_initialized"
	if _state.status == "finished":
		return "match_closed"
	if player_id < 0 or player_id >= 4:
		return "invalid_player"
	if not _handlers.has(kind):
		return "unsupported_command"
	return _handlers[kind].validate.call(snapshot(), {
		"player_id": player_id, "command_type": kind, "payload": payload.duplicate(true)})

func submit(raw: Variant, authenticated_player: int) -> Dictionary:
	if _state.is_empty():
		return {"status": "not_initialized"}
	if _stepping or _state.status == "finished":
		return {"status": "match_closed"}
	var error: String = Envelope.validate(raw, _state.match_id, _state.tick, authenticated_player)
	if not error.is_empty():
		return {"status": error}
	# Retries may carry a later server receipt tick; identity excludes that stamp.
	var identity: Dictionary = raw.duplicate(true)
	identity.erase("server_received_tick")
	var fingerprint: String = Canonical.encode(identity)
	if _state.command_results.has(raw.command_id):
		var previous: Dictionary = _state.command_results[raw.command_id]
		return {"status": "duplicate" if previous.fingerprint == fingerprint else "command_id_conflict"}
	for queued in _pending:
		if queued.command_id == raw.command_id:
			var queued_identity: Dictionary = queued.duplicate(true)
			queued_identity.erase("server_received_tick")
			return {"status": "duplicate" if Canonical.encode(queued_identity) == fingerprint else "command_id_conflict"}
		if queued.player_id == raw.player_id and queued.command_seq == raw.command_seq:
			return {"status": "sequence_conflict"}
	if raw.command_seq <= _state.last_command_seq[raw.player_id]:
		return {"status": "stale_sequence"}
	_pending.append(raw.duplicate(true))
	return {"status": "queued"}

## Trusted batch runners may validate once at publication. Interactive and test
## integrations use phase-by-phase validation for fault localization.
func step(validate_each_phase: bool = true) -> Dictionary:
	if _state.is_empty():
		return {"status": "not_initialized"}
	if _stepping or _state.status == "finished":
		return {"status": "match_closed"}
	_stepping = true
	var candidate: Dictionary = _state.duplicate(true)
	var rng = Random.new()
	rng.state = _rng.state
	var commands: Array = _pending.duplicate(true)
	commands.sort_custom(func(a, b): return Envelope.before(a, b, candidate.seed))
	var context: Dictionary = {"start_tick": candidate.tick, "end_tick": candidate.tick + 1,
		# Batch systems share read-only context; other integrations receive detached
		# snapshot and per-system context copies.
		"start_snapshot": _state.duplicate(true) if validate_each_phase else _state}
	var results: Array = []
	for phase in Pipeline.PHASES:
		var error: String = ""
		if phase == "commands":
			for command in commands:
				var outcome: Dictionary = _execute_command(candidate, command, rng)
				candidate = outcome.state
				results.append({"command_id": command.command_id, "status": outcome.status})
		elif phase == "advance_time":
			candidate.tick += 1
			if candidate.tick == _balance.match_seconds:
				candidate.status = "finished"
		else:
			error = _pipeline.run_phase(phase, candidate, context, rng, validate_each_phase)
		if error.is_empty() and (validate_each_phase or phase == "publish"):
			error = _validate_state(candidate)
		var expected_tick: int = context.end_tick if phase in ["advance_time", "publish"] else context.start_tick
		if error.is_empty() and candidate.tick != expected_tick:
			error = "system_changed_authoritative_time"
		if not error.is_empty():
			_stepping = false
			return {"status": "tick_rejected", "phase": phase, "error": error}
	_state = candidate
	_rng.state = rng.state
	_pending.clear()
	_started = true
	_stepping = false
	return {"status": "advanced", "tick": _state.tick, "commands": results}

func _execute_command(state: Dictionary, command: Dictionary, rng: RefCounted) -> Dictionary:
	var candidate: Dictionary = state.duplicate(true)
	var error: String = "unsupported_command"
	var rng_before: int = rng.state
	if _handlers.has(command.command_type):
		var handler: Dictionary = _handlers[command.command_type]
		var validation: Variant = handler.validate.call(candidate.duplicate(true), command.duplicate(true))
		error = validation if typeof(validation) == TYPE_STRING else "invalid_validator_result"
		if error.is_empty():
			var execution: Variant = handler.execute.call(candidate, command.duplicate(true), rng)
			error = execution if typeof(execution) == TYPE_STRING else "invalid_handler_result"
		if error.is_empty():
			error = _validate_state(candidate)
	if not error.is_empty():
		candidate = state.duplicate(true)
		rng.state = rng_before
	else:
		candidate.applied_command_ids.append(command.command_id)
	candidate.last_command_seq[command.player_id] = command.command_seq
	var identity: Dictionary = command.duplicate(true)
	identity.erase("server_received_tick")
	var status: String = "applied" if error.is_empty() else error
	candidate.command_results[command.command_id] = {"status": status,
		"fingerprint": Canonical.encode(identity), "tick": state.tick}
	return {"state": candidate, "status": status}

func _validate_state(state: Dictionary) -> String:
	return State.validate(state)
