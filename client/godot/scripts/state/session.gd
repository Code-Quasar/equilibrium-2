class_name Session
extends Node
## Everything the client knows about its seat, built only from server
## messages. Screens read it and call its intent methods; nothing here
## simulates the game or decides an outcome.
##
## Actions go through four visible states: sending → queued (admitted, runs on
## the next tick) or applied → applied/rejected on execution. An action is never
## shown as done before the server says so.

signal changed(what: String)                 # "phase", "lobby", "draft", "view", "actions", "link"
signal notice(text: String, level: String)   # level: info, good, warn, bad

const STORE := "user://session.cfg"
## Where this seat's credentials live; tests running two players in one process use two files.
var store := STORE
const REJOIN_EVERY_MS := 3000

var link: Link
var server_url := ""
var phase := "menu"          # menu, connecting, lobby, draft, play, over, cancelled
var live := false            # true while the socket is open and authenticated
var seat := -1
var is_host := false
var lobby_id := ""
var join_code := ""
var lobby: Dictionary = {}   # last lobby_state
var draft: Dictionary = {}   # last draft_state
var view: Dictionary = {}    # last player_view (newest view_seq)
var final_result: Variant = null
var actions := {}            # action_id -> {kind, payload, label, status, error, sent_ms, done_ms}
var draft_choice := {}       # {action_id, foundation} while a Foundation pick is pending
var last_error := ""
var view_ms := 0             # when the newest player_view arrived (diagnostics)
var ack_avg_ms := -1.0       # average send → admission time (diagnostics)

var _intent := {}            # what to do once the socket is ready
var _rejoin_at := -1


func _ready() -> void:
	link = Link.new()
	add_child(link)
	link.opened.connect(_on_open)
	link.message.connect(_on_message)
	link.closed.connect(_on_closed)
	_load()


# ---------------------------------------------------------------- intents ---

func create(url: String, city := "") -> void:
	var m := {"type": "create_lobby"}
	if city.strip_edges() != "":
		m["city_name"] = city.strip_edges()
	_start(url, m)


func join(url: String, code: String, city := "") -> void:
	var m := {"type": "join_lobby", "join_code": code.strip_edges().to_upper()}
	if city.strip_edges() != "":
		m["city_name"] = city.strip_edges()
	_start(url, m)


## The name a seat's player chose, from the lobby the server sent.
func city_name(s: int) -> String:
	for row in lobby.get("seats", []):
		if int(row.get("seat", -1)) == s and str(row.get("name", "")) != "":
			return str(row["name"])
	return "City %d" % (s + 1)


func has_saved_seat() -> bool:
	var c := ConfigFile.new()
	return c.load(store) == OK and str(c.get_value("seat", "token", "")) != ""


func rejoin() -> void:
	var c := ConfigFile.new()
	if c.load(store) != OK:
		return
	_start(str(c.get_value("seat", "url", server_url)), {"type": "rejoin",
		"lobby_id": str(c.get_value("seat", "lobby_id", "")), "rejoin_token": str(c.get_value("seat", "token", ""))})


func set_ready(on: bool) -> void:
	link.send("set_ready", {"ready": on})


func start_match() -> void:
	link.send("start_match")


func choose_foundation(id: String) -> void:
	if not draft_choice.is_empty():
		return
	var aid := Link.new_id()
	draft_choice = {"action_id": aid, "foundation": id, "status": "sending"}
	if link.send("choose_foundation", {"action_id": aid, "foundation": id}) == "":
		draft_choice = {}
		notice.emit("Not connected", "bad")
	changed.emit("draft")


## Sends a gameplay action. label is the player-facing description.
func act(kind: String, payload: Dictionary, label: String) -> String:
	if phase != "play" or not live:
		notice.emit("Reconnecting — actions are paused", "warn")
		return ""
	var aid := Link.new_id()
	actions[aid] = {"kind": kind, "payload": payload.duplicate(true), "label": label, "status": "sending",
		"error": "", "sent_ms": Time.get_ticks_msec(), "done_ms": 0}
	var m := {"action_id": aid, "kind": kind, "payload": payload}
	if view.has("tick"):
		m["observed_tick"] = int(view["tick"])
	if link.send("submit_action", m) == "":
		actions[aid]["status"] = "rejected"
		actions[aid]["error"] = "not_connected"
	changed.emit("actions")
	return aid


