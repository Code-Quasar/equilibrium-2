class_name Settings
extends RefCounted
## Device preferences: volumes, reduced motion, secure transport, developer
## diagnostics and the last server address. Nothing here reaches the server or changes the game.

const PATH := "user://settings.cfg"

static var master := 0.8
static var music := 0.6
static var sfx := 0.8
static var muted := false
static var secure := false          # wss:// instead of ws://
static var diagnostics := false     # developer network overlay
static var reduce_motion := false   # gentler effects: no repeated pulses
static var vibration := true        # short haptic taps in the emergencies (phones)
static var address := ""            # host:port as typed
static var _loaded := false


static func value(key: String) -> float:
	return {"master": master, "music": music, "sfx": sfx}.get(key, 0.0)


static func set_value(key: String, v: float) -> void:
	match key:
		"master": master = v
		"music": music = v
		"sfx": sfx = v


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		master = float(c.get_value("audio", "master", master))
		music = float(c.get_value("audio", "music", music))
		sfx = float(c.get_value("audio", "sfx", sfx))
		muted = bool(c.get_value("audio", "muted", muted))
		secure = bool(c.get_value("net", "secure", secure))
		diagnostics = bool(c.get_value("net", "diagnostics", diagnostics))
		reduce_motion = bool(c.get_value("display", "reduce_motion", reduce_motion))
		vibration = bool(c.get_value("display", "vibration", vibration))
		address = str(c.get_value("net", "address", address))
	apply_audio()


static func save() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("audio", "muted", muted)
	c.set_value("net", "secure", secure)
	c.set_value("net", "diagnostics", diagnostics)
	c.set_value("display", "reduce_motion", reduce_motion)
	c.set_value("display", "vibration", vibration)
	c.set_value("net", "address", address)
	c.save(PATH)
	apply_audio()


## Master, Music and SFX buses, made at runtime so the project file stays as it is.
static func ensure_buses() -> void:
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")


static func apply_audio() -> void:
	ensure_buses()
	_bus("Master", master)
	_bus("Music", music)
	_bus("SFX", sfx)
	AudioServer.set_bus_mute(0, muted)


static func _bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001 or (i == 0 and muted))


## What is wrong with a typed address ("" when it is fine). Accepts host,
## host:port, IPv4 and [IPv6]:port; a pasted ws:// or wss:// is tolerated.
static func address_problem(text: String) -> String:
	var a := _strip_scheme(text.strip_edges())
	if a == "":
		return "Enter the server address, for example 192.168.1.20:9080"
	if " " in a or "/" in a:
		return "Use only host:port, for example 192.168.1.20:9080"
	var hp := split_address(a)
	var host: String = hp[0]
	var port: int = hp[1]
	if host == "":
		return "The address needs a host before the colon"
	if port < 1 or port > 65535:
		return "The port must be a number from 1 to 65535"
	if host.begins_with("["):
		return ""
	var parts := host.split(".")
	var numeric := true
	for p in parts:
		if not p.is_valid_int():
			numeric = false
	if numeric:
		if parts.size() != 4:
			return "An IP address has four numbers, like 192.168.1.20"
		for p in parts:
			if int(p) < 0 or int(p) > 255:
				return "Each IP number must be between 0 and 255"
		return ""
	var re := RegEx.create_from_string("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$")
	if re.search(host) == null:
		return "That host name has characters an address cannot have"
	return ""


## [host, port]; the port is 9080 when none is typed, -1 when it is not a number.
static func split_address(a: String) -> Array:
	a = _strip_scheme(a.strip_edges())
	if a.begins_with("["):
		var close := a.find("]")
		if close < 0:
			return ["", -1]
		var rest := a.substr(close + 1)
		if rest == "":
			return [a.substr(0, close + 1), 9080]
		if not rest.begins_with(":") or not rest.substr(1).is_valid_int():
			return [a.substr(0, close + 1), -1]
		return [a.substr(0, close + 1), int(rest.substr(1))]
	var i := a.rfind(":")
	if i < 0:
		return [a, 9080]
	var p := a.substr(i + 1)
	return [a.substr(0, i), int(p) if p.is_valid_int() else -1]


static func address_to_url(text: String) -> String:
	var hp := split_address(text)
	return "%s://%s:%d" % ["wss" if secure else "ws", hp[0], hp[1]]


## A saved ws:// URL shown back as host:port.
static func url_to_address(url: String) -> String:
	return _strip_scheme(url).trim_suffix("/")


static func _strip_scheme(a: String) -> String:
	for s in ["wss://", "ws://", "https://", "http://"]:
		if a.to_lower().begins_with(s):
			return a.substr(s.length())
	return a
