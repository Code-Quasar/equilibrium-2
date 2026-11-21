extends RefCounted
## Building catalogue, construction commands and project lifecycle.
## Tier values are totals: a Medium building has the Medium row's capacities, not
## Small plus Medium. Prerequisites are completed buildings the city itself owns.
const A = preload("res://simulation/core/arithmetic.gd")
const Balance = preload("res://simulation/core/balance.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Materials = preload("res://simulation/systems/materials.gd")
const COMMANDS = ["construct", "upgrade", "cancel_project", "demolish", "disable", "enable"]
const NEXT_SIZE = {"S": "M", "M": "L"}
var b: Dictionary

func _init(config: Dictionary) -> void:
	b = config

static func record(id: int, kind: String, size: String, tile: int, tick: int, complete: bool) -> Dictionary:
	return {"id": id, "type": kind, "size": size, "tile": tile,
		"status": "complete" if complete else "constructing", "enabled": true, "reactivate_at": 0,
		"created_tick": tick, "completed_tick": tick if complete else -1,
		"op": idle(), "carries": {}}

## Operation record for a building that does not run this tick.
static func idle() -> Dictionary:
	return {"funded": false, "requested_micro_E": 0, "delivered_micro_E": 0, "power_micro": 0,
		"workers": 0, "staff_micro": 0, "fraction_micro": 0, "emitted_micro": 0, "budget_micro": 0}

func tier(building: Dictionary) -> Dictionary:
	return b.buildings[building.type][building.size]

## Complete, enabled buildings whose upkeep was paid this tick.
static func operating(building: Dictionary) -> bool:
	return building.op.funded

static func find(city: Dictionary, id: int) -> Dictionary:
	for building in city.buildings:
		if building.id == id:
			return building
	return {}

static func project_index(city: Dictionary, id: int) -> int:
	for i in range(city.projects.size()):
		if city.projects[i] != null and city.projects[i].building_id == id:
			return i
	return -1

## Buildings sorted by a type priority list, then by plot. Unlisted types go last.
static func ordered(city: Dictionary, priority: Array) -> Array:
	var result: Array = city.buildings.duplicate()
	result.sort_custom(func(x, y):
		var px: int = priority.find(x.type)
		var py: int = priority.find(y.type)
		px = priority.size() if px < 0 else px
		py = priority.size() if py < 0 else py
		return px < py if px != py else x.tile < y.tile)
	return result

static func by_tile(city: Dictionary, kind: String) -> Array:
	var result: Array = city.buildings.filter(func(x): return x.type == kind)
	result.sort_custom(func(x, y): return x.tile < y.tile)
	return result

func next_tile(city: Dictionary) -> int:
	var occupied: Array = city.buildings.map(func(x): return x.tile)
	for tile in range(b.tiles):
		if tile not in occupied:
			return tile
	return -1

## "" when every required type has a completed building owned by this city.
func prerequisite_error(city: Dictionary, kind: String) -> String:
	for required in b.buildings[kind].requires:
		var states: Array = city.buildings.filter(func(x): return x.type == required).map(func(x): return x.status)
		if "complete" not in states:
			return "prerequisite_under_construction" if "constructing" in states else "requires_" + required
	return ""

## Nominal housing from the municipal baseline and enabled, completed districts.
func enabled_housing(city: Dictionary) -> int:
	var housing: int = b.city.housing
	for building in city.buildings:
		if building.status == "complete" and building.enabled:
			housing += tier(building).housing
	return housing

func validate(state: Dictionary, command: Dictionary) -> String:
	var city: Dictionary = state.cities[command.player_id]
	var p: Dictionary = command.payload
	var kind: String = command.command_type
	if kind == "construct":
		if not p.has("building_type") or not p.has("size") or p.size() > (3 if p.has("tile") else 2):
			return "invalid_payload"
		if typeof(p.building_type) != TYPE_STRING or not b.buildings.has(p.building_type):
			return "invalid_building_type"
		if typeof(p.size) != TYPE_STRING or p.size not in Balance.SIZES:
			return "invalid_size"
		if p.has("tile"):
			if typeof(p.tile) != TYPE_INT or p.tile < 0 or p.tile >= b.tiles:
				return "invalid_tile"
			if city.buildings.any(func(x): return x.tile == p.tile):
				return "tile_occupied"
		elif next_tile(city) < 0:
			return "no_free_tile"
		var error: String = prerequisite_error(city, p.building_type)
		if not error.is_empty():
			return error
		var t: Dictionary = b.buildings[p.building_type][p.size]
		return _project_error(state, city, t.credits, t.materials, t.seconds)
	if p.size() != 1 or typeof(p.get("building_id")) != TYPE_INT:
		return "invalid_payload"
	var building: Dictionary = find(city, p.building_id)
	if building.is_empty():
		return "building_not_owned"
	if kind == "cancel_project":
		return "" if project_index(city, building.id) >= 0 else "no_active_project"
	if building.status != "complete":
		return "not_complete"
	match kind:
		"upgrade":
			if not NEXT_SIZE.has(building.size):
				return "maximum_size"
			if project_index(city, building.id) >= 0:
				return "already_upgrading"
			var up: Dictionary = b.buildings[building.type][NEXT_SIZE[building.size]].upgrade
			return _project_error(state, city, up.credits, up.materials, up.seconds)
		"demolish":
			if project_index(city, building.id) >= 0:
				return "cancel_project_first"
			if _sole_prerequisite(city, building):
				return "dependent_buildings_exist"
			if building.enabled and enabled_housing(city) - tier(building).housing < city.population:
				return "housing_below_population"
			return ""
		"disable":
			return "" if building.enabled else "already_disabled"
		"enable":
			if building.enabled:
				return "already_enabled"
			return "reactivation_cooldown" if state.tick < building.reactivate_at else ""
	return "unsupported_command"

func _project_error(state: Dictionary, city: Dictionary, credits: int, materials: int, seconds: int) -> String:
	if null not in city.projects:
		return "construction_slots_full"
	if state.tick + seconds >= b.duration:
		return "not_enough_time"
	if Finance.available(city) < credits + Materials.purchase_cost(city, b, materials):
		return "insufficient_funds"
	return ""

## True when demolishing this building would leave a dependent without its prerequisite.
func _sole_prerequisite(city: Dictionary, building: Dictionary) -> bool:
	var others: int = city.buildings.filter(func(x): return x.type == building.type and x.status == "complete" and x.id != building.id).size()
	if others > 0:
		return false
	for other in city.buildings:
		if building.type in b.buildings[other.type].requires:
			return true
	return false

## Execution revalidates against the authoritative state, so a rejected command
## never charges credits, consumes materials, takes a plot or occupies a slot.
func execute(state: Dictionary, command: Dictionary) -> String:
	var error: String = validate(state, command)
	if not error.is_empty():
		return error
	var city: Dictionary = state.cities[command.player_id]
	var p: Dictionary = command.payload
	match command.command_type:
		"construct":
			var t: Dictionary = b.buildings[p.building_type][p.size]
			var building: Dictionary = record(city.next_building_id, p.building_type, p.size, p.get("tile", next_tile(city)), state.tick, false)
			city.next_building_id += 1
			city.buildings.append(building)
			return _start_project(state, city, building.id, "construct", p.size, t.credits, t.materials, t.seconds)
		"upgrade":
			var building: Dictionary = find(city, p.building_id)
			var target: String = NEXT_SIZE[building.size]
			var up: Dictionary = b.buildings[building.type][target].upgrade
			return _start_project(state, city, building.id, "upgrade", target, up.credits, up.materials, up.seconds)
		"cancel_project":
			var index: int = project_index(city, p.building_id)
			var project: Dictionary = city.projects[index]
			Finance.credit(city, A.mul(project.credits_paid, b.construction.cancel_refund), "refunds")
			Materials.refund(city, A.mul(project.materials_paid, b.construction.cancel_materials_refund))
			city.projects[index] = null
			if project.kind == "construct":
				city.buildings.erase(find(city, p.building_id))
		"demolish":
			var building: Dictionary = find(city, p.building_id)
			Finance.credit(city, A.mul(tier(building).credits, b.construction.demolition_refund), "refunds")
			city.buildings.erase(building)
		"disable":
			var building: Dictionary = find(city, p.building_id)
			building.enabled = false
			building.op = idle()
			building.reactivate_at = state.tick + b.construction.reactivation_cooldown
		"enable":
			find(city, p.building_id).enabled = true
	return ""

## Credits and materials are paid in full at acceptance. A failure here makes the
## engine discard the whole command.
func _start_project(state: Dictionary, city: Dictionary, id: int, kind: String, size: String, credits: int, materials: int, seconds: int) -> String:
	if not Finance.debit(city, credits, "construction") or not Materials.consume(city, b, materials):
		return "insufficient_funds"
	city.projects[city.projects.find(null)] = {"building_id": id, "kind": kind, "target_size": size,
		"complete_tick": state.tick + seconds, "credits_paid": credits, "materials_paid": materials}
	return ""

## Phase: projects due at this tick finish and operate from this tick onward.
func complete_projects(state: Dictionary, _ctx: Dictionary) -> String:
	for city in state.cities:
		var due: Array = city.projects.filter(func(x): return x != null and x.complete_tick == state.tick)
		due.sort_custom(func(x, y): return x.building_id < y.building_id)
		for project in due:
			var building: Dictionary = find(city, project.building_id)
			building.size = project.target_size
			if project.kind == "construct":
				building.status = "complete"
				building.completed_tick = state.tick
			city.projects[project_index(city, building.id)] = null
	return ""

func validate_city(city: Dictionary) -> String:
	var ids: Array = []
	var tiles: Array = []
	for building in city.buildings:
		if not b.buildings.has(building.type) or building.size not in Balance.SIZES or building.status not in ["complete", "constructing"]:
			return "building_state"
		if building.id in ids or building.id < 0 or building.id >= city.next_building_id:
			return "building_identity"
		if building.tile in tiles or building.tile < 0 or building.tile >= b.tiles:
			return "occupied_or_invalid_tile"
		if building.op.funded and (building.status != "complete" or not building.enabled):
			return "ineligible_operation"
		for carry in building.carries.values():
			if typeof(carry) != TYPE_INT or carry < 0:
				return "invalid_carry"
		if not prerequisite_error(city, building.type).is_empty():
			return "prerequisite_chain_broken"
		ids.append(building.id)
		tiles.append(building.tile)
	if city.projects.size() != b.construction.slots:
		return "construction_bounds"
	var projected: Array = []
	for project in city.projects:
		if project == null:
			continue
		var building: Dictionary = find(city, project.building_id)
		if building.is_empty() or project.building_id in projected or project.complete_tick >= b.duration:
			return "invalid_project"
		var valid: bool = building.status == "constructing" and project.target_size == building.size if project.kind == "construct" \
			else building.status == "complete" and NEXT_SIZE.get(building.size) == project.target_size
		if not valid:
			return "invalid_project_state"
		projected.append(project.building_id)
	for building in city.buildings:
		if building.status == "constructing" and building.id not in projected:
			return "orphan_construction"
	return ""