## Pending and recent actions, newest first, for the activity strip.
func recent_actions(n := 5) -> Array:
	var out := []
	for id in actions:
		out.append(actions[id].merged({"id": id}))
	out.sort_custom(func(a, b): return a["sent_ms"] > b["sent_ms"])
	return out.slice(0, n)


func pending_for(kind: String, key: String, value: Variant) -> bool:
	for id in actions:
		var a: Dictionary = actions[id]
		if a["kind"] == kind and a["status"] in ["sending", "queued"] and a["payload"].get(key) == value:
			return true
	return false


func leave() -> void:
	_intent = {}
	_rejoin_at = -1
	link.close()
	live = false
	_reset_room()
	_forget_seat()
	phase = "menu"
	changed.emit("phase")


# ------------------------------------------------------------- connection ---

func _start(url: String, intent: Dictionary) -> void:
	server_url = url.strip_edges()
	if not server_url.begins_with("ws://") and not server_url.begins_with("wss://"):
		server_url = "ws://" + server_url
	_save_url()
	_intent = intent
	if intent["type"] != "rejoin":
		_reset_room()
	phase = "connecting" if phase in ["menu", "cancelled", "over"] else phase
	changed.emit("phase")
	link.open(server_url)


func _on_open() -> void:
	live = true
	_rejoin_at = -1
	changed.emit("link")
	if not _intent.is_empty():
		var t: String = _intent["type"]
		var body := _intent.duplicate()
		body.erase("type")
		link.send(t, body)
		_intent = {}


func _on_closed(reason: String) -> void:
	var was_live := live
	live = false
	changed.emit("link")
	if phase in ["draft", "play"] and has_saved_seat():
		# The seat is reserved: keep the last authoritative view on screen,
		# marked stale, and try to rejoin.
		if was_live:
			notice.emit("Connection lost — reconnecting…", "warn")
		_rejoin_at = Time.get_ticks_msec() + REJOIN_EVERY_MS
		return
	if phase == "lobby":
		notice.emit("Disconnected: a lobby seat is released when you leave. Join again with the code.", "bad")
		_reset_room()
		_forget_seat()
	elif phase == "connecting":
		notice.emit(_explain(reason, "Cannot reach the server at %s" % server_url), "bad")
	if phase in ["lobby", "connecting"]:
		phase = "menu"
		changed.emit("phase")


func _process(_delta: float) -> void:
	if _rejoin_at > 0 and Time.get_ticks_msec() >= _rejoin_at:
		_rejoin_at = Time.get_ticks_msec() + REJOIN_EVERY_MS
		var c := ConfigFile.new()
		if c.load(store) == OK:
			_intent = {"type": "rejoin", "lobby_id": str(c.get_value("seat", "lobby_id", "")), "rejoin_token": str(c.get_value("seat", "token", ""))}
			link.open(server_url)


# --------------------------------------------------------------- messages ---

