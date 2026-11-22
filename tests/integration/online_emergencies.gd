extends SceneTree
## ECO EMERGENCIES through the real server application with four human seats:
## everyone sees the same event and challenge, joining is optional, scores come
## only from validated actions, a disconnect neither pauses nor restarts the
## event, and the winner and boost reach every view.
const Protocol = preload("res://shared/protocol_v1.gd")
const App = preload("res://server/application.gd")
const Em = preload("res://simulation/systems/emergencies.gd")
var checks: int = 0
var failures: int = 0
var now: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if OS.has_environment("EM_VERBOSE"): print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1; printerr("FAIL: " + label)

func message(kind: String, body: Dictionary = {}) -> Dictionary:
	body.correlation_id = "t"
	return Protocol.message(kind, body)

func views(app, conn: int) -> Array:
	return app.outbox.filter(func(i): return i.connection == conn and i.message.type == "player_view").map(func(i): return i.message)

func last_view(app, conn: int) -> Dictionary:
	var v: Array = views(app, conn)
	return v[-1] if not v.is_empty() else {}

func tick(app) -> void:
	now += 1000
	app.advance(now)

func act(app, conn: int, id: String, kind: String, payload: Dictionary) -> String:
	var mark: int = app.outbox.size()
	app.request(conn, message("submit_action", {"action_id": id, "kind": kind, "payload": payload}), now)
	var errors: Array = app.outbox.slice(mark).filter(func(i): return i.connection == conn and i.message.type == "protocol_error")
	if not errors.is_empty():
		return "protocol:" + str(errors[0].message.code)
	tick(app)
	var acks: Array = app.outbox.slice(mark).filter(func(i): return i.connection == conn and i.message.type == "action_ack" and i.message.get("action_id", "") == id)
	return str(acks[-1].message.status) if not acks.is_empty() else "no_ack"

