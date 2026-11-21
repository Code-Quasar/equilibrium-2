extends SceneTree
## Two graphical-client sessions against a real running server (protocol v1):
## create, join, ready, start, draft, build with receipts, a market offer,
## a disconnect and rejoin of the same seat, and isolation between seats.
##
##   godot --headless --path client/godot --script res://tests/two_players.gd -- ws://127.0.0.1:9080
## The server must be fresh (one lobby per process).

var a: Session
var b: Session
var step := 0
var t := 0.0
var wait := 0.0
var fails := 0
var url := "ws://127.0.0.1:9080"
var built_id := ""
var b_seat := -1


func ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		url = args[0]
	var live := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://").path_join("../../config/balance/B2_1.json").simplify_path())
	ok(not live.is_empty() and Catalogue.data().get("source_sha256", "") == _sha256(live), "display catalogue matches the live B2.1 configuration")
	a = _session("user://test_a.cfg")
	b = _session("user://test_b.cfg")


static func _sha256(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


func _session(path: String) -> Session:
	var s := Session.new()
	s.store = path
	root.add_child(s)
	s._forget_seat()
	s.notice.connect(func(text, level): print("   [%s] %s" % [level, text]))
	return s


func next(delay := 0.0) -> void:
	step += 1
	t = 0.0
	wait = delay


func _process(delta: float) -> bool:
	t += delta
	if t < wait:
		return false
	match step:
		0:
			a.create(url)
			next()
		1:
			if a.join_code != "" and a.phase == "lobby":
				ok(a.seat >= 0 and a.is_host, "host seated and marked host")
				ok(a.has_saved_seat(), "rejoin credential saved privately")
				b.join(url, a.join_code)
				next()
		2:
			if b.phase == "lobby" and b.seat >= 0:
				b_seat = b.seat
				ok(b.seat != a.seat and not b.is_host, "guest gets its own seat")
				next(0.3)
		3:
			var humans := 0
			for r in a.lobby.get("seats", []):
				if r["controller"] == "human":
					humans += 1
			ok(humans == 2, "host's lobby shows both humans")
			a.start_match()  # not everyone ready yet: must be refused
			next(0.5)
		4:
			ok(a.last_error == "not_ready", "start refused until everyone is ready (%s)" % a.last_error)
			a.set_ready(true)
			b.set_ready(true)
			next(0.5)
		5:
			a.start_match()
			next()
		6:
			if a.phase == "draft" and b.phase == "draft":
				ok(true, "both clients moved to the draft")
				next()
		7:
			# Each human picks the first available Foundation on its turn; bots pick themselves.
			for s in [a, b]:
				if s.phase == "draft" and int(s.draft.get("turn_seat", -1)) == s.seat and s.draft_choice.is_empty():
					var other: Session = b if s == a else a
					if other.phase == "draft" and other.draft_choice.is_empty():
						other.choose_foundation(other.draft.get("available_foundations", ["x"])[0])  # out of turn
					s.choose_foundation(s.draft["available_foundations"][0])
			if a.phase == "play" and b.phase == "play" and not a.view.is_empty() and not b.view.is_empty():
				ok(true, "both reached gameplay with a live view")
				ok(a.view["own_city"]["city_id"] == a.seat and b.view["own_city"]["city_id"] == b.seat, "each view is the player's own city")
				ok(not a.view.has("cities"), "no other city's private state in the view")
				next()
		8:
			built_id = a.act("construct", {"building_type": "residential_district", "size": "S", "tile": 14}, "Build Residential District")
			ok(a.actions[built_id]["status"] == "sending", "action shown as sending, not done")
			next()
		9:
			var st: String = a.actions[built_id]["status"]
			if st in ["applied", "rejected"]:
				ok(st == "applied", "construction executed by the server (%s)" % a.actions[built_id]["error"])
				next(1.2)
		10:
			var found := {}
			for bl in a.view["own_city"]["buildings"]:
				if int(bl["tile"]) == 14:
					found = bl
			ok(not found.is_empty() and found["status"] != "complete", "building appears on tile 14 under construction")
			var bad := a.act("construct", {"building_type": "landfill", "size": "S", "tile": 14}, "Build Landfill")
			built_id = bad
			next()
		11:
			if a.actions[built_id]["status"] in ["applied", "rejected"]:
				ok(a.actions[built_id]["status"] == "rejected" and a.actions[built_id]["error"] == "tile_occupied", "occupied tile rejected with a reason (%s)" % a.actions[built_id]["error"])
				built_id = b.act("publish_offer", {"type": "electricity", "rate": 5000000}, "Offer Electricity")
				next()
		12:
			if b.actions[built_id]["status"] in ["applied", "rejected"]:
				ok(true, "market offer answered by the server (%s %s)" % [b.actions[built_id]["status"], b.actions[built_id]["error"]])
				ok(not a.view["own_city"].get("build_options", {}).is_empty(), "views carry the server's build options")
				# Seat isolation: b's view never contains a's buildings.
				var mine := 0
				for bl in b.view["own_city"]["buildings"]:
					if int(bl["tile"]) == 14 and bl["type"] == "residential_district":
						mine += 1
				ok(mine == 0, "the other player's city is untouched")
				b.link.close()  # drop the connection
				b._on_closed("connection_lost")
				next(0.5)
		13:
			ok(not b.live and b.phase == "play", "after a drop: stale, still in the match")
			next()
		14:
			if b.live and b.seat == b_seat and not b.view.is_empty():
				ok(true, "rejoined the same seat automatically")
				next(1.5)
		15:
			var tk := int(b.view.get("tick", 0))
			ok(tk > 0 and b.view["own_city"]["city_id"] == b_seat, "fresh authoritative views after rejoin (tick %d)" % tk)
			print("fails=", fails)
			quit(1 if fails > 0 else 0)
	if t > 25.0:
		print("TIMEOUT at step %d (a %s, b %s)" % [step, a.phase, b.phase])
		quit(2)
	return false
