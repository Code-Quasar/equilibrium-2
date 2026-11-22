extends SceneTree
const Application = preload("res://server/application.gd")
const Transport = preload("res://server/websocket_transport.gd")
var app = Application.new()
var transport = Transport.new(app)
var stop_file: String = ""
var closing_at: int = -1
func _initialize() -> void:
	var bind: String = "127.0.0.1"
	var port: int = 9080
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() % 2 != 0: fail("Expected option/value pairs"); return
	for i in range(0,args.size(),2):
		match args[i]:
			"--bind": bind = args[i+1]
			"--port":
				if not args[i+1].is_valid_int(): fail("Invalid port"); return
				port = int(args[i+1])
			"--seed":
				if not args[i+1].is_valid_int(): fail("Invalid seed"); return
				app.seed_value = int(args[i+1])
			"--stop-file": stop_file = args[i+1]
			"--dev-emergencies":
				# Developer mode only: "collection_crisis@30,sorting_overload@90,recycling_breakdown@150".
				var plan: Array = []
				for part in args[i+1].split(","):
					var bits: PackedStringArray = part.split("@")
					if bits.size() != 2 or bits[0] not in ["collection_crisis","sorting_overload","recycling_breakdown"] or not bits[1].is_valid_int():
						fail("Invalid --dev-emergencies"); return
					plan.append({"type":bits[0],"start":int(bits[1])})
				app.dev_emergencies = plan
				print("DEVELOPER MODE: fixed emergency schedule ", plan)
			"--draft-grace-ms":
				if not args[i+1].is_valid_int() or int(args[i+1]) < 100: fail("Invalid draft grace"); return
				app.draft_grace_ms = int(args[i+1])
			_: fail("Unknown option"); return
	if port < 1 or port > 65535: fail("Invalid port"); return
	if transport.listen(bind,port) != OK: fail("Cannot listen"); return
	print("ONLINE_READY "+bind+":"+str(port))
func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_msec()
	if closing_at < 0 and stop_file != "" and FileAccess.file_exists(stop_file):
		transport.shutdown()
		closing_at = now
	if closing_at < 0:
		# Draft expiry wins at the exact deadline, before any queued rejoin or
		# draft action can be admitted by the transport poll.
		app.enforce_draft_deadlines(now)
	transport.poll(now)
	if closing_at < 0:
		# Cutoff: all drained messages precede the next due tick; no concurrent submit.
		app.advance(now)
		transport.flush()
	elif transport.peers.is_empty() or now-closing_at >= 1200: return true
	return false
func fail(reason: String) -> void:
	printerr(reason)
	quit(1)
