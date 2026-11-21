extends SceneTree
const EngineCore = preload("res://simulation/core/engine.gd")
const State = preload("res://simulation/core/match_state.gd")
const Random = preload("res://simulation/core/seeded_random.gd")
const Fixed = preload("res://simulation/core/fixed_point.gd")
const Canonical = preload("res://simulation/core/canonical.gd")
const Pipeline = preload("res://simulation/core/pipeline.gd")
const FOUNDATIONS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_initialization()
	_test_random_and_fixed()
	_test_commands()
	_test_order_and_replay()
	_test_pipeline()
	_test_full_match()
	print("Core: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func fresh(seed_value: int = 0):
	var simulation = EngineCore.new()
	check(simulation.initialize("test", seed_value, FOUNDATIONS).is_empty(), "valid setup")
	return simulation

func envelope(player: int = 0, seq: int = 0, kind: String = "probe", tick: int = 0) -> Dictionary:
	return {"match_id": "test", "player_id": player, "command_seq": seq,
		"command_id": "%d:%d" % [player, seq], "command_type": kind,
		"payload": {}, "server_received_tick": tick}

func _test_initialization() -> void:
	var simulation = fresh()
	var state: Dictionary = simulation.snapshot()
	check(state.cities.size() == 4, "exactly four cities")
	var population: int = 0
	var founders: int = 0
	for id in range(4):
		var city: Dictionary = state.cities[id]
		population += city.population
		founders += city.founding_population
		check(city.city_id == id and city.player_id == id, "one owner per city")
		check(city.population == 1000 and city.founding_population == 500, "starting residents")
		check(city.uncollected_micro == [0, 0, 0] and city.sorted_micro == [0, 0, 0], "empty waste")
	check(population == 4000 and founders == 2000, "regional and mobile pool conservation")
	check(state.cities[0].money_micro == 480000000 and state.cities[3].money_micro == 900000000, "Foundation cash")
	check(state.cities[0].buildings[0].type == "factory" and state.cities[3].buildings.is_empty(), "Foundation structures")
	state.cities[0].population = 0
	check(simulation.snapshot().cities[0].population == 1000, "detached snapshot")
	for selections in [[], FOUNDATIONS.slice(0, 3), FOUNDATIONS + [FOUNDATIONS[0]], ["bad", "b", "c", "d"], [FOUNDATIONS[0], FOUNDATIONS[0], FOUNDATIONS[2], FOUNDATIONS[3]]]:
		check(EngineCore.new().initialize("test", 0, selections) == "invalid_match_setup", "invalid setup rejected")
	check(simulation.initialize("other", 0, FOUNDATIONS) == "already_initialized", "no repeated packages")
	check(State.validate(simulation.snapshot()).is_empty(), "initial invariants")
	for field in ["money_micro", "materials_micro", "previous_biogas_micro_E"]:
		var invalid: Dictionary = simulation.snapshot()
		invalid.cities[0][field] = -1
		check(State.validate(invalid) == "negative_or_invalid_resource", "nonnegative " + field)
	for field in ["uncollected_micro", "sorted_micro"]:
		for category in range(3):
			var invalid: Dictionary = simulation.snapshot()
			invalid.cities[0][field][category] = -1
			check(State.validate(invalid) == "negative_or_invalid_resource", "nonnegative waste category")
	var invented_mass: Dictionary = simulation.snapshot()
	invented_mass.cities[0].sorted_micro[0] = 1
	check(State.validate(invented_mass) == "waste_conservation", "unaccounted mass rejected")
	var invented_resident: Dictionary = simulation.snapshot()
	invented_resident.cities[0].population += 1
	check(State.validate(invented_resident) == "population_conservation", "invented resident rejected")

func _test_random_and_fixed() -> void:
	var rng = Random.new(0)
	for expected in [16807, 282475249, 1622650073, 984943658, 1144108930]:
		check(rng.next_int() == expected, "PRNG golden vector")
	for seed_value in [-9223372036854775807, -1, 0, 1, 9223372036854775807]:
		var a = Random.new(seed_value)
		var b = Random.new(seed_value)
		for _i in range(30):
			var sample: int = a.below(4)
			check(sample == b.below(4) and sample >= 0 and sample < 4, "seeded bounded random")
	var total: int = 0
	var carry: int = 0
	for _i in range(60):
		var result: Dictionary = Fixed.per_second(1000000, carry)
		total += result.amount
		carry = result.carry
	check(total == 1000000 and carry == 0, "exact per-minute carry")
	check(Canonical.encode({"z": 9223372036854775807, "a": [1, true]}) == '{"a":[1,true],"z":9223372036854775807}', "exact int64 canonical form")
	check(Canonical.encode({"b": 1, "a": 2}) == Canonical.encode({"a": 2, "b": 1}), "dictionary insertion independence")

func _test_commands() -> void:
	var simulation = fresh()
	var before: String = simulation.serialize()
	for raw in [null, [], {}, {"player_id": 0}]:
		check(simulation.submit(raw, 0).status == "malformed_command", "malformed envelope")
	for player in [-1, 4, 100]:
		check(simulation.submit(envelope(player), player).status == "invalid_player", "invalid player")
	check(simulation.submit(envelope(1), 0).status == "unauthorized_player", "authenticated owner")
	for field in ["player_id", "command_seq", "server_received_tick"]:
		var raw: Dictionary = envelope()
		raw[field] = 0.0
		check(simulation.submit(raw, 0).status == "malformed_command", "float identifier rejected")
	var wrong: Dictionary = envelope()
	wrong.match_id = "other"
	check(simulation.submit(wrong, 0).status == "wrong_match", "wrong match")
	check(simulation.submit(envelope(0, 0, "probe", 1), 0).status == "invalid_received_tick", "future clock rejected")
	var malformed: Dictionary = envelope()
	malformed.payload = {"amount": -0.5}
	check(simulation.submit(malformed, 0).status == "malformed_payload", "noninteger payload")
	check(simulation.serialize() == before, "malformed commands leave state unchanged")
	check(simulation.submit(envelope(), 0).status == "queued", "valid envelope queued")
	check(simulation.submit(envelope(), 0).status == "duplicate", "queued retry")
	var conflict: Dictionary = envelope()
	conflict.payload = {"different": true}
	check(simulation.submit(conflict, 0).status == "command_id_conflict", "conflicting ID")
	conflict = envelope()
	conflict.command_id = "different"
	check(simulation.submit(conflict, 0).status == "sequence_conflict", "duplicate sequence")
	check(simulation.step().commands[0].status == "unsupported_command", "gameplay not enabled")
	check(simulation.submit(envelope(0, 0, "probe", 1), 0).status == "duplicate", "completed retry")
	conflict = envelope(0, 0, "probe", 1)
	conflict.command_id = "new-id"
	check(simulation.submit(conflict, 0).status == "stale_sequence", "stale sequence")
	var atomic = fresh()
	atomic.register_command("negative", func(_s, _c): return "", func(s, _c, r):
		s.cities[0].money_micro = -1
		r.next_int()
		return "")
	atomic.submit(envelope(0, 0, "negative"), 0)
	var rng_before: String = atomic.serialize()
	check(atomic.step().commands[0].status == "negative_or_invalid_resource", "reject negative mutation")
	check(atomic.snapshot().cities[0].money_micro == 480000000, "rollback resource mutation")
	check('"rng_state":1' in rng_before and '"rng_state":1' in atomic.serialize(), "rollback random consumption")
	check(atomic.snapshot().applied_command_ids.is_empty(), "rejected command not applied")
	var payload_test = fresh()
	payload_test.register_command("probe", func(_s, c): return "invalid_payload" if not c.payload.is_empty() else "", func(_s, _c, _r): return "")
	var bad_payload: Dictionary = envelope()
	bad_payload.payload = {"unexpected": 1}
	payload_test.submit(bad_payload, 0)
	check(payload_test.step().commands[0].status == "invalid_payload", "handler payload validation")

func attach_probe(simulation) -> void:
	# Test-only command: append random audit markers, no production gameplay API.
	check(simulation.register_command("probe", func(_s, _c): return "", func(s, c, r):
		s.transfer_ledger.append({"id": c.command_id, "sample": r.next_int()})
		return ""), "register test handler")

func _test_order_and_replay() -> void:
	for seed_value in range(4):
		var a = fresh(seed_value)
		var b = fresh(seed_value)
		attach_probe(a)
		attach_probe(b)
		var commands: Array = []
		for player in range(4):
			for seq in range(2):
				commands.append(envelope(player, seq))
		for command in commands:
			a.submit(command, command.player_id)
		commands.reverse()
		for command in commands:
			b.submit(command, command.player_id)
		check(a.serialize() == b.serialize(), "pending serialization ordered")
		check(a.step().status == "advanced" and b.step().status == "advanced", "ordered tick")
		var expected: Array = []
		for rank in range(4):
			for seq in range(2):
				expected.append("%d:%d" % [(seed_value + rank) % 4, seq])
		check(a.snapshot().applied_command_ids == expected, "seed rotation and ascending sequence")
		for _i in range(3):
			a.step()
			b.step()
		check(a.serialize() == b.serialize(), "same seed and commands reproduce state")
		check(a.serialize() == a.serialize(), "repeatable serialization")
		check(not a.register_command("late", func(_s, _c): return "", func(_s, _c, _r): return ""), "registry locked")
	var serial = fresh()
	serial.register_command("spend", func(s, _c): return "insufficient_funds" if s.cities[0].money_micro < 400000000 else "", func(s, _c, _r):
		s.cities[0].money_micro -= 400000000
		return "")
	serial.submit(envelope(0, 1, "spend"), 0)
	serial.submit(envelope(0, 0, "spend"), 0)
	var result: Dictionary = serial.step()
	check(result.commands[0].status == "applied" and result.commands[1].status == "insufficient_funds", "later validation observes earlier committed spending")
	check(serial.snapshot().cities[0].money_micro == 80000000, "no double spending")
	var after_spend: int = serial.snapshot().cities[0].money_micro
	check(serial.submit(envelope(0, 0, "spend", 1), 0).status == "duplicate", "successful spend retry")
	serial.step()
	check(serial.snapshot().cities[0].money_micro == after_spend, "retry cannot spend twice")

func _test_pipeline() -> void:
	var simulation = fresh()
	var expected: Array = []
	for phase in Pipeline.PHASES:
		if phase in ["snapshot", "commands", "advance_time", "publish"]:
			continue
		for id in ["b", "a"]:
			var label: String = phase + ":" + id
			check(simulation.register_system(phase, id, func(s, ctx, _r):
				if ctx.start_tick != 0 or ctx.end_tick != 1 or ctx.start_snapshot.tick != 0:
					return "bad_interval"
				s.transfer_ledger.append(label)
				return ""), "register phase system")
		expected.append(phase + ":a")
		expected.append(phase + ":b")
	check(simulation.step().status == "advanced", "pipeline advances")
	check(simulation.snapshot().transfer_ledger == expected, "phase and system ordering")
	var broken = fresh()
	broken.register_system("production", "bad", func(s, _ctx, r):
		s.cities[0].sorted_micro[0] = -1
		r.next_int()
		return "")
	var before: String = broken.serialize()
	check(broken.step().status == "tick_rejected", "invalid system rejected")
	check(broken.serialize() == before, "entire tick and RNG rollback")
	var batch_broken = fresh()
	batch_broken.register_system("production", "bad", func(s, _ctx, r):
		s.cities[0].sorted_micro[0] = -1
		r.next_int()
		return "")
	var batch_before: String = batch_broken.serialize()
	check(batch_broken.step(false).status == "tick_rejected", "batch publication rejects invalid state")
	check(batch_broken.serialize() == batch_before, "batch publication rolls back state and RNG")
	var clock_edit = fresh()
	clock_edit.register_system("production", "bad_clock", func(s, _ctx, _r):
		s.tick += 1
		return "")
	check(clock_edit.step().error == "system_changed_authoritative_time", "systems cannot advance clock")
	check(clock_edit.snapshot().tick == 0, "clock edit rolled back")

func _test_full_match() -> void:
	var simulation = fresh()
	var initial_cities: Array = simulation.snapshot().cities
	for tick in range(1200):
		var result: Dictionary = simulation.step()
		check(result.status == "advanced" and simulation.snapshot().tick == tick + 1, "exactly one second per call")
		check(State.validate(simulation.snapshot()).is_empty(), "invariants every tick")
	check(simulation.snapshot().cities == initial_cities, "deferred gameplay does not execute")
	check(simulation.snapshot().status == "finished", "match ends at 1200")
	var final_state: String = simulation.serialize()
	check(simulation.step().status == "match_closed", "no 1201st transition")
	check(simulation.submit(envelope(0, 0, "probe", 1200), 0).status == "match_closed", "no post-match commands")
	check(simulation.serialize() == final_state, "final state frozen")
