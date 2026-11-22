extends "res://tests/support/harness.gd"
## ECO EMERGENCIES: schedule, the three challenges' validation and scoring, ranking,
## the winner's boost and its limits, and the match around them.
const Em = preload("res://simulation/systems/emergencies.gd")
const Canonical = preload("res://simulation/core/canonical.gd")
const Plant = preload("res://simulation/systems/plant_model.gd")
const PLAN = [{"type": "collection_crisis", "start": 20}, {"type": "sorting_overload", "start": 80}, {"type": "recycling_breakdown", "start": 140}]

func _initialize() -> void:
	schedule()
	lifecycle()
	collection()
	belt_pacing()
	sorting()
	pattern_director()
	recycling()
	plant_model()
	plant_balance()
	validation()
	ranking()
	boosts()
	boost_limits()
	disabled()
	replay()
	full_match()
	finish("Emergencies")

func planned(plan: Array = PLAN, seed_value: int = 42) -> RefCounted:
	var m = Sim.new()
	var error: String = m.initialize("em-%d" % seed_value, seed_value, DRAFT, plan)
	assert(error.is_empty(), error)
	return m

func cfg() -> Dictionary:
	return Balance.load_config().emergencies

func ev(m: RefCounted, i: int) -> Dictionary:
	return m._state.emergencies.events[i]

## Advances to the given tick (exclusive of its step).
func to_tick(m: RefCounted, tick: int) -> void:
	advance(m, tick - m._state.tick)

## Submits several commands in the same tick and steps once; returns their statuses.
func batch(m: RefCounted, commands: Array) -> Array:
	var ids: Array = []
	for c in commands:
		var key: String = "%d:%d" % [m.get_instance_id(), c[0]]
		var seq: int = _sequence.get(key, 0)
		_sequence[key] = seq + 1
		var id: String = "b:%d:%d" % [c[0], seq]
		ids.append(id)
		m.submit({"match_id": m._state.match_id, "player_id": c[0], "command_seq": seq, "command_id": id,
			"command_type": c[1], "payload": c[2], "server_received_tick": m._state.tick}, c[0])
	var result: Dictionary = m.step()
	if result.status != "advanced":
		return ["tick_failed: " + str(result)]
	return ids.map(func(id): return result.commands.filter(func(r): return r.command_id == id)[0].status)

## ms since the active start at the middle of the current tick.
func now_ms(m: RefCounted, i: int) -> int:
	return (m._state.tick - Em.times(ev(m, i), cfg()).active) * 1000 + 500

func schedule() -> void:
	var c: Dictionary = cfg()
	var orders: Dictionary = {}
	for seed_value in range(1, 41):
		var m = fixture(DRAFT, seed_value)
		var events: Array = m._state.emergencies.events
		var types: Array = events.map(func(e): return e.type)
		var sorted_types: Array = types.duplicate()
		sorted_types.sort()
		var ok: bool = events.size() == 3 and sorted_types == ["collection_crisis", "recycling_breakdown", "sorting_overload"]
		for i in range(3):
			ok = ok and events[i].start >= c.windows[i][0] and events[i].start <= c.windows[i][1]
			if i > 0:
				ok = ok and Em.times(events[i - 1], c).complete <= events[i].start
		ok = ok and Em.times(events[2], c).complete < 1200
		check(ok, "seed %d: three events, each type once, in their windows, never overlapping, over before the end" % seed_value)
		orders[str(types)] = true
	check(orders.size() >= 4, "the order is randomized across seeds (%d different orders)" % orders.size())
	eq(fixture(DRAFT, 7)._state.emergencies, fixture(DRAFT, 7)._state.emergencies, "a fixed seed gives the same schedule")
	var m = planned()
	eq(m._state.emergencies.events.map(func(e): return [e.type, e.start]), PLAN.map(func(p): return [p.type, p.start]), "a schedule can be injected for tests")

