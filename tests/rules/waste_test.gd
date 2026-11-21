extends "res://tests/support/harness.gd"
## Progressive valorization and the physical waste ledger.
const Waste = preload("res://simulation/systems/waste.gd")
const SEAT = 3

func _initialize() -> void:
	reference_chain()
	household_minute()
	operating_limits()
	isolation_and_caps()
	biogas_power_is_next_tick()
	landfill_rules()
	finish("Waste")

## A city with the given operating facilities and nothing else running.
func bench(kinds: Array) -> Array:
	var m = fixture()
	var c: Dictionary = city(m, SEAT)
	for kind in kinds:
		operate(place(m, c, kind))
	return [m, c]

## Runs the dedicated stages (no household waste, no municipal fleet) until idle.
func drain(m: RefCounted, c: Dictionary) -> void:
	for i in range(5000):
		if A.total(c.street_micro) + A.total(c.mixed_micro) + c.sorted_micro[Waste.R] == 0:
			return
		var before: int = A.total(c.street_micro) + A.total(c.mixed_micro) + c.sorted_micro[Waste.R]
		m.waste._collect(c)
		m.waste._sort(c)
		m.waste._budget(c)
		c.sorted_micro[Waste.R] -= m.waste.treat(c, Waste.R, c.sorted_micro[Waste.R])
		if before == A.total(c.street_micro) + A.total(c.mixed_micro) + c.sorted_micro[Waste.R]:
			return

## The normalized B2.1 example: 100 units of pure recyclable waste, Small facilities.
func reference_chain() -> void:
	var results: Array = []
	for chain in [["collection_center"], ["collection_center", "sorting_center"], ["collection_center", "sorting_center", "recycling_center"]]:
		var bench_city: Array = bench(chain)
		var m = bench_city[0]
		var c: Dictionary = bench_city[1]
		add_street(c, [100 * U, 0, 0])
		drain(m, c)
		eq(m.waste.validate_city(c), "", "mass conserved for " + str(chain))
		results.append(c.materials_micro)
		var t: Dictionary = c.waste.totals
		match chain.size():
			1:
				eq([t.salvaged, A.total(c.mixed_micro)], [8 * U, 92 * U], "Collection alone: 8 recovered, 92 remain")
			2:
				eq([t.salvaged, t.captured_recyclable, t.sorting_reuse, c.sorted_micro[Waste.R], c.disposal_micro],
					[8 * U, 73600000, 11776000, 61824000, 18400000], "Collection + Sorting: 8 + 11.776, 61.824 sorted, 18.4 missed")
			3:
				eq([t.salvaged, t.sorting_reuse, t.recycled, t.recycled_materials, t.recycling_rejects],
					[8 * U, 11776000, 61824000, 49459200, 12364800], "full chain stage by stage")
				eq(c.disposal_micro, 30764800, "18.4 sorting misses + 12.3648 rejects remain for disposal")
				eq(c.materials_micro + c.disposal_micro, 100 * U, "recovered plus unrecovered is exactly the original mass")
	eq(results, [8 * U, 19776000, 69235200], "cumulative recovery 8 -> 19.776 -> 69.2352")
	check(results[0] < results[1] and results[1] < results[2], "each built stage recovers more")

## Audit §8: 1,000 residents with Small Collection, Sorting, Recycling and Biogas for one minute.
func household_minute() -> void:
	var bench_city: Array = bench(["collection_center", "sorting_center", "recycling_center", "biogas_facility"])
	var m = bench_city[0]
	var c: Dictionary = bench_city[1]
	for i in range(60):
		m.waste.generate(c, c.carries, "household", m._balance.waste.household * c.population, U)
		m.waste._collect(c)
		m.waste._municipal_collect(c)
		m.waste._sort(c)
		m.waste._budget(c)
		m.waste.treat_local({"cities": [c]}, {})
	var t: Dictionary = c.waste.totals
	eq(t.generated, 30 * U, "30 units generated")
	# Proportional per-second allocation quantizes each category by at most one micro-unit per tick.
	for item in [["collected", 23 * U], ["municipal_collected", 7 * U], ["salvaged", 920000], ["captured_recyclable", 8464000],
			["sorting_reuse", 1354240], ["recycled", 7109760], ["recycled_materials", 5687808], ["captured_organic", 5175000],
			["digested_converted", 4140000]]:
		near(t[item[0]], item[1], 120, "audit example " + item[0])
	near(Waste.recovered(c), 7962048, 120, "7.962048 materials recovered")
	near(c.disposal_micro, 17897952, 120, "17.897952 left for disposal")
	eq(Waste.recovered(c) + t.digested_converted + c.disposal_micro + A.total(c.street_micro + c.mixed_micro + c.sorted_micro), 30 * U, "the 30 units are fully accounted for")

