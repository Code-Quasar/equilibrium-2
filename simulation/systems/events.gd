extends RefCounted
static func apply(state: Dictionary, schedule: Array, balance: Dictionary) -> void:
	state["event_state"] = {"warnings": [], "active": [], "interval_start": state.tick}
	var modifiers: Dictionary = {"household_percent":100,"factory_percent":100,"commerce_percent":100,"air_percent":100,"municipal_E":balance.municipal_generation_E,"uncollected_penalty_micro":balance.local_simulation.uncollected_penalty_micro}
	for event in schedule:
		if state.tick >= event.warning and state.tick < event.start: state.event_state.warnings.append(event.id)
		if state.tick >= event.start and state.tick < event.end:
			state.event_state.active.append(event.id)
			for key in event.modifiers: modifiers[key] = event.modifiers[key]
	for c in state.cities: c["event_modifiers"] = modifiers.duplicate()