func _on_message(m: Dictionary) -> void:
	match str(m.get("type", "")):
		"seat_assigned":
			seat = int(m["seat"])
			is_host = bool(m.get("host", false))
			lobby_id = str(m["lobby_id"])
			# Persist the rotated credential before anything else can fail.
			_save_seat(lobby_id, str(m["rejoin_token"]))
			if phase in ["connecting", "menu"]:
				phase = "lobby"
				changed.emit("phase")
		"lobby_created":
			join_code = str(m["join_code"])
			changed.emit("lobby")
		"lobby_state":
			lobby = m
			is_host = int(m.get("host_seat", -1)) == seat
			match str(m.get("phase", "")):
				"waiting":
					_set_phase("lobby")
				"draft":
					_set_phase("draft")
				"running":
					_set_phase("play")
				"finished":
					_set_phase("over")
			changed.emit("lobby")
		"draft_state":
			draft = m
			var picks: Array = m.get("choices", [])
			if not draft_choice.is_empty() and seat >= 0 and seat < picks.size() and picks[seat] != null:
				draft_choice = {}
			_set_phase("draft")
			changed.emit("draft")
		"match_started":
			draft_choice = {}
			_set_phase("play")
		"player_view":
			if not view.is_empty() and m.get("match_id") == view.get("match_id") and int(m.get("view_seq", 0)) < int(view.get("view_seq", 0)):
				return  # an older snapshot arriving late
			view = m
			view_ms = Time.get_ticks_msec()
			if phase in ["draft", "lobby", "connecting", "menu"] and str(m["public"].get("phase", "")) != "finished":
				_set_phase("play")
			if m.get("final_result") != null:
				final_result = m["final_result"]
			changed.emit("view")
		"action_ack":
			_ack(m)
		"match_finished":
			final_result = m
			_set_phase("over")
			_forget_seat()
		"match_cancelled":
			notice.emit("The draft was cancelled: a player did not return in time.", "bad")
			_reset_room()
			_forget_seat()
			_set_phase("cancelled")
		"protocol_error":
			var code := str(m.get("code", ""))
			last_error = code
			if code == "authentication_failed":
				_forget_seat()
				_rejoin_at = -1
				if phase in ["draft", "play", "connecting"]:
					notice.emit("Your seat could not be restored. The match may be over or the server restarted.", "bad")
					_set_phase("menu")
				return
			notice.emit(_explain(code, code), "bad")
			if phase == "connecting":
				_set_phase("menu")


func _ack(m: Dictionary) -> void:
	var aid := str(m.get("action_id", ""))
	var phase_name := str(m.get("phase", ""))
	var status := str(m.get("status", ""))
	if not draft_choice.is_empty() and aid == draft_choice["action_id"]:
		if status in ["queued", "applied"]:
			draft_choice["status"] = "confirmed" if status == "applied" else "queued"
		else:
			notice.emit("Not chosen: %s" % _explain(status, status), "bad")
			draft_choice = {}
		changed.emit("draft")
		return
	if not actions.has(aid):
		return  # an older action replayed after rejoin
	var a: Dictionary = actions[aid]
	if a["status"] in ["applied", "rejected"]:
		return  # never let a later message override an outcome
	if not a.has("ack_ms"):
		a["ack_ms"] = Time.get_ticks_msec()
		var lat := float(a["ack_ms"] - int(a.get("sent_ms", a["ack_ms"])))
		ack_avg_ms = lat if ack_avg_ms < 0 else lerpf(ack_avg_ms, lat, 0.25)
	if status == "queued" and phase_name == "admission":
		a["status"] = "queued"
	elif status == "applied":
		# Shown in the action list; no toast, to keep the screen calm.
		a["status"] = "applied"
		a["done_ms"] = Time.get_ticks_msec()
	else:
		a["status"] = "rejected"
		a["error"] = status
		a["done_ms"] = Time.get_ticks_msec()
		notice.emit("%s — %s" % [a["label"], _explain(status, status)], "bad")
	changed.emit("actions")


func _set_phase(p: String) -> void:
	if phase != p:
		phase = p
		changed.emit("phase")


func _reset_room() -> void:
	seat = -1
	is_host = false
	lobby_id = ""
	join_code = ""
	lobby = {}
	draft = {}
	view = {}
	final_result = null
	actions.clear()
	draft_choice = {}


# ----------------------------------------------------------- credentials ---
# The rejoin token is a secret: it is stored in the app's private user://
# folder, never displayed and never logged.

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(store) == OK:
		server_url = str(c.get_value("server", "url", ""))


func _save_url() -> void:
	var c := ConfigFile.new()
	c.load(store)
	c.set_value("server", "url", server_url)
	c.save(store)


func _save_seat(lid: String, token: String) -> void:
	var c := ConfigFile.new()
	c.load(store)
	c.set_value("seat", "url", server_url)
	c.set_value("seat", "lobby_id", lid)
	c.set_value("seat", "token", token)
	if c.save(store) != OK:
		notice.emit("Could not save your seat: you will not be able to rejoin after a disconnect.", "warn")


func _forget_seat() -> void:
	var c := ConfigFile.new()
	if c.load(store) == OK and c.has_section("seat"):
		c.erase_section("seat")
		c.save(store)


# ------------------------------------------------------------------ text ---

static func _explain(code: String, fallback: String) -> String:
	return Catalogue.error_text(code) if Catalogue.error_text(code) != "" else fallback.replace("_", " ")
