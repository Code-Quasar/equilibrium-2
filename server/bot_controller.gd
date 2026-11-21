extends RefCounted
const Plan = preload("res://simulation/interfaces/local_bot.gd")
static func draft(game: RefCounted, gateway: RefCounted, bots: Array) -> void:
	while game.engine == null:
		var seat: int = game.draft.order[game.draft.turn]
		if seat not in bots: return
		for card in game.CARDS:
			if card not in game.draft.choices:
				gateway.issue(seat,"bot-draft","select_foundation",{"foundation":card})
				break
static func play(game: RefCounted, gateway: RefCounted, bots: Array) -> void:
	var tick: int = game.snapshot().tick
	if tick % 90 != 0: return
	@warning_ignore("integer_division")
	var index: int = tick/90
	if index >= Plan.PLAN.size(): return
	var payload: Dictionary = {"building_type":Plan.PLAN[index]}
	for seat in bots:
		if game.engine.preview(seat,"construct",payload) == "":
			gateway.issue(seat,"bot-%d" % tick,"construct",payload)
