extends RefCounted
## ECO EMERGENCIES: three short competitive recycling challenges per match, one per
## stage of the chain (collection, sorting, recycling), in a seeded random order.
##
## Timeline of one event, in ticks from its scheduled start S (all configurable):
##   [S, +announcement)        announcement   join allowed
##   [.., +join)               joining        join allowed
##   [.., +countdown)          countdown      join allowed
##   [C, C+active)             active         join and play; C is the active start
##   [E, E+results)            results        E = C + active; ranking frozen at tick E
##   after                     complete
## The city simulation never pauses. Every player gets the same challenge, generated
## from the event seed; the server validates each action against it and computes the
## score. Players' action times are milliseconds since the active start, accepted only
## inside a bounded window around the second the server received them (late by at
## most late_action_ms, early by at most early_action_ms), the same for everyone.
## The winner's boost multiplies one stage's processing rate for boost_seconds; it
## never creates waste or materials and needs that stage's own operating buildings.
const A = preload("res://simulation/core/arithmetic.gd")
const Random = preload("res://simulation/core/seeded_random.gd")
const Plant = preload("res://simulation/systems/plant_model.gd")

const TYPES = ["collection_crisis", "sorting_overload", "recycling_breakdown"]
const STAGES = {"collection_crisis": "collection", "sorting_overload": "sorting", "recycling_breakdown": "recycling"}
const COMMANDS = {"emergency_join": "", "emergency_route": "collection_crisis",
	"emergency_slice": "sorting_overload", "emergency_repair": "recycling_breakdown"}
## Waste items: kind -> category (0 recyclable, 1 organic, 2 residual).
const ROUTE_KINDS = {"plastic_bottle": 0, "aluminum_can": 0, "cardboard": 0, "glass_bottle": 0,
	"banana_peel": 1, "apple_core": 1, "food_scraps": 1,
	"dirty_tissue": 2, "greasy_packaging": 2, "mixed_waste": 2}
## Flying objects: kind -> 0 recyclable (slice), 1 contaminated (avoid), 2 hazardous (avoid).
const SLICE_KINDS = {"plastic_bottle": 0, "aluminum_can": 0, "cardboard": 0, "glass_bottle": 0,
	"greasy_packaging": 1, "battery": 2, "medical_waste": 2}
## Sorting play area: 1000 x 1000 units, y down; objects rise from below and fall back.
const FIELD = 1000
const LAUNCH_Y = 1080
const COMPONENTS = ["shredder", "filter", "press"]

var b: Dictionary
var _challenges: Dictionary = {}           # event seed -> generated challenge (pure cache)

func _init(config: Dictionary) -> void:
	b = config

# ---------------------------------------------------------------- schedule ---

## One event per type in a seeded permutation, one start per window. override, for
## tests and the server's developer mode only, fixes [{type, start}] instead.
static func create_state(seed_value: int, cfg: Dictionary, override: Array = []) -> Dictionary:
	var events: Array = []
	if not cfg.enabled:
		return {"events": events, "boosts": []}
	var rng = Random.new(seed_value * 7919 + 104729)
	var order: Array = TYPES.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.below(i + 1)
		var swap: Variant = order[i]
		order[i] = order[j]
		order[j] = swap
	var plan: Array = []
	if override.is_empty():
		for i in range(order.size()):
			var window: Array = cfg.windows[i]
			plan.append({"type": order[i], "start": window[0] + rng.below(window[1] - window[0] + 1)})
	else:
		plan = override
	for i in range(plan.size()):
		var players: Array = []
		for p in range(4):
			var player: Dictionary = {"joined": false, "joined_tick": -1, "score": 0, "correct": 0, "wrong": 0,
				"streak": 0, "best_streak": 0, "done": [], "rate_tick": -1, "rate_count": 0}
			if plan[i].type == "recycling_breakdown":
				player["plant"] = Plant.new_state()
			players.append(player)
		events.append({"id": "em%d" % (i + 1), "type": plan[i].type, "start": plan[i].start,
			"seed": rng.next_int(), "players": players, "result": null})
	return {"events": events, "boosts": []}

