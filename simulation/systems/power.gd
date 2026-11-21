extends RefCounted
const A = preload("res://simulation/core/arithmetic.gd")
const TIERS = [["recovery_hub", "landfill"], ["biogas_facility", "recycling_center"], ["public_services_center"], ["commercial_district"], ["factory"]]

static func allocate(city: Dictionary, catalogue: RefCounted, municipal_demand: int, imports: int = 0, exports: int = 0) -> void:
	var supply: int = city.capacity.generation_micro_E + imports - exports
	var municipal_delivered: int = mini(supply, municipal_demand)
	var remaining: int = supply - municipal_delivered
	var records: Array = []
	var ordered: Array = city.buildings.duplicate()
	ordered.sort_custom(func(a, b): return a.id < b.id)
	for building in ordered:
		building["power_requested_micro_E"] = 0
		building["power_delivered_micro_E"] = 0
		building.power_factor_micro = 0
		building.operational = false
		if not building.funded: continue
		var d: Dictionary = catalogue.effects(building)
		var requested: Dictionary = A.product(d.demand_micro_E, city.capacity.staffing_micro, A.S)
		building.power_requested_micro_E = requested.q + (1 if requested.r > 0 else 0)
		if building.power_requested_micro_E == 0:
			building.power_factor_micro = A.S
			building.operational = true
	for tier in TIERS:
		var loads: Array = []
		var weights: Array = []
		for building in ordered:
			if building.funded and building.type in tier:
				loads.append(building)
				weights.append(building.power_requested_micro_E)
		var delivered: Array = A.allocate(remaining, weights)
		for i in range(loads.size()):
			var building: Dictionary = loads[i]
			building.power_delivered_micro_E = delivered[i]
			remaining -= delivered[i]
			building.power_factor_micro = A.mul(delivered[i], A.S, weights[i]) if weights[i] > 0 else A.S
			building.operational = building.power_factor_micro > 0
	var demand: int = municipal_demand
	for building in ordered:
		demand += building.power_requested_micro_E
		records.append({"id": building.id, "requested": building.power_requested_micro_E, "delivered": building.power_delivered_micro_E})
		if building.operational:
			building.operational_ticks += 1
			city.operation_totals.operational_ticks += 1
	var delivered: int = supply - remaining
	city.capacity.demand_micro_E = demand
	city.capacity["reliability_micro"] = A.mul(delivered, A.S, demand) if demand > 0 else A.S
	city.capacity.power_status = "all_loads_supplied" if delivered == demand else "partial_supply"
	city["electricity"] = {"supply": city.capacity.generation_micro_E, "demand": demand, "delivered": delivered,
		"unused": remaining, "shortage": demand - delivered, "imports": imports, "exports": exports,
		"municipal_requested": municipal_demand, "municipal_delivered": municipal_delivered,
		"recipients": records, "biogas_available": city.previous_biogas_micro_E}
