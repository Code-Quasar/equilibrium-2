extends SceneTree
const Protocol=preload("res://simulation/interfaces/local_protocol.gd")
func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var seed_value: int=int(args[0]) if args.size()>0 else 42
	var humans: int=int(args[1]) if args.size()>1 else 4
	structured(seed_value,humans,"admin" in args)

func structured(seed_value: int, humans: int, admin: bool) -> void:
	var protocol=Protocol.new()
	var error: String=protocol.initialize(seed_value,humans,admin)
	print("@RESULT "+JSON.stringify({"v":1,"id":0,"status":"ready" if error=="" else error}))
	if error!="":quit(1);return
	while true:
		var line: String=OS.read_string_from_stdin()
		if line.is_empty():break
		var raw: Variant=JSON.parse_string(line)
		var result: Dictionary
		if not valid_numbers(raw):
			result={"v":1,"id":raw.get("id") if raw is Dictionary else null,"status":"invalid_request"}
		else:result=protocol.request(Protocol.Balance._integers(raw))
		print("@RESULT "+JSON.stringify(result))
		if result.status=="quit":break
	quit(0)
func valid_numbers(value: Variant) -> bool:
	if typeof(value)==TYPE_FLOAT:return is_finite(value) and value==floor(value) and abs(value)<=9007199254740991.0
	if value is Dictionary:
		for item in value.values():
			if not valid_numbers(item):return false
	if value is Array:
		for item in value:
			if not valid_numbers(item):return false
	return true
