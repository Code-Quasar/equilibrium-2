extends "res://tests/support/harness.gd"
## Construction: Foundations, the Collection -> Sorting -> Recycling/Biogas chain,
## S/M/L prices and totals, upgrades, cancellation, demolition and disabling.
const INDUSTRIAL = 0
const CIRCULAR = 1
const ENERGY = 2
const INVESTMENT = 3

func _initialize() -> void:
	foundations()
	prerequisites()
	rejected_commands_leave_no_trace()
	prices_and_slots()
	upgrades()
	cancellation()
	demolition()
	disabling()
	finish("Construction")

## What a rejected construction could have touched.
static func footprint(c: Dictionary) -> Array:
	return [c.buildings.size(), c.next_building_id, c.projects.duplicate(), c.finance.totals.construction,
		c.finance.totals.material_purchases, c.materials.duplicate()]

func foundations() -> void:
	var m = fixture()
	var cities: Array = m._state.cities
	eq(of_type(cities[INDUSTRIAL], "factory").map(func(x): return [x.size, x.status]), [["S", "complete"]], "Industrial starts with a Small Factory")
	eq(cities[INDUSTRIAL].money_micro, 413 * U, "Industrial cash")
	eq(cities[CIRCULAR].buildings.map(func(x): return [x.type, x.size, x.status, x.tile]),
		[["collection_center", "S", "complete", 0], ["sorting_center", "S", "complete", 1]], "Circular starts with a completed Collection and Sorting chain")
	eq(of_type(cities[CIRCULAR], "recycling_center").size(), 0, "Circular has no Recycling Center")
	eq(cities[CIRCULAR].money_micro, 393 * U, "Circular cash")
	eq(of_type(cities[ENERGY], "renewable_power_plant").size(), 1, "Energy starts with a Renewable plant")
	eq(cities[ENERGY].money_micro, 395 * U, "Energy cash")
	eq([cities[INVESTMENT].buildings.size(), cities[INVESTMENT].money_micro], [0, 660 * U], "Investment starts empty with 660")
	for c in cities:
		eq([c.population, c.materials_micro, c.projects], [1000, 0, [null, null]], "common starting state %d" % c.city_id)
	eq(act(m, CIRCULAR, "construct", {"building_type": "recycling_center", "size": "S"}), "applied", "Circular may start a Recycling Center at once")
	var duplicate = Sim.new()
	eq(duplicate.initialize("dup", 1, ["energy_pioneer", "energy_pioneer", "industrial_legacy", "investment_district"]), "invalid_match_setup", "duplicate Foundations rejected")

func prerequisites() -> void:
	var m = fixture()
	set_cash(city(m, INVESTMENT), 5000 * U)
	eq(act(m, INVESTMENT, "construct", {"building_type": "sorting_center", "size": "S"}), "requires_collection_center", "Sorting needs a Collection Center; municipal collection does not count")
	eq(act(m, INVESTMENT, "construct", {"building_type": "recycling_center", "size": "S"}), "requires_collection_center", "Recycling needs a Collection Center")
	eq(act(m, INVESTMENT, "construct", {"building_type": "biogas_facility", "size": "L"}), "requires_collection_center", "Biogas needs a Collection Center")
	eq(act(m, INDUSTRIAL, "construct", {"building_type": "sorting_center", "size": "S"}), "requires_collection_center", "a rival's Collection Center does not count")
	eq(act(m, INVESTMENT, "construct", {"building_type": "collection_center", "size": "M"}), "applied", "Collection Center needs nothing")
	eq(act(m, INVESTMENT, "construct", {"building_type": "sorting_center", "size": "S"}), "prerequisite_under_construction", "an unfinished Collection Center does not count")
	advance(m, 39)
	eq(first(m, INVESTMENT, "collection_center").status, "complete", "Medium Collection completes after 39 s")
	eq(act(m, INVESTMENT, "construct", {"building_type": "recycling_center", "size": "S"}), "requires_sorting_center", "Recycling also needs a Sorting Center")
	eq(act(m, INVESTMENT, "construct", {"building_type": "sorting_center", "size": "S"}), "applied", "a completed Medium Collection Center satisfies Sorting")
	eq(act(m, INVESTMENT, "construct", {"building_type": "biogas_facility", "size": "S"}), "prerequisite_under_construction", "an unfinished Sorting Center does not count")
	advance(m, 25)
	eq(act(m, INVESTMENT, "construct", {"building_type": "recycling_center", "size": "S"}), "applied", "the full chain unlocks Recycling")
	eq(m.preview(INVESTMENT, "construct", {"building_type": "biogas_facility", "size": "S"}), "", "the full chain unlocks Biogas")
	var options: Dictionary = m.build_options(INDUSTRIAL)
	eq([options.sorting_center.S, options.recycling_center.L, options.factory.S], ["requires_collection_center", "requires_collection_center", ""], "build options report lock reasons")
	var large = fixture()
	set_cash(city(large, INDUSTRIAL), 5000 * U)
	eq(act(large, INDUSTRIAL, "construct", {"building_type": "collection_center", "size": "L"}), "applied", "Large Collection Center")
	advance(large, 58)
	eq(large.preview(INDUSTRIAL, "construct", {"building_type": "sorting_center", "size": "S"}), "", "a completed Large Collection Center counts")

