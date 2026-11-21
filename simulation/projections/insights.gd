extends RefCounted
## Read-only projections. No persistent counters, RNG, forecasts or game mutations.
const A=preload("res://simulation/core/arithmetic.gd")
static func note(rows: Array, condition: String, measurements: Dictionary, cause: String, effect: String, actions: Array=[], severity: String="warning", relation: String="confirmed") -> void:
	rows.append({"condition":condition,"severity":severity,"measurements":measurements,"cause":cause,"relation":relation,"effect":effect,"possible_actions":actions})
static func city(state: Dictionary, owner: int, balance: Dictionary, catalogue: RefCounted, previous: Dictionary={}) -> Dictionary:
	var c: Dictionary=state.cities[owner]
	var rows: Array=[]
	# Score constraints use the population evaluated before migration, not the
	# newly published post-migration population.
	var evaluated_population: int=c.population
	if not state.transfer_ledger.is_empty() and state.transfer_ledger[-1].time==state.tick:
		evaluated_population=state.transfer_ledger[-1].before[owner]
	var street: int=A.total(c.uncollected_micro)
	var recovery: Dictionary={}
	var delta: Variant=null
	if not previous.is_empty() and previous.get("match_id")==state.match_id and previous.tick<state.tick:
		var old: Dictionary=previous.cities[owner]
		recovery={"from_tick":previous.tick,"to_tick":state.tick,"environment_change_micro":c.environment_micro-old.environment_micro,"air_change_micro":c.air_micro-old.air_micro,"landfill_change_micro":c.landfill_damage_micro-old.landfill_damage_micro,"street_change_micro":street-A.total(old.uncollected_micro)}
		if recovery.environment_change_micro>0:
			note(rows,"environmental_recovery",recovery,"measured_environment_increase","higher_environment_component",[],"info","observation")
	if state.tick>0:
		if street>0:note(rows,"collection_overload",{"uncollected_micro":c.uncollected_micro.duplicate(),"overflow_micro":c.overflow_micro},"uncollected_inventory","waste_environment_penalty",["build_recovery_hub","activate_waste_prevention"],"warning","contributor")
		for i in range(2):
			if c.sorted_micro[i]>0:note(rows,"recycling_capacity" if i==0 else "organic_capacity",{"remaining_sorted_micro":c.sorted_micro[i]},"untreated_sorted_inventory","waste_environment_penalty",["build_recycling_center" if i==0 else "build_biogas_facility","request_treatment"],"warning","contributor")
		if c.landfill_damage_micro>0:note(rows,"landfill_pressure",{"landfill_damage_micro":c.landfill_damage_micro,"disposed_this_tick_micro":c.disposed_this_tick},"accumulated_landfill_damage","lower_environment",["activate_waste_prevention","inspect_treatment"],"warning","contributor")
		if c.electricity.shortage>0:note(rows,"electricity_shortage",{"demand_micro_E":c.electricity.demand,"delivered_micro_E":c.electricity.delivered,"shortage_micro_E":c.electricity.shortage},"demand_exceeds_delivered_power","lower_power_satisfaction",["build_renewable_power_plant","request_electricity"])
		var required: int=evaluated_population*balance.satisfaction.capacity_requirement_percent
		if c.capacity.housing*100<required:note(rows,"housing_shortage",{"housing":c.capacity.housing,"population":c.population,"evaluated_population":evaluated_population,"requirement_percent":balance.satisfaction.capacity_requirement_percent},"housing_below_satisfaction_requirement","reduced_housing_component",["build_residential_district"])
		if c.capacity.services_micro*100<required*A.S:note(rows,"services_shortage",{"services_micro":c.capacity.services_micro,"population":c.population,"evaluated_population":evaluated_population,"requirement_percent":balance.satisfaction.capacity_requirement_percent},"services_below_satisfaction_requirement","reduced_services_component",["build_public_services_center"])
		if c.capacity.realized_jobs_micro<evaluated_population*A.S:note(rows,"employment_shortage",{"realized_jobs_micro":c.capacity.realized_jobs_micro,"population":c.population,"evaluated_population":evaluated_population},"realized_jobs_below_population","reduced_employment_component",["inspect_building_operation","build_commercial_district"])
	var buildings: Array=[]
	for plant in c.buildings:
		var efficiency: int=A.efficiency(c,plant)
		var status: String="unevaluated" if state.tick==0 else ("inactive" if not plant.operational else ("constrained" if efficiency<A.S else "operational"))
		buildings.append({"id":plant.id,"status":status,"enabled":plant.enabled,"funded":plant.funded,"power_factor_micro":plant.power_factor_micro,"staffing_micro":c.capacity.staffing_micro,"efficiency_micro":efficiency})
		if plant.funded and plant.enabled and plant.status=="complete":
			if plant.power_factor_micro<A.S:note(rows,"building_power_constraint",{"building_id":plant.id,"power_factor_micro":plant.power_factor_micro},"allocated_power_below_request","reduced_building_operation",["inspect_electricity"])
			if c.capacity.staffing_micro<A.S:note(rows,"building_staffing_constraint",{"building_id":plant.id,"staffing_micro":c.capacity.staffing_micro},"workers_below_funded_jobs","reduced_building_operation",["inspect_employment"])
		if plant.type=="factory" and efficiency>0:
			var emissions: int=A.mul(catalogue.effects(plant).air_micro_per_minute,efficiency)
			if emissions>0:note(rows,"industrial_pollution",{"building_id":plant.id,"emission_rate_micro_per_minute":emissions,"air_micro":c.air_micro},"operating_factory_emissions","air_pollution_pressure",["build_green_space","disable_factory"],"warning","contributor")
	for k in state.contracts:
		if k.status!="active" or owner not in [k.buyer,k.seller]:continue
		# Waste carries can vary a quantum between seconds; compare against floor rate.
		var expected: int=k.rate if k.type=="electricity" else A.divi(k.rate,60)
		if k.last_delivery<expected:note(rows,"contract_under_delivery",{"contract_id":k.id,"service":k.type,"last_delivery_micro":k.last_delivery,"nominal_tick_micro":expected,"valid_request":k.last_valid_request,"seller_capacity_micro":k.last_seller_capacity},"actual_delivery_below_nominal","less_service_and_usage_payment",["inspect_contract","cancel_contract"],"warning","observation")
	if not state.transfer_ledger.is_empty():
		var last: Dictionary=state.transfer_ledger[-1]
		delta=last.after[owner]-last.before[owner]
		if delta<0:note(rows,"population_decline",{"pulse_time":last.time,"delta":delta,"scores":last.satisfaction_micro.duplicate(),"before":last.before.duplicate(),"after":last.after.duplicate()},"regional_migration_allocation","fewer_residents",["inspect_migration","inspect_satisfaction"],"warning","observation")
	return {"city_id":owner,"tick":state.tick,"conditions":rows,"environment":{"air_micro":c.air_micro,"effective_air_micro":c.effective_air_micro,"street_waste_micro":street,"landfill_damage_micro":c.landfill_damage_micro,"overflow_micro":c.overflow_micro,"environment_micro":c.environment_micro},"activity":{"recycled_micro":c.waste_totals.recycled,"organic_processed_micro":c.waste_totals.organic_processed,"biogas_micro_E":c.previous_biogas_micro_E},"power_status":"unevaluated" if state.tick==0 else ("shortage" if c.electricity.shortage>0 else "stable"),"collection_status":"unevaluated" if state.tick==0 else ("overflow" if street>0 else "clear"),"buildings":buildings,"last_migration_delta":delta,"trend":recovery}
