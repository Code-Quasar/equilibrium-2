extends SceneTree
const Life=preload("res://simulation/interfaces/lifecycle.gd")
const Balance=preload("res://simulation/core/balance.gd")
func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.is_empty():printerr("Usage: -- <record.json>");quit(1);return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not parsed is Dictionary:printerr("Invalid recording");quit(1);return
	var record: Dictionary=Balance._integers(parsed)
	if not record.get("commands") is Array or not record.has("tick"):printerr("Incomplete recording");quit(1);return
	var game=Life.new();game.create("local-"+str(record.seed),record.seed)
	var index: int=0
	for tick in range(record.tick+1):
		while index<record.commands.size() and record.commands[index].envelope.server_received_tick==tick:
			var entry: Dictionary=record.commands[index]
			var result: Dictionary=game.submit(entry.envelope,entry.authenticated_player)
			if result.status!=entry.admission:printerr("Admission mismatch "+str(index));quit(1);return
			index+=1
		if tick<record.tick:
			var result: Dictionary=game.step()
			if result.status!="advanced":printerr(result);quit(1);return
	if game.engine==null or index!=record.commands.size() or game.engine.serialize().sha256_text()!=record.canonical_sha256:
		printerr("Replay mismatch");quit(1);return
	print("Local replay: byte-identical canonical hash "+record.canonical_sha256);quit(0)