func rejected_commands_leave_no_trace() -> void:
	var m = fixture()
	for seat in range(4):
		set_cash(city(m, seat), 5000 * U)
	var cases: Array = [
		[INVESTMENT, {"building_type": "sorting_center", "size": "S"}, "requires_collection_center"],
		[INVESTMENT, {"building_type": "recycling_center", "size": "M"}, "requires_collection_center"],
		[CIRCULAR, {"building_type": "factory", "size": "S", "tile": 0}, "tile_occupied"],
		[CIRCULAR, {"building_type": "factory", "size": "S", "tile": 36}, "invalid_tile"],
		[CIRCULAR, {"building_type": "factory", "size": "XL"}, "invalid_size"],
		[CIRCULAR, {"building_type": "recovery_hub", "size": "S"}, "invalid_building_type"],
		[CIRCULAR, {"building_type": "factory"}, "invalid_payload"],
	]
	for item in cases:
		var before: Array = footprint(city(m, item[0]))
		eq(act(m, item[0], "construct", item[1]), item[2], "rejected " + str(item[1]))
		eq(footprint(city(m, item[0])), before, "no credits, materials, plot or slot used by " + item[2])
	var poor = fixture()
	set_cash(city(poor, INVESTMENT), 246 * U)
	eq(act(poor, INVESTMENT, "construct", {"building_type": "factory", "size": "S"}), "insufficient_funds", "247 credits needed with no stocked materials")
	var c: Dictionary = city(poor, INVESTMENT)
	eq([c.buildings.size(), c.projects, c.finance.totals.construction], [0, [null, null], 0], "unaffordable construction changes nothing")

func prices_and_slots() -> void:
	var m = fixture()
	var before: int = city(m, INVESTMENT).money_micro
	eq(act(m, INVESTMENT, "construct", {"building_type": "factory", "size": "S"}), "applied", "factory S")
	var c: Dictionary = city(m, INVESTMENT)
	eq([c.finance.tick.construction, c.finance.tick.material_purchases, c.materials.purchased], [175 * U, 72 * U, 12 * U], "175 credits plus 12 bought materials at 6")
	check(before > c.money_micro, "construction is paid at acceptance")
	set_materials(c, 10 * U)
	eq(act(m, INVESTMENT, "construct", {"building_type": "landfill", "size": "M"}), "applied", "landfill M")
	c = city(m, INVESTMENT)
	eq([c.finance.tick.construction, c.finance.tick.material_purchases, c.materials_micro, c.materials.used], [165 * U, 0, 1 * U, 9 * U], "stocked materials are used before buying")
	eq(act(m, INVESTMENT, "construct", {"building_type": "park", "size": "S"}), "construction_slots_full", "two projects at most")
	eq(city(m, INVESTMENT).projects.map(func(p): return p.complete_tick), [0 + 28, 1 + 36], "projects finish after their own duration")
	advance(m, 27)
	eq(first(m, INVESTMENT, "factory").status, "complete", "factory completes at its tick")
	m._state.tick = 1175
	eq(act(m, INVESTMENT, "construct", {"building_type": "factory", "size": "S"}), "not_enough_time", "a project must finish before the match ends")

func upgrades() -> void:
	var m = fixture()
	set_cash(city(m, CIRCULAR), 2000 * U)
	var id: int = first(m, CIRCULAR, "collection_center").id
	eq(m.buildings.tier(building(m, CIRCULAR, id)).collection, 23 * U, "Small collection 23/min")
	eq(act(m, CIRCULAR, "upgrade", {"building_id": id}), "applied", "upgrade S to M")
	eq([city(m, CIRCULAR).finance.tick.construction, city(m, CIRCULAR).finance.tick.material_purchases], [87 * U, 30 * U], "S->M costs 87 credits and 5 materials")
	eq(act(m, CIRCULAR, "upgrade", {"building_id": id}), "already_upgrading", "one upgrade at a time")
	check(advance(m, 28), "upgrade under way")
	var collection: Dictionary = building(m, CIRCULAR, id)
	eq([collection.size, collection.op.funded, city(m, CIRCULAR).waste.tick.collected > 0], ["S", true, true], "Small keeps operating during its upgrade")
	advance(m, 1)
	collection = building(m, CIRCULAR, id)
	eq(collection.size, "M", "upgrade completes after 30 s")
	eq(m.buildings.tier(collection).collection, 45 * U, "Medium total is 45/min, not 23 + 45")
	eq(act(m, CIRCULAR, "upgrade", {"building_id": id}), "applied", "upgrade M to L")
	advance(m, 44)
	collection = building(m, CIRCULAR, id)
	eq([collection.size, m.buildings.tier(collection).collection], ["L", 72 * U], "Large total is 72/min")
	eq(act(m, CIRCULAR, "upgrade", {"building_id": id}), "maximum_size", "Large is the last tier")

