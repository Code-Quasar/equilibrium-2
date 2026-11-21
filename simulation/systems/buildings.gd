extends RefCounted
const Finance = preload("res://simulation/systems/finance.gd")
const SCALE: int = 1000000
var balance: Dictionary

func _init(config: Dictionary) -> void:
	balance = config.duplicate(true)

func record(id: int, kind: String, city_id: int, tile: int, tick: int, complete: bool) -> Dictionary:
	return {"id": id, "type": kind, "owner_city": city_id, "tile": tile,
		"level": 1, "status": "complete" if complete else "constructing", "created_tick": tick,
		"completed_tick": tick if complete else -1, "enabled": true, "reactivate_at": 0,
		"funded": false, "operational": false, "productive": false, "power_factor_micro": null,
		"money_paid_micro": 0, "materials_paid_micro": 0, "upkeep_carry": 0, "income_carry": 0,
		"eligible_ticks": 0, "funded_ticks": 0, "operational_ticks": 0, "productive_ticks": 0,
		"funding_failures": 0}

func effects(building: Dictionary) -> Dictionary:
	var definition: Dictionary = balance.buildings[building.type]
	var result: Dictionary = definition.l1.duplicate()
	if building.level == 2:
		for key in result:
			if key not in ["cost_micro", "duration_seconds"]:
				result[key] += definition.upgrade_delta[key]
	return result

static func find_building(city: Dictionary, id: int) -> Dictionary:
	for building in city.buildings:
		if building.id == id:
			return building
	return {}

static func project_index(city: Dictionary, id: int) -> int:
	for i in range(city.project_slots.size()):
		if city.project_slots[i] != null and city.project_slots[i].building_id == id:
			return i
	return -1

func next_tile(city: Dictionary) -> int:
	var occupied: Array = []
	for building in city.buildings:
		occupied.append(building.tile)
	# Cosmetic row-major fallback; explicit tiles use the same occupancy validation.
	for tile in range(balance.grid_width * balance.grid_height):
		if tile not in occupied:
			return tile
	return -1

func quote(city: Dictionary, cost: int) -> Dictionary:
	@warning_ignore("integer_division")
	var materials: int = mini(city.materials_micro, cost * balance.economy.material_discount_percent / 100)
	return {"cash": cost - materials, "materials": materials}

func validate_command(state: Dictionary, command: Dictionary) -> String:
	var city: Dictionary = state.cities[command.player_id]
	var p: Dictionary = command.payload
	var kind: String = command.command_type
	if kind == "set_reduce_waste":
		if p.size() != 1 or typeof(p.get("enabled")) != TYPE_BOOL:
			return "invalid_payload"
		if p.enabled == city.reduce_waste:
			return "already_set"
		return "policy_cooldown" if state.tick < city.policy_change_at else ""
	if (kind != "construct" and p.size() != 1) or (kind == "construct" and (p.size() < 1 or p.size() > 2 or (p.size() == 2 and not p.has("tile")))):
		return "invalid_payload"
	var building: Dictionary = {}
	var price: int = 0
	var duration: int = 0
	if kind == "construct":
		if typeof(p.get("building_type")) != TYPE_STRING or not balance.buildings.has(p.building_type):
			return "invalid_building_type"
		if p.has("tile"):
			if state.scope != "complete":return "invalid_payload"
			if typeof(p.tile) != TYPE_INT or p.tile < 0 or p.tile >= balance.grid_width * balance.grid_height:
				return "invalid_tile"
			for occupied in city.buildings:
				if occupied.tile == p.tile:return "tile_occupied"
		var definition: Dictionary = balance.buildings[p.building_type]
		if city.development_micro < definition.build_unlock_micro:
			return "development_locked"
		if next_tile(city) < 0:
			return "no_free_tile"
		price = definition.l1.cost_micro
		duration = definition.l1.duration_seconds
	else:
		if typeof(p.get("building_id")) != TYPE_INT:
			return "invalid_payload"
		building = find_building(city, p.building_id)
		if building.is_empty():
			return "building_not_owned"
		if kind == "cancel_project":
			return "" if project_index(city, building.id) >= 0 else "no_active_project"
		if building.status != "complete":
			return "not_complete"
		if kind == "upgrade":
			if building.level != 1:
				return "maximum_level"
			if project_index(city, building.id) >= 0:
				return "already_upgrading"
			var definition: Dictionary = balance.buildings[building.type]
			if city.development_micro < definition.upgrade_unlock_micro:
				return "development_locked"
			price = definition.upgrade_delta.cost_micro
			duration = definition.upgrade_delta.duration_seconds
		elif kind == "disable":
			return "" if building.enabled else "already_disabled"
		elif kind == "enable":
			if building.enabled:
				return "already_enabled"
			return "reactivation_cooldown" if state.tick < building.reactivate_at else ""
		elif kind == "demolish":
			if project_index(city, building.id) >= 0:
				return "cancel_project_first"
			# Contract reservations must be resolved before demolition.
			if state.scope != "complete" and (not city.contract_reservations.is_empty() or not city.incoming_contract_ids.is_empty() or not city.outgoing_contract_ids.is_empty()):
				return "contract_validation_required"
			return ""
		else:
			return "unsupported_command"
	if null not in city.project_slots:
		return "construction_slots_full"
	if state.tick + duration >= balance.match_seconds:
		return "not_enough_time"
	return "" if Finance.available(city) >= quote(city, price).cash else "insufficient_funds"

