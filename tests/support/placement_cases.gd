extends RefCounted
const Sim=preload("res://simulation/match.gd")
const Cards=preload("res://simulation/interfaces/lifecycle.gd").CARDS
static func run(check: Callable) -> void:
	var sim=Sim.new()
	check.call(sim.initialize("tiles",42,Cards)=="","placement initializes")
	var catalogue=sim._buildings
	var state: Dictionary=sim.snapshot()
	var command: Dictionary={"player_id":3,"command_type":"construct","payload":{"building_type":"residential_district","tile":35}}
	check.call(catalogue.validate_command(state,command)=="","explicit empty tile valid")
	for tile in [-1,36,1.5,"1",true]:
		command.payload.tile=tile
		check.call(catalogue.validate_command(state,command)=="invalid_tile","reject malformed/range tile")
	command.payload.tile=0;command.player_id=0
	check.call(catalogue.validate_command(state,command)=="tile_occupied","foundation occupies tile")
	for seq in range(2):
		var envelope: Dictionary={"match_id":"tiles","player_id":3,"command_seq":seq,"command_id":"tile:"+str(seq),"command_type":"construct","payload":{"building_type":"residential_district","tile":35},"server_received_tick":0}
		check.call(sim.submit(envelope,3).status=="queued","simultaneous tile commands admitted")
	var result: Dictionary=sim.step()
	check.call(result.status=="advanced","placement tick advances")
	check.call(result.commands[0].status=="applied" and result.commands[1].status=="tile_occupied","execution occupancy is atomic")
	check.call(sim.snapshot().cities[3].buildings.size()==1 and sim.snapshot().cities[3].buildings[0].tile==35,"one building on selected tile")
