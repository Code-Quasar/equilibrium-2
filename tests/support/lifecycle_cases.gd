extends RefCounted
const Life=preload("res://simulation/interfaces/lifecycle.gd")
static func run(check: Callable) -> void:
	var game=Life.new();var other=Life.new()
	check.call(game.create("draft",42)=="" and other.create("draft",42)=="","draft creation")
	check.call(game.draft==other.draft,"seeded identical draft order")
	check.call(game.step().status=="draft_in_progress","no pre-draft tick")
	for i in range(4):
		var owner: int=game.draft.order[i]
		var command: Dictionary={"match_id":"draft","player_id":owner,"command_seq":i,"command_id":"draft:"+str(i),"command_type":"select_foundation","payload":{"foundation":Life.CARDS[i]},"server_received_tick":0}
		check.call(game.submit(command,(owner+1)%4).status=="unauthorized_player","draft authentication")
		check.call(game.submit(command,owner).status=="applied","draft selection")
		check.call(game.submit(command,owner).status=="duplicate","draft replay")
	check.call(game.engine!=null and game.snapshot().cities.size()==4,"draft creates real engine")
	check.call(game.step().status=="advanced","draft running transition")

	var config: Dictionary=Life.Sim.Balance.load_b1()
	var duplicates: Array=["industrial_legacy","industrial_legacy","industrial_legacy","industrial_legacy"]
	check.call(Life.Sim.State.create("unique",42,duplicates,config).is_empty(),"default unique Foundation enforcement")
	config["allow_duplicate_foundations"]=true
	var fallback: Dictionary=Life.Sim.State.create("fallback",42,duplicates,config)
	check.call(not fallback.is_empty() and fallback.cities.all(func(c):return c.money_micro==480000000 and c.buildings.size()==1),"explicit specification duplicate fallback preserves packages")
	config.allow_duplicate_foundations=1
	check.call(Life.Sim.Balance.validate(config)=="invalid_duplicate_foundation_flag","duplicate config must be boolean")