static func times(ev: Dictionary, cfg: Dictionary) -> Dictionary:
	var joining: int = ev.start + cfg.announcement
	var countdown: int = joining + cfg.join
	var active: int = countdown + cfg.countdown
	var end: int = active + cfg.active
	return {"start": ev.start, "joining": joining, "countdown": countdown, "active": active,
		"end": end, "complete": end + cfg.results}

static func phase(ev: Dictionary, tick: int, cfg: Dictionary) -> String:
	var t: Dictionary = times(ev, cfg)
	if tick < t.start:
		return "scheduled"
	if tick < t.joining:
		return "announcement"
	if tick < t.countdown:
		return "joining"
	if tick < t.active:
		return "countdown"
	if tick < t.end:
		return "active"
	if tick == t.end:
		return "finalizing"
	if tick < t.complete:
		return "results"
	return "complete"

## The event a view shows at this tick: the one between its start and the end of
## its results, if any.
static func current(state: Dictionary, cfg: Dictionary) -> Dictionary:
	for ev in state.emergencies.events:
		var p: String = phase(ev, state.tick, cfg)
		if p != "scheduled" and p != "complete":
			return ev
	return {}

static func find(state: Dictionary, id: Variant) -> Dictionary:
	for ev in state.emergencies.events:
		if ev.id == id:
			return ev
	return {}

# --------------------------------------------------------------- challenges ---

## The challenge every player of an event gets, from its seed alone.
func challenge(ev: Dictionary) -> Dictionary:
	var key: String = "%s:%d" % [ev.type, ev.seed]
	if not _challenges.has(key):
		var rng = Random.new(ev.seed)
		var p: Dictionary = b.emergencies.pacing[ev.type]
		var total: int = b.emergencies.active * 1000
		match ev.type:
			"collection_crisis":
				_challenges[key] = {"items": _route_items(rng, p, total)}
			"sorting_overload":
				_challenges[key] = {"objects": _slice_objects(rng, p, total)}
			_:
				_challenges[key] = {"faults": _faults(rng, p, total), "params": plant_params()}
	return _challenges[key]

## A pacing value by phase of the round: a before phase_b_ms, b before phase_c_ms, c after.
static func _phase_value(p: Dictionary, at: int, key: String) -> int:
	return p[key.replace("#", "a")] if at < p.phase_b_ms else (p[key.replace("#", "b")] if at < p.phase_c_ms else p[key.replace("#", "c")])

## Waste on the belt in three phases: single items far apart; then a faster belt
## with occasional close pairs; then the fastest belt with pairs and short bursts.
## Items in a pair or burst are never closer than pair_gap_ms (a finger apart).
static func _route_items(rng, p: Dictionary, total: int) -> Array:
	var kinds: Array = ROUTE_KINDS.keys()
	var items: Array = []
	var at: int = p.first_ms
	var last_kind: String = ""
	while at < total - 1500:
		var travel: int = _phase_value(p, at, "travel_#_ms")
		var count: int = 1
		if at >= p.phase_c_ms and rng.below(100) < p.burst_c_percent:
			count = 3
		elif at >= p.phase_b_ms and rng.below(100) < (p.pair_c_percent if at >= p.phase_c_ms else p.pair_b_percent):
			count = 2
		for k in range(count):
			var when: int = at + k * p.pair_gap_ms
			if when >= total - 1500:
				break
			var kind: String = kinds[rng.below(kinds.size())]
			if kind == last_kind:
				kind = kinds[(kinds.find(kind) + 1 + rng.below(kinds.size() - 1)) % kinds.size()]
			last_kind = kind
			items.append({"id": items.size(), "kind": kind, "spawn_ms": when, "travel_ms": travel})
		at += (count - 1) * p.pair_gap_ms + _phase_value(p, at, "gap_#_ms")
	return items

## Pattern families of the sorting line, by the phase they start in.
const PATTERNS = {"solo": 0, "double_toss": 0, "high_arc": 0, "recyclable_burst": 1, "hazard_mix": 1, "crossfire": 1,
	"speed_burst": 2, "precision_gap": 2}