func cancellation() -> void:
	var m = fixture()
	eq(act(m, INVESTMENT, "construct", {"building_type": "commercial_district", "size": "M"}), "applied", "commercial M")
	var id: int = city(m, INVESTMENT).projects[0].building_id
	var materials_before: int = city(m, INVESTMENT).materials_micro
	eq(act(m, INVESTMENT, "cancel_project", {"building_id": id}), "applied", "cancel construction")
	var c: Dictionary = city(m, INVESTMENT)
	eq([c.finance.tick.refunds, c.materials_micro - materials_before], [208 * U, 14 * U], "80% of 260 credits and every material unit back")
	eq([c.projects, Buildings.find(c, id)], [[null, null], {}], "cancelled construction frees its plot and slot")
	eq(act(m, INVESTMENT, "cancel_project", {"building_id": id}), "building_not_owned", "cancellation cannot repeat")
	var sorter: int = first(m, CIRCULAR, "sorting_center").id
	eq(act(m, CIRCULAR, "upgrade", {"building_id": sorter}), "applied", "start an upgrade")
	eq(act(m, CIRCULAR, "cancel_project", {"building_id": sorter}), "applied", "cancel the upgrade")
	eq([building(m, CIRCULAR, sorter).size, building(m, CIRCULAR, sorter).status, city(m, CIRCULAR).finance.tick.refunds],
		["S", "complete", A.mul(98 * U, 800000)], "a cancelled upgrade keeps the Small building")

func demolition() -> void:
	var m = fixture()
	set_cash(city(m, CIRCULAR), 3000 * U)
	var collection: int = first(m, CIRCULAR, "collection_center").id
	var sorter: int = first(m, CIRCULAR, "sorting_center").id
	eq(act(m, CIRCULAR, "demolish", {"building_id": collection}), "dependent_buildings_exist", "the last Collection Center cannot be demolished under a Sorting Center")
	eq(act(m, CIRCULAR, "construct", {"building_type": "recycling_center", "size": "S"}), "applied", "start a Recycling Center")
	eq(act(m, CIRCULAR, "demolish", {"building_id": sorter}), "dependent_buildings_exist", "a Recycling project protects the last Sorting Center")
	eq(act(m, CIRCULAR, "construct", {"building_type": "collection_center", "size": "S"}), "applied", "second Collection Center")
	advance(m, 23)
	eq(act(m, CIRCULAR, "demolish", {"building_id": collection}), "applied", "a Collection Center may go while another remains")
	eq(city(m, CIRCULAR).finance.tick.refunds, A.mul(95 * U, 100000), "demolition refunds 10% of base credits")
	var crowded = fixture()
	city(crowded, ENERGY).population += 200
	city(crowded, INVESTMENT).population -= 200
	set_cash(city(crowded, ENERGY), 1000 * U)
	eq(act(crowded, ENERGY, "construct", {"building_type": "residential_district", "size": "S"}), "applied", "housing for a crowded city")
	advance(crowded, 25)
	var district: int = first(crowded, ENERGY, "residential_district").id
	eq(act(crowded, ENERGY, "demolish", {"building_id": district}), "housing_below_population", "demolition cannot push housing below the population")

func disabling() -> void:
	var m = fixture()
	var id: int = first(m, CIRCULAR, "collection_center").id
	advance(m, 2)
	var upkeep: int = city(m, CIRCULAR).finance.tick.building_upkeep
	eq(act(m, CIRCULAR, "disable", {"building_id": id}), "applied", "disable the Collection Center")
	var c: Dictionary = city(m, CIRCULAR)
	var collection: Dictionary = building(m, CIRCULAR, id)
	eq([collection.enabled, collection.op.funded, c.waste.tick.collected, c.waste.tick.salvaged], [false, false, 0, 0], "a disabled Collection Center collects nothing")
	check(c.finance.tick.standby_upkeep > 0 and c.finance.tick.building_upkeep < upkeep, "a disabled building pays standby, not full upkeep")
	eq(m.preview(CIRCULAR, "construct", {"building_type": "recycling_center", "size": "S"}), "", "a disabled prerequisite still counts")
	eq(act(m, CIRCULAR, "enable", {"building_id": id}), "reactivation_cooldown", "re-enabling waits for the cooldown")
	advance(m, 8)
	eq(act(m, CIRCULAR, "enable", {"building_id": id}), "applied", "re-enabled after 10 s")
	eq([building(m, CIRCULAR, id).op.funded, city(m, CIRCULAR).waste.tick.collected > 0], [true, true], "collection resumes")
