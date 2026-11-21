extends RefCounted
## Indices correspond exactly to spec section 19.1. Engine owns 01/04/19/20.
const PHASES = [
	"snapshot", "event_boundaries", "construction_completion", "commands",
	"municipal_finances", "facility_funding", "workforce_generation",
	"power_allocation_settlement", "production", "household_collection",
	"contracted_processing", "local_processing", "landfill", "material_sales",
	"environment", "scores_development", "migration", "contract_expiry",
	"advance_time", "publish"
]
var _systems: Dictionary = {}

func register_system(phase: String, system_id: String, execute: Callable) -> bool:
	if phase not in PHASES or phase in ["snapshot", "commands", "advance_time", "publish"]:
		return false
	if system_id.is_empty() or not execute.is_valid():
		return false
	if not _systems.has(phase):
		_systems[phase] = {}
	if _systems[phase].has(system_id):
		return false
	_systems[phase][system_id] = execute
	return true

func run_phase(phase: String, state: Dictionary, context: Dictionary, rng: RefCounted,
		isolate_context: bool = true) -> String:
	var systems: Dictionary = _systems.get(phase, {})
	var ids: Array = systems.keys()
	ids.sort()
	for id in ids:
		# Trusted batch execution shares read-only context. Other integrations receive
		# fully detached state and per-system context copies.
		var system_context: Dictionary = context.duplicate(true) if isolate_context else context
		var result: Variant = systems[id].call(state, system_context, rng)
		if typeof(result) != TYPE_STRING:
			return "invalid_system_result:" + id
		if not result.is_empty():
			return result
	return ""

func manifest() -> Dictionary:
	var result: Dictionary = {}
	for phase in PHASES:
		var ids: Array = _systems.get(phase, {}).keys()
		ids.sort()
		result[phase] = ids
	return result
