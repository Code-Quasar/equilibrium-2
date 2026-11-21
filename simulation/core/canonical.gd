extends RefCounted
## Version 1 wire form: sorted string keys, exact decimal integers, no floats.
## JSON.parse_string converts JSON numbers to doubles: do not use it to restore
## arbitrary int64 snapshots. A future decoder must preserve integer tokens.

static func supports(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item in value:
				if not supports(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not supports(value[key]):
					return false
			return true
	return false

static func encode(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_STRING:
			return JSON.stringify(value)
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for item in value:
				parts.append(encode(item))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var parts: PackedStringArray = []
			for key in keys:
				parts.append(JSON.stringify(key) + ":" + encode(value[key]))
			return "{" + ",".join(parts) + "}"
	assert(false, "Unsupported canonical value")
	return ""
