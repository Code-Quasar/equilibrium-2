extends SceneTree
const Sim=preload("res://simulation/match.gd")
const Cases=preload("res://tests/support/market_cases.gd")
func _initialize() -> void:
	var sim=Sim.new()
	if sim.initialize("cancellation-replay",43,Cases.FOUNDATIONS)!="":quit(1);return
	for tick in range(1200):
		if tick==0:Cases.command(sim,1,"publish_offer",{"type":"recyclable","rate":5000000,"price":1000000})
		if tick==1:Cases.command(sim,0,"accept_quote",{"id":0})
		if tick==10:
			var owners: Array=[1,0] if "reverse" in OS.get_cmdline_user_args() else [0,1]
			for owner in owners:Cases.command(sim,owner,"cancel_contract",{"id":1})
		var result: Dictionary=sim.step()
		if result.status!="advanced":printerr(result);quit(1);return
		if tick==10 and sim.snapshot().contracts[0].status!="cancelled":printerr("FAIL cancellation replay");quit(1);return
	print(sim.serialize())
	quit(0)
