class_name Soundtrack
extends Node
## Ambient music and one-shot alerts. The music state follows the city's
## authoritative environment and the match's events; changes crossfade.
## Alerts play once per transition (a warning appearing, a crisis starting,
## a building finishing), never on every update.

const STATES := ["calm", "strained", "polluted", "crisis"]
const FADE := 3.0
const ALERTS := {
	"warning": "res://assets/kenney/sounds/question_002.ogg",
	"crisis": "res://assets/kenney/sounds/error_004.ogg",
	"crisis_over": "res://assets/kenney/sounds/confirmation_002.ogg",
	"notice": "res://assets/kenney/sounds/glass_002.ogg",
	"built": "res://assets/kenney/sounds/maximize_006.ogg",
}
## Short effects for the ECO EMERGENCIES, several at once from a small pool.
const SFX := {
	"alert": "res://assets/kenney/sounds/question_004.ogg",
	"countdown": "res://assets/kenney/sounds/tick_002.ogg",
	"go": "res://assets/kenney/sounds/maximize_003.ogg",
	"final": "res://assets/kenney/sounds/tick_004.ogg",
	"right": "res://assets/kenney/sounds/confirmation_001.ogg",
	"wrong": "res://assets/kenney/sounds/error_006.ogg",
	"combo": "res://assets/kenney/sounds/maximize_008.ogg",
	"bin": "res://assets/kenney/sounds/drop_002.ogg",
	"swipe": "res://assets/kenney/sounds/scratch_002.ogg",
	"slice": "res://assets/kenney/sounds/glass_004.ogg",
	"hazard": "res://assets/kenney/sounds/glitch_002.ogg",
	"fault": "res://assets/kenney/sounds/switch_004.ogg",
	"repair": "res://assets/kenney/sounds/confirmation_003.ogg",
	"stable": "res://assets/kenney/sounds/maximize_005.ogg",
	"victory": "res://assets/kenney/sounds/maximize_009.ogg",
	"defeat": "res://assets/kenney/sounds/close_003.ogg",
	"boost": "res://assets/kenney/sounds/maximize_006.ogg",
	"pickup": "res://assets/kenney/sounds/select_002.ogg",
	"exit_warn": "res://assets/kenney/sounds/tick_001.ogg",
	"slice_plastic": "res://assets/kenney/sounds/pluck_002.ogg",
	"slice_metal": "res://assets/kenney/sounds/switch_006.ogg",
	"slice_paper": "res://assets/kenney/sounds/scratch_004.ogg",
	"slice_glass": "res://assets/kenney/sounds/glass_004.ogg",
	"multi": "res://assets/kenney/sounds/maximize_002.ogg",
	"jam": "res://assets/kenney/sounds/glitch_003.ogg",
	"pressure": "res://assets/kenney/sounds/question_003.ogg",
	"misalign": "res://assets/kenney/sounds/switch_007.ogg",
	"recover": "res://assets/kenney/sounds/maximize_005.ogg",
	"critical": "res://assets/kenney/sounds/error_004.ogg",
	"partial": "res://assets/kenney/sounds/click_003.ogg",
}
## The shortest gap between two plays of one effect: a burst of hits is one sound.
const SFX_GAP_MS := 70

var state := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _alert: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _last_sfx := {}                  # effect -> when it last played
var played := {}                     # tests only: effect -> times played
var _streams := {}
var _warned := {}
var _active_events := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_alert = AudioStreamPlayer.new()
	_alert.bus = "SFX"
	_alert.volume_db = -4.0
	add_child(_alert)
	for i in 6:
		var s := AudioStreamPlayer.new()
		s.bus = "SFX"
		s.volume_db = -6.0
		add_child(s)
		_sfx.append(s)


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var s: AudioStream = load("res://assets/music/%s.ogg" % name)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_streams[name] = s
	return _streams[name]


## Crossfades to a music state; the same state again does nothing.
func play_state(name: String) -> void:
	if name == state or not name in STATES:
		return
	state = name
	var old := _players[_active]
	_active = 1 - _active
	var nxt := _players[_active]
	nxt.stream = _stream(name)
	nxt.volume_db = -40.0
	nxt.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(nxt, "volume_db", -8.0, FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_property(old, "volume_db", -60.0, FADE).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(func():
		if old != _players[_active]:
			old.stop())


## The state for a city: a crisis under way first, then a poor environment,
## then a strained one (environment or satisfaction middling), else calm.
static func state_for(view: Dictionary) -> String:
	var own: Dictionary = view.get("own_city", {})
	var ev: Dictionary = view.get("public", {}).get("crisis", {})
	if not ev.get("active", []).is_empty():
		return "crisis"
	var env := float(own.get("environment_micro", 0)) / 1000000.0
	var sat := float(own.get("satisfaction_micro", 0) if own.get("satisfaction_micro") != null else 0) / 1000000.0
	if env < 45.0:
		return "polluted"
	if env < 65.0 or sat < 55.0 or not ev.get("announced", []).is_empty():
		return "strained"
	return "calm"


## Called with each new view: music state, and alerts for event transitions.
func follow(view: Dictionary) -> void:
	play_state(state_for(view))
	var ev: Dictionary = view.get("public", {}).get("crisis", {})
	var warnings := {}
	for id in ev.get("announced", []):
		warnings[id] = true
		if not _warned.has(id):
			alert("warning")
	var active := {}
	for id in ev.get("active", []):
		active[id] = true
		if not _active_events.has(id):
			alert("crisis")
	for id in _active_events:
		if not active.has(id):
			alert("crisis_over")
	_warned = warnings
	_active_events = active


## One short effect; up to six play at once and the same one at most every
## SFX_GAP_MS, so bursts never become a wall of noise. A missing sound plays nothing.
func sfx(kind: String) -> void:
	if not SFX.has(kind) or _sfx.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_sfx.get(kind, -100000)) < SFX_GAP_MS:
		return
	_last_sfx[kind] = now
	played[kind] = int(played.get(kind, 0)) + 1
	var stream: Variant = load(SFX[kind])
	if stream == null:
		return
	var p: AudioStreamPlayer = _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.stream = stream
	p.play()


func alert(kind: String) -> void:
	if not ALERTS.has(kind):
		return
	_alert.stream = load(ALERTS[kind])
	_alert.play()


func _notification(what: int) -> void:
	# Phones: silence while the app is in the background, resume after.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("mobile"):
		for p in _players:
			p.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN and OS.has_feature("mobile"):
		for p in _players:
			p.stream_paused = false