## Sorting Overload's pattern director: seeded patterns of thrown objects, never the
## same pattern twice in a row. Every hazard or contaminated item keeps at least
## hazard_clearance from any recyclable in flight at the same moment (moved or, if
## no place works, dropped), so a careful swipe can always avoid it.
static func _slice_objects(rng, p: Dictionary, total: int) -> Array:
	var good: Array = SLICE_KINDS.keys().filter(func(k): return SLICE_KINDS[k] == 0)
	var objects: Array = []
	var at: int = p.first_ms
	var last: String = ""
	var last_phase: int = 0
	while at < total - 2300:
		var phase: int = 0 if at < p.phase_b_ms else (1 if at < p.phase_c_ms else 2)
		var choices: Array = PATTERNS.keys().filter(func(k): return PATTERNS[k] <= phase and k != last)
		# Newer families are favoured in their own phase.
		var weighted: Array = []
		for k in choices:
			for w in range(1 + (2 if PATTERNS[k] == phase and phase > 0 else 0) + (2 if k == "hazard_mix" else 0)):
				weighted.append(k)
		var pattern: String = weighted[rng.below(weighted.size())]
		# Each new phase opens with a hazard mix, so every round teaches what to avoid.
		if phase > last_phase and last != "hazard_mix":
			pattern = "hazard_mix"
		last_phase = phase
		last = pattern
		var flight: int = _phase_value(p, at, "flight_#_ms")
		var shots: Array = []          # [kind, launch, flight, x0, x1, apex]
		var g := func() -> String: return good[rng.below(good.size())]
		match pattern:
			"solo":
				var x: int = 180 + rng.below(641)
				shots.append([g.call(), at, flight, x, clampi(x + rng.below(241) - 120, 120, 880), 200 + rng.below(221)])
			"double_toss":
				var xl: int = 160 + rng.below(240)
				var xr: int = 600 + rng.below(240)
				var d: int = rng.below(251)
				shots.append([g.call(), at, flight, xl, xl + rng.below(121), 220 + rng.below(181)])
				shots.append([g.call(), at + d, flight, xr, xr - rng.below(121), 220 + rng.below(181)])
			"high_arc":
				var n: int = 1 + rng.below(2)
				for k in range(n):
					var x: int = 220 + rng.below(561)
					shots.append([g.call(), at + k * 400, flight * 5 / 4, x, clampi(x + rng.below(201) - 100, 120, 880), 120 + rng.below(61)])
			"recyclable_burst":
				var n: int = 3 + rng.below(2)
				var c: int = 380 + rng.below(241)
				for k in range(n):
					var spread: int = (k - (n - 1) / 2) * 140
					shots.append([g.call(), at + k * 110, flight, c + spread / 3, clampi(c + spread, 120, 880), 220 + rng.below(161)])
			"hazard_mix":
				var left: bool = rng.below(2) == 0
				for k in range(2):
					var x: int = (160 + rng.below(260)) if left else (580 + rng.below(260))
					shots.append([g.call(), at + k * 200, flight, x, clampi(x + rng.below(161) - 80, 120, 880), 220 + rng.below(181)])
				var xb: int = (600 + rng.below(240)) if left else (160 + rng.below(240))
				shots.append([_bad(rng, phase), at + 320, flight, xb, clampi(xb + rng.below(121) - 60, 120, 880), 240 + rng.below(161)])
			"crossfire":
				var apex: int = 240 + rng.below(141)
				shots.append([g.call(), at, flight, 140 + rng.below(80), 780 + rng.below(80), apex])
				shots.append([g.call(), at + rng.below(150), flight, 860 - rng.below(80), 220 - rng.below(80), apex + 60])
				if phase == 2 and rng.below(3) > 0:
					shots.append([_bad(rng, phase), at + 700, flight, 500 + rng.below(101) - 50, 500 + rng.below(101) - 50, 300 + rng.below(101)])
			"speed_burst":
				for k in range(3):
					var x: int = 180 + rng.below(641)
					shots.append([g.call(), at + k * 220, flight * 4 / 5, x, clampi(x + rng.below(201) - 100, 120, 880), 200 + rng.below(201)])
			"precision_gap":
				var a: int = 260 + rng.below(80)
				var z: int = 660 + rng.below(80)
				shots.append([g.call(), at, flight, a, a - rng.below(60), 230 + rng.below(121)])
				shots.append([g.call(), at, flight, z, z + rng.below(60), 230 + rng.below(121)])
				shots.append([_bad(rng, phase), at + 520, flight, (a + z) / 2, (a + z) / 2 + rng.below(81) - 40, 260 + rng.below(121)])
		# From the middle phase on, a lone item to avoid sometimes rides along on the
		# far side of an easy pattern.
		if phase > 0 and pattern in ["solo", "double_toss", "high_arc", "speed_burst"] and rng.below(100) < 25 + phase * 10:
			var side: int = shots[0][3]
			var xb: int = (620 + rng.below(220)) if side < 500 else (160 + rng.below(220))
			shots.append([_bad(rng, phase), at + 250 + rng.below(250), flight, xb, clampi(xb + rng.below(121) - 60, 120, 880), 240 + rng.below(181)])
		for shot in shots:
			var o: Dictionary = {"id": 0, "kind": shot[0], "pattern": pattern, "launch_ms": shot[1], "flight_ms": shot[2],
				"x0": shot[3], "x1": shot[4], "apex": shot[5], "spin": rng.below(7) - 3}
			# A recyclable thrown after an item to avoid steps out of its way (or is left out).
			if SLICE_KINDS[o.kind] == 0 and not _clear(o, objects, p.hazard_clearance):
				var moved: bool = false
				for tries in range(8):
					o.x0 = 140 + rng.below(721)
					o.x1 = clampi(o.x0 + rng.below(161) - 80, 120, 880)
					if _clear(o, objects, p.hazard_clearance):
						moved = true
						break
				if not moved:
					continue
			if SLICE_KINDS[o.kind] != 0 and not _clear(o, objects + _as_objects(shots, pattern), p.hazard_clearance):
				var placed: bool = false
				for tries in range(12):
					o.x0 = 140 + rng.below(721)
					if tries >= 4:
						o.launch_ms += 150
					o.x1 = clampi(o.x0 + rng.below(121) - 60, 120, 880)
					if o.launch_ms + o.flight_ms < total - 300 and _clear(o, objects + _as_objects(shots, pattern), p.hazard_clearance):
						placed = true
						break
				if not placed:
					continue
			o.id = objects.size()
			objects.append(o)
		at += _phase_value(p, at, "gap_#_ms") + (300 if pattern in ["recyclable_burst", "speed_burst", "precision_gap"] else 0)
	# Final fairness pass over the whole round: a later pattern may have thrown a
	# recyclable near an earlier hazard. Such an item moves to a clear spot or goes.
	var goods: Array = objects.filter(func(o): return SLICE_KINDS[o.kind] == 0)
	var kept: Array = []
	for o in objects:
		if SLICE_KINDS[o.kind] != 0 and not _clear(o, goods, p.hazard_clearance):
			var placed: bool = false
			for tries in range(12):
				o.x0 = 140 + rng.below(721)
				if tries >= 4:
					o.launch_ms += 150
				o.x1 = clampi(o.x0 + rng.below(121) - 60, 120, 880)
				if o.launch_ms + o.flight_ms < total - 300 and _clear(o, goods, p.hazard_clearance):
					placed = true
					break
			if not placed:
				continue
		kept.append(o)
	kept.sort_custom(func(x, y): return x.launch_ms < y.launch_ms if x.launch_ms != y.launch_ms else x.id < y.id)
	for i in range(kept.size()):
		kept[i].id = i
	return kept

