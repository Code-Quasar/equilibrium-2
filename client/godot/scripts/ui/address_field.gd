class_name AddressField
extends VBoxContainer
## The server address as a player types it: four numbers of an IP address and a
## port, each in its own numeric box. The dots and the colon are drawn, never
## typed; a full number moves on to the next box, "." or ":" jumps ahead,
## Backspace in an empty box goes back, and a pasted "a.b.c.d:port" fills every
## box. Each box is checked as it is typed and the first problem is shown under
## the row, so no connection is tried with an address that cannot work.

signal changed
signal submitted

var parts: Array[LineEdit] = []     # four IP numbers, then the port
var _error: Label


func _init(address := "") -> void:
	add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in 5:
		var f := LineEdit.new()
		f.theme_type_variation = "DarkField"
		# No max_length: it would cut a pasted address before it can be spread
		# over the boxes. Lengths are kept in _on_text instead.
		f.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		f.placeholder_text = ["192", "168", "1", "20", "9080"][i]
		f.alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.add_theme_font_override("font", UI.number_font())
		f.select_all_on_focus = true
		f.custom_minimum_size = Vector2(0, 50)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.size_flags_stretch_ratio = 1.0 if i < 4 else 1.45
		f.text_changed.connect(_on_text.bind(i))
		f.gui_input.connect(_on_key.bind(i))
		f.text_submitted.connect(func(_t): _advance(i, true))
		parts.append(f)
		row.add_child(f)
		if i < 4:
			var sep := Label.new()
			sep.text = "." if i < 3 else ":"
			sep.theme_type_variation = "OnDarkTitle"
			sep.size_flags_vertical = Control.SIZE_SHRINK_END
			row.add_child(sep)
	_error = Label.new()
	_error.theme_type_variation = "OnDarkError"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.visible = false
	add_child(_error)
	set_address(address)


## Fills the boxes from "a.b.c.d:port" (anything else leaves them empty).
func set_address(address: String) -> void:
	var hp := Settings.split_address(address)
	var ip: PackedStringArray = str(hp[0]).split(".")
	var numeric := ip.size() == 4
	for x in ip:
		numeric = numeric and x.is_valid_int()
	for i in 4:
		parts[i].text = ip[i] if numeric else ""
	parts[4].text = str(hp[1]) if numeric and int(hp[1]) > 0 else ""


## "a.b.c.d:port" as typed.
func address() -> String:
	return "%s.%s.%s.%s:%s" % [parts[0].text, parts[1].text, parts[2].text, parts[3].text, parts[4].text]


## The first problem with the boxes, or "" when the address can be used.
func problem() -> String:
	for i in 4:
		if parts[i].text == "":
			return "Enter all four numbers of the IP address"
		if int(parts[i].text) > 255:
			return "Each IP number is 0 to 255"
	if parts[4].text == "":
		return "Enter the port, for example 9080"
	var port := int(parts[4].text)
	if port < 1 or port > 65535:
		return "The port is a number from 1 to 65535"
	return ""


## Shows the first problem and marks the boxes at fault; true when valid.
func validate() -> bool:
	var why := problem()
	_error.text = why
	_error.visible = why != ""
	for i in 5:
		var bad := parts[i].text == "" or (int(parts[i].text) > 255 if i < 4 else (int(parts[i].text) < 1 or int(parts[i].text) > 65535))
		parts[i].modulate = Color(1, 0.72, 0.68) if why != "" and bad else Color.WHITE
	return why == ""


func focus_first_problem() -> void:
	for i in 5:
		var t := parts[i].text
		if t == "" or (i < 4 and int(t) > 255) or (i == 4 and (int(t) < 1 or int(t) > 65535)):
			parts[i].grab_focus()
			return


func _on_text(text: String, i: int) -> void:
	# A pasted full address fills every box.
	if text.count(".") == 3:
		set_address(text.strip_edges())
		parts[4].grab_focus()
		_after_change()
		return
	var jump := text.ends_with(".") or text.ends_with(":")
	var digits := ""
	for ch in text:
		if ch >= "0" and ch <= "9":
			digits += ch
	var most := 3 if i < 4 else 5
	digits = digits.substr(0, most)
	if digits != text:
		var caret := parts[i].caret_column
		parts[i].text = digits
		parts[i].caret_column = mini(caret, digits.length())
	if jump and digits != "":
		_advance(i, false)
	elif i < 4 and digits.length() == most:
		_advance(i, false)
	_after_change()


func _after_change() -> void:
	if _error.visible:
		validate()
	changed.emit()


func _on_key(event: InputEvent, i: int) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE and parts[i].text == "" and i > 0:
		parts[i - 1].grab_focus()
		parts[i - 1].caret_column = parts[i - 1].text.length()
		parts[i].accept_event()


func _advance(i: int, submit: bool) -> void:
	if i < 4:
		parts[i + 1].grab_focus()
		parts[i + 1].select_all()
	elif submit:
		submitted.emit()