func _initialize() -> void:
	var app = App.new()
	app.dev_emergencies = [{"type": "collection_crisis", "start": 5}, {"type": "sorting_overload", "start": 60}, {"type": "recycling_breakdown", "start": 120}]
	var credentials: Array = []
	for id in range(1, 5):
		app.connect_peer(id)
		app.request(id, message("hello", {"client": "test", "client_version": "1"}), 0)
		app.request(id, message("create_lobby") if id == 1 else message("join_lobby", {"join_code": app.join_code}), 0)
		credentials.append(app.outbox.filter(func(i): return i.connection == id and i.message.type == "seat_assigned")[-1].message)
		app.request(id, message("set_ready", {"ready": true}), 0)
	app.request(1, message("start_match"), 0)
	while app.phase == "draft":
		var d: Dictionary = app.match_session.draft_view()
		app.request(app.sessions.entries[d.turn_seat].connection, message("choose_foundation", {"action_id": "d%d" % d.turn_seat, "foundation": d.available_foundations[0]}), 0)
	check(app.phase == "running", "four humans, no bots")
	var conn: Array = range(4).map(func(seat): return app.sessions.entries[seat].connection)
	for i in range(5):
		tick(app)
	app.outbox.clear()
	tick(app)
	var events: Array = conn.map(func(c): return last_view(app, c).public.emergency)
	check(events.all(func(e): return e != null and e.id == "em1" and e.type == "collection_crisis"), "all four players see the same emergency")
	check(events.all(func(e): return e.challenge == events[0].challenge and e.start == events[0].start), "with the same challenge and timeline")
	check(last_view(app, conn[0]).public.get("developer_mode", false), "developer mode is labelled in the view")
	# Seats 0 and 1 respond; seat 2 declines (does nothing); seat 3 joins late.
	check(act(app, conn[0], "j0", "emergency_join", {"event": "em1"}) == "applied", "seat 0 responds")
	check(act(app, conn[1], "j1", "emergency_join", {"event": "em1"}) == "applied", "seat 1 responds")
	check(act(app, conn[0], "bad", "emergency_join", {"event": "em9"}) == "unknown_event", "an unknown event is refused")
	var e: Dictionary = last_view(app, conn[0]).public.emergency
	var items: Array = e.challenge.items
	while int(last_view(app, conn[0]).tick) < e.active + 1:
		tick(app)
	# Seat 0 routes three items right; seat 1 one wrong; every score is the server's.
	var at_tick := func() -> int: return (int(last_view(app, conn[0]).tick) - e.active) * 1000 + 300
	var routed: int = 0
	for item in items:
		if routed == 3:
			break
		var mid: int = item.spawn_ms + item.travel_ms / 2
		while (int(last_view(app, conn[0]).tick) - e.active) * 1000 < mid - 500:
			tick(app)
		var ms: int = at_tick.call()
		if ms < item.spawn_ms or ms > item.spawn_ms + item.travel_ms:
			continue
		var route: Dictionary = {"event": "em1", "item": item.id, "bin": Em.ROUTE_KINDS[item.kind], "t_ms": ms}
		check(act(app, conn[0], "r%d" % item.id, "emergency_route", route) == "applied", "route item %d" % item.id)
		routed += 1
		if routed == 1:
			var score: int = last_view(app, conn[0]).public.emergency.leaderboard[0].score
			act(app, conn[0], "r%d" % item.id, "emergency_route", route)
			check(last_view(app, conn[0]).public.emergency.leaderboard[0].score == score, "the same action sent twice scores once")
	check(act(app, conn[0], "cheat", "emergency_route", {"event": "em1", "item": 0, "bin": 0, "t_ms": 0, "score": 999999}) == "protocol:invalid_payload", "a score cannot be submitted")
	check(act(app, conn[2], "nj", "emergency_route", {"event": "em1", "item": items[0].id, "bin": 0, "t_ms": at_tick.call()}) == "not_participating", "a player who declined cannot score")
	var board: Array = last_view(app, conn[1]).public.emergency.leaderboard
	check(board[0].score == 30 and board[0].correct == 3, "every player's leaderboard shows the server's score for seat 0 (%s)" % str(board[0]))
	check(not board[2].joined, "declining leaves no trace")
	# Late join: seat 3 joins during play; time does not restart.
	var before: Dictionary = last_view(app, conn[3]).public.emergency
	check(act(app, conn[3], "j3", "emergency_join", {"event": "em1"}) == "applied", "a late player joins during play")
	var after: Dictionary = last_view(app, conn[3]).public.emergency
	check(after.active == before.active and after.end == before.end and after.phase == "active", "and the round keeps its timeline")
	# Seat 1 disconnects: the event goes on; rejoining shows the same event and score.
	var cred: Dictionary = credentials[1]
	var t_before: int = int(last_view(app, conn[0]).tick)
	app.disconnect_peer(conn[1], now)
	tick(app)
	tick(app)
	check(int(last_view(app, conn[0]).tick) == t_before + 2, "a disconnect does not pause anything")
	app.connect_peer(9)
	app.request(9, message("hello", {"client": "test", "client_version": "1"}), now)
	app.request(9, message("rejoin", {"lobby_id": cred.lobby_id, "rejoin_token": cred.rejoin_token}), now)
	tick(app)
	var back: Dictionary = last_view(app, 9)
	check(not back.is_empty() and back.public.emergency.id == "em1" and back.own_city.emergency.joined, "rejoining restores the event and the seat's participation")
	check(back.public.emergency.active == before.active, "without restarting it")
	# The round ends: the winner and the boost reach every player.
	while last_view(app, conn[0]).public.emergency != null and last_view(app, conn[0]).public.emergency.phase != "results":
		tick(app)
	var result: Variant = last_view(app, conn[0]).public.emergency.result
	check(result != null and result.winner == 0 and result.ranking[0] == 0, "seat 0 wins (%s)" % str(result))
	check(last_view(app, conn[2]).public.emergency.result.winner == 0, "every player sees the same winner")
	var boosts: Array = last_view(app, conn[0]).own_city.boosts
	check(boosts.size() == 1 and boosts[0].stage == "collection" and boosts[0].multiplier_micro == 1300000, "the winner holds the Collection Surge")
	check(last_view(app, conn[2]).own_city.boosts.is_empty(), "nobody else does")
	print("Online emergencies: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
