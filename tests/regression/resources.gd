extends SceneTree
const Sim = preload("res://tests/support/resource_simulation.gd")
const A = preload("res://simulation/core/arithmetic.gd")
const Power = preload("res://simulation/systems/power.gd")
const Env = preload("res://simulation/systems/environment.gd")
const Validation = preload("res://simulation/core/resource_invariants.gd")
const S: int = 1000000
const FOUNDATIONS = ["industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"]
var checks: int = 0
var failures: int = 0
var seq: int = 0

func _initialize() -> void:
	arithmetic()
	opening()
	power_cases()
	generation_collection()
	recycling()
	biogas()
	landfill_materials()
	environment_scores()
	additional_boundaries()
	integration()
	print("Resources: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL resources: " + label)

func fresh():
	var sim = Sim.new()
	check(sim.initialize("resource-test",42,FOUNDATIONS) == "", "initialize")
	return sim

func run(sim, count: int = 1) -> bool:
	for _i in range(count):
		var result: Dictionary = sim.step()
		check(result.status == "advanced", "advance " + str(result))
		if result.status != "advanced": return false
		check(sim._validate_state(sim.snapshot()) == "", "all invariant checks")
	return true

func command(sim, kind: String, payload: Dictionary, owner: int = 3) -> Dictionary:
	seq += 1
	var c: Dictionary = {"match_id":"resource-test", "player_id":owner, "command_seq":seq,
		"command_id":str(seq), "command_type":kind, "payload":payload, "server_received_tick":sim.snapshot().tick}
	check(sim.submit(c,owner).status == "queued", "admit " + kind)
	return c

# Trusted conserved fixtures only; never exposed as player commands.
func add(sim, kind: String, level: int = 1, owner: int = 3) -> Dictionary:
	var c: Dictionary = sim._state.cities[owner]
	var b: Dictionary = sim._buildings.record(c.next_building_id,kind,owner,sim._buildings.next_tile(c),sim._state.tick,true)
	c.next_building_id += 1
	b.level = level
	c.buildings.append(b)
	return b

func stock(sim, category: int, amount: int, owner: int = 3) -> void:
	var c: Dictionary = sim._state.cities[owner]
	c.sorted_micro[category] += amount
	c.mass_ledger_micro.generated += amount
	c.waste_totals.generated_by_source.household[category] += amount
	c.waste_totals.collected += amount

func cash(sim, amount: int, owner: int = 3) -> void:
	var c: Dictionary = sim._state.cities[owner]
	c.finance.initial_cash += amount - c.money_micro
	c.money_micro = amount

func arithmetic() -> void:
	check(A.allocate(2,[1,1,1]) == [1,1,0], "largest remainder stable tie")
	check(A.allocate(100,[1,2,3]) == [1,2,3], "allocation cannot exceed request")
	check(A.allocate(0,[1,2]) == [0,0] and A.allocate(1,[0,0]) == [0,0], "zero allocation")
	check(A.product(4000000000,4000000000,4000000000) == {"q":4000000000,"r":0}, "overflow safe product")
	for x in range(12):
		for y in range(12):
			for budget in range(12):
				var out: Array = A.allocate(budget,[x,y,3])
				check(A.total(out) == mini(budget,x+y+3) and out[0] <= x and out[1] <= y and out[2] <= 3, "exhaustive small conserved allocation")
	var s = fresh()
	var config: Dictionary = s._balance.duplicate(true)
	config.local_simulation.reuse_yield_percent = 101
	check(Validation.config(config) != "", "bad yield rejected")
	config = s._balance.duplicate(true)
	config.local_simulation.erase("landfill_price_micro")
	check(Validation.config(config) != "", "missing local rule rejected")