static func _bad(rng, phase: int) -> String:
	if rng.below(100) < 35 + phase * 10:
		return "battery" if rng.below(2) == 0 else "medical_waste"
	return "greasy_packaging"

static func _as_objects(shots: Array, pattern: String) -> Array:
	return shots.filter(func(s): return SLICE_KINDS[s[0]] == 0).map(func(s):
		return {"kind": s[0], "pattern": pattern, "launch_ms": s[1], "flight_ms": s[2], "x0": s[3], "x1": s[4], "apex": s[5]})

## True when the object never comes within clearance of an object of the other
## class (a recyclable for an item to avoid, and the reverse) while both are in reach.
static func _clear(o: Dictionary, others: Array, clearance: int) -> bool:
	var bad: bool = SLICE_KINDS[o.kind] != 0
	for other in others:
		if (SLICE_KINDS[other.kind] != 0) == bad:
			continue
		var t: int = maxi(o.launch_ms, other.launch_ms)
		var end: int = mini(o.launch_ms + o.flight_ms, other.launch_ms + other.flight_ms)
		while t <= end:
			var a: Variant = position(o, t)
			var c: Variant = position(other, t)
			# Only where a swipe can reach: both on screen (below the field nobody can cut).
			if a != null and c != null and (a as Vector2).y < FIELD - 40 and (c as Vector2).y < FIELD - 40 and (a as Vector2).distance_to(c) < clearance:
				return false
			t += 50
	return true