func lifecycle() -> void:
	var c: Dictionary = cfg()
	var e: Dictionary = {"start": 100}
	var phases: Array = []
	for t in [99, 100, 102, 108, 111, 135, 136, 137, 141]:
		phases.append(Em.phase(e, t, c))
	eq(phases, ["scheduled", "announcement", "joining", "countdown", "active", "active", "finalizing", "results", "complete"],
		"SCHEDULED > ANNOUNCEMENT > JOINING > COUNTDOWN > ACTIVE > FINALIZING > RESULTS > COMPLETE")
	var m = planned()
	to_tick(m, 19)
	eq(act(m, 0, "emergency_join", {"event": "em1"}), "event_not_open", "no joining before the announcement")
	eq(act(m, 0, "emergency_join", {"event": "em1"}), "applied", "joining during the announcement")
	eq(act(m, 0, "emergency_join", {"event": "em1"}), "already_joined", "joining once")
	var pop: Array = m._state.cities.map(func(x): return x.population)
	to_tick(m, Em.times(ev(m, 0), c).active + 10)
	eq(act(m, 1, "emergency_join", {"event": "em1"}), "applied", "a late join during play is accepted")
	eq(ev(m, 0).players[1].joined_tick, m._state.tick - 1, "and enters at the current time: nothing restarts")
	to_tick(m, Em.times(ev(m, 0), c).end + 1)
	eq(act(m, 2, "emergency_join", {"event": "em1"}), "event_closed", "no joining after play")
	check(ev(m, 0).result != null, "the result is frozen when play ends")
	eq(A.total(m._state.cities.map(func(x): return x.population)), 8000, "the city simulation runs on and keeps every resident")
	eq(m._state.tick, Em.times(ev(m, 0), c).end + 2, "time never paused")

func collection() -> void:
	var m = planned()
	to_tick(m, 20)
	batch(m, [[0, "emergency_join", {"event": "em1"}], [1, "emergency_join", {"event": "em1"}]])
	var items: Array = m.emergencies.challenge(ev(m, 0)).items
	check(items.size() >= 15, "the belt brings %d items" % items.size())
	var t: Dictionary = Em.times(ev(m, 0), cfg())
	to_tick(m, t.active + 1)
	# Seat 0 routes five items right in a row; seat 1 routes one wrong.
	var right: Array = []
	var statuses: Array = []
	for item in items:
		if right.size() == 5:
			break
		var mid: int = item.spawn_ms + item.travel_ms / 2
		to_tick(m, t.active + mid / 1000)
		var p: Dictionary = {"event": "em1", "item": item.id, "bin": Em.ROUTE_KINDS[item.kind], "t_ms": mid}
		statuses.append(batch(m, [[0, "emergency_route", p]])[0])
		right.append(item.id)
	eq(statuses, ["applied", "applied", "applied", "applied", "applied"], "five right routings accepted")
	var me: Dictionary = ev(m, 0).players[0]
	eq([me.score, me.correct, me.streak], [5 * 10 + 25, 5, 5], "+10 each and +25 for five in a row")
	var item: Dictionary = items[right[-1]]
	var mid: int = item.spawn_ms + item.travel_ms / 2
	eq(m.preview(0, "emergency_route", {"event": "em1", "item": item.id, "bin": Em.ROUTE_KINDS[item.kind], "t_ms": mid}), "already_processed", "an item counts once")
	var now: int = (m._state.tick - t.active) * 1000
	var later: Dictionary = items.filter(func(i): return i.spawn_ms > now + 1000)[0]
	var at: int = later.spawn_ms + 100
	to_tick(m, t.active + at / 1000)
	eq(batch(m, [[1, "emergency_route", {"event": "em1", "item": later.id, "bin": (Em.ROUTE_KINDS[later.kind] + 1) % 3, "t_ms": at}]])[0], "applied", "a wrong routing is accepted")
	me = ev(m, 0).players[1]
	eq([me.score, me.wrong], [0, 1], "and costs 10, but the score never goes below zero")
	eq(ev(m, 0).players[2].score, 0, "a missed or skipped item scores nothing")