func opening() -> void:
	var sim = fresh()
	check(sim.snapshot().cities.size() == 4, "four cities")
	check(sim.snapshot().cities[3].satisfaction_micro == null, "no pre-operation score")
	if not run(sim,60): return
	var c: Dictionary = sim.snapshot().cities[3]
	check(c.money_micro == 997*S, "neutral minute net97")
	check(c.mass_ledger_micro.generated == 40*S and c.mass_ledger_micro.disposed == 40*S, "household exact minute mass")
	check(c.waste_totals.generated_by_source.household == [18*S,14*S,8*S], "household composition")
	check(c.environment_micro == 86250000 and c.satisfaction_micro == 86387500, "neutral evolving environment and Satisfaction")
	c = sim.snapshot().cities[1]
	check(c.mass_ledger_micro.recovered == 15900000 and c.mass_ledger_micro.disposed == 24100000, "spec household recycling15.9/24.1")
	check(c.materials_micro == 15900000 and c.money_micro == 727080000, "Circular inventory and disposal bill")
	c = sim.snapshot().cities[0]
	check(c.mass_ledger_micro.generated == 70*S and A.total(c.uncollected_micro) == 10*S and A.total(c.sorted_micro) == 10*S, "Factory backlog collection/disposal bottlenecks")
	check(c.waste_totals.generated_by_source.factory == [15*S,3*S,12*S], "Factory fractions")
	var bad: Dictionary = sim.snapshot()
	bad.cities[3].materials_micro += 1
	check(sim._validate_state(bad) == "material_conservation", "forged material rejected")

func power_cases() -> void:
	var sim = fresh()
	add(sim,"factory")
	add(sim,"recycling_center")
	if not run(sim): return
	var c: Dictionary = sim.snapshot().cities[3]
	check(c.electricity.supply == 145*S and c.electricity.demand == 159*S, "specified shortage159/145")
	check(c.buildings[1].power_delivered_micro_E == 16*S and c.buildings[0].power_delivered_micro_E == 24*S, "processing priority over Factory")
	check(c.buildings[0].power_factor_micro == 631578 and c.buildings[0].operational, "fractional operation legal")
	check(c.finance.totals.building_income == A.divi(155*S*631578,60*S), "partial Factory income")
	check(c.finance.totals.building_upkeep == 550000, "full fixed upkeep despite shortage")
	check(c.capacity.realized_jobs_micro == 849473400, "partial realized jobs")
	# Direct dispatch fixtures cover severe/zero/exact supply without changing B1.
	var local: Dictionary = c.duplicate(true)
	local.capacity.generation_micro_E = 100*S
	Power.allocate(local,sim._buildings,105*S)
	check(local.electricity.municipal_delivered == 100*S and local.buildings[0].power_delivered_micro_E == 0, "municipal shortage first")
	local.capacity.generation_micro_E = 159*S
	Power.allocate(local,sim._buildings,105*S)
	check(local.electricity.unused == 0 and local.electricity.shortage == 0, "exact sufficiency")
	local.capacity.generation_micro_E = 0
	for building in local.buildings: building.funded = false
	Power.allocate(local,sim._buildings,0)
	check(local.capacity.reliability_micro == S and local.electricity.delivered == 0, "zero demand reliability")
	var tiers = fresh()
	for kind in ["factory","commercial_district","public_services_center","biogas_facility","recycling_center","landfill","recovery_hub"]: add(tiers,kind)
	run(tiers)
	c = tiers.snapshot().cities[3]
	check(c.buildings[5].power_factor_micro == S and c.buildings[6].power_factor_micro == S, "top optional tier full")
	check(c.buildings[0].power_delivered_micro_E == 0, "Factory last")
	var two = fresh()
	add(two,"factory")
	add(two,"factory")
	run(two)
	c = two.snapshot().cities[3]
	check(c.buildings[0].power_delivered_micro_E == c.buildings[1].power_delivered_micro_E, "equal same-tier shares")
	check(c.capacity.staffing_micro < S, "staffing dilution")
	var disabled = fresh()
	command(disabled,"disable",{"building_id":0},2)
	run(disabled)
	check(disabled.snapshot().cities[2].electricity.supply == 145*S, "disabled plant zero generation")
	var unfunded = fresh()
	for _i in range(20): add(unfunded,"renewable_power_plant")
	cash(unfunded,0)
	run(unfunded)
	c = unfunded.snapshot().cities[3]
	check(c.operation_totals.funding_failures > 0 and not c.buildings[-1].operational, "unfunded plant cannot generate")

