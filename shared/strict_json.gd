extends RefCounted
## Bounded integer-only JSON decoder. Never delegates object/number parsing to JSON.
const MAX_BYTES = 32768
const MAX_DEPTH = 8
const MAX_STRING = 1024
const MAX_ITEMS = 64
const MAX_INTEGER = 9007199254740991
var text: String
var pos: int = 0
var error: String = ""

func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_BYTES: return {"error":"message_too_large"}
	text = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes: return {"error":"invalid_utf8"}
	pos = 0
	error = ""
	var value: Variant = parse_value(0)
	space()
	if error.is_empty() and (pos != text.length() or not value is Dictionary): error = "invalid_json"
	return {"error":error,"value":value}

func space() -> void:
	while pos < text.length() and text[pos] in [" ","\t","\r","\n"]: pos += 1

func parse_value(depth: int) -> Variant:
	space()
	if depth > MAX_DEPTH or pos >= text.length():
		error = "invalid_json"
		return null
	var ch: String = text[pos]
	if ch == '"': return string_value()
	if ch in ["{","["]:
		pos += 1
		var object: bool = ch == "{"
		var result: Variant = {} if object else []
		var end: String = "}" if object else "]"
		space()
		if pos < text.length() and text[pos] == end:
			pos += 1
			return result
		while error.is_empty():
			if result.size() >= MAX_ITEMS:
				error = "container_too_large"
				break
			var key: String = ""
			if object:
				space()
				if pos >= text.length() or text[pos] != '"': break
				key = string_value()
				space()
				if result.has(key):
					error = "duplicate_key"
					break
				if pos >= text.length() or text[pos] != ":": break
				pos += 1
			var item: Variant = parse_value(depth + 1)
			if not error.is_empty(): break
			if object: result[key] = item
			else: result.append(item)
			space()
			if pos >= text.length(): break
			if text[pos] == end:
				pos += 1
				return result
			if text[pos] != ",": break
			pos += 1
		if error.is_empty(): error = "invalid_json"
		return null
	for literal in ["true","false","null"]:
		if text.substr(pos,literal.length()) == literal:
			pos += literal.length()
			if literal == "null": return null
			return literal == "true"
	var start: int = pos
	if ch == "-": pos += 1
	var digits: int = pos
	while pos < text.length() and text[pos] >= "0" and text[pos] <= "9": pos += 1
	var token: String = text.substr(start,pos-start)
	if pos == digits or (pos-digits > 1 and text[digits] == "0") or token.length() > 17:
		error = "invalid_number"
		return null
	if pos < text.length() and text[pos] in [".","e","E","+"]:
		error = "invalid_number"
		return null
	var number: int = token.to_int()
	if absi(number) > MAX_INTEGER: error = "invalid_number"
	return number

func hex4() -> int:
	if pos + 4 > text.length(): return -1
	var value: int = 0
	for i in range(4):
		var digit: int = "0123456789abcdef".find(text[pos+i].to_lower())
		if digit < 0: return -1
		value = value * 16 + digit
	pos += 4
	return value

func string_value() -> String:
	pos += 1
	var result: String = ""
	while pos < text.length():
		var ch: String = text[pos]
		pos += 1
		if ch == '"': return result
		if ch.unicode_at(0) < 32: break
		if ch == "\\":
			if pos >= text.length(): break
			ch = text[pos]
			pos += 1
			var escapes: Dictionary = {'"':'"',"\\":"\\","/":"/","b":"\b","f":"\f","n":"\n","r":"\r","t":"\t"}
			if escapes.has(ch): ch = escapes[ch]
			elif ch == "u":
				var code: int = hex4()
				if code < 0: break
				if code >= 0xD800 and code <= 0xDBFF:
					if text.substr(pos,2) != "\\u": break
					pos += 2
					var low: int = hex4()
					if low < 0xDC00 or low > 0xDFFF: break
					code = 0x10000 + (code-0xD800)*1024 + low-0xDC00
				elif code >= 0xDC00 and code <= 0xDFFF: break
				ch = String.chr(code)
			else: break
		result += ch
		if result.length() > MAX_STRING:
			error = "string_too_large"
			return ""
	error = "invalid_string"
	return ""
