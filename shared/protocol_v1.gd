extends RefCounted
const Decoder = preload("res://shared/strict_json.gd")
const Canonical = preload("res://simulation/core/canonical.gd")
const FIELDS = {
	"hello":{"client":TYPE_STRING,"client_version":TYPE_STRING},
	"create_lobby":{}, "join_lobby":{"join_code":TYPE_STRING},
	"set_ready":{"ready":TYPE_BOOL}, "start_match":{},
	"choose_foundation":{"action_id":TYPE_STRING,"foundation":TYPE_STRING},
	"submit_action":{"action_id":TYPE_STRING,"kind":TYPE_STRING,"payload":TYPE_DICTIONARY},
	"rejoin":{"lobby_id":TYPE_STRING,"rejoin_token":TYPE_STRING}
}
## Required payload fields per action; OPTIONAL lists the fields an action may add.
const PAYLOADS = {
	"construct":{"building_type":TYPE_STRING,"size":TYPE_STRING},
	"upgrade":{"building_id":TYPE_INT},"disable":{"building_id":TYPE_INT},
	"enable":{"building_id":TYPE_INT},"demolish":{"building_id":TYPE_INT},"cancel_project":{"building_id":TYPE_INT},
	"sell_materials":{"amount":TYPE_INT},
	"publish_offer":{"type":TYPE_STRING,"rate":TYPE_INT},
	"withdraw_offer":{"id":TYPE_INT},"accept_offer":{"id":TYPE_INT},"cancel_contract":{"id":TYPE_INT}
}
const OPTIONAL = {"construct":{"tile":TYPE_INT},"accept_offer":{"duration":TYPE_INT}}
static func decode(bytes: PackedByteArray) -> Dictionary:
	var result: Dictionary = Decoder.new().decode(bytes)
	if result.error == "": result.error = validate(result.value)
	return result

static func shape(value: Dictionary, required: Dictionary, optional: Dictionary = {}) -> bool:
	for key in required:
		if not value.has(key) or typeof(value[key]) != required[key]: return false
	for key in value:
		if not required.has(key) and (not optional.has(key) or typeof(value[key]) != optional[key]): return false
	return true

static func identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 64: return false
	for ch in value:
		if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func validate(m: Dictionary) -> String:
	if typeof(m.get("v")) != TYPE_INT or m.v != 1: return "unsupported_version"
	if typeof(m.get("type")) != TYPE_STRING or not FIELDS.has(m.type): return "unknown_message"
	var fields: Dictionary = FIELDS[m.type].duplicate()
	fields.merge({"v":TYPE_INT,"type":TYPE_STRING,"correlation_id":TYPE_STRING})
	var optional: Dictionary = {"observed_tick":TYPE_INT} if m.type == "submit_action" else {}
	if m.type in ["create_lobby","join_lobby"]: optional = {"city_name":TYPE_STRING}
	if not shape(m,fields,optional): return "invalid_fields"
	if not identifier(m.correlation_id): return "invalid_identifier"
	if m.has("action_id") and not identifier(m.action_id): return "invalid_identifier"
	if m.has("observed_tick") and (m.observed_tick < 0 or m.observed_tick > 1200): return "invalid_tick"
	if m.type == "hello" and (m.client not in ["terminal","godot","test"] or m.client_version.length() > 64): return "invalid_client"
	if m.has("city_name") and city_name_error(m.city_name) != "": return "invalid_city_name"
	if m.type == "submit_action": return payload_error(m.kind,m.payload)
	return ""

## A city name: 2 to 20 letters, digits, spaces, apostrophes or hyphens,
## with no space at either end or two in a row.
const NAME_MIN := 2
const NAME_MAX := 20
static func city_name_error(name: String) -> String:
	if name.length() < NAME_MIN or name.length() > NAME_MAX: return "length"
	if name != name.strip_edges() or "  " in name: return "spaces"
	for ch in name:
		var c: int = ch.unicode_at(0)
		var letter: bool = (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 0xC0 and c <= 0x24F)
		if not (letter or (c >= 48 and c <= 57) or ch in " '-"): return "characters"
	return ""

static func payload_error(kind: String, p: Dictionary) -> String:
	if not PAYLOADS.has(kind): return "invalid_command_kind"
	if not shape(p,PAYLOADS[kind],OPTIONAL.get(kind,{})): return "invalid_payload"
	for key in p:
		if typeof(p[key]) == TYPE_INT and (p[key] < 0 or p[key] > 100000000000): return "invalid_payload"
	if (p.has("tile") and p.tile > 35) or (p.has("duration") and p.duration > 1200): return "invalid_payload"
	return ""

static func message(kind: String, body: Dictionary = {}) -> Dictionary:
	var result: Dictionary = body.duplicate(true)
	result.v = 1
	result.type = kind
	return result
