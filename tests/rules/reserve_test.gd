extends "res://tests/support/harness.gd"
## The natural-resource reserve: it only declines; residents, non-renewable
## electricity and bought materials draw on it; renewable power and recycling
## slow it; at zero the city is eliminated, cannot act, loses its residents'
## goodwill and ranks below every survivor. Also prints how long typical
## strategies last, to keep the numbers honest.
const Reserve = preload("res://simulation/systems/reserve.gd")
const Migration = preload("res://simulation/systems/migration.gd")
const INDUSTRIAL = 0
const CIRCULAR = 1
const ENERGY = 2
const INVESTMENT = 3

func _initialize() -> void:
	declines_every_second()
	renewable_power_slows_it()
	recycling_slows_it()
	bought_materials_draw_it()
	elimination()
	strategies()
	finish("Reserve")

func declines_every_second() -> void:
	var m = fixture()
	var start: int = city(m, INVESTMENT).reserve.units_micro
	eq(start, 650 * U, "every city starts with 650 units")
	var previous: int = start
	var always_down: bool = true
	for i in range(120):
		advance(m, 1)
		var now: int = city(m, INVESTMENT).reserve.units_micro
		always_down = always_down and now <= previous
		previous = now
	check(always_down and previous < start, "the reserve never rises and falls over time")
	var c: Dictionary = city(m, INVESTMENT)
	check(c.reserve.totals.residents > 0 and c.reserve.totals.power > 0, "residents and grid electricity both draw on it")
	eq(c.reserve.units_micro, c.reserve.initial_micro - c.reserve.drawn_micro, "stock = start - drawn")

func renewable_power_slows_it() -> void:
	var m = fixture()
	advance(m, 60)
	var fossil_only: int = city(m, INVESTMENT).reserve.totals.power
	var green: int = city(m, ENERGY).reserve.totals.power
	check(city(m, ENERGY).reserve.renewable_share_micro > 0, "a renewable plant gives a clean share")
	check(green < fossil_only, "the Energy Pioneer's power draw is lower (%d < %d)" % [green, fossil_only])

func recycling_slows_it() -> void:
	var m = fixture()
	advance(m, 30)
	# Two copies of the same second, one with half its waste recovered.
	var plain: Dictionary = m.snapshot()
	var circular: Dictionary = m.snapshot()
	var c: Dictionary = circular.cities[INVESTMENT]
	c.waste.totals.recycled_materials += c.waste.totals.generated / 2
	eq(Reserve.circularity(c), U / 2, "circularity = recovered / generated")
	var ctx: Dictionary = {"start_tick": 30, "end_tick": 31}
	var base: int = plain.cities[INVESTMENT].reserve.totals.residents
	m.reserve.draw(plain, ctx)
	m.reserve.draw(circular, ctx)
	var a: int = 0
	var b: int = 0
	for i in range(59):
		m.reserve.draw(plain, ctx)
		m.reserve.draw(circular, ctx)
	a = plain.cities[INVESTMENT].reserve.totals.residents - base
	b = circular.cities[INVESTMENT].reserve.totals.residents - base
	check(b < a, "recycling half the waste cuts the residents' draw (%d < %d)" % [b, a])
	near(b * 1000 / a, 625, 3, "by 0.75 x 50 %% = 37.5 %%")

func bought_materials_draw_it() -> void:
	var m = fixture()
	var before: int = city(m, INVESTMENT).reserve.totals.materials
	eq(act(m, INVESTMENT, "construct", {"building_type": "residential_district", "size": "S"}), "applied", "a home is started")
	eq(city(m, INVESTMENT).reserve.totals.materials - before, 9 * U, "its 9 bought materials come out of the reserve")
	var twin = fixture()
	set_materials(city(twin, INVESTMENT), 20 * U)
	act(twin, INVESTMENT, "construct", {"building_type": "residential_district", "size": "S"})
	eq(city(twin, INVESTMENT).reserve.totals.materials, 0, "building from recovered stock draws nothing")

func elimination() -> void:
	var m = fixture()
	var c: Dictionary = city(m, INDUSTRIAL)
	# Ledger-consistent: lower the opening stock to almost nothing.
	c.reserve.initial_micro = c.reserve.drawn_micro + 1000
	c.reserve.units_micro = 1000
	advance(m, 2)
	c = city(m, INDUSTRIAL)
	eq(c.status, "eliminated", "a city whose reserve hits zero is eliminated")
	eq(c.reserve.units_micro, 0, "the reserve stops at zero")
	check(c.eliminated_tick > 0, "the tick is recorded")
	eq(act(m, INDUSTRIAL, "construct", {"building_type": "park", "size": "S"}), "city_eliminated", "an eliminated city cannot act")
	eq(m.preview(INDUSTRIAL, "construct", {"building_type": "park", "size": "S"}), "city_eliminated", "previews say so too")
	eq(m.build_options(INDUSTRIAL).park.S, "city_eliminated", "and so do build options")
	advance(m, 1)
	eq(city(m, INDUSTRIAL).satisfaction_micro, 0, "nobody wants to live there: Satisfaction 0")
	var rows: Array = Migration.ranking(m._state)
	eq(rows[3].city_id, INDUSTRIAL, "it ranks last")
	check(rows[3].eliminated and not rows[0].eliminated, "rankings say who is out")
	var population: int = city(m, INDUSTRIAL).population
	advance(m, 120)
	check(city(m, INDUSTRIAL).population < population, "its residents move away")
	eq(A.total(m._state.cities.map(func(x): return x.population)), 4000, "residents are never lost")

## Typical play, for calibration: how much is left after 20 minutes.
func strategies() -> void:
	var idle = fixture()
	advance(idle, 1199)
	var left: int = city(idle, INVESTMENT).reserve.units_micro
	print("  idle city keeps %d of 650 after 20 minutes" % (left / U))
	check(left > 0, "a city that builds nothing survives the match")
	var dirty = fixture()
	var c: Dictionary = city(dirty, INDUSTRIAL)
	set_cash(c, 100000 * U)
	for kind in ["factory", "factory", "fossil_power_plant", "residential_district", "commercial_district", "factory"]:
		place(dirty, c, kind, "L")
	var out_at: int = -1
	for t in range(1199):
		advance(dirty, 1)
		if out_at < 0 and city(dirty, INDUSTRIAL).status == "eliminated":
			out_at = dirty._state.tick
	print("  factories and fossil power, no recycling: %s" % ("eliminated at %d:%02d" % [out_at / 60, out_at % 60] if out_at > 0 else "survives with %d" % (city(dirty, INDUSTRIAL).reserve.units_micro / U)))
	check(out_at > 0, "an all-industry, no-recycling city runs out")
	var green = fixture()
	c = city(green, CIRCULAR)
	set_cash(c, 100000 * U)
	for kind in ["factory", "renewable_power_plant", "recycling_center", "residential_district", "biogas_facility", "renewable_power_plant"]:
		place(green, c, kind, "L")
	advance(green, 1199)
	var kept: int = city(green, CIRCULAR).reserve.units_micro
	print("  same industry with renewables and recycling keeps %d of 650" % (kept / U))
	check(city(green, CIRCULAR).status != "eliminated", "renewables and recycling let it last")
