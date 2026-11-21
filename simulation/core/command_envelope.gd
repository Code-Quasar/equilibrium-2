extends RefCounted
const Canonical = preload("res://simulation/core/canonical.gd")
const FIELDS = ["match_id", "player_id", "command_seq", "command_id", "command_type", "payload", "server_received_tick"]

static func validate(raw: Variant, match_id: String, tick: int, authenticated_player: int) -> String:
	if not raw is Dictionary or raw.size() != FIELDS.size():
		return "malformed_command"
	for field in FIELDS:
		if not raw.has(field):
			return "malformed_command"
	for field in ["match_id", "command_id", "command_type"]:
		if typeof(raw[field]) != TYPE_STRING or raw[field].is_empty():
			return "malformed_command"
	for field in ["player_id", "command_seq", "server_received_tick"]:
		if typeof(raw[field]) != TYPE_INT:
			return "malformed_command"
	if not raw.payload is Dictionary or not Canonical.supports(raw.payload):
		return "malformed_payload"
	if raw.player_id < 0 or raw.player_id >= 4:
		return "invalid_player"
	if raw.player_id != authenticated_player:
		return "unauthorized_player"
	if raw.match_id != match_id:
		return "wrong_match"
	if raw.command_seq < 0:
		return "invalid_sequence"
	# Only the trusted adapter creates envelopes, stamped with current server tick.
	if raw.server_received_tick != tick:
		return "invalid_received_tick"
	return ""

static func before(a: Dictionary, b: Dictionary, seed_value: int) -> bool:
	if a.server_received_tick != b.server_received_tick:
		return a.server_received_tick < b.server_received_tick
	var rotation: int = posmod(seed_value, 4)
	var rank_a: int = posmod(a.player_id - rotation, 4)
	var rank_b: int = posmod(b.player_id - rotation, 4)
	if rank_a != rank_b:
		return rank_a < rank_b
	return a.command_seq < b.command_seq
