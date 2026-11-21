extends RefCounted
## Deterministic opponents for unoccupied seats. They draft the first free Foundation
## and try one ordinary construction every 90 seconds, submitted only when the
## engine preview allows it. Bots get no grants and never control a human seat.
const PLAN = [
	{"building_type": "commercial_district", "size": "S"},
	{"building_type": "renewable_power_plant", "size": "S"},
	{"building_type": "collection_center", "size": "S"},
	{"building_type": "residential_district", "size": "S"},
	{"building_type": "sorting_center", "size": "S"},
	{"building_type": "public_services_center", "size": "S"},
	{"building_type": "recycling_center", "size": "S"},
	{"building_type": "biogas_facility", "size": "S"},
]
const INTERVAL = 90

static func draft(game: RefCounted, gateway: RefCounted, bots: Array) -> void:
	while game.engine == null:
		var seat: int = game.draft.order[game.draft.turn]
		if seat not in bots:
			return
		for card in game.CARDS:
			if card not in game.draft.choices:
				gateway.issue(seat, "bot-draft", "select_foundation", {"foundation": card})
				break

static func play(game: RefCounted, gateway: RefCounted, bots: Array) -> void:
	var tick: int = game.snapshot().tick
	@warning_ignore("integer_division")
	var index: int = tick / INTERVAL
	if tick % INTERVAL != 0 or index >= PLAN.size():
		return
	for seat in bots:
		if game.engine.preview(seat, "construct", PLAN[index]) == "":
			gateway.issue(seat, "bot-%d" % tick, "construct", PLAN[index])
