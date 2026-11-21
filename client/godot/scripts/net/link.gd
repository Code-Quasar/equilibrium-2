class_name Link
extends Node
## One WebSocket to the authoritative server, speaking protocol v1: one JSON
## object per text message, integers only, every request tagged with a
## correlation id. It performs the hello/welcome handshake and measures how
## long the server takes to answer, for the network diagnostics panel. It
## knows nothing about lobbies or games.

signal opened                       # welcome received; requests may be sent
signal message(m: Dictionary)       # every server message after welcome
signal closed(reason: String)       # the socket closed or never opened

const CLIENT_VERSION := "1.0"
const CONNECT_TIMEOUT_MS := 8000

var url := ""
var handshaken := false             # welcome received
var rtt_ms := -1.0                  # last request→answer time
var rtt_avg_ms := -1.0
var jitter_ms := 0.0

var _ws: WebSocketPeer
var _opening_since := 0
var _hello_id := ""
var _sent_at := {}                  # correlation id -> ticks_msec
var _was_open := false


func open(address: String) -> void:
	close()
	url = address
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 16
	_ws.max_queued_packets = 256
	_ws.heartbeat_interval = 10.0
	_opening_since = Time.get_ticks_msec()
	_was_open = false
	handshaken = false
	if _ws.connect_to_url(address) != OK:
		_ws = null
		closed.emit("bad_address")


func close() -> void:
	if _ws != null:
		_ws.close(1000, "client")
	_ws = null
	handshaken = false
	_sent_at.clear()


func is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Sends a protocol message and returns its correlation id, or "" if the
## socket is not ready. Fields must already be integer-valued where numeric.
func send(kind: String, fields: Dictionary = {}) -> String:
	if not is_open() or (not handshaken and kind != "hello"):
		return ""
	var m := fields.duplicate(true)
	m["v"] = 1
	m["type"] = kind
	m["correlation_id"] = new_id()
	_sent_at[m["correlation_id"]] = Time.get_ticks_msec()
	_ws.send_text(JSON.stringify(m))
	return m["correlation_id"]


static func new_id() -> String:
	var b := PackedByteArray()
	for i in 12:
		b.append(randi() & 0xff)
	return b.hex_encode()


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - _opening_since > CONNECT_TIMEOUT_MS:
		_ws = null
		closed.emit("timeout")
		return
	if state == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_hello_id = send("hello", {"client": "godot", "client_version": CLIENT_VERSION})
	while _ws != null and _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		_receive(_integers(data))
	if _ws != null and state == WebSocketPeer.STATE_CLOSED:
		var why := _ws.get_close_reason()
		_ws = null
		handshaken = false
		closed.emit(why if why != "" else ("refused" if not _was_open else "connection_lost"))


func _receive(m: Dictionary) -> void:
	var cid: String = str(m.get("correlation_id", ""))
	if _sent_at.has(cid):
		_measure(Time.get_ticks_msec() - int(_sent_at[cid]))
		_sent_at.erase(cid)
	if not handshaken:
		if m.get("type") == "welcome":
			handshaken = true
			opened.emit()
		elif m.get("type") == "protocol_error":
			closed.emit(str(m.get("code", "handshake_failed")))
			close()
		return
	message.emit(m)


func _measure(ms: float) -> void:
	if rtt_avg_ms < 0:
		rtt_avg_ms = ms
	else:
		jitter_ms = lerpf(jitter_ms, absf(ms - rtt_avg_ms), 0.2)
		rtt_avg_ms = lerpf(rtt_avg_ms, ms, 0.2)
	rtt_ms = ms


## Godot's JSON parser returns every number as a float; the protocol is
## integer-only, so whole floats become ints again.
static func _integers(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) and absf(v) < 9.0e15 else v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _integers(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_integers(x))
			return a
	return v