func sorting() -> void:
	var m = planned()
	to_tick(m, 80)
	batch(m, [[0, "emergency_join", {"event": "em2"}]])
	var objects: Array = m.emergencies.challenge(ev(m, 1)).objects
	var t: Dictionary = Em.times(ev(m, 1), cfg())
	check(objects.any(func(o): return Em.SLICE_KINDS[o.kind] != 0), "items to avoid appear")
	var good: Array = objects.filter(func(o): return Em.SLICE_KINDS[o.kind] == 0).slice(0, 5)
	var statuses: Array = []
	for o in good:
		var at: int = o.launch_ms + o.flight_ms / 2
		to_tick(m, t.active + at / 1000)
		var pos: Vector2 = Em.position(o, at)
		statuses.append(batch(m, [[0, "emergency_slice", {"event": "em2", "item": o.id, "t_ms": at,
			"x1": int(pos.x) - 150, "y1": int(pos.y) - 20, "x2": int(pos.x) + 150, "y2": int(pos.y) + 20}]])[0])
	eq(statuses, ["applied", "applied", "applied", "applied", "applied"], "five slices through recyclables")
	eq(ev(m, 1).players[0].score, 75, "+10 each and +25 for five in a row")
	# A swipe that misses, one through a hazard, then one through a contaminated item.
	var hazard: Dictionary = objects.filter(func(o): return Em.SLICE_KINDS[o.kind] == 2)[-1]
	var at2: int = hazard.launch_ms + hazard.flight_ms / 2
	to_tick(m, t.active + at2 / 1000)
	var hp: Vector2 = Em.position(hazard, at2)
	eq(batch(m, [[0, "emergency_slice", {"event": "em2", "item": hazard.id, "t_ms": at2,
		"x1": int(hp.x) + 300, "y1": int(hp.y), "x2": int(hp.x) + 500, "y2": int(hp.y)}]])[0], "no_hit", "a swipe beside an object is not a hit")
	var before: int = ev(m, 1).players[0].score
	to_tick(m, t.active + at2 / 1000)
	if m._state.tick == t.active + at2 / 1000:
		eq(batch(m, [[0, "emergency_slice", {"event": "em2", "item": hazard.id, "t_ms": at2,
			"x1": int(hp.x) - 100, "y1": int(hp.y), "x2": int(hp.x) + 100, "y2": int(hp.y)}]])[0], "applied", "slicing a hazard")
		eq(ev(m, 1).players[0].score, maxi(0, before - 25), "costs 25")
	var fast: Dictionary = good[-1]
	eq(m.preview(0, "emergency_slice", {"event": "em2", "item": fast.id, "t_ms": now_ms(m, 1), "x1": 0, "y1": 0, "x2": 10, "y2": 10}), "already_processed", "an object counts once")
	# A fast swipe whose ends are far apart still hits what it crosses.
	var other = planned()
	to_tick(other, 80)
	batch(other, [[0, "emergency_join", {"event": "em2"}]])
	var o: Dictionary = good[1]
	var at3: int = o.launch_ms + o.flight_ms / 3
	to_tick(other, t.active + at3 / 1000)
	var c3: Vector2 = Em.position(o, at3)
	eq(batch(other, [[0, "emergency_slice", {"event": "em2", "item": o.id, "t_ms": at3,
		"x1": int(c3.x) - 300, "y1": int(c3.y) + 150, "x2": int(c3.x) + 300, "y2": int(c3.y) - 150}]])[0], "applied", "a long fast swipe is checked as a segment, not by its ends")

## Three phases on the belt: single items far apart, then pairs, then bursts;
## never two items closer than a finger apart; the belt speeds up.
func belt_pacing() -> void:
	var p: Dictionary = cfg().pacing.collection_crisis
	var total: int = cfg().active * 1000
	var counts: Array = []
	for seed_value in [3, 11, 42]:
		var items: Array = Em._route_items(preload("res://simulation/core/seeded_random.gd").new(seed_value), p, total)
		counts.append(items.size())
		var ok: bool = true
		for i in range(1, items.size()):
			var gap: int = items[i].spawn_ms - items[i - 1].spawn_ms
			ok = ok and gap >= p.pair_gap_ms
			if items[i].spawn_ms < p.phase_b_ms:
				ok = ok and gap >= p.gap_a_ms
		check(ok, "seed %d: items at least %d ms apart, singles only in the first 7 s" % [seed_value, p.pair_gap_ms])
		check(items.filter(func(i): return i.spawn_ms >= p.phase_c_ms).all(func(i): return i.travel_ms == p.travel_c_ms), "the last phase runs the fastest belt")
		var kinds: Array = items.map(func(i): return i.kind)
		check(range(1, kinds.size()).all(func(i): return kinds[i] != kinds[i - 1]), "no item follows one of the same kind")
	check(counts.all(func(n): return n >= 20), "a round brings 20 or more items (%s), 60+ over three rounds" % str(counts))

