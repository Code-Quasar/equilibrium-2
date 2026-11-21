extends SceneTree
const Sim = preload("res://simulation/match.gd")
const M = preload("res://simulation/systems/migration.gd")
const A = preload("res://simulation/core/arithmetic.gd")
const FOUNDATIONS = ["industrial_legacy","circular_foundation","energy_pioneer","investment_district"]
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+label)
func _initialize() -> void:
	migration_tests()
	configuration_and_rollback()
	event_tests()
	preload("res://tests/support/lifecycle_cases.gd").run(check)
	preload("res://tests/support/local_cases.gd").run(check)
	preload("res://tests/support/placement_cases.gd").run(check)
	preload("res://tests/support/market_cases.gd").run(check)
	preload("res://tests/support/market_cases.gd").adversarial(check)
	preload("res://tests/support/market_cases.gd").organic_and_edges(check)
	full_match()
	print("Regional: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func migration_tests() -> void:
	var refs = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/exp_reference.json"))
	var previous: int = M.Q
	for pair in refs:
		var actual: int = M.weight(int(pair[0]))
		check(absi(actual-int(pair[1])) <= 1000, "exp absolute error <1e-9")
		check(actual <= previous, "monotone exp")
		previous = actual
	for turn in range(4):
		for budget in range(51):
			var caps: Array = [2,25,3,20]
			var allocated: Array = M.allocate(budget,[100,50,1000,20],caps,turn)
			check(A.total(allocated)==budget, "capped reallocation uses feasible capacity")
			for i in range(4): check(allocated[i]>=0 and allocated[i]<=caps[i], "allocation cap")
	var sim = Sim.new()
	check(sim.initialize("migration",42,FOUNDATIONS)=="", "initialize complete match")
	var state: Dictionary = sim.snapshot()
	for c in state.cities: c.satisfaction_micro = 80000000
	var rules: Dictionary = {"sender_cap":25,"receiver_cap":30,"regional_cap":50}
	var rec: Dictionary = M.pulse(state,rules)
	check(rec.transferred==0 and rec.after==[1000,1000,1000,1000],"equal scores")
	state.cities[0].satisfaction_micro = 86000000
	rec=M.pulse(state,rules)
	check(rec.received[0]==30 and rec.total==4000,"attractive city receiver cap")
	for case in range(100):
		for i in range(4):
			state.cities[i].satisfaction_micro = ((case*17+i*31)%101)*A.S
			state.cities[i].capacity.housing = 500+(case*23+i*41)%1700
		rec=M.pulse(state,rules)
		check(rec.total==4000 and rec.transferred<=50,"pulse conservation")
		for i in range(4):
			check(rec.after[i]>=500 and rec.sent[i]<=25 and rec.received[i]<=30,"founder/caps")
			check(rec.received[i]==0 or rec.after[i]<=rec.housing[i],"incoming housing ceiling")
	for c in state.cities:
		c.population=1000;c.satisfaction_micro=80000000;c.environment_micro=80000000;c.money_micro=1000000
	check(M.ranking(state).all(func(r): return r.rank==1),"shared exact tie")
	for field in ["money_micro","environment_micro","satisfaction_micro","population"]:
		state.cities[3][field]+=1
		check(M.ranking(state)[0].city_id==3,"ranking "+field)
		state.cities[3][field]-=1
func full_match() -> void:
	var sim = Sim.new()
	check(sim.initialize("regional-full",42,FOUNDATIONS)=="","full initialize")
	for tick in range(1200):
		var before: Dictionary = {}
		if tick in [80,100,660,940,1140]:
			before=sim.snapshot()
		var result: Dictionary = sim.step()
		if not before.is_empty() and result.status=="advanced":
			var after: Dictionary=sim.snapshot()
			for i in range(4):
				var c: Dictionary=before.cities[i]
				var expected: int=A.divi(100000000+c.population*70000+c.rate_carries.get("municipal_income",0),60)
				check(after.cities[i].finance.totals.municipal_income-c.finance.totals.municipal_income==expected,"migration feeds municipal income")
				check(after.cities[i].electricity.municipal_requested==85000000+c.population*20000,"migration feeds power demand")
				check(after.cities[i].capacity.staffing_micro==mini(A.S,A.divi(c.population*A.S,after.cities[i].capacity.potential_jobs)),"migration feeds staffing")
		check(result.status=="advanced","advance "+str(tick)+str(result))
		if result.status!="advanced": return
	var state: Dictionary = sim.snapshot()
	check(state.transfer_ledger.size()==57,"57 migrations")
	check(state.transfer_ledger[0].time==80 and state.transfer_ledger[-1].time==1200,"pulse endpoints")
	check(state.final_result!=null and state.status=="finished","winner/freeze")
	var frozen: String = sim.serialize()
	check(sim.step().status=="match_closed" and sim.serialize()==frozen,"no post-match mutation")
	print("Regional actual final: "+JSON.stringify(state.final_result))

func event_tests() -> void:
	var sim = Sim.new()
	check(sim.initialize("events",7,FOUNDATIONS)=="","events init")
	var state: Dictionary = sim.snapshot()
	for event in state.event_schedule:
		for time in [event.warning-1,event.warning,event.start-1,event.start,event.start+1,event.end-1,event.end,event.end+1]:
			state.tick=time
			Sim.Events.apply(state,state.event_schedule,sim._balance)
			check((event.id in state.event_state.active)==(time>=event.start and time<event.end),"event active boundary")
			check((event.id in state.event_state.warnings)==(time>=event.warning and time<event.start),"warning boundary")
			if time>=event.start and time<event.end:
				for key in event.modifiers: check(state.cities[0].event_modifiers[key]==event.modifiers[key],"event modifier")

func configuration_and_rollback() -> void:
	var cfg: Dictionary=Sim.Balance.load_b1()
	check(preload("res://simulation/core/regional_config.gd").validate(cfg)=="","regional config")
	var broken: Dictionary=cfg.duplicate(true)
	broken.market.prices.electricity.step=0
	check(preload("res://simulation/core/regional_config.gd").validate(broken)!="","zero price step rejected")
	var sim=Sim.new();sim.initialize("rollback",42,FOUNDATIONS)
	sim.register_system("migration","zz_failure",func(state,_ctx,rng):
		rng.next_int();state.cities[0].population+=1;return "forced_failure")
	var before: String=sim.serialize()
	check(sim.step().status=="tick_rejected" and sim.serialize()==before,"regional atomic state/RNG rollback")
