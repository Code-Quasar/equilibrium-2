extends SceneTree
## Shared test harness: checks, fixture matches, single-command steps and
## ledger-consistent state edits for setting up scenarios.
const Sim = preload("res://simulation/match.gd")
const A = preload("res://simulation/core/arithmetic.gd")
const Balance = preload("res://simulation/core/balance.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const DRAFT = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
const U: int = 1000000
var checks: int = 0
var failures: int = 0
var _sequence: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (got %s, expected %s)" % [label, str(actual), str(expected)])

func near(actual: int, expected: int, tolerance: int, label: String) -> void:
	check(absi(actual - expected) <= tolerance, "%s (got %d, expected %d +- %d)" % [label, actual, expected, tolerance])

func finish(suite: String) -> void:
	print("%s: %d checks, %d failures" % [suite, checks, failures])
	quit(1 if failures > 0 else 0)

func fixture(foundations: Array = DRAFT, seed_value: int = 42) -> RefCounted:
	var m = Sim.new()
	var error: String = m.initialize("test-%d" % seed_value, seed_value, foundations)
	assert(error.is_empty(), error)
	return m

## Queues one command, advances one tick and returns that command's result.
func act(m: RefCounted, seat: int, kind: String, payload: Dictionary) -> String:
	var key: String = "%d:%d" % [m.get_instance_id(), seat]
	var seq: int = _sequence.get(key, 0)
	_sequence[key] = seq + 1
	var id: String = "t:%d:%d" % [seat, seq]
	var admitted: Dictionary = m.submit({"match_id": m._state.match_id, "player_id": seat, "command_seq": seq,
		"command_id": id, "command_type": kind, "payload": payload, "server_received_tick": m._state.tick}, seat)
	if admitted.status != "queued":
		return "admission:" + admitted.status
	var result: Dictionary = m.step()
	if result.status != "advanced":
		return "tick:%s:%s" % [result.get("phase", ""), result.get("error", "")]
	return result.commands.filter(func(r): return r.command_id == id)[0].status

func advance(m: RefCounted, ticks: int) -> bool:
	for i in range(ticks):
		var result: Dictionary = m.step()
		if result.status != "advanced":
			printerr("step failed: " + str(result))
			return false
	return true

## Each tick replaces the authoritative state with a new copy: look cities and
## buildings up again after every step instead of holding references across ticks.
func city(m: RefCounted, seat: int) -> Dictionary:
	return m._state.cities[seat]

func building(m: RefCounted, seat: int, id: int) -> Dictionary:
	return Buildings.find(city(m, seat), id)

func first(m: RefCounted, seat: int, kind: String) -> Dictionary:
	return of_type(city(m, seat), kind)[0]

## Ledger-consistent edits: the opening balance absorbs the change.
static func set_cash(c: Dictionary, micro: int) -> void:
	c.finance.initial += micro - c.money_micro
	c.money_micro = micro

static func set_materials(c: Dictionary, micro: int) -> void:
	c.materials.initial += micro - c.materials_micro
	c.materials_micro = micro

static func add_street(c: Dictionary, amounts: Array) -> void:
	for i in range(3):
		c.street_micro[i] += amounts[i]
		c.waste.totals.generated += amounts[i]

## Adds a completed building on the next free plot, bypassing construction.
static func place(m: RefCounted, c: Dictionary, kind: String, size: String = "S") -> Dictionary:
	var building: Dictionary = Buildings.record(c.next_building_id, kind, size, m.buildings.next_tile(c), m._state.tick, true)
	c.next_building_id += 1
	c.buildings.append(building)
	return building

static func of_type(c: Dictionary, kind: String) -> Array:
	return c.buildings.filter(func(x): return x.type == kind)

## Marks a completed building as fully operating for direct stage calls.
static func operate(building: Dictionary, fraction: int = U) -> void:
	building.op = Buildings.idle()
	building.op.funded = true
	building.op.power_micro = fraction
	building.op.staff_micro = U
	building.op.fraction_micro = fraction