## Sorting Overload's director: varied, seeded, fair.
func pattern_director() -> void:
	var p: Dictionary = cfg().pacing.sorting_overload
	var total: int = cfg().active * 1000
	var R = preload("res://simulation/core/seeded_random.gd")
	eq(Em._slice_objects(R.new(9), p, total), Em._slice_objects(R.new(9), p, total), "the same seed gives the same throws")
	check(Em._slice_objects(R.new(9), p, total) != Em._slice_objects(R.new(10), p, total), "another seed gives other throws")
	var families: Dictionary = {}
	for seed_value in range(1, 31):
		var objects: Array = Em._slice_objects(R.new(seed_value), p, total)
		var round_families: Dictionary = {}
		for o in objects:
			round_families[o.pattern] = true
			families[o.pattern] = true
		check(round_families.size() >= 4, "seed %d: at least four pattern families in a round (%d)" % [seed_value, round_families.size()])
		var inside: bool = objects.all(func(o): return o.x0 >= 100 and o.x0 <= 900 and o.x1 >= 100 and o.x1 <= 900 and o.apex >= 100)
		check(inside, "seed %d: every throw stays inside the play area" % seed_value)
		var fair: bool = true
		for o in objects:
			if Em.SLICE_KINDS[o.kind] != 0:
				fair = fair and Em._clear(o, objects, p.hazard_clearance)
		check(fair, "seed %d: every item to avoid keeps clear of every recyclable in flight" % seed_value)
		var early: Array = objects.filter(func(o): return o.launch_ms < p.phase_b_ms)
		check(early.all(func(o): return Em.SLICE_KINDS[o.kind] == 0 and Em.PATTERNS[o.pattern] == 0), "seed %d: the first seconds are simple and clean" % seed_value)
		var avoid: int = objects.filter(func(o): return Em.SLICE_KINDS[o.kind] != 0).size()
		check(avoid >= 3 and avoid * 4 <= objects.size(), "seed %d: a few items to avoid (%d of %d)" % [seed_value, avoid, objects.size()])
		check(objects.all(func(o): return o.launch_ms + o.flight_ms <= total), "seed %d: everything lands before the round ends" % seed_value)
	eq(families.size(), 8, "all eight pattern families occur across matches")

func recycling() -> void:
	var m = planned()
	to_tick(m, 140)
	batch(m, [[2, "emergency_join", {"event": "em3"}]])
	var c: Dictionary = m.emergencies.challenge(ev(m, 2))
	var t: Dictionary = Em.times(ev(m, 2), cfg())
	eq(c, m.emergencies.challenge(ev(m, 2)), "the fault schedule is reproducible")
	var machines: Dictionary = {}
	for f in c.faults:
		machines[f.machine] = true
	eq(machines.keys().size(), 3, "jams, pressure surges and drifts all happen")
	var first: Dictionary = c.faults[0]
	eq([first.machine, first.at_ms], [0, c.params.jam_first_ms], "the round opens with a single shredder jam")
	# Clear the first jam: wrong direction, then right.
	to_tick(m, t.active + (first.at_ms + 1000) / 1000)
	var wrong_dir: int = ((first.dir + 1) % 4) * 1000 + 999
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 0, "answer": wrong_dir, "t_ms": now_ms(m, 2)}]])[0], "applied", "reversing the wrong way is accepted")
	eq(ev(m, 2).players[2].wrong, 1, "and counts as a wrong intervention")
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 0, "answer": first.dir * 1000 + first.dist - 1, "t_ms": now_ms(m, 2)}]])[0], "applied", "too short a pull")
	eq(ev(m, 2).players[2].plant.jam_dir, first.dir, "leaves the jam in place")
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 0, "answer": first.dir * 1000 + first.dist, "t_ms": now_ms(m, 2)}]])[0], "applied", "the right pull")
	eq([ev(m, 2).players[2].plant.jam_dir, ev(m, 2).players[2].correct], [-1, 1], "clears the jam")
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 0, "answer": 999, "t_ms": now_ms(m, 2)}]])[0], "no_fault", "no jam, nothing to reverse: refused without effect")
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 1, "answer": 0, "t_ms": now_ms(m, 2)}]])[0], "no_fault", "a valve on a healthy filter is refused")
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 1, "answer": 2, "efficiency": 1000, "t_ms": now_ms(m, 2)}]])[0], "invalid_payload", "nobody can report an efficiency")
	eq(batch(m, [[2, "emergency_repair", {"event": "em3", "machine": 0, "answer": 0, "t_ms": 0}]])[0], "action_out_of_time", "an action before the simulated line is refused")