func operating_limits() -> void:
	var bench_city: Array = bench(["collection_center"])
	var m = bench_city[0]
	var c: Dictionary = bench_city[1]
	m.waste._collect(c)
	eq([c.waste.totals.collected, c.materials_micro], [0, 0], "no feedstock, no materials")
	add_street(c, [1000 * U, 0, 0])
	var center: Dictionary = of_type(c, "collection_center")[0]
	center.op.fraction_micro = 500000
	for i in range(60):
		m.waste._collect(c)
	eq(c.waste.totals.collected, 11500000, "half power or staff collects 11.5 of 23 per minute")
	center.op = Buildings.idle()
	m.waste._collect(c)
	eq(c.waste.totals.collected, 11500000, "an unfunded Collection Center collects nothing")
	var pair: Array = bench(["collection_center", "collection_center", "sorting_center", "recycling_center", "recycling_center"])
	var p: Dictionary = pair[1]
	add_street(p, [300000, 0, 0])
	pair[0].waste._collect(p)
	eq(p.waste.totals.collected, 300000, "two Collection Centers share, never exceed, the street stock")
	p.sorted_micro[Waste.R] = 100000
	p.waste.totals.generated += 100000
	pair[0].waste._budget(p)
	eq(pair[0].waste.treat(p, Waste.R, p.sorted_micro[Waste.R]), 100000, "two recyclers treat only the stock that exists")

func isolation_and_caps() -> void:
	var m = fixture()
	advance(m, 30)
	var c: Dictionary = city(m, SEAT)
	eq([A.total(c.mixed_micro), c.waste.totals.salvaged, c.waste.totals.sorted, c.waste.totals.collected], [0, 0, 0, 0], "municipal collection feeds neither salvage nor sorting")
	check(c.waste.totals.municipal_collected > 0 and c.waste.totals.landfilled > 0, "municipal waste goes to disposal")
	var bench_city: Array = bench(["collection_center", "sorting_center"])
	var b = bench_city[1]
	b.sorted_micro[Waste.R] = 249999000
	b.waste.totals.generated += 249999000
	add_street(b, [100 * U, 0, 0])
	for i in range(60):
		bench_city[0].waste._collect(b)
		bench_city[0].waste._sort(b)
	eq(b.sorted_micro[Waste.R], 250 * U, "sorted recyclable stops at its 250 cap")
	check(b.waste.totals.overflow_to_disposal > 0, "sorted overflow goes to disposal, not back to sorting")
	eq(bench_city[0].waste.validate_city(b), "", "overflow conserves mass")
	var full: Array = bench(["collection_center"])
	var f: Dictionary = full[1]
	f.mixed_micro[Waste.X] = 299900000
	f.waste.totals.generated += 299900000
	add_street(f, [0, 0, 10 * U])
	full[0].waste._collect(f)
	eq(A.total(f.mixed_micro), 300 * U, "collection stops at the 300 mixed-buffer cap")

func biogas_power_is_next_tick() -> void:
	var m = fixture()
	set_cash(city(m, 1), 2000 * U)
	place(m, city(m, 1), "biogas_facility")
	advance(m, 3)
	var digested: int = city(m, 1).waste.tick.digested
	var pending: int = city(m, 1).biogas_pending_micro_E
	check(digested > 0, "biogas digests sorted organics")
	eq(pending, A.mul(60 * digested, 2600000), "next-tick power is 2.6 E per organic unit per minute")
	advance(m, 1)
	eq(city(m, 1).power.biogas_micro_E, pending, "biogas power arrives the following tick")
	first(m, 1, "sorting_center").enabled = false
	first(m, 1, "sorting_center").op = Buildings.idle()
	advance(m, 2)
	eq(city(m, 1).power.biogas_micro_E, 0, "no feedstock, no biogas power")

func landfill_rules() -> void:
	var m = fixture()
	advance(m, 60)
	var c: Dictionary = city(m, SEAT)
	var t: Dictionary = c.waste.totals
	eq(t.landfilled, t.municipal_collected, "household waste is landfilled through the municipal fleet")
	near(c.finance.totals.landfill_fees, A.mul(t.landfilled, 850000), 1, "0.85 credits per landfilled unit")
	near(c.landfill_damage_micro - m._balance.city.landfill_damage, A.mul(t.landfilled, 45000), 1, "0.045 damage per landfilled unit")
	var poor: Array = bench([])
	var p: Dictionary = poor[1]
	p.disposal_micro = 10 * U
	p.waste.totals.generated += 10 * U
	set_cash(p, 100000)
	poor[0].waste.landfill({"cities": [p]}, {})
	eq(p.waste.tick.landfilled, 117648, "0.1 credits pays for 0.117648 units at 0.85 with the fee remainder carried")
	check(p.money_micro >= 0 and p.finance.totals.landfill_fees <= 100000, "fees never exceed the treasury")
	eq(p.disposal_micro, 10 * U - 117648, "unpaid disposal waits in the queue")
	var mixed: Array = bench(["collection_center"])
	var x: Dictionary = mixed[1]
	x.disposal_micro = 500000
	x.mixed_micro[Waste.R] = 500000
	x.waste.totals.generated += 1000000
	mixed[0].waste.landfill({"cities": [x]}, {})
	eq([x.waste.tick.landfilled, x.disposal_micro, x.mixed_micro[Waste.R], x.waste.tick.landfilled_unsorted], [633333, 0, 366667, 133333], "the disposal queue goes first, then unsorted mixed waste")