func generation_collection() -> void:
	var sim = fresh()
	add(sim,"commercial_district")
	command(sim,"set_reduce_waste",{"enabled":true})
	command(sim,"set_reduce_waste",{"enabled":true},0)
	run(sim,60)
	var c: Dictionary = sim.snapshot().cities[3]
	check(c.waste_totals.generated_by_source.household == [13500000,10500000,6000000], "prevention household")
	check(c.waste_totals.generated_by_source.commerce == [5400000,2250000,1350000], "prevention Commerce")
	check(c.finance.totals.building_income == 85500000 and c.finance.totals.policy == 18*S, "policy income and fee exactly once")
	check(sim.snapshot().cities[0].waste_totals.generated_by_source.factory == [13500000,2700000,10800000], "prevention Factory")
	command(sim,"set_reduce_waste",{"enabled":false})
	run(sim,60)
	c = sim.snapshot().cities[3]
	check(c.waste_totals.generated_by_source.commerce == [11400000,4750000,2850000], "Commerce OFF subsequent generation")
	var hub = fresh()
	add(hub,"recovery_hub")
	stock(hub,0,3*S)
	# Transfer conserved stock to street; proportional collection must preserve categories.
	var h: Dictionary = hub._state.cities[3]
	h.sorted_micro[0] -= 3*S
	h.uncollected_micro[0] += 3*S
	h.waste_totals.collected -= 3*S
	run(hub)
	check(A.total(hub.snapshot().cities[3].uncollected_micro) < 3*S, "extra collection clears backlog")

func recycling() -> void:
	for level in [1,2]:
		var sim = fresh()
		var building: Dictionary = add(sim,"recycling_center",level)
		var c: Dictionary = sim._state.cities[3]
		building.funded = true
		building.operational = true
		building.power_factor_micro = S
		var totals: Array = [0,0,0]
		for _i in range(60):
			sim._economy.waste.prepare(c)
			var result: Dictionary = sim._economy.waste.process(c,building,100*S,false)
			totals[0] += result.input
			totals[1] += result.output
			totals[2] += result.rejects
		check(totals[0] == (35 if level == 1 else 60)*S, "L1/L2 capacity")
		check(totals[1] == (29500000 if level == 1 else 50400000), "full reuse plus recycling yield")
		check(totals[0] == totals[1]+totals[2], "yield exact conservation")
		sim._economy.waste.prepare(c)
		check(sim._economy.waste.process(c,building,0,false).output == 0, "no recyclable input")
		var partial: Dictionary = sim._economy.waste.process(c,building,1000,false)
		check(partial.output == 950 and partial.rejects == 50, "below reuse slice")
		building.power_factor_micro = 500000
		c.capacity.staffing_micro = 500000
		var processed: int = 0
		for _i in range(60):
			sim._economy.waste.prepare(c)
			processed += sim._economy.waste.process(c,building,100*S,false).input
		check(absi(processed - (8750000 if level == 1 else 15000000)) <= 1, "staffing times power throughput")
		# Multiple uses of a budget cannot reset the high-yield slice or capacity.
		sim._economy.waste.prepare(c)
		var capacity: int = c.processing_budgets[str(building.id)].remaining
		var first: Dictionary = sim._economy.waste.process(c,building,capacity,false)
		var second: Dictionary = sim._economy.waste.process(c,building,capacity,false)
		check(first.input == capacity and second.input == 0, "shared contracted/local budget boundary")