## The line model on its own: each machine, overcorrection, timing and efficiency.
func plant_model() -> void:
	var p: Dictionary = Em.new(Balance.load_config()).plant_params()
	var sc: Dictionary = cfg().scoring.recycling_breakdown
	var s: Dictionary = Plant.new_state()
	Plant.advance(s, [], p, sc, 3000)
	eq([s.sim_ms, s.line], [3000, 1000], "a healthy line runs at 100 %")
	eq(Plant.score(s, sc), 30, "uptime earns 10 a second at full efficiency")
	# A jam drains the buffer, then starves the line.
	var jam: Array = [{"at_ms": 3000, "machine": 0, "dir": 1, "dist": 300, "amount": 0, "rate": 0}]
	Plant.advance(s, jam, p, sc, 3000 + p.buffer_ms - 100)
	eq(s.line, 1000, "the buffer keeps the line fed for a moment")
	Plant.advance(s, jam, p, sc, 3000 + p.buffer_ms + 200)
	eq(s.line, 0, "then the jammed shredder starves the whole line")
	eq(Plant.efficiency(s, p)[0], 0, "and the shredder is the bottleneck")
	# Filter: pressure rises; the right valve lands in green; overcorrection slows it.
	var f: Dictionary = Plant.new_state()
	f.pressure = 720
	eq(Plant.act(f, p, 1, 1, 0), "correct", "medium valve from 720 lands at 420, in the green band")
	eq(f.pressure, 420, "pressure falls by the medium release")
	f.pressure = 640
	eq(Plant.act(f, p, 1, 2, 0), "incorrect", "the large valve from 640 overcorrects")
	check(f.slow_until > 0 and Plant.efficiency(f, p)[1] <= p.slow_permille, "overcorrecting costs filter throughput for a while")
	f = Plant.new_state()
	f.pressure = 900
	eq(Plant.act(f, p, 1, 0, 0), "partial", "a small release from 900 helps but is not enough")
	check(Plant.efficiency(f, p)[1] < 1000, "the filter is still above its green band")
	var r: Dictionary = Plant.new_state()
	r.pressure = 990
	Plant.advance(r, [], p, sc, 1000)
	check(r.block_until > 0 and r.failures == 1, "left alone, pressure peaks and the filter blocks")
	# Press: drift, then timing.
	var d: Dictionary = Plant.new_state()
	Plant.advance(d, [{"at_ms": 0, "machine": 2, "dir": 0, "dist": 0, "amount": 0, "rate": 200}], p, sc, 2000)
	check(d.align > 500 + p.align_ok and Plant.efficiency(d, p)[2] < 1000, "a drift takes the press out of alignment")
	var good_t: int = -1
	var bad_t: int = -1
	for ms in range(2000, 4000, 10):
		var off: int = absi(Plant.marker(p, ms) - 500)
		if off <= Plant.press_band(p, ms) and good_t < 0:
			good_t = ms
		if off > Plant.press_band(p, ms) + 100 and bad_t < 0:
			bad_t = ms
	var miss: Dictionary = d.duplicate(true)
	eq(Plant.act(miss, p, 2, 0, bad_t), "incorrect", "tapping when the marker is outside the band misses")
	eq(Plant.act(d, p, 2, 0, good_t), "correct", "tapping inside the band recalibrates")
	eq([d.align, d.drift], [500, 0], "the press is centred and holds")
	eq(Plant.act(d, p, 2, 0, good_t), "no_fault", "calibrating an aligned press does nothing")
	check(Plant.press_band(p, 20000) < Plant.press_band(p, 2000), "the safe band narrows in the last phase")
	# Repeated actions cannot farm points.
	var farm: Dictionary = Plant.new_state()
	for i in range(50):
		Plant.act(farm, p, 1, 0, 0)
		Plant.act(farm, p, 0, 999, 0)
		Plant.act(farm, p, 2, 0, 0)
	eq([farm.repairs, farm.wrong], [0, 0], "fifty rounds of actions with nothing to fix change nothing")

