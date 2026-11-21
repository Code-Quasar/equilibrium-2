extends RefCounted
## Announced regional crises. Multipliers act only on new flows during the active
## interval [start, end); stocks they caused persist after the crisis ends.
const A = preload("res://simulation/core/arithmetic.gd")
const EFFECTS = ["emission", "air_decay", "household", "factory", "commercial", "municipal_power"]

## Phase: crisis state for the interval [tick, tick + 1).
static func apply(state: Dictionary, crises: Array) -> void:
	var effects: Dictionary = {}
	for key in EFFECTS:
		effects[key] = A.S
	var announced: Array = []
	var active: Array = []
	for crisis in crises:
		if state.tick >= crisis.announce and state.tick < crisis.start:
			announced.append(crisis.id)
		if state.tick >= crisis.start and state.tick < crisis.end:
			active.append(crisis.id)
			for key in EFFECTS:
				effects[key] = A.mul(effects[key], crisis[key])
	state["crisis"] = {"announced": announced, "active": active, "effects": effects}