func biogas() -> void:
	for action in ["none","disable","demolish","unfunded","upgrade","no_input","shortage"]:
		var sim = fresh()
		var building: Dictionary = add(sim,"biogas_facility")
		stock(sim,1,100*S)
		run(sim)
		var c: Dictionary = sim.snapshot().cities[3]
		check(c.electricity.biogas_available == 0 and c.biogas_pending["0"] == 90*S, "no same-tick Biogas; full L1 next90")
		check(c.mass_ledger_micro.organic_sink == 450000 and c.waste_totals.organic_processed == 500000, "Biogas90/10")
		if action in ["disable","demolish"]: command(sim,action,{"building_id":0})
		if action == "unfunded":
			cash(sim,0)
			for _i in range(20): add(sim,"renewable_power_plant")
			var real: Dictionary = sim._state.cities[3].buildings[0]
			real.created_tick = 100
		if action == "upgrade": sim._state.cities[3].buildings[0].level = 2
		if action == "no_input":
			var target: Dictionary = sim._state.cities[3]
			var removed: int = target.sorted_micro[1]
			target.sorted_micro[1] = 0
			target.uncollected_micro[1] += removed
			target.waste_totals.collected -= removed
			# Disable collection via isolated processing test below; household input remains real in integrated run.
		if action == "shortage":
			for _i in range(10): add(sim,"recovery_hub")
		run(sim)
		c = sim.snapshot().cities[3]
		if action in ["disable","demolish","unfunded"]:
			check(c.electricity.biogas_available == 0 and A.total(c.biogas_pending.values()) == 0, "Biogas lifecycle discards " + action)
		else:
			check(c.electricity.biogas_available == 90*S, "eligible prior output not rescaled " + action)
		if action == "upgrade": check(c.biogas_pending["0"] == 149999940, "L2 rate first interval carry")
		check(c.development_micro >= 0, "earned development bounded")
	var empty = fresh()
	var plant: Dictionary = add(empty,"biogas_facility")
	var city: Dictionary = empty._state.cities[3]
	plant.funded = true
	plant.operational = true
	plant.power_factor_micro = S
	city.biogas_pending["0"] = 90*S
	for target in empty._state.cities: empty._economy.waste.prepare(target)
	empty._economy.waste.local_processing(empty._state,{},null)
	check(city.biogas_pending["0"] == 0, "no input overwrites deferred energy")

func landfill_materials() -> void:
	var sim = fresh()
	stock(sim,0,S)
	stock(sim,1,S)
	stock(sim,2,S)
	var c: Dictionary = sim._state.cities[3]
	cash(sim,1) # One microcredit buys no whole micro-unit at price1.2.
	sim._economy.waste.landfill(sim._state,{},null)
	check(c.mass_ledger_micro.disposed == 0 and c.money_micro == 1, "cannot dispose unpaid fraction")
	cash(sim,2)
	sim._economy.waste.landfill(sim._state,{},null)
	check(c.mass_ledger_micro.disposed == 1 and c.sorted_micro == [S,S,S-1] and c.money_micro == 0, "affordable residual first")
	check(c.disposal_prepaid_fraction == 800000, "fractional charge prepaid exactly")
	check(sim._validate_state(sim._state) == "", "fractional cash/mass reconciliation")
	cash(sim,10*S)
	sim._economy.waste.landfill(sim._state,{},null)
	check(c.sorted_micro[0] == S and c.sorted_micro[1] == S, "residual priority")
	sim._economy.waste.landfill(sim._state,{},null)
	check(c.sorted_micro[1] < S and c.sorted_micro[0] == S, "organic before recyclable")
	var materials = fresh()
	var m: Dictionary = materials._state.cities[3]
	m.initial_materials_micro = 100*S
	m.materials_micro = 100*S
	command(materials,"construct",{"building_type":"factory"})
	run(materials)
	m = materials.snapshot().cities[3]
	check(m.finance.materials_spent == 65*S and m.finance.totals.construction == 195*S, "25 percent ceiling")
	check(m.materials_sold == 15*S and m.materials_micro == 20*S and m.finance.totals.material_sales == 12*S, "surplus sales after spending")
	command(materials,"cancel_project",{"building_id":0})
	run(materials)
	check(materials.snapshot().cities[3].finance.totals.refunds == 97500000, "cash-only half cancellation")
	var fractional = fresh()
	m = fractional._state.cities[3]
	m.initial_materials_micro = 20*S+1
	m.materials_micro = 20*S+1
	fractional._economy.waste.material_sales(fractional._state,{},null)
	check(m.materials_micro == 20*S and m.finance.totals.material_sales == 0 and m.local_carries.material_sale.r == 800000, "fractional sale receivable")
	check(fractional._validate_state(fractional._state) == "", "material sale exact reconciliation")

