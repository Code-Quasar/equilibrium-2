extends "res://tests/support/harness.gd"
## Municipal budget, upkeep, factory inputs, staffing, electricity, environment,
## Satisfaction, crises and the material market.
const INDUSTRIAL = 0
const CIRCULAR = 1
const ENERGY = 2
const INVESTMENT = 3

func _initialize() -> void:
	baseline_minute()
	factory_inputs()
	staffing()
	electricity()
	environment()
	crises()
	materials()
	municipal_shortfall()
	finish("Economy")

func baseline_minute() -> void:
	var m = fixture()
	advance(m, 1)
	var c: Dictionary = city(m, INVESTMENT)
	var parts: Dictionary = c.satisfaction_components_micro
	eq([parts.employment, parts.housing, parts.services, parts.power], [10 * U, 15 * U, 15 * U, 15 * U], "baseline employment 500/1000, full housing, services and power")
	eq(fixture()._state.cities[INVESTMENT].environment_micro, 96 * U, "starting Environment 100 - 3 air - 1 landfill = 96")
	eq(A.mul(35 * 96 * U, 1, 100) + 55 * U, 88600000, "so neutral starting Satisfaction is 33.6 + 55 = 88.6")
	eq(c.satisfaction_micro, parts.environment + 55 * U, "after one second only Environment has moved")
	eq(parts.environment, A.mul(35 * c.environment_micro, 1, 100), "Environment weighs 35 points")
	advance(m, 59)
	c = city(m, INVESTMENT)
	eq([c.finance.totals.taxes, c.finance.totals.municipal_upkeep], [110 * U, 52 * U], "0.11 per resident and 52 upkeep per minute")
	eq(city(m, INDUSTRIAL).finance.totals.building_upkeep, 22 * U, "factory upkeep 22 per minute")
	eq(c.power.municipal_requested_micro_E, 63 * U, "municipal demand 43 + 0.02 x 1000")
	eq(c.waste.totals.generated, 30 * U, "households generate 0.03 per resident per minute")

func factory_inputs() -> void:
	var m = fixture()
	advance(m, 60)
	var c: Dictionary = city(m, INDUSTRIAL)
	var f: Dictionary = c.finance.totals
	eq([f.building_income, f.material_purchases, f.emissions_levy], [145 * U, 42 * U, 1500000], "full factory: 145 income, 7 bought materials, 1.5 levy per minute")
	eq([c.materials.purchased, c.materials.used], [7 * U, 0], "with no stock every input is bought")
	eq(c.waste.totals.generated, 44 * U, "households 30 plus factory 14 per minute")
	var stocked = fixture()
	set_materials(city(stocked, INDUSTRIAL), 100 * U)
	advance(stocked, 60)
	c = city(stocked, INDUSTRIAL)
	eq([c.materials.used, c.materials.purchased, c.finance.totals.material_purchases, c.materials_micro], [7 * U, 0, 0, 93 * U], "stocked materials feed the factory first")
	var broke = fixture()
	set_cash(city(broke, INDUSTRIAL), 0)
	advance(broke, 1)
	c = city(broke, INDUSTRIAL)
	var factory: Dictionary = first(broke, INDUSTRIAL, "factory")
	check(factory.op.fraction_micro > 0 and factory.op.fraction_micro < U, "a factory short of cash for inputs runs partially")
	near(c.finance.tick.building_income, A.mul(145 * U, factory.op.fraction_micro, 60 * U), 1, "income follows the realized fraction")
	check(c.money_micro >= 0, "the treasury never goes negative")

func staffing() -> void:
	var m = fixture()
	var c: Dictionary = city(m, INVESTMENT)
	place(m, c, "fossil_power_plant", "L")
	for i in range(4):
		place(m, c, "factory")
	set_cash(c, 5000 * U)
	advance(m, 1)
	c = city(m, INVESTMENT)
	var factories: Array = of_type(c, "factory")
	eq(of_type(c, "fossil_power_plant")[0].op.workers, 32, "the plant is staffed before factories")
	eq(factories.map(func(x): return x.op.workers), [155, 155, 155, 3], "factories staff in plot order from 468 remaining workers")
	eq(factories[3].op.staff_micro, A.mul(3, U, 155), "the last factory runs at 3/155 staff")
	eq(factories[3].op.fraction_micro, factories[3].op.staff_micro, "operation follows the staff share")
	eq([c.employment.municipal, c.employment.buildings, c.satisfaction_components_micro.employment], [500, 500, 20 * U], "every resident employed")

func electricity() -> void:
	var m = fixture()
	var c: Dictionary = city(m, INVESTMENT)
	set_cash(c, 5000 * U)
	for i in range(3):
		place(m, c, "factory")
	place(m, c, "collection_center")
	advance(m, 1)
	c = city(m, INVESTMENT)
	eq(first(m, INVESTMENT, "collection_center").op.power_micro, U, "collection is powered before factories")
	var share: int = A.mul(10 * U, U, 26 * U)
	eq(of_type(c, "factory").map(func(x): return x.op.power_micro), [share, share, share], "factories share the remaining 30 E")
	eq(c.power.reliability_micro, A.mul(100 * U, U, 148 * U), "reliability is delivered over requested")
	eq(c.satisfaction_components_micro.power, 15 * c.power.reliability_micro, "power Satisfaction is 15 x reliability")
	var energy: Dictionary = city(m, ENERGY)
	eq([energy.power.plants_micro_E, energy.power.unused_micro_E], [75 * U, 112 * U], "the renewable plant adds 75 E; surplus is unused, not stored or sold")