## Faults of the recycling line: shredder jams, filter pressure surges and press
## drifts, sparse while the player learns, then overlapping on different machines.
static func _faults(rng, p: Dictionary, total: int) -> Array:
	var faults: Array = []
	var at: int = p.jam_first_ms
	while at < total - 2500:
		faults.append({"at_ms": at, "machine": 0, "dir": rng.below(4), "dist": p.jam_dist_min + rng.below(p.jam_dist_max - p.jam_dist_min + 1), "amount": 0, "rate": 0})
		at += _phase_value(p, at, "jam_gap_#_ms") + rng.below(801)
	at = p.surge_first_ms
	while at < total - 2500:
		faults.append({"at_ms": at, "machine": 1, "dir": 0, "dist": 0, "amount": p.surge_amount + rng.below(61), "rate": 0})
		at += (p.surge_gap_b_ms if at < p.phase_c_ms else p.surge_gap_c_ms) + rng.below(601)
	at = p.drift_first_ms
	while at < total - 2500:
		var rate: int = (p.drift_rate + rng.below(61)) * (1 if rng.below(2) == 0 else -1)
		faults.append({"at_ms": at, "machine": 2, "dir": 0, "dist": 0, "amount": 0, "rate": rate})
		at += (p.drift_gap_b_ms if at < p.phase_c_ms else p.drift_gap_c_ms) + rng.below(701)
	faults.sort_custom(func(x, y): return x.at_ms < y.at_ms if x.at_ms != y.at_ms else x.machine < y.machine)
	for i in range(faults.size()):
		faults[i]["id"] = i
	return faults

## The plant model's parameters for this match: pacing plus the round length.
func plant_params() -> Dictionary:
	var p: Dictionary = b.emergencies.pacing.recycling_breakdown.duplicate()
	p["active_ms"] = b.emergencies.active * 1000
	return p

## Where a flying object is at ms since the active start, or null when not in flight.
static func position(o: Dictionary, ms: int) -> Variant:
	var t: int = ms - o.launch_ms
	if t < 0 or t > o.flight_ms:
		return null
	var u: float = float(t) / float(o.flight_ms)
	return Vector2(o.x0 + (o.x1 - o.x0) * u, LAUNCH_Y - 4.0 * (LAUNCH_Y - o.apex) * u * (1.0 - u))

# ------------------------------------------------------------------ commands ---

func validate(state: Dictionary, command: Dictionary) -> String:
	return _apply(state, command, false)

func execute(state: Dictionary, command: Dictionary) -> String:
	return _apply(state, command, true)