func environment_scores() -> void:
	var sim = fresh()
	var c: Dictionary = sim._state.cities[3]
	c.capacity.reliability_micro = S
	c.electricity.demand = 105*S
	c.electricity.delivered = 105*S
	Env.satisfaction(c,sim._balance.satisfaction)
	check(c.satisfaction_micro == 86650000, "exact neutral opening formula")
	c.environment_micro = 0
	c.capacity.realized_jobs_micro = 0
	c.capacity.housing = 0
	c.capacity.services_micro = 0
	c.electricity.delivered = 0
	Env.satisfaction(c,sim._balance.satisfaction)
	check(c.satisfaction_micro == 0, "score lower boundary")
	c.environment_micro = 100*S
	c.capacity.realized_jobs_micro = 1000*S
	c.capacity.housing = 2000
	c.capacity.services_micro = 2000*S
	c.electricity.delivered = c.electricity.demand
	Env.satisfaction(c,sim._balance.satisfaction)
	check(c.satisfaction_micro == 100*S, "score upper boundary")
	for kind in ["factory","commercial_district","fossil_power_plant","green_space"]:
		var local = fresh()
		add(local,kind)
		run(local,60)
		var expected: Dictionary = {"factory":9900000,"commercial_district":7950000,"fossil_power_plant":10500000,"green_space":6200000}
		check(local.snapshot().cities[3].air_micro == expected[kind], "minute air " + kind)
	var park = fresh()
	add(park,"green_space")
	park._state.cities[3].air_micro = 0
	stock(park,2,100*S)
	run(park)
	c = park.snapshot().cities[3]
	check(c.air_micro == 0 and c.landfill_damage_micro > 5*S and A.total(c.sorted_micro) > 99*S, "park cannot clean landfill or waste; clamp zero")
	var dirty = fresh()
	for _i in range(10): add(dirty,"fossil_power_plant")
	dirty._state.cities[3].air_micro = 40*S
	dirty._state.cities[3].landfill_damage_micro = 35*S
	stock(dirty,2,1000*S)
	run(dirty)
	c = dirty.snapshot().cities[3]
	check(c.air_micro == 40*S and c.landfill_damage_micro == 35*S and c.overflow_micro == 45*S and c.environment_micro == 0, "all environmental clamps")
	var partial = fresh()
	for _i in range(4): add(partial,"public_services_center")
	run(partial)
	c = partial.snapshot().cities[3]
	check(c.capacity.services_micro == 3033332600 and c.capacity.staffing_micro == S, "services power fraction without staffing reduction")
	var bio_short = fresh()
	add(bio_short,"biogas_facility")
	for _i in range(10): add(bio_short,"recovery_hub")
	stock(bio_short,1,100*S)
	run(bio_short)
	check(bio_short.snapshot().cities[3].biogas_pending["0"] == 0, "unpowered Biogas produces nothing")

func integration() -> void:
	var sim = fresh()
	var a: Dictionary = command(sim,"construct",{"building_type":"residential_district"})
	check(sim.submit(a,3).status == "duplicate", "resource build retry")
	command(sim,"construct",{"building_type":"recycling_center","price":0})
	var result: Dictionary = sim.step()
	check(result.status == "advanced" and result.commands[1].status == "invalid_payload", "adversarial price injection rejected")
	run(sim,21)
	check(sim.snapshot().cities[3].capacity.housing == 1200, "no early completion")
	run(sim)
	check(sim.snapshot().cities[3].capacity.housing == 1650, "completion operates at22")
	var dev: int = sim.snapshot().cities[3].development_micro
	command(sim,"demolish",{"building_id":0})
	run(sim)
	check(sim.snapshot().cities[3].development_micro >= dev, "demonstrated peak survives demolition")
	var circular = fresh()
	run(circular,60)
	dev = circular.snapshot().cities[1].development_micro
	command(circular,"disable",{"building_id":0},1)
	run(circular,20)
	check(circular.snapshot().cities[1].development_micro == dev and circular.snapshot().cities[1].mass_ledger_micro.recovered == 15900000, "no circular credit without new processing")
	var rollback = fresh()
	command(rollback,"construct",{"building_type":"factory"})
	rollback.register_system("material_sales","zz_corrupt",func(s,_c,r):
		s.cities[3].materials_micro += 1
		r.next_int()
		return "")
	var before: String = rollback.serialize()
	check(rollback.step().status == "tick_rejected" and rollback.serialize() == before, "resource systems RNG commands roll back")
	var full = fresh()
	command(full,"construct",{"building_type":"renewable_power_plant"},0)
	command(full,"construct",{"building_type":"recycling_center"},3)
	if not run(full,1200): return
	for city in full.snapshot().cities:
		check(city.population == 1000 and city.satisfaction_micro != null and city.development_micro <= 100*S, "complete local city score/population")
	before = full.serialize()
	check(full.step().status == "match_closed" and full.serialize() == before, "final freeze")
	check(full.snapshot().final_result == null and full.snapshot().contracts.is_empty(), "resource harness excludes regional systems")

