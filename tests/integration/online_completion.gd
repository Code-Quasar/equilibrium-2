extends SceneTree
## Injected clock drives a real complete match, never edits simulation state/time.
const App = preload("res://server/application.gd")
const P = preload("res://shared/protocol_v1.gd")
func send(app: RefCounted, kind: String, fields: Dictionary = {}) -> void:
	fields.correlation_id = "test"
	app.request(1,P.message(kind,fields),0)
func _initialize() -> void:
	var app = App.new()
	app.connect_peer(1)
	send(app,"hello",{"client":"test","client_version":"1"})
	send(app,"create_lobby")
	send(app,"set_ready",{"ready":true})
	send(app,"start_match")
	while app.phase == "draft":
		var d: Dictionary = app.match_session.draft_view()
		send(app,"choose_foundation",{"action_id":"draft","foundation":d.available_foundations[0]})
	send(app,"submit_action",{"action_id":"policy","kind":"set_reduce_waste","payload":{"enabled":true}})
	var previous: int = 0
	for tick in range(1,1201):
		app.outbox.clear()
		app.advance(tick*1000)
		var state: Dictionary = app.match_session.game.snapshot()
		if state.tick != previous+1 or state.cities.reduce(func(n,c): return n+c.population,0) != 4000:
			printerr("FAIL: tick/conservation"); quit(1); return
		previous = state.tick
	var state: Dictionary = app.match_session.game.snapshot()
	var canonical: String = app.match_session.game.engine.serialize()
	app.advance(9000000)
	if app.phase != "finished" or state.final_result.duration != 1200 or canonical != app.match_session.game.engine.serialize():
		printerr("FAIL: completion"); quit(1); return
	if not app.outbox.any(func(item): return item.message.type == "match_finished"):
		printerr("FAIL: final publication"); quit(1); return
	print("PASS: 1200 injected-clock ticks, four-city conservation, final results, no post-finish steps")
	quit(0)