func _apply(state: Dictionary, command: Dictionary, commit: bool) -> String:
	var cfg: Dictionary = b.emergencies
	var p: Dictionary = command.payload
	if typeof(p.get("event")) != TYPE_STRING:
		return "invalid_payload"
	var ev: Dictionary = find(state, p.event)
	if ev.is_empty():
		return "unknown_event"
	var ph: String = phase(ev, state.tick, cfg)
	var me: Dictionary = ev.players[command.player_id]
	if command.command_type == "emergency_join":
		if p.size() != 1:
			return "invalid_payload"
		if ph not in ["announcement", "joining", "countdown", "active"]:
			return "event_not_open" if ph == "scheduled" else "event_closed"
		if me.joined:
			return "already_joined"
		if commit:
			me.joined = true
			me.joined_tick = state.tick
		return ""
	if COMMANDS.get(command.command_type, "") != ev.type:
		return "wrong_event_type"
	if not me.joined:
		return "not_participating"
	var t: Dictionary = times(ev, cfg)
	if state.tick < t.active:
		return "event_not_active"
	if state.tick > t.end:
		return "event_closed"
	if typeof(p.get("t_ms")) != TYPE_INT:
		return "invalid_payload"
	# Bounded latency compensation, identical for every player.
	var second: int = (state.tick - t.active) * 1000
	if p.t_ms < 0 or p.t_ms >= cfg.active * 1000 or p.t_ms > second + 1000 + cfg.early_ms or p.t_ms < second - cfg.late_ms:
		return "action_out_of_time"
	if me.rate_tick == state.tick and me.rate_count >= cfg.max_actions:
		return "rate_limited"
	if command.command_type == "emergency_repair":
		var error: String = _repair(ev, me, p, commit)
		if error.is_empty() and commit:
			me.rate_count = me.rate_count + 1 if me.rate_tick == state.tick else 1
			me.rate_tick = state.tick
		return error
	var outcome: Array
	match command.command_type:
		"emergency_route":
			outcome = _route(ev, me, p)
		_:
			outcome = _slice(ev, me, p)
	if outcome[0] != "":
		return outcome[0]
	if commit:
		me.rate_count = me.rate_count + 1 if me.rate_tick == state.tick else 1
		me.rate_tick = state.tick
		_score(ev, me, outcome[1], outcome[2])
	return ""

## [error, kind ("correct" / "incorrect" / "hazard" / "neutral"), id to mark done or -1]
func _route(ev: Dictionary, me: Dictionary, p: Dictionary) -> Array:
	if p.size() != 4 or typeof(p.get("item")) != TYPE_INT or typeof(p.get("bin")) != TYPE_INT:
		return ["invalid_payload"]
	var items: Array = challenge(ev).items
	if p.item < 0 or p.item >= items.size():
		return ["invalid_object"]
	if p.bin < 0 or p.bin > 2:
		return ["invalid_choice"]
	if p.item in me.done:
		return ["already_processed"]
	var item: Dictionary = items[p.item]
	if p.t_ms < item.spawn_ms or p.t_ms > item.spawn_ms + item.travel_ms:
		return ["object_not_available"]
	return ["", "correct" if ROUTE_KINDS[item.kind] == p.bin else "incorrect", p.item]

func _slice(ev: Dictionary, me: Dictionary, p: Dictionary) -> Array:
	if p.size() != 7 or typeof(p.get("item")) != TYPE_INT:
		return ["invalid_payload"]
	for k in ["x1", "y1", "x2", "y2"]:
		if typeof(p.get(k)) != TYPE_INT or p[k] < -300 or p[k] > FIELD + 300:
			return ["invalid_payload"]
	var objects: Array = challenge(ev).objects
	if p.item < 0 or p.item >= objects.size():
		return ["invalid_object"]
	if p.item in me.done:
		return ["already_processed"]
	var o: Dictionary = objects[p.item]
	var a := Vector2(p.x1, p.y1)
	var z := Vector2(p.x2, p.y2)
	if a.distance_to(z) > 700.0:
		return ["invalid_swipe"]
	# The swipe segment must cross the object near the time the player gave, which
	# tolerates a frame either side; a pass anywhere else is not a hit.
	var hit: bool = false
	for dt in [-60, -30, 0, 30, 60]:
		var at: Variant = position(o, p.t_ms + dt)
		if at != null and Geometry2D.get_closest_point_to_segment(at, a, z).distance_to(at) <= float(b.emergencies.pacing.sorting_overload.hit_radius):
			hit = true
			break
	if not hit:
		return ["no_hit"]
	var cls: int = SLICE_KINDS[o.kind]
	return ["", "correct" if cls == 0 else ("incorrect" if cls == 1 else "hazard"), p.item]