func environment() -> void:
	var m = fixture()
	var c: Dictionary = city(m, INVESTMENT)
	set_cash(c, 5000 * U)
	place(m, c, "fossil_power_plant")
	advance(m, 60)
	c = city(m, INVESTMENT)
	eq(c.finance.totals.emissions_levy, 1900000, "fossil levy: 0.95 air points x 2 credits per minute")
	eq(c.air_micro, 3 * U + 950000 - 120000, "air gains emissions and loses 0.12 natural recovery")
	var green = fixture()
	c = city(green, INVESTMENT)
	place(green, c, "park")
	advance(green, 60)
	c = city(green, INVESTMENT)
	eq(c.air_micro, 3 * U - 120000 - 240000, "a Small park cleans 0.24 per minute")
	eq(c.amenity_micro, 1 * U, "a Small park adds 1 amenity point")
	check(c.landfill_damage_micro > 1 * U, "landfill damage keeps accumulating with a park")
	eq(c.environment_micro, 100 * U - c.air_micro - c.landfill_damage_micro - c.pressure_micro + c.amenity_micro, "Environment = 100 - air - landfill - pressure + amenity")
	var street = fixture()
	c = city(street, INVESTMENT)
	add_street(c, [100 * U, 0, 0])
	advance(street, 1)
	c = city(street, INVESTMENT)
	eq(c.pressure_micro, A.mul(A.total(c.street_micro), 160000) + A.mul(c.disposal_micro + A.total(c.sorted_micro), 25000), "street waste weighs 0.16, stored waste 0.025")

func crises() -> void:
	var m = fixture()
	var c: Dictionary = city(m, INVESTMENT)
	set_cash(c, 5000 * U)
	place(m, c, "fossil_power_plant")
	m._state.tick = 255
	advance(m, 1)
	eq(m._state.crisis.announced, ["smog_alert"], "smog announced 45 s ahead")
	m._state.tick = 300
	var air: int = city(m, INVESTMENT).air_micro
	advance(m, 60)
	c = city(m, INVESTMENT)
	eq(m._state.crisis.active, ["smog_alert"], "smog active")
	eq(c.air_micro - air, A.mul(950000, 1500000) - A.mul(120000, 500000), "smog: emissions x1.5, natural recovery x0.5")
	m._state.tick = 600
	var generated: int = city(m, ENERGY).waste.totals.generated
	var residents: int = city(m, ENERGY).population
	advance(m, 20)
	eq(city(m, ENERGY).waste.totals.generated - generated, 15000 * residents, "waste surge: household waste x1.5 (0.045 per resident per minute)")
	m._state.tick = 900
	advance(m, 1)
	eq(city(m, ENERGY).power.municipal_micro_E, 55 * U, "power shortage: municipal output x0.55")
	eq(city(m, ENERGY).power.plants_micro_E, 75 * U, "owned plants are unaffected")
	m._state.tick = 990
	advance(m, 1)
	eq([m._state.crisis.active, city(m, ENERGY).power.municipal_micro_E], [[], 100 * U], "crisis multipliers end on schedule")
	m._state.tick = 1150
	advance(m, 1)
	eq([m._state.crisis.announced, m._state.crisis.active], [["equilibrium_2050"], []], "EQUILIBRIUM 2050 is announced and has no economic effect")

func materials() -> void:
	var m = fixture()
	var c: Dictionary = city(m, CIRCULAR)
	set_materials(c, 499 * U)
	advance(m, 60)
	c = city(m, CIRCULAR)
	eq(c.materials_micro, 500 * U, "stock above 500 is sold at tick end")
	eq(c.finance.totals.material_sales, A.mul(c.materials.sold, 2 * U), "overflow sells at 2 credits per unit")
	eq(act(m, CIRCULAR, "sell_materials", {"amount": 100 * U}), "applied", "manual sale")
	eq(city(m, CIRCULAR).finance.tick.material_sales, 200 * U, "manual sale at 2 credits per unit")
	eq(act(m, CIRCULAR, "sell_materials", {"amount": 900 * U}), "insufficient_materials", "cannot sell more than the stock")
	eq(act(m, CIRCULAR, "sell_materials", {"amount": 0}), "invalid_payload", "nothing to sell")

func municipal_shortfall() -> void:
	var m = fixture()
	city(m, INVESTMENT).population = 400
	city(m, ENERGY).population = 1600
	set_cash(city(m, INVESTMENT), 0)
	check(advance(m, 120), "a city whose taxes no longer cover upkeep keeps running")
	var c: Dictionary = city(m, INVESTMENT)
	check(c.finance.unpaid_municipal_upkeep > 0 and c.money_micro >= 0, "unpaid municipal upkeep is recorded; the treasury stays non-negative")