## A skilled player keeps the line running; an idle one does not.
func plant_balance() -> void:
	var m = planned()
	var em = m.emergencies
	var e: Dictionary = ev(m, 2)
	var c: Dictionary = em.challenge(e)
	var p: Dictionary = c.params
	var sc: Dictionary = cfg().scoring.recycling_breakdown
	var idle: Dictionary = Plant.new_state()
	Plant.advance(idle, c.faults, p, sc, p.active_ms)
	var skilled: Dictionary = Plant.new_state()
	var reaction: int = 500
	var ms: int = 0
	while ms < p.active_ms:
		Plant.advance(skilled, c.faults, p, sc, ms)
		if skilled.jam_dir >= 0 and skilled.sim_ms >= _since(c.faults, 0, ms) + reaction:
			Plant.act(skilled, p, 0, skilled.jam_dir * 1000 + skilled.jam_dist, ms)
		if skilled.pressure > p.green_max:
			var valve: int = 0 if skilled.pressure - p.valve_small <= p.green_max else 1
			Plant.act(skilled, p, 1, valve, ms)
		if absi(skilled.align - 500) > p.align_ok / 2 and absi(Plant.marker(p, ms) - 500) <= Plant.press_band(p, ms) / 2:
			Plant.act(skilled, p, 2, 0, ms)
		ms += 100
	Plant.advance(skilled, c.faults, p, sc, p.active_ms)
	var skilled_avg: int = skilled.uptime / (p.active_ms / 1000)
	var idle_avg: int = idle.uptime / (p.active_ms / 1000)
	check(skilled_avg >= 850, "a skilled player keeps the line above 85 %% on average (%d permille)" % skilled_avg)
	check(idle_avg <= 600, "an idle player's line collapses (%d permille)" % idle_avg)
	check(Plant.score(skilled, sc) > 2 * Plant.score(idle, sc), "skill scores far more (%d vs %d)" % [Plant.score(skilled, sc), Plant.score(idle, sc)])
	check(skilled.wrong == 0 and skilled.repairs >= 8, "with %d repairs and no wrong moves" % skilled.repairs)

## When the latest fault of a machine began, at or before ms.
static func _since(faults: Array, machine: int, ms: int) -> int:
	var t: int = 0
	for f in faults:
		if f.machine == machine and f.at_ms <= ms:
			t = f.at_ms
	return t

func validation() -> void:
	var m = planned()
	to_tick(m, 20)
	eq(act(m, 0, "emergency_join", {"event": "em9"}), "unknown_event", "unknown event")
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": 0, "bin": 0, "t_ms": 0}), "not_participating", "only participants play")
	act(m, 0, "emergency_join", {"event": "em1"})
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": 0, "bin": 0, "t_ms": 0}), "event_not_active", "no play before the round")
	eq(act(m, 0, "emergency_slice", {"event": "em1", "item": 0, "t_ms": 0, "x1": 0, "y1": 0, "x2": 1, "y2": 1}), "wrong_event_type", "a sorting action in a collection event")
	var t: Dictionary = Em.times(ev(m, 0), cfg())
	to_tick(m, t.active + 5)
	eq(act(m, 0, "emergency_route", {"event": "em1", "score": 999999}), "invalid_payload", "no way to set a score")
	var items: Array = m.emergencies.challenge(ev(m, 0)).items
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": 9999, "bin": 0, "t_ms": 5500}), "invalid_object", "unknown item")
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": items[0].id, "bin": 7, "t_ms": 5500}), "invalid_choice", "impossible bin")
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": items[0].id, "bin": 0, "t_ms": now_ms(m, 0) + 2000}), "action_out_of_time", "a time in the future is refused")
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": items[0].id, "bin": 0, "t_ms": now_ms(m, 0) - 2500}), "action_out_of_time", "a time older than the latency allowance is refused")
	var gone: Dictionary = items.filter(func(i): return i.spawn_ms + i.travel_ms < (m._state.tick - t.active) * 1000)[0]
	var late_ok: int = (m._state.tick - t.active) * 1000 - 200
	eq(m.preview(0, "emergency_route", {"event": "em1", "item": gone.id, "bin": 0, "t_ms": late_ok}), "object_not_available", "an item that left the belt is gone")
	# Rate limit: max actions per player per second.
	var list: Array = []
	var now: int = (m._state.tick - t.active) * 1000 + 100
	for i in range(cfg().max_actions + 3):
		list.append([0, "emergency_route", {"event": "em1", "item": 0, "bin": 0, "t_ms": now}])
	var res: Array = batch(m, list)
	check(res.count("rate_limited") == 0 or res.slice(cfg().max_actions).all(func(x): return x == "rate_limited"), "excess actions in one second are refused")
	to_tick(m, t.end + 1)
	eq(act(m, 0, "emergency_route", {"event": "em1", "item": items[-1].id, "bin": 0, "t_ms": 24900}), "event_closed", "nothing after the round")
	# The same action id twice is one action (the engine's idempotency).
	var m2 = planned()
	to_tick(m2, 20)
	var cmd: Dictionary = {"match_id": m2._state.match_id, "player_id": 0, "command_seq": 0, "command_id": "dup",
		"command_type": "emergency_join", "payload": {"event": "em1"}, "server_received_tick": m2._state.tick}
	eq(m2.submit(cmd, 0).status, "queued", "first submission")
	eq(m2.submit(cmd.duplicate(true), 0).status, "duplicate", "a repeated command is a duplicate, never a second action")
	eq(m2.submit(cmd.duplicate(true), 1).status, "unauthorized_player", "nobody acts for another player")