## A recycling intervention: the player's line is advanced to the action's time and
## the action applied there. Actions cannot go back before what is already simulated,
## and an action with nothing to fix is refused without effect, so repairs cannot be
## farmed; the score is the line's own (repairs, wrong moves, uptime, sustained bonus).
func _repair(ev: Dictionary, me: Dictionary, p: Dictionary, commit: bool) -> String:
	if p.size() != 4 or typeof(p.get("machine")) != TYPE_INT or typeof(p.get("answer")) != TYPE_INT:
		return "invalid_payload"
	if p.machine < 0 or p.machine > 2:
		return "invalid_choice"
	var plant: Dictionary = me.plant if commit else me.plant.duplicate(true)
	if p.t_ms < plant.sim_ms:
		return "action_out_of_time"
	var c: Dictionary = challenge(ev)
	Plant.advance(plant, c.faults, c.params, b.emergencies.scoring[ev.type], p.t_ms)
	var outcome: String = Plant.act(plant, c.params, p.machine, p.answer, p.t_ms)
	if outcome in ["no_fault", "invalid_choice"]:
		return outcome
	if commit:
		_plant_score(ev, me)
	return ""

func _plant_score(ev: Dictionary, me: Dictionary) -> void:
	var sc: Dictionary = b.emergencies.scoring[ev.type]
	me.score = Plant.score(me.plant, sc)
	me.correct = me.plant.repairs
	me.wrong = me.plant.wrong
	me.streak = me.plant.high_ms / 1000

## Validated outcome -> score. Never below zero; a streak bonus every N in a row.
func _score(ev: Dictionary, me: Dictionary, kind: String, done: int) -> void:
	var s: Dictionary = b.emergencies.scoring[ev.type]
	if done >= 0:
		me.done.append(done)
	if kind == "correct":
		me.correct += 1
		me.streak += 1
		me.best_streak = maxi(me.best_streak, me.streak)
		me.score += s.correct + (s.streak_bonus if me.streak % s.streak == 0 else 0)
	else:
		me.wrong += 1
		me.streak = 0
		me.score = maxi(0, me.score - (s.hazard if kind == "hazard" else s.incorrect))

# --------------------------------------------------------------------- phase ---

## Phase: at the tick an event's play ends, rank its participants and give the
## winner the stage's boost from the next tick. Expired boosts are dropped.
func update(state: Dictionary, _ctx: Dictionary) -> String:
	var cfg: Dictionary = b.emergencies
	var em: Dictionary = state.emergencies
	em.boosts = em.boosts.filter(func(x): return x.end > state.tick)
	for ev in em.events:
		var ph: String = phase(ev, state.tick, cfg)
		if ev.type == "recycling_breakdown" and ph in ["active", "finalizing"] and ev.result == null:
			var c: Dictionary = challenge(ev)
			var t: Dictionary = times(ev, cfg)
			var upto: int = cfg.active * 1000 if ph == "finalizing" else (state.tick - t.active) * 1000 - cfg.late_ms
			for me in ev.players:
				if me.joined and upto > me.plant.sim_ms:
					Plant.advance(me.plant, c.faults, c.params, cfg.scoring[ev.type], upto)
					_plant_score(ev, me)
		if ev.result != null or ph != "finalizing":
			continue
		var ranking: Array = ranking_of(ev)
		var winner: int = ranking[0] if not ranking.is_empty() and ev.players[ranking[0]].score > 0 else -1
		var shared: int = 0
		for pl in ev.players:
			shared += pl.correct
		ev.result = {"ranking": ranking, "winner": winner, "shared": shared, "tick": state.tick}
		if winner >= 0:
			var stage: String = STAGES[ev.type]
			# A new boost of the same stage replaces the old one; it never stacks.
			em.boosts = em.boosts.filter(func(x): return not (x.player == winner and x.stage == stage))
			em.boosts.append({"player": winner, "stage": stage, "multiplier_micro": cfg.multipliers[ev.type],
				"start": state.tick + 1, "end": state.tick + 1 + cfg.boost, "source": ev.id})
	return ""