func additional_boundaries() -> void:
	check(A.allocate(5,[2,3,7]) == [1,1,3], "unequal proportional remainders")
	var failed_policy = fresh()
	for _i in range(20): add(failed_policy,"renewable_power_plant")
	cash(failed_policy,0)
	command(failed_policy,"set_reduce_waste",{"enabled":true})
	run(failed_policy)
	var c: Dictionary = failed_policy.snapshot().cities[3]
	check(c.reduce_waste and not c.policy_active and c.finance.totals.policy == 0, "failed policy fee preserves desired state only")
	check(c.mass_ledger_micro.generated == 666666, "failed prevention does not reduce household waste")
	for level in [1,2]:
		var sim = fresh()
		var plant: Dictionary = add(sim,"biogas_facility",level)
		var city: Dictionary = sim._state.cities[3]
		plant.funded = true
		plant.operational = true
		plant.power_factor_micro = 500000
		city.capacity.staffing_micro = 500000
		var input_mass: int = 0
		var converted: int = 0
		var rejects: int = 0
		for _i in range(60):
			sim._economy.waste.prepare(city)
			var result: Dictionary = sim._economy.waste.process(city,plant,100*S,true)
			input_mass += result.input
			converted += result.output
			rejects += result.rejects
		check(input_mass == (7500000 if level == 1 else 12500000), "Biogas partial power and staffing L"+str(level))
		check(converted == input_mass*9/10 and rejects+converted == input_mass, "Biogas fractional conversion exact minute")
	var dormant = fresh()
	add(dormant,"fossil_power_plant")
	command(dormant,"disable",{"building_id":0})
	run(dormant,60)
	check(dormant.snapshot().cities[3].air_micro == 7700000, "disabled polluter emits nothing")
	var disposal = fresh()
	add(disposal,"landfill")
	stock(disposal,2,100*S)
	run(disposal,60)
	check(disposal.snapshot().cities[3].mass_ledger_micro.disposed == 105*S, "funded landfill adds55 to base50")
	var bio_dev = fresh()
	add(bio_dev,"biogas_facility")
	stock(bio_dev,1,100*S)
	run(bio_dev)
	var first: int = bio_dev.snapshot().cities[3].development_micro
	run(bio_dev)
	c = bio_dev.snapshot().cities[3]
	check(c.peaks.generation_micro_E == 235*S and c.development_micro > first, "Biogas earns own generation peak only when available")
	var invalid: Dictionary = bio_dev.snapshot()
	invalid.cities[3].electricity.recipients[0].delivered += S
	check(bio_dev._validate_state(invalid) != "", "overallocated electricity rejected")
	invalid = bio_dev.snapshot()
	invalid.cities[3].local_carries["bad"] = {"r":60,"d":60}
	check(bio_dev._validate_state(invalid) == "invalid_local_carry", "invalid residue rejected")
	invalid = bio_dev.snapshot()
	invalid.cities[3].mass_ledger_micro.generated += 1
	check(bio_dev._validate_state(invalid) != "", "invented mass rejected")