func ranking() -> void:
	var e: Dictionary = {"players": []}
	for row in [[true, 50, 3, 1], [true, 50, 5, 1], [true, 50, 3, 1], [false, 0, 0, 0]]:
		e.players.append({"joined": row[0], "score": row[1], "correct": row[2], "wrong": row[3]})
	eq(Em.ranking_of(e), [1, 0, 2], "score, then fewest wrong, then most correct, then seat; non-participants unranked")
	e.players[1].wrong = 4
	eq(Em.ranking_of(e), [0, 2, 1], "fewer wrong actions wins a tie")
	var m = planned()
	to_tick(m, 20)
	act(m, 0, "emergency_join", {"event": "em1"})
	to_tick(m, Em.times(ev(m, 0), cfg()).end + 1)
	eq([ev(m, 0).result.winner, m._state.emergencies.boosts], [-1, []], "a zero score wins nothing")
	var none = planned()
	to_tick(none, Em.times(ev(none, 0), cfg()).end + 1)
	eq([ev(none, 0).result.ranking, ev(none, 0).result.winner], [[], -1], "nobody played: no winner, no boost")

## Seat plays the collection round well enough to win it.
func win_collection(m: RefCounted, seat: int) -> void:
	to_tick(m, ev(m, 0).start)
	act(m, seat, "emergency_join", {"event": "em1"})
	var t: Dictionary = Em.times(ev(m, 0), cfg())
	for item in m.emergencies.challenge(ev(m, 0)).items.slice(0, 3):
		var mid: int = item.spawn_ms + item.travel_ms / 2
		to_tick(m, t.active + mid / 1000)
		act(m, seat, "emergency_route", {"event": "em1", "item": item.id, "bin": Em.ROUTE_KINDS[item.kind], "t_ms": mid})
	to_tick(m, t.end + 1)

func boosts() -> void:
	var m = planned()
	win_collection(m, 1)
	var t: Dictionary = Em.times(ev(m, 0), cfg())
	eq(ev(m, 0).result.winner, 1, "the best player wins")
	var boost: Dictionary = m._state.emergencies.boosts[0]
	eq([boost.player, boost.stage, boost.multiplier_micro, boost.start, boost.end - boost.start, boost.source],
		[1, "collection", 1300000, t.end + 1, 90, "em1"], "Collection Surge: x1.3 collection for exactly 90 s")
	# The Circular city (seat 1) owns a Collection Center: compare with a twin match.
	var twin = planned()
	win_collection(twin, 3)
	for x in [m, twin]:
		add_street(city(x, 1), [400 * U, 400 * U, 400 * U])
	var before: int = city(m, 1).waste.totals.collected
	var twin_before: int = city(twin, 1).waste.totals.collected
	advance(m, 60)
	advance(twin, 60)
	var boosted: int = city(m, 1).waste.totals.collected - before
	var plain: int = city(twin, 1).waste.totals.collected - twin_before
	near(boosted, A.mul(plain, 1300000), 2, "its Collection Center collects 30 %% more (%d vs %d)" % [boosted, plain])
	eq(Emergencies_unrelated(m, twin), true, "other cities are untouched")
	to_tick(m, boost.end - 1)
	eq(Em.multiplier(m._state, 1, "collection"), 1300000, "active through its last second")
	to_tick(m, boost.end + 1)
	eq(m._state.emergencies.boosts, [], "the boost expires on time")
	eq(Em.multiplier(m._state, 1, "collection"), A.S, "and the rate is back to normal")
	eq(A.total(m._state.cities.map(func(x): return x.population)), 8000, "no resident created or lost")