## Participants by score, then fewest wrong actions, most correct ones, seat order.
static func ranking_of(ev: Dictionary) -> Array:
	var ids: Array = range(4).filter(func(i): return ev.players[i].joined)
	ids.sort_custom(func(x, y):
		var a: Dictionary = ev.players[x]
		var c: Dictionary = ev.players[y]
		if a.score != c.score:
			return a.score > c.score
		if a.wrong != c.wrong:
			return a.wrong < c.wrong
		if a.correct != c.correct:
			return a.correct > c.correct
		return x < y)
	return ids

## The rate multiplier of a city's stage this tick (A.S when no boost is active).
static func multiplier(state: Dictionary, city_id: int, stage: String) -> int:
	for x in state.emergencies.boosts:
		if x.player == city_id and x.stage == stage and x.start <= state.tick and state.tick < x.end:
			return x.multiplier_micro
	return A.S

## What one seat sees. The challenge is sent from the announcement to the end of
## the results, so every client draws the same items at the same times.
func view(state: Dictionary, seat: int) -> Dictionary:
	var cfg: Dictionary = b.emergencies
	var boosts: Array = state.emergencies.boosts.filter(func(x): return x.player == seat).map(func(x):
		return {"stage": x.stage, "multiplier_micro": x.multiplier_micro, "start": x.start, "end": x.end, "source": x.source})
	var ev: Dictionary = current(state, cfg)
	if ev.is_empty():
		return {"event": null, "own": null, "boosts": boosts}
	var t: Dictionary = times(ev, cfg)
	var board: Array = []
	var shared: int = 0
	for i in range(4):
		var pl: Dictionary = ev.players[i]
		shared += pl.correct
		board.append({"city_id": i, "joined": pl.joined, "score": pl.score, "correct": pl.correct, "wrong": pl.wrong, "streak": pl.streak})
	var me: Dictionary = ev.players[seat]
	var event: Dictionary = {"id": ev.id, "type": ev.type, "phase": phase(ev, state.tick, cfg), "start": t.start, "joining": t.joining,
		"countdown": t.countdown, "active": t.active, "end": t.end, "complete": t.complete, "challenge": challenge(ev).duplicate(true),
		"leaderboard": board, "shared": shared, "result": ev.result.duplicate(true) if ev.result != null else null,
		"multiplier_micro": cfg.multipliers[ev.type], "boost_seconds": cfg.boost, "late_ms": cfg.late_ms,
		"scoring": cfg.scoring[ev.type].duplicate(), "pacing": cfg.pacing[ev.type].duplicate()}
	var own: Dictionary = {"joined": me.joined, "score": me.score, "correct": me.correct, "wrong": me.wrong,
		"streak": me.streak, "best_streak": me.best_streak, "done": me.done.duplicate()}
	if me.has("plant"):
		own["plant"] = me.plant.duplicate()
	return {"event": event, "own": own, "boosts": boosts}

static func validate_state(state: Dictionary, cfg: Dictionary) -> String:
	var em: Variant = state.get("emergencies")
	if not em is Dictionary or not em.get("events") is Array or not em.get("boosts") is Array:
		return "emergency_state"
	for ev in em.events:
		if ev.type not in TYPES or ev.players.size() != 4:
			return "emergency_event"
		for pl in ev.players:
			if pl.score < 0 or pl.correct < 0 or pl.wrong < 0 or pl.streak < 0 or (not pl.joined and (pl.score != 0 or not pl.done.is_empty())):
				return "emergency_score"
			if pl.has("plant") and (pl.plant.sim_ms < 0 or pl.plant.sim_ms > cfg.active * 1000 or pl.plant.pressure < 0 or pl.plant.pressure > 1000 \
					or pl.plant.align < 0 or pl.plant.align > 1000 or pl.plant.line < 0 or pl.plant.line > 1000):
				return "emergency_plant"
	var seen: Dictionary = {}
	for x in em.boosts:
		var key: String = "%d:%s" % [x.player, x.stage]
		if seen.has(key) or x.end - x.start != cfg.boost or x.multiplier_micro <= 0:
			return "emergency_boost"
		seen[key] = true
	return ""
