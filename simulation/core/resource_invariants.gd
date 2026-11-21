extends RefCounted
const A = preload("res://simulation/core/arithmetic.gd")
const REQUIRED = ["household_waste_micro_per_resident_minute", "household_R_percent", "household_O_percent", "household_X_percent", "factory_R_percent", "factory_O_percent", "factory_X_percent", "commerce_R_percent", "commerce_O_percent", "commerce_X_percent", "policy_household_percent", "policy_factory_percent", "policy_commerce_percent", "reuse_yield_percent", "recycle_yield_percent", "organic_sink_percent", "biogas_E_per_unit_minute", "landfill_price_micro", "material_reserve_micro", "material_sale_price_micro", "air_max_micro", "landfill_max_micro", "overflow_max_micro", "air_recovery_micro_per_minute", "landfill_recovery_micro_per_minute", "landfill_damage_per_unit_micro", "uncollected_penalty_micro", "sorted_penalty_micro"]

static func config(b: Dictionary) -> String:
	if not b.get("local_simulation") is Dictionary: return "missing_local_simulation"
	var r: Dictionary = b.local_simulation
	for key in REQUIRED:
		if typeof(r.get(key)) != TYPE_INT or r[key] < 0 or r[key] > 100000000: return "invalid_local_rule:" + key
		if key.ends_with("percent") and r[key] > 100: return "invalid_local_percentage"
	for source in ["household", "factory", "commerce"]:
		if r[source+"_R_percent"] + r[source+"_O_percent"] + r[source+"_X_percent"] != 100: return "invalid_composition"
	if r.landfill_price_micro <= 0 or r.biogas_E_per_unit_minute > 100 or b.initial_waste != 0 or b.initial_materials != 0: return "invalid_local_bounds"
	return ""

static func city(c: Dictionary, rules: Dictionary, complete_game: bool = false) -> String:
	if not complete_game and c.population != 1000: return "resource_scope_population_changed"
	var m: Dictionary = c.mass_ledger_micro
	var imported: int = c.get("trade_mass", {}).get("imports", 0)
	var exported: int = c.get("trade_mass", {}).get("exports", 0)
	if imported < 0 or exported < 0: return "negative_trade_mass"
	if m.generated + imported - exported != A.total(c.uncollected_micro) + A.total(c.sorted_micro) + m.recovered + m.organic_sink + m.disposed: return "city_waste_conservation"
	if c.materials_micro != c.initial_materials_micro + m.recovered - c.finance.materials_spent - c.materials_sold: return "material_conservation"
	if c.materials_sold < 0 or c.finance.materials_spent < 0: return "negative_material_ledger"
	var generated: int = 0
	for amounts in c.waste_totals.generated_by_source.values():
		for amount in amounts:
			if typeof(amount) != TYPE_INT or amount < 0: return "invalid_source_mass"
			generated += amount
	if generated != m.generated: return "source_mass_conservation"
	for key in ["collected", "recycled", "organic_processed"]:
		if c.waste_totals[key] < 0: return "negative_throughput"
	if c.waste_totals.collected > m.generated or c.waste_totals.recycled + c.waste_totals.organic_processed > c.waste_totals.collected + imported: return "invalid_throughput"
	for carry in c.local_carries.values():
		if typeof(carry.r) != TYPE_INT or typeof(carry.d) != TYPE_INT or carry.d <= 0 or carry.r < 0 or carry.r >= carry.d: return "invalid_local_carry"
	if c.disposal_prepaid_fraction < 0 or c.disposal_prepaid_fraction >= A.S: return "invalid_disposal_fraction"
	if c.finance.totals.landfill * A.S != m.disposed * rules.landfill_price_micro + c.disposal_prepaid_fraction: return "landfill_charge_conservation"
	var sale_remainder: int = c.local_carries.get("material_sale", {"r": 0}).r
	if c.materials_sold * rules.material_sale_price_micro != c.finance.totals.material_sales * A.S + sale_remainder: return "sale_conservation"
	if c.air_micro > rules.air_max_micro or c.landfill_damage_micro > rules.landfill_max_micro or c.overflow_micro < 0 or c.overflow_micro > rules.overflow_max_micro: return "environment_stock_bounds"
	for value in c.biogas_pending.values():
		if typeof(value) != TYPE_INT or value < 0: return "invalid_biogas"
	for budget in c.processing_budgets.values():
		if budget.remaining < 0 or budget.reuse_remaining < 0: return "processing_budget_negative"
	var e: Dictionary = c.electricity
	for key in ["supply", "demand", "delivered", "unused", "shortage", "municipal_requested", "municipal_delivered", "biogas_available"]:
		if typeof(e[key]) != TYPE_INT or e[key] < 0: return "invalid_electricity"
	if not complete_game and (e.imports != 0 or e.exports != 0): return "resource_scope_external_power"
	if e.imports < 0 or e.exports < 0 or e.exports > e.supply: return "invalid_power_trade"
	var delivered: int = e.municipal_delivered
	var requested: int = e.municipal_requested
	if delivered > requested: return "municipal_overallocation"
	var ids: Array = []
	for item in e.recipients:
		if item.id in ids or item.delivered < 0 or item.requested < 0 or item.delivered > item.requested: return "recipient_overallocation"
		ids.append(item.id)
		delivered += item.delivered
		requested += item.requested
	if delivered != e.delivered or requested != e.demand or e.supply + e.imports != delivered + e.unused + e.exports or e.demand != delivered + e.shortage: return "electricity_conservation"
	return ""