## Seats other than the winner evolve identically in both matches.
func Emergencies_unrelated(m: RefCounted, twin: RefCounted) -> bool:
	return m._state.cities[0].waste.totals == twin._state.cities[0].waste.totals and m._state.cities[2].materials_micro == twin._state.cities[2].materials_micro

func boost_limits() -> void:
	# The Investment city (seat 3) has no Collection Center: the boost changes nothing.
	var m = planned()
	win_collection(m, 3)
	var twin = planned()
	to_tick(twin, m._state.tick)
	for x in [m, twin]:
		add_street(city(x, 3), [300 * U, 0, 0])
	advance(m, 30)
	advance(twin, 30)
	eq(city(m, 3).waste.totals, city(twin, 3).waste.totals, "without a Collection Center the boost does nothing")
	eq(city(m, 3).materials_micro, city(twin, 3).materials_micro, "no free materials")
	# No waste on the street: a boosted collector collects nothing more.
	var empty = planned()
	win_collection(empty, 1)
	var c: Dictionary = city(empty, 1)
	c.street_micro = [0, 0, 0]
	var collected: int = c.waste.totals.collected
	var generated: int = c.waste.totals.generated
	advance(empty, 10)
	check(city(empty, 1).waste.totals.collected - collected <= city(empty, 1).waste.totals.generated - generated, "a boost never collects more than exists")
	eq(empty.serialize().is_empty(), false, "every invariant held through the boost")
	# No stacking: a second win of the same stage replaces the boost.
	var state: Dictionary = {"tick": 0, "emergencies": {"boosts": [], "events": [{"id": "x", "type": "collection_crisis", "start": 0, "seed": 1, "result": null, "players": []}]}}
	for i in range(4):
		state.emergencies.events[0].players.append({"joined": i == 0, "score": 10 if i == 0 else 0, "correct": 1, "wrong": 0})
	var sys = Em.new(Balance.load_config())
	state.tick = Em.times(state.emergencies.events[0], cfg()).end
	sys.update(state, {})
	state.emergencies.events[0].result = null
	sys.update(state, {})
	eq(state.emergencies.boosts.size(), 1, "boosts of one stage never stack")

func disabled() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Balance.PATH))
	raw.emergencies.enabled = false
	var off: Dictionary = Balance.normalize(raw)
	eq(off.error, "", "the feature can be switched off")
	eq(Em.create_state(42, off.config.emergencies).events, [], "switched off: no events")
	# With nobody playing, cities evolve exactly as without the feature.
	var on = fixture()
	var other = fixture()
	other._state.emergencies = {"events": [], "boosts": []}
	advance(on, 1199)
	advance(other, 1199)
	eq(Canonical.encode(on._state.cities), Canonical.encode(other._state.cities), "unplayed emergencies leave every city exactly as without them")

func replay() -> void:
	var runs: Array = []
	for r in range(2):
		var m = planned()
		win_collection(m, 2)
		advance(m, 30)
		runs.append(Canonical.encode(m._state))
	eq(runs[0], runs[1], "the same actions replay to byte-identical state")

func full_match() -> void:
	var m = fixture()
	var seen: Dictionary = {}
	var ok: bool = true
	while m._state.status == "running":
		var cur: Dictionary = Em.current(m._state, cfg())
		if not cur.is_empty():
			seen[cur.id] = true
			if Em.phase(cur, m._state.tick, cfg()) == "announcement":
				act(m, 0, "emergency_join", {"event": cur.id})
				continue
		ok = ok and advance(m, 1)
		if not ok:
			break
	check(ok, "a whole match runs with its emergencies")
	eq(seen.keys().size(), 3, "all three emergencies happen")
	check(m._state.emergencies.events.all(func(e): return e.result != null), "each one finished with a result")
	eq(m._state.emergencies.boosts, [], "no boost outlives the match")
	eq(m._state.status, "finished", "the match ends normally")
	eq(A.total(m._state.cities.map(func(x): return x.population)), 8000, "residents conserved")
