extends SceneTree
const Sim = preload("res://tests/support/construction_simulation.gd")
const Balance = preload("res://simulation/core/balance.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Economy = preload("res://simulation/systems/economy/municipal.gd")
const S: int = 1000000
const FOUNDATIONS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
var checks: int = 0
var failures: int = 0
var sequence: int = 0

func _initialize() -> void:
	configuration()
	foundations_and_economy()
	construction()
	upgrades()
	lifecycle()
	funding_and_staffing()
	policy_and_materials()
	determinism_and_rollback()
	print("Construction: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL construction: " + message)

func fresh():
	var sim = Sim.new()
	check(sim.initialize("construction-test", 42, FOUNDATIONS) == "", "initialize construction harness")
	return sim

func city(sim, id: int = 3) -> Dictionary:
	return sim.snapshot().cities[id]

func queue(sim, owner: int, kind: String, payload: Dictionary) -> Dictionary:
	sequence += 1
	var command: Dictionary = {"match_id": "construction-test", "player_id": owner, "command_seq": sequence,
		"command_id": str(sequence), "command_type": kind, "payload": payload,
		"server_received_tick": sim.snapshot().tick}
	check(sim.submit(command, owner).status == "queued", "queue " + kind)
	return command

func step(sim) -> Dictionary:
	var result: Dictionary = sim.step()
	check(result.status == "advanced", "tick advances: " + str(result.get("error", "")))
	return result

func issue(sim, owner: int, kind: String, payload: Dictionary) -> String:
	queue(sim, owner, kind, payload)
	var result: Dictionary = step(sim)
	return result.commands[-1].status if result.has("commands") else "tick_failed"

func until(sim, tick: int) -> void:
	while sim.snapshot().tick < tick:
		if step(sim).status != "advanced":
			return

# Trusted unit-test fixtures only. No production command can set cash, scores,
# complete buildings, or add materials. Each fixture repairs its audit baseline.
func cash_fixture(sim, amount: int, owner: int = 3) -> void:
	var target: Dictionary = sim._state.cities[owner]
	target.finance.initial_cash += amount - target.money_micro
	target.money_micro = amount

func building_fixture(sim, kind: String, owner: int = 3) -> int:
	var target: Dictionary = sim._state.cities[owner]
	var id: int = target.next_building_id
	target.next_building_id += 1
	target.buildings.append(sim._buildings.record(id, kind, owner, sim._buildings.next_tile(target), 0, true))
	return id

func configuration() -> void:
	var b: Dictionary = Balance.load_b1()
	check(b.buildings.size() == 11, "eleven types")
	check(b.buildings.factory.l1.cost_micro == 260 * S and b.buildings.factory.upgrade_delta.income_micro_per_minute == 85 * S, "authoritative Factory values")
	for key in Balance.ROOT_INTS + ["buildings", "economy", "foundations", "development", "satisfaction"]:
		var invalid: Dictionary = b.duplicate(true)
		invalid.erase(key)
		check(not Balance.validate(invalid).is_empty(), "missing config " + key)
	for bad in [-1, 1.5, true, "260", null]:
		var invalid: Dictionary = b.duplicate(true)
		invalid.buildings.factory.l1.cost_micro = bad
		check(not Balance.validate(invalid).is_empty(), "bad catalogue numeric")
	var invalid: Dictionary = b.duplicate(true)
	invalid.buildings.factory.l1.duration_seconds = 0
	check(not Balance.validate(invalid).is_empty(), "zero duration")
	invalid = b.duplicate(true)
	invalid.economy.municipal_upkeep_micro_per_minute = 999 * S
	check(not Balance.validate(invalid).is_empty(), "softlock config")
	invalid = b.duplicate(true)
	invalid.foundations.industrial_legacy.building = "unknown"
	check(not Balance.validate(invalid).is_empty(), "invalid Foundation ref")
	invalid = b.duplicate(true)
	invalid.regional_population = 3999
	check(not Balance.validate(invalid).is_empty(), "population consistency")
	var path: String = "/tmp/equilibrium-invalid-balance.json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"match_seconds":1.5}')
	file.close()
	check(Balance.load_b1(path).is_empty(), "startup loader rejects malformed data without assert")
	var catalogue = Buildings.new(b)
	for kind in Balance.TYPES:
		var record: Dictionary = catalogue.record(0, kind, 0, 0, 0, true)
		var first: Dictionary = catalogue.effects(record)
		record.level = 2
		var second: Dictionary = catalogue.effects(record)
		for effect in Balance.EFFECTS:
			if effect not in ["cost_micro", "duration_seconds"]:
				check(second[effect] == first[effect] + b.buildings[kind].upgrade_delta[effect], "additive upgrade " + kind + ":" + effect)

func foundations_and_economy() -> void:
	var sim = fresh()
	for owner in range(4):
		var c: Dictionary = city(sim, owner)
		check(c.money_micro == [480,620,520,900][owner] * S, "Foundation cash")
		check(c.development_micro == 0 and c.satisfaction_micro == null and c.score_evaluated_tick == null, "no pre-operation achievement")
		check(c.finance.totals.construction == 0, "no Foundation charge")
		if owner < 3:
			check(c.buildings[0].level == 1 and c.buildings[0].owner_city == owner and not c.buildings[0].funded, "Foundation normal initial eligibility")
	step(sim)
	check(city(sim,0).buildings[0].productive, "funded starting Factory")
	check(city(sim,0).capacity.realized_jobs_micro == 860*S, "Factory jobs")
	check(city(sim,0).development_micro == 12500000, "earned Factory development after interval zero")
	check(city(sim,1).materials_micro == 0 and city(sim,1).mass_ledger_micro.recovered == 0, "no fake recycling")
	check(city(sim,2).capacity.generation_micro_E == 245*S, "funded Renewable power potential")
	check(city(sim,0).score_evaluated_tick == 1 and city(sim,0).satisfaction_components_micro.employment == 17200000, "first score components after interval zero")
	until(sim,60)
	for owner in range(4):
		var c: Dictionary = city(sim,owner)
		check(c.finance.totals.municipal_income == 170*S and c.finance.totals.municipal_upkeep == 25*S, "exact minute municipal accounting")
		check(c.money_micro == [756,756,654,1045][owner]*S, "one minute package cash")
		check(Finance.validate(c) == "", "ledger reconciles")
	check(sim.initialize("again",1,FOUNDATIONS) == "already_initialized", "no repeated Foundation benefits")
	var commerce = fresh()
	building_fixture(commerce,"commercial_district")
	until(commerce,60)
	check(city(commerce).finance.totals.building_income == 90*S and city(commerce).finance.totals.building_upkeep == 12*S, "Commerce gross margin 78 in construction harness")
	var zero = fresh()
	cash_fixture(zero,0)
	until(zero,60)
	check(city(zero).money_micro == 145*S, "zero-cash municipal recovery")

func construction() -> void:
	var sim = fresh()
	var first: Dictionary = queue(sim,3,"construct",{"building_type":"residential_district"})
	check(sim.submit(first,3).status == "duplicate", "pending build retry")
	queue(sim,3,"construct",{"building_type":"public_services_center"})
	queue(sim,3,"construct",{"building_type":"factory"})
	var result: Dictionary = step(sim)
	check(result.commands[0].status == "applied" and result.commands[1].status == "applied" and result.commands[2].status == "construction_slots_full", "two projects, no queue")
	check(city(sim).finance.totals.construction == 325*S and city(sim).buildings.size() == 2, "atomic construction spending")
	check(city(sim).buildings[0].tile == 0 and city(sim).buildings[1].tile == 1, "skip occupied tile")
	check(city(sim).capacity.housing == 1200, "no benefit while constructing")
	first.server_received_tick = 1
	check(sim.submit(first,3).status == "duplicate", "applied build retry")
	until(sim,22)
	check(city(sim).buildings[0].status == "constructing", "completion not early at state22")
	step(sim)
	check(city(sim).buildings[0].status == "complete" and city(sim).capacity.housing == 1650, "complete before operation interval22")
	until(sim,29)
	check(city(sim).capacity.services_micro == 1750*S, "service completion and capacity")
	check(issue(sim,3,"construct",{"building_type":"bad"}) == "invalid_building_type", "unknown type")
	check(issue(sim,3,"construct",{"building_type":"factory","tile":0}) == "invalid_payload", "manual occupied tile rejected")
	check(issue(sim,3,"construct",{"building_type":"factory","tile":36}) == "invalid_payload", "out of grid rejected")
	check(issue(sim,3,"construct",{"building_type":"biogas_facility"}) == "development_locked", "Biogas unlock")
	var poor = fresh()
	cash_fixture(poor,0)
	check(issue(poor,3,"construct",{"building_type":"factory"}) == "insufficient_funds", "cannot spend future municipal income")
	check(city(poor).buildings.is_empty(), "failed construction creates nothing")
	var full = fresh()
	for _i in range(36): building_fixture(full,"residential_district")
	check(issue(full,3,"construct",{"building_type":"factory"}) == "no_free_tile", "grid full")
	var late = fresh()
	late._state.tick = 1178
	check(issue(late,3,"construct",{"building_type":"residential_district"}) == "not_enough_time", "completion exactly1200 rejected")
	check(issue(late,3,"construct",{"building_type":"factory"}) == "not_enough_time", "completion after1200 rejected")
	var just_in_time = fresh()
	just_in_time._state.tick = 1177
	check(issue(just_in_time,3,"construct",{"building_type":"residential_district"}) == "applied", "completion1199 allowed")
	until(just_in_time,1200)
	check(city(just_in_time).buildings[0].operational_ticks == 1, "last valid operating interval")
	var broken: Dictionary = city(sim)
	broken.buildings[1].tile = broken.buildings[0].tile
	check(sim._buildings.validate_city(broken) == "occupied_or_invalid_tile", "tile overlap invariant")

func upgrades() -> void:
	var sim = fresh()
	var id: int = building_fixture(sim,"residential_district")
	check(issue(sim,3,"upgrade",{"building_id":id}) == "development_locked", "upgrade requires Development")
	sim._state.cities[3].development_micro = 70*S
	var start: int = sim.snapshot().tick
	check(issue(sim,3,"upgrade",{"building_id":id}) == "applied", "valid upgrade")
	check(city(sim).capacity.housing == 1650, "L1 remains operating during upgrade")
	check(city(sim).finance.totals.construction == 95*S, "upgrade cost")
	check(issue(sim,3,"upgrade",{"building_id":id}) == "already_upgrading", "duplicate upgrade")
	until(sim,start+18)
	check(city(sim).buildings[0].level == 1, "upgrade not early")
	step(sim)
	check(city(sim).buildings[0].level == 2 and city(sim).capacity.housing == 2000, "additive L2 capacity at completion")
	check(issue(sim,3,"upgrade",{"building_id":id}) == "maximum_level", "no L3")
	var disabled = fresh()
	id = building_fixture(disabled,"public_services_center")
	disabled._state.cities[3].development_micro = 70*S
	check(issue(disabled,3,"disable",{"building_id":id}) == "applied", "disable before upgrade")
	check(issue(disabled,3,"upgrade",{"building_id":id}) == "applied", "disabled upgrade allowed")
	until(disabled,22)
	check(city(disabled).buildings[0].level == 2 and not city(disabled).buildings[0].enabled and city(disabled).capacity.services_micro == 1200*S, "upgrade does not enable building")
	check(issue(disabled,3,"enable",{"building_id":id}) == "applied", "enable completed L2")
	check(city(disabled).capacity.services_micro == 2100*S, "L2 services unscaled by staffing")
	var poor = fresh()
	id = building_fixture(poor,"factory")
	poor._state.cities[3].development_micro = 70*S
	cash_fixture(poor,0)
	check(issue(poor,3,"upgrade",{"building_id":id}) == "insufficient_funds", "unaffordable upgrade")
	var slots = fresh()
	id = building_fixture(slots,"factory")
	slots._state.cities[3].development_micro = 70*S
	queue(slots,3,"construct",{"building_type":"residential_district"})
	queue(slots,3,"construct",{"building_type":"residential_district"})
	queue(slots,3,"upgrade",{"building_id":id})
	check(step(slots).commands[-1].status == "construction_slots_full", "upgrade needs slot")

func lifecycle() -> void:
	var sim = fresh()
	check(issue(sim,0,"disable",{"building_id":0}) == "applied", "same-interval disable")
	check(city(sim,0).finance.totals.building_upkeep == 0 and city(sim,0).finance.totals.building_income == 0, "no disable interval fee or output")
	until(sim,9)
	check(issue(sim,0,"enable",{"building_id":0}) == "reactivation_cooldown", "t9 blocked")
	check(issue(sim,0,"enable",{"building_id":0}) == "applied", "t10 allowed")
	check(city(sim,0).buildings[0].productive_ticks == 1, "no retroactive production")
	var spending_before: int = city(sim,0).finance.totals.refunds
	check(issue(sim,0,"demolish",{"building_id":0}) == "applied", "demolish complete")
	check(city(sim,0).finance.totals.refunds == spending_before and city(sim,0).buildings.is_empty(), "zero demolition refund")
	check(issue(sim,0,"demolish",{"building_id":0}) == "building_not_owned", "no repeated demolition")
	check(issue(sim,0,"construct",{"building_type":"factory"}) == "applied", "rebuild uses new ID")
	check(city(sim,0).buildings[0].id == 1, "building ID never reused")
	check(issue(sim,0,"disable",{"building_id":1}) == "not_complete", "cannot disable construction")
	check(issue(sim,0,"demolish",{"building_id":1}) == "not_complete", "must cancel construction")
	check(issue(sim,0,"cancel_project",{"building_id":1}) == "applied", "cancel construction")
	check(city(sim,0).finance.totals.refunds == 130*S, "half actual cash refunded")
	check(issue(sim,0,"cancel_project",{"building_id":1}) == "building_not_owned", "no repeat refund")
	var ownership = fresh()
	check(issue(ownership,3,"disable",{"building_id":0}) == "building_not_owned", "cannot control rival building")
	check(city(ownership,0).buildings[0].enabled, "rival unchanged")
	check(issue(ownership,0,"disable",{"building_id":0,"city_id":1}) == "invalid_payload", "explicit rival targeting rejected")
	var upgrading = fresh()
	upgrading._state.cities[0].development_micro = 70*S
	check(issue(upgrading,0,"upgrade",{"building_id":0}) == "applied", "start upgrade")
	check(issue(upgrading,0,"demolish",{"building_id":0}) == "cancel_project_first", "no ambiguous active-upgrade demolition")
	check(issue(upgrading,0,"cancel_project",{"building_id":0}) == "applied", "cancel upgrade")
	check(city(upgrading,0).buildings[0].level == 1 and city(upgrading,0).finance.totals.refunds == 90*S, "cancel upgrade retains L1")

func funding_and_staffing() -> void:
	var sim = fresh()
	cash_fixture(sim,0)
	for _i in range(20): building_fixture(sim,"renewable_power_plant")
	step(sim)
	check(city(sim).buildings[0].funded and not city(sim).buildings[19].funded, "oldest then ID funding priority")
	check(city(sim).operation_totals.funding_failures > 0 and city(sim).money_micro >= 0, "insufficient funding never negative")
	var reserved = fresh()
	cash_fixture(reserved,0,0)
	reserved.register_system("facility_funding","00_test_reservation",func(s,_c,_r):
		var c: Dictionary = s.cities[0]
		return "" if Finance.reserve(c,"future-obligation",Finance.available(c),s.tick) else "reserve_failed")
	step(reserved)
	check(city(reserved,0).finance.totals.municipal_upkeep > 0, "mandatory precedes reservations")
	check(not city(reserved,0).buildings[0].funded and city(reserved,0).finance.totals.building_income == 0, "reserved cash cannot fund factory")
	check(city(reserved,0).finance.reserved.is_empty(), "unused reservations released at phase18")
	var c: Dictionary = city(reserved,0)
	check(Finance.reserve(c,"x",c.money_micro,1), "reserve actual available funds")
	check(not Finance.reserve(c,"x",0,1) and not Finance.reserve(c,"y",1,1), "no duplicate or double reservation")
	var before_payment: int = c.money_micro
	check(Finance.consume_reserved(c,"x",1), "reserved settlement interface")
	check(c.money_micro == before_payment - 1 and Finance.validate(c) == "", "reserved settlement debits exactly once")
	check(not Finance.consume_reserved(c,"x",before_payment), "settlement cannot exceed reservation")
	Finance.release(c,"x")
	check(Finance.available(c) == c.money_micro, "release returns spending availability")
	var shortage = fresh()
	building_fixture(shortage,"factory",0)
	step(shortage)
	check(city(shortage,0).capacity.power_status == "awaiting_detailed_allocation", "power shortage explicit")
	check(city(shortage,0).finance.totals.building_income == 0 and not city(shortage,0).buildings[0].operational, "no unproven powered income")
	check(city(shortage,0).satisfaction_components_micro.employment == null, "shortage-dependent score deferred")
	var workforce = fresh()
	for _i in range(2): building_fixture(workforce,"factory")
	for _i in range(2): building_fixture(workforce,"renewable_power_plant")
	step(workforce)
	check(city(workforce).capacity.potential_jobs == 1280 and city(workforce).capacity.staffing_micro == 781250, "single global workforce factor")
	check(city(workforce).capacity.realized_jobs_micro == 1000*S, "realized jobs population cap")
	until(workforce,60)
	check(city(workforce).finance.totals.building_income == 242187500, "staffed Factory income with exact carry")
	check(city(workforce).finance.totals.building_upkeep == 70*S, "fixed upkeep not scaled")
	building_fixture(workforce,"public_services_center")
	building_fixture(workforce,"residential_district")
	step(workforce)
	check(city(workforce).capacity.staffing_micro < S and city(workforce).capacity.housing == 1650 and city(workforce).capacity.services_micro == 1750*S, "housing and services not staffing-scaled")
	var forged: Dictionary = city(workforce)
	forged.money_micro += 1
	check(Finance.validate(forged) == "financial_conservation", "unexplained money rejected")

func policy_and_materials() -> void:
	var sim = fresh()
	check(issue(sim,0,"set_reduce_waste",{"enabled":true}) == "applied", "policy toggle")
	until(sim,60)
	check(city(sim,0).finance.totals.policy == 18*S and city(sim,0).finance.totals.building_income == 139500000, "paid policy fee and Factory income modifier")
	check(city(sim,0).mass_ledger_micro.generated == 0, "no fictional waste reductions")
	check(issue(sim,0,"set_reduce_waste",{"enabled":false}) == "applied", "policy t60 cooldown expires")
	check(issue(sim,0,"set_reduce_waste",{"enabled":true}) == "policy_cooldown", "policy cooldown enforced")
	var failed = fresh()
	cash_fixture(failed,0,0)
	failed.register_system("facility_funding","00_test_reservation",func(s,_c,_r):
		var c: Dictionary = s.cities[0]
		return "" if Finance.reserve(c,"hold",Finance.available(c),s.tick) else "reserve_failed")
	check(issue(failed,0,"set_reduce_waste",{"enabled":true}) == "applied", "policy requested under funding pressure")
	check(not city(failed,0).policy_active and city(failed,0).finance.totals.policy == 0 and city(failed,0).policy_change_at == 60, "failed fee no effect or new cooldown")
	var materials = fresh()
	materials._state.cities[3].materials_micro = 100*S
	materials._state.cities[3].mass_ledger_micro.generated = 100*S
	materials._state.cities[3].mass_ledger_micro.recovered = 100*S
	check(issue(materials,3,"construct",{"building_type":"factory"}) == "applied", "construction consumes materials")
	check(city(materials).finance.totals.construction == 195*S and city(materials).materials_micro == 35*S, "25 percent maximum discount")
	check(issue(materials,3,"cancel_project",{"building_id":0}) == "applied", "cancel discounted project")
	check(city(materials).finance.totals.refunds == 97500000 and city(materials).materials_micro == 35*S, "refund only actual cash, no materials")

func determinism_and_rollback() -> void:
	var a = fresh()
	var b = fresh()
	var commands: Array = []
	for owner in range(4):
		commands.append(queue(a,owner,"construct",{"building_type":"residential_district"}))
	commands.reverse()
	for command in commands: check(b.submit(command,command.player_id).status == "queued", "reversed arrivals")
	for _i in range(1200):
		if step(a).status != "advanced" or step(b).status != "advanced": return
	check(a.serialize() == b.serialize(), "full 1200-tick replay independent of arrival order")
	check(a.snapshot().status == "finished" and a.snapshot().tick == 1200, "final time")
	var final: String = a.serialize()
	check(a.step().status == "match_closed", "no post-final tick")
	var late: Dictionary = commands[0].duplicate(true)
	late.server_received_tick = 1200
	check(a.submit(late,late.player_id).status == "match_closed" and a.serialize() == final, "frozen final snapshot")
	var rollback = fresh()
	queue(rollback,3,"construct",{"building_type":"factory"})
	rollback.register_system("production","zz_fail",func(s,_c,r):
		s.cities[0].money_micro += 1
		r.next_int()
		return "intentional_failure")
	var before: String = rollback.serialize()
	check(rollback.step().status == "tick_rejected" and rollback.serialize() == before, "atomic tick rolls back construction, finances, RNG and commands")
