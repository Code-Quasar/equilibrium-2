extends "res://simulation/systems/economy/municipal.gd"
const A = preload("res://simulation/core/arithmetic.gd")
const Power = preload("res://simulation/systems/power.gd")
const Waste = preload("res://simulation/systems/waste.gd")
const LocalEnvironment = preload("res://simulation/systems/environment.gd")
var waste: RefCounted
var environment: RefCounted

func _init(config: Dictionary, buildings: RefCounted) -> void:
	super(config, buildings)
	waste = Waste.new(balance, catalogue)
	environment = LocalEnvironment.new(balance, catalogue)

func initialize_city(city: Dictionary) -> void:
	super.initialize_city(city)
	city["resource_systems_enabled"] = true
	city["local_carries"] = {}
	city["initial_materials_micro"] = city.materials_micro
	city["materials_sold"] = 0
	city["biogas_pending"] = {}
	city["processing_budgets"] = {}
	city["disposal_prepaid_fraction"] = 0
	city["disposed_this_tick"] = 0
	city["waste_totals"] = {"generated_by_source": {"household": [0,0,0], "factory": [0,0,0], "commerce": [0,0,0]}, "collected": 0, "recycled": 0, "organic_processed": 0}
	city["electricity"] = {"supply": 0, "demand": 0, "delivered": 0, "unused": 0,
		"shortage": 0, "imports": 0, "exports": 0, "municipal_requested": 0, "municipal_delivered": 0, "recipients": [], "biogas_available": 0}
	city["environment_status"] = "initial_stocks_not_yet_evaluated"
	city["overflow_micro"] = 0
	city["effective_air_micro"] = city.air_micro
	city.capacity["reliability_micro"] = A.S

func workforce(state: Dictionary, ctx: Dictionary, rng: RefCounted) -> String:
	super.workforce(state, ctx, rng)
	for city in state.cities:
		var previous: int = 0
		for building in city.buildings:
			if building.type == "biogas_facility" and building.funded:
				previous += city.biogas_pending.get(str(building.id), 0)
		city.previous_biogas_micro_E = previous
		city.capacity.generation_micro_E += previous
	return ""

func power_dependency(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		Power.allocate(city, catalogue, balance.municipal_base_demand_E * A.S + balance.municipal_demand_per_resident_micro_E * city.population)
		waste.prepare(city)
	return ""

func production(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		for building in Waste.ordered(city):
			if not building.operational: continue
			var d: Dictionary = catalogue.effects(building)
			var efficiency: int = A.efficiency(city, building)
			if d.income_micro_per_minute > 0:
				var rate: int = d.income_micro_per_minute
				if city.policy_active:
					var percent: int = balance.economy.policy_factory_income_percent if building.type == "factory" else balance.economy.policy_commerce_income_percent
					rate = A.mul(rate, percent, 100)
				var income: int = A.rate(city, "income:" + str(building.id), rate, efficiency)
				Finance.credit(city, income, "building_income", building.id)
				building.productive = true
				building.productive_ticks += 1
				city.operation_totals.productive_ticks += 1
			if d.waste_per_minute > 0:
				var source: String = "factory" if building.type == "factory" else "commerce"
				var rate: int = d.waste_per_minute * A.S
				if city.policy_active: rate = A.mul(rate, balance.local_simulation["policy_" + source + "_percent"], 100)
				waste.generate(city, source, "waste:" + str(building.id), rate, efficiency)
	return ""

func scores(state: Dictionary, ctx: Dictionary, rng: RefCounted) -> String:
	super.scores(state, ctx, rng)
	for city in state.cities:
		LocalEnvironment.satisfaction(city, balance.satisfaction)
	return ""