func execute_command(state: Dictionary, command: Dictionary, _rng: RefCounted) -> String:
	# Execution revalidates against the current authoritative state.
	var error: String = validate_command(state, command)
	if not error.is_empty():
		return error
	var city: Dictionary = state.cities[command.player_id]
	var p: Dictionary = command.payload
	var kind: String = command.command_type
	if kind == "set_reduce_waste":
		city["reduce_waste"] = p.enabled
		city["policy_change_at"] = state.tick + balance.economy.policy_cooldown_seconds
		return ""
	if kind in ["construct", "upgrade"]:
		var building: Dictionary
		var definition: Dictionary
		if kind == "construct":
			building = record(city.next_building_id, p.building_type, city.city_id, p.get("tile", next_tile(city)), state.tick, false)
			city.next_building_id += 1
			city.buildings.append(building)
			definition = balance.buildings[p.building_type].l1
		else:
			building = find_building(city, p.building_id)
			definition = balance.buildings[building.type].upgrade_delta
		var payment: Dictionary = quote(city, definition.cost_micro)
		if not Finance.debit(city, payment.cash, "construction", building.id):
			return "insufficient_funds"
		city.materials_micro -= payment.materials
		city.finance.materials_spent += payment.materials
		building.money_paid_micro += payment.cash
		building.materials_paid_micro += payment.materials
		var slot: int = city.project_slots.find(null)
		city.project_slots[slot] = {"building_id": building.id, "kind": kind,
			"complete_tick": state.tick + definition.duration_seconds,
			"cash_paid": payment.cash, "materials_paid": payment.materials}
		return ""
	var building: Dictionary = find_building(city, p.building_id)
	match kind:
		"disable":
			building.enabled = false
			building.funded = false
			building.operational = false
			building.productive = false
			building.reactivate_at = state.tick + balance.economy.reactivation_cooldown_seconds
		"enable":
			building.enabled = true
		"demolish":
			city.buildings.erase(building)
		"cancel_project":
			var index: int = project_index(city, building.id)
			var project: Dictionary = city.project_slots[index]
			@warning_ignore("integer_division")
			var refund: int = project.cash_paid * balance.economy.cancel_refund_percent / 100
			Finance.credit(city, refund, "refunds", building.id)
			city.project_slots[index] = null
			if project.kind == "construct":
				city.buildings.erase(building)
	return ""

func complete_projects(state: Dictionary, _ctx: Dictionary, _rng: RefCounted) -> String:
	for city in state.cities:
		city.finance.last_tick.clear()
		for building in city.buildings:
			building.funded = false
			building.operational = false
			building.productive = false
			building.power_factor_micro = null
		# Building ID order is stable even when slot indices are reused.
		var due: Array = []
		for project in city.project_slots:
			if project != null and project.complete_tick == state.tick:
				due.append(project)
		due.sort_custom(func(a, b): return a.building_id < b.building_id)
		for project in due:
			var building: Dictionary = find_building(city, project.building_id)
			if project.kind == "construct":
				building.status = "complete"
				building.completed_tick = state.tick
			else:
				building.level = 2
			city.project_slots[project_index(city, building.id)] = null
	return ""

func validate_city(city: Dictionary) -> String:
	var ids: Array = []
	var tiles: Array = []
	for building in city.buildings:
		if not balance.buildings.has(building.type) or building.owner_city != city.city_id or building.id in ids or building.id < 0 or building.id >= city.next_building_id:
			return "building_identity"
		if building.tile in tiles or building.tile < 0 or building.tile >= balance.grid_width * balance.grid_height:
			return "occupied_or_invalid_tile"
		if building.level not in [1, 2] or building.status not in ["complete", "constructing"]:
			return "building_state"
		if building.funded and (not building.enabled or building.status != "complete"):
			return "ineligible_funding"
		var powered: bool = typeof(building.power_factor_micro) == TYPE_INT and building.power_factor_micro > 0 and building.power_factor_micro <= SCALE
		if not city.get("resource_systems_enabled", false):
			powered = building.power_factor_micro == SCALE
		if building.operational and (not building.funded or not powered):
			return "unfunded_or_unpowered_operation"
		if building.productive and (not building.operational or effects(building).income_micro_per_minute == 0):
			return "invalid_production"
		if building.upkeep_carry < 0 or building.upkeep_carry >= 60 or building.income_carry < 0 or building.income_carry >= 60 * SCALE:
			return "invalid_building_carry"
		ids.append(building.id)
		tiles.append(building.tile)
	var projects: Array = []
	for project in city.project_slots:
		if project == null:
			continue
		if project.building_id not in ids or project.building_id in projects or project.complete_tick >= balance.match_seconds:
			return "invalid_project"
		var building: Dictionary = find_building(city, project.building_id)
		if (project.kind == "construct" and building.status != "constructing") or (project.kind == "upgrade" and (building.status != "complete" or building.level != 1)):
			return "invalid_project_state"
		projects.append(project.building_id)
	for building in city.buildings:
		if building.status == "constructing" and building.id not in projects:
			return "orphan_construction"
	return ""
