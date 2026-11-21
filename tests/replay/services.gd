extends SceneTree
func _initialize() -> void:
	var result: Dictionary=preload("res://tests/support/service_scenarios.gd").run("competition",42,0,"reverse" in OS.get_cmdline_user_args())
	if result.has("error"):printerr(result);quit(1);return
	var types: Array=[]
	for contract in result.contracts:
		if contract.delivered>0 and contract.type not in types:types.append(contract.type)
	if types.size()!=3:printerr("FAIL: replay must exercise all three contract types: "+str(types));quit(1);return
	print(result.final_canonical);quit(0)
