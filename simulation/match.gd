extends RefCounted
## The authoritative EQUILIBRIUM match under the B2.1 ruleset.
## Each one-second tick runs every phase, in order, on a candidate copy of the state;
## the candidate replaces the authoritative state only if every phase and invariant
## passes. Identical inputs produce byte-identical canonical state.
const A = preload("res://simulation/core/arithmetic.gd")
const Balance = preload("res://simulation/core/balance.gd")
const Canonical = preload("res://simulation/core/canonical.gd")
const Envelope = preload("res://simulation/core/command_envelope.gd")
const State = preload("res://simulation/core/match_state.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const EnvironmentSystem = preload("res://simulation/systems/environment.gd")
const Events = preload("res://simulation/systems/events.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Market = preload("res://simulation/systems/market.gd")
const Materials = preload("res://simulation/systems/materials.gd")
const Migration = preload("res://simulation/systems/migration.gd")
const Operations = preload("res://simulation/systems/operations.gd")
const Production = preload("res://simulation/systems/production.gd")
const Reserve = preload("res://simulation/systems/reserve.gd")
const Satisfaction = preload("res://simulation/systems/satisfaction.gd")
const Waste = preload("res://simulation/systems/waste.gd")

var buildings: RefCounted
var operations: RefCounted
var waste: RefCounted
var environment: RefCounted
var production: RefCounted
var satisfaction: RefCounted
var market: RefCounted
var reserve: RefCounted
var _balance: Dictionary = {}
var _state: Dictionary = {}
var _pending: Array = []
var _stepping: bool = false
var _commands: Dictionary = {}
var _phases: Array = []

func initialize(match_id: String, seed_value: int, foundations: Array) -> String:
	if not _state.is_empty():
		return "already_initialized"
	_balance = Balance.load_config()
	if _balance.is_empty():
		return "invalid_balance"
	var b: Dictionary = _balance
	buildings = Buildings.new(b)
	operations = Operations.new(b, buildings)
	waste = Waste.new(b, buildings)
	market = Market.new(b, waste)
	production = Production.new(b, buildings, waste)
	environment = EnvironmentSystem.new(b, buildings)
	satisfaction = Satisfaction.new(b, buildings, operations)
	reserve = Reserve.new(b, buildings)
	for kind in Buildings.COMMANDS:
		_commands[kind] = [buildings.validate, buildings.execute]
	for kind in Market.COMMANDS:
		_commands[kind] = [market.validate, market.execute]
	_commands["sell_materials"] = [Materials.validate_sale, _sell_materials]
	_phases = [
		["begin", _begin],
		["construction", buildings.complete_projects],
		["commands", Callable()],
		["municipal_budget", operations.municipal],
		["funding", operations.fund],
		["power_generation", operations.measure],
		["power_contracts", market.settle_electricity],
		["power_allocation", operations.allocate],
		["staffing", operations.staff],
		["production", production.run],
		["collection_and_sorting", waste.collect_and_sort],
		["treatment_contracts", market.settle_waste],
		["local_treatment", waste.treat_local],
		["landfill", waste.landfill],
		["material_overflow", _sell_overflow],
		["resource_reserve", reserve.draw],
		["environment", environment.update],
		["satisfaction", satisfaction.update],
		["migration", _migrate],
		["contract_expiry", market.expire],
		["advance_time", _advance],
	]
	_state = State.create(match_id, seed_value, foundations, b)
	if _state.is_empty():
		return "invalid_match_setup"
	Events.apply(_state, b.crises)
	return _validate(_state, true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func serialize() -> String:
	var pending: Array = _pending.duplicate(true)
	pending.sort_custom(func(x, y): return Envelope.before(x, y, _state.seed))
	var commands: Array = _commands.keys()
	commands.sort()
	return Canonical.encode({"state": _state, "pending_commands": pending, "balance": _balance,
		"phases": _phases.map(func(phase): return phase[0]), "command_types": commands})

## Read-only check of a command against the current state.
func preview(player_id: int, kind: String, payload: Dictionary) -> String:
	if _state.is_empty():
		return "not_initialized"
	if _state.status == "finished":
		return "match_closed"
	if player_id < 0 or player_id >= _balance.players:
		return "invalid_player"
	if not _commands.has(kind):
		return "unsupported_command"
	if Reserve.eliminated(_state.cities[player_id]):
		return "city_eliminated"
	return _commands[kind][0].call(snapshot(), {"player_id": player_id, "command_type": kind, "payload": payload.duplicate(true)})

## Why each building type and size can or cannot be started now ("" = allowed).
func build_options(player_id: int) -> Dictionary:
	var result: Dictionary = {}
	for kind in Balance.TYPES:
		result[kind] = {}
		for size in Balance.SIZES:
			var command: Dictionary = {"player_id": player_id, "command_type": "construct", "payload": {"building_type": kind, "size": size}}
			result[kind][size] = "match_closed" if _state.status == "finished" else ("city_eliminated" if Reserve.eliminated(_state.cities[player_id]) else buildings.validate(_state, command))
	return result

func submit(raw: Variant, authenticated_player: int) -> Dictionary:
	if _state.is_empty():
		return {"status": "not_initialized"}
	if _stepping or _state.status == "finished":
		return {"status": "match_closed"}
	var error: String = Envelope.validate(raw, _state.match_id, _state.tick, authenticated_player)
	if not error.is_empty():
		return {"status": error}
	# Retries may carry a later receipt tick; identity excludes that stamp.
	var fingerprint: String = _fingerprint(raw)
	if _state.command_results.has(raw.command_id):
		return {"status": "duplicate" if _state.command_results[raw.command_id].fingerprint == fingerprint else "command_id_conflict"}
	for queued in _pending:
		if queued.command_id == raw.command_id:
			return {"status": "duplicate" if _fingerprint(queued) == fingerprint else "command_id_conflict"}
		if queued.player_id == raw.player_id and queued.command_seq == raw.command_seq:
			return {"status": "sequence_conflict"}
	if raw.command_seq <= _state.last_command_seq[raw.player_id]:
		return {"status": "stale_sequence"}
	_pending.append(raw.duplicate(true))
	return {"status": "queued"}

static func _fingerprint(command: Dictionary) -> String:
	var identity: Dictionary = command.duplicate(true)
	identity.erase("server_received_tick")
	return Canonical.encode(identity)

## Runs one tick. Interactive and test integrations validate after every phase for
## fault localization; trusted batch runners may validate once per tick.
func step(validate_each_phase: bool = true) -> Dictionary:
	if _state.is_empty():
		return {"status": "not_initialized"}
	if _stepping or _state.status == "finished":
		return {"status": "match_closed"}
	_stepping = true
	var candidate: Dictionary = _state.duplicate(true)
	var context: Dictionary = {"start_tick": candidate.tick, "end_tick": candidate.tick + 1}
	var results: Array = []
	for phase in _phases:
		var error: String = ""
		if phase[0] == "commands":
			var commands: Array = _pending.duplicate(true)
			commands.sort_custom(func(x, y): return Envelope.before(x, y, candidate.seed))
			for command in commands:
				var outcome: Dictionary = _execute(candidate, command)
				candidate = outcome.state
				results.append({"command_id": command.command_id, "status": outcome.status})
		else:
			error = phase[1].call(candidate, context)
		var final: bool = phase[0] == "advance_time"
		if error.is_empty() and (validate_each_phase or final):
			error = _validate(candidate, final)
		if error.is_empty() and candidate.tick != (context.end_tick if final else context.start_tick):
			error = "phase_changed_time"
		if not error.is_empty():
			_stepping = false
			return {"status": "tick_rejected", "phase": phase[0], "error": error}
	_state = candidate
	_pending.clear()
	_stepping = false
	return {"status": "advanced", "tick": _state.tick, "commands": results}

## A command either applies completely or leaves the state exactly as it was.
func _execute(state: Dictionary, command: Dictionary) -> Dictionary:
	var candidate: Dictionary = state.duplicate(true)
	var error: String = "unsupported_command"
	if Reserve.eliminated(state.cities[command.player_id]):
		error = "city_eliminated"
	elif _commands.has(command.command_type):
		var handler: Array = _commands[command.command_type]
		error = handler[0].call(candidate.duplicate(true), command.duplicate(true))
		if error.is_empty():
			error = handler[1].call(candidate, command.duplicate(true))
		if error.is_empty():
			error = _validate(candidate, false)
	if not error.is_empty():
		candidate = state.duplicate(true)
	candidate.last_command_seq[command.player_id] = command.command_seq
	candidate.command_results[command.command_id] = {"status": "applied" if error.is_empty() else error,
		"fingerprint": _fingerprint(command), "tick": state.tick}
	return {"state": candidate, "status": "applied" if error.is_empty() else error}

func _begin(state: Dictionary, _ctx: Dictionary) -> String:
	Events.apply(state, _balance.crises)
	for city in state.cities:
		Finance.begin_tick(city)
	return ""

func _sell_materials(state: Dictionary, command: Dictionary) -> String:
	var error: String = Materials.validate_sale(state, command)
	if error.is_empty():
		Materials.sell(state.cities[command.player_id], _balance, command.payload.amount)
	return error

func _sell_overflow(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		Materials.sell_overflow(city, _balance)
	return ""

func _migrate(state: Dictionary, ctx: Dictionary) -> String:
	if Migration.due(_balance.migration, ctx.end_tick):
		state.migrations.append(Migration.pulse(state, _balance.migration, ctx.end_tick))
	return ""

func _advance(state: Dictionary, _ctx: Dictionary) -> String:
	state.tick += 1
	if state.tick == _balance.duration:
		state.status = "finished"
		var rankings: Array = Migration.ranking(state)
		state.final_result = {"rankings": rankings, "duration": state.tick,
			"winners": rankings.filter(func(row): return row.rank == 1).map(func(row): return row.city_id)}
		# The hash covers the final canonical payload with the hash field absent.
		state.final_result["canonical_sha256"] = Canonical.encode(state).sha256_text()
	return ""

func _validate(state: Dictionary, end_of_tick: bool) -> String:
	var error: String = State.validate(state, _balance)
	if not error.is_empty():
		return error
	for city in state.cities:
		for check in [buildings.validate_city(city), waste.validate_city(city), environment.validate_city(city), Operations.validate_power(city)]:
			if not check.is_empty():
				return check
		if end_of_tick and city.materials_micro > _balance.economy.material_cap:
			return "material_inventory_cap"
	return market.validate_state(state)
