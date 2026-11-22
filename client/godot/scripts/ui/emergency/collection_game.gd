class_name CollectionGame
extends EmergencyGame
## COLLECTION CRISIS · fast waste routing. Waste rides a conveyor through the
## collection hall from left to right; drag each item into its bin (or tap it, then
## the bin) before it falls off the end. The belt speeds up in three phases. Items
## are drawn each frame from the server's challenge and the event clock: nothing is
## pooled or kept between rounds, so no state can go stale.

const CATEGORY := {"plastic_bottle": 0, "aluminum_can": 0, "cardboard": 0, "glass_bottle": 0,
	"banana_peel": 1, "apple_core": 1, "food_scraps": 1,
	"dirty_tissue": 2, "greasy_packaging": 2, "mixed_waste": 2}
const BINS := [
	["RECYCLABLES", Color("#2f7fd6"), "bottles · cans · clean cardboard · glass", "plastic_bottle"],
	["ORGANICS", Color("#3aa65a"), "peels · cores · food scraps", "banana_peel"],
	["RESIDUAL", Color("#5b6670"), "tissues · greasy packaging · mixed", "dirty_tissue"],
]
const EXIT_ZONE := 0.82                    # share of the belt after which an item is about to fall

var _held := -1                            # item being dragged, or tapped and waiting for a bin
var _held_at := Vector2.ZERO
var _dragging := false
var _press_at := Vector2.ZERO
var _bin_bump := [0.0, 0.0, 0.0]
var _bin_shake := [0.0, 0.0, 0.0]
var _bin_glow := [0.0, 0.0, 0.0]
var _flying := []                          # routed items flying into a bin: {kind, from, to, t, right}
var _warned := {}                          # items that entered the exit zone (one tick each)
var _belt_phase := 0.0
var _dust := []                            # a few motes in the light
var drawn := {}                            # tests only: ids drawn on the belt at least once
var routed_ok := 0                         # tests only: items routed into the right bin
var feedback := 0                          # tests only: feedback effects started


func _ready() -> void:
	for i in 14:
		_dust.append(Vector3(randf(), randf() * 0.45, randf_range(0.2, 1.0)))


func _items() -> Array:
	return ev.get("challenge", {}).get("items", [])


func _belt() -> Rect2:
	return Rect2(0, size.y * 0.13, size.x, size.y * 0.27)


func _bin_rect(i: int) -> Rect2:
	var w := size.x / 3.0
	var top := size.y * 0.53
	return Rect2(w * i + 12, top, w - 24, size.y - top - 10)


func _item_size() -> float:
	return clampf(size.y * 0.16, 52.0, 92.0)


## Where an item is on the belt now, or null when it is not on the belt.
func _item_pos(item: Dictionary, ms: int) -> Variant:
	var u := float(ms - int(item.spawn_ms)) / float(item.travel_ms)
	if u < 0.0 or u > 1.0:
		return null
	var b := _belt()
	var lane := 0.36 if int(item.id) % 2 == 0 else 0.62
	return Vector2(b.position.x - 46 + (b.size.x + 92) * u, b.position.y + b.size.y * lane)


func _progress(item: Dictionary, ms: int) -> float:
	return float(ms - int(item.spawn_ms)) / float(item.travel_ms)


func tick(delta: float) -> void:
	var speed := 1.0 + float(maxi(0, now_ms())) / 9000.0
	_belt_phase = fmod(_belt_phase + delta * speed * 120.0, 48.0)
	for i in 3:
		_bin_bump[i] = maxf(0.0, _bin_bump[i] - delta * 3.0)
		_bin_shake[i] = maxf(0.0, _bin_shake[i] - delta * 3.5)
		_bin_glow[i] = maxf(0.0, _bin_glow[i] - delta * 1.8)
	for f in _flying:
		f.t += delta / 0.28
	_flying = _flying.filter(func(f): return f.t < 1.0)
	for d in _dust:
		d.x = fmod(d.x + delta * 0.01 * d.z, 1.0)
	var ms := now_ms()
	# An item entering the exit zone ticks once; a held item that falls off is lost.
	for item in _items():
		var id := int(item.id)
		if done.has(id):
			continue
		var u := _progress(item, ms)
		if u >= EXIT_ZONE and u <= 1.0 and not _warned.has(id) and active():
			_warned[id] = true
			sound("exit_warn")
	if _held >= 0 and ms > int(_items()[_held].spawn_ms) + int(_items()[_held].travel_ms):
		_held = -1
		_dragging = false


func _gui_input(e: InputEvent) -> void:
	if not active():
		return
	var pos: Vector2
	var pressed := false
	var released := false
	var moved := false
	if e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventScreenDrag or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		pos = e.position
		moved = true
	else:
		return
	accept_event()
	if pressed:
		_press_at = pos
		var hit := _item_at(pos)
		if hit >= 0:
			_held = hit
			_held_at = pos
			_dragging = true
			sound("pickup")
			UI.haptic(10)
		elif _held >= 0:
			var bin := _bin_at(pos)
			if bin >= 0:
				route(_held, bin)
	elif moved and _dragging and _held >= 0:
		_held_at = pos
	elif released and _dragging:
		_dragging = false
		var bin := _bin_at(pos)
		if bin >= 0 and _held >= 0 and pos.distance_to(_press_at) > 12.0:
			route(_held, bin)
		# A tap without a drag keeps the item selected: tap a bin next.


func _item_at(pos: Vector2) -> int:
	var best := -1
	var best_d := _item_size() * 0.8
	for item in _items():
		if done.has(int(item.id)):
			continue
		var p: Variant = _item_pos(item, now_ms())
		if p != null and (p as Vector2).distance_to(pos) < best_d:
			best_d = (p as Vector2).distance_to(pos)
			best = int(item.id)
	return best


func _bin_at(pos: Vector2) -> int:
	for i in 3:
		if _bin_rect(i).grow(12).has_point(pos):
			return i
	return -1


## Routes an item into a bin: shown at once, scored by the server.
func route(id: int, bin: int) -> void:
	var item: Dictionary = _items()[id]
	var ms := now_ms()
	var on_belt: Variant = _item_pos(item, ms)
	var from: Vector2 = _held_at if (_held == id and _dragging) or on_belt == null else on_belt
	_held = -1
	_dragging = false
	if done.has(id) or ms > int(item.spawn_ms) + int(item.travel_ms):
		return
	done[id] = true
	var right: bool = CATEGORY.get(str(item.kind), -1) == bin
	var r := _bin_rect(bin)
	_flying.append({"kind": str(item.kind), "from": from, "to": Vector2(r.get_center().x, r.position.y + 18), "t": 0.0, "right": right})
	send("emergency_route", {"item": id, "bin": bin, "t_ms": ms}, "correct" if right else "incorrect")
	var rules: Dictionary = ev.get("scoring", {})
	pop(Vector2(r.get_center().x, r.position.y - 10), ("+%d" % int(rules.get("correct", 10))) if right else ("−%d" % int(rules.get("incorrect", 10))), right)
	feedback += 1
	if right:
		routed_ok += 1
		_bin_bump[bin] = 1.0
		_bin_glow[bin] = 1.0
		sparks(Vector2(r.get_center().x, r.position.y + 10), (BINS[bin][1] as Color).lightened(0.35), 16)
		sound("bin")
		sound("right")
		UI.haptic(15)
	else:
		_bin_shake[bin] = 1.0
		sound("wrong")
		UI.haptic(40)


func _draw() -> void:
	var w := size.x
	var h := size.y
	# The hall: back wall with depth, pipes and two hanging lights.
	draw_rect(Rect2(0, 0, w, h), Color("#17222a"))
	draw_rect(Rect2(0, 0, w, h * 0.48), Color("#1f2d36"))
	for i in 6:
		draw_rect(Rect2(w * (0.08 + i * 0.17), 0, 10, h * 0.48), Color("#1a262e"))
	draw_rect(Rect2(0, h * 0.04, w, 8), Color("#2b3c47"))
	draw_rect(Rect2(0, h * 0.075, w, 4), Color("#33485a"))
	for lx in [w * 0.25, w * 0.72]:
		draw_colored_polygon(PackedVector2Array([Vector2(lx - 14, 0), Vector2(lx + 14, 0), Vector2(lx + 120, h * 0.48), Vector2(lx - 120, h * 0.48)]), Color(1, 0.93, 0.7, 0.045))
		draw_rect(Rect2(lx - 16, 0, 32, 8), Color("#f2d27a"))
	for d in _dust:
		draw_circle(Vector2(d.x * w, h * 0.06 + d.y * h), 1.6, Color(1, 0.95, 0.8, 0.12 * d.z))
	var b := _belt()
	# Support legs and frame under the belt.
	for i in 7:
		draw_rect(Rect2(w * (0.04 + i * 0.155), b.end.y + 8, 10, h * 0.1), Color("#2b3740"))
	draw_rect(Rect2(0, b.position.y - 14, w, b.size.y + 28), Color("#0e1519"))
	# The belt: moving slats, rollers at each end, side rails with hazard stripes.
	draw_rect(b, Color("#37434c"))
	var x := -48.0 + _belt_phase
	while x < w + 48:
		draw_rect(Rect2(x, b.position.y, 22, b.size.y), Color("#3f4c56"))
		draw_line(Vector2(x, b.position.y), Vector2(x, b.end.y), Color(0, 0, 0, 0.18), 2)
		x += 48.0
	# The exit zone: a calm amber wash over the last stretch of the belt.
	var zx := b.position.x - 46 + (b.size.x + 92) * EXIT_ZONE
	draw_rect(Rect2(zx, b.position.y, w - zx, b.size.y), Color(1, 0.7, 0.15, 0.12))
	draw_line(Vector2(zx, b.position.y), Vector2(zx, b.end.y), Color(1, 0.75, 0.25, 0.5), 2)
	for yy in [b.position.y - 8, b.end.y + 2]:
		draw_rect(Rect2(0, yy, w, 6), Color("#f2b33d"))
		var s := -26.0 + fmod(_belt_phase, 26.0)
		while s < w:
			draw_colored_polygon(PackedVector2Array([Vector2(s, yy), Vector2(s + 12, yy), Vector2(s + 6, yy + 6), Vector2(s - 6, yy + 6)]), Color("#17222a"))
			s += 26.0
	# Rollers under the belt's lower edge, turning with it.
	var a := _belt_phase / 48.0 * TAU
	var rx := 24.0
	while rx < w:
		var rc := Vector2(rx, b.end.y + 13)
		draw_circle(rc, 7.0, Color("#56646e"))
		draw_line(rc, rc + Vector2(cos(a), sin(a)) * 6.0, Color("#9aa8b2"), 2)
		rx += 48.0
	# Bins.
	var font := UI.font(500)
	var small := UI.font(400)
	for i in 3:
		var r := _bin_rect(i)
		var bump: float = sin(_bin_bump[i] * PI) * 8.0
		var shake: float = sin(_bin_shake[i] * 40.0) * 7.0 * _bin_shake[i]
		var body := Rect2(r.position + Vector2(shake, -bump), r.size)
		var col: Color = BINS[i][1]
		var hot := _held >= 0 and _dragging and _bin_at(_held_at) == i
		draw_rect(Rect2(body.position + Vector2(5, 8), body.size), Color(0, 0, 0, 0.3))
		draw_rect(body, col.darkened(0.2))
		draw_rect(Rect2(body.position + Vector2(8, 26), body.size - Vector2(16, 34)), col.darkened(0.05))
		# The open mouth of the bin, with a lip.
		draw_rect(Rect2(body.position + Vector2(-6, 0), Vector2(body.size.x + 12, 18)), col.lightened(0.15))
		draw_rect(Rect2(body.position + Vector2(4, 4), Vector2(body.size.x - 8, 10)), Color(0.04, 0.06, 0.08, 0.7))
		if hot:
			draw_rect(Rect2(body.position + Vector2(-6, -4), Vector2(body.size.x + 12, body.size.y + 4)), Color(1, 1, 1, 0.16))
			draw_rect(Rect2(body.position + Vector2(-6, -4), Vector2(body.size.x + 12, 4)), Color.WHITE)
		if _bin_glow[i] > 0.0:
			draw_rect(body, Color(0.25, 1.0, 0.6, 0.28 * _bin_glow[i]))
		if _bin_shake[i] > 0.0:
			draw_rect(body, Color(1.0, 0.25, 0.2, 0.32 * _bin_shake[i]))
		var title: String = BINS[i][0]
		var fs := int(clampf(body.size.x / 11.0, 14.0, 21.0))
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(body.get_center().x - tw / 2.0, body.position.y + 48), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var hint: String = BINS[i][2]
		var hs := int(clampf(body.size.x / 23.0, 10.0, 13.0))
		var hw := small.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		draw_string(small, Vector2(body.get_center().x - hw / 2.0, body.position.y + 68), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(1, 1, 1, 0.78))
		WasteArt.draw(self, BINS[i][3], body.get_center() + Vector2(0, body.size.y * 0.2), minf(body.size.y * 0.3, 56.0), 0.0, 0.42)
	# Items on the belt, each with its shadow; amber ring in the exit zone.
	var ms := now_ms()
	var s2 := _item_size()
	for item in _items():
		var id := int(item.id)
		if done.has(id) or (id == _held and _dragging):
			continue
		var p: Variant = _item_pos(item, ms)
		if p == null:
			continue
		drawn[id] = true
		var u := _progress(item, ms)
		draw_circle(p + Vector2(4, s2 * 0.42), s2 * 0.34, Color(0, 0, 0, 0.22))
		if u >= EXIT_ZONE:
			draw_arc(p, s2 * 0.6, 0, TAU, 28, Color(1, 0.72, 0.2, 0.55 + 0.25 * sin(float(ms) / 120.0)), 3.0, true)
		if id == _held:
			draw_arc(p, s2 * 0.62, 0, TAU, 28, Color(1, 0.86, 0.3, 0.9), 4.0, true)
		WasteArt.draw(self, str(item.kind), p, s2, sin(float(ms) / 160.0 + id) * 0.06)
	# Routed items dropping into their bins.
	for f in _flying:
		var k: float = f.t
		var at: Vector2 = (f.from as Vector2).lerp(f.to, k) + Vector2(0, -60.0 * sin(k * PI))
		WasteArt.draw(self, f.kind, at, s2 * (1.0 - 0.55 * k), k * 3.0, 1.0 - 0.6 * k)
	# The held item: lifted, a little larger, with its shadow on the floor.
	if _held >= 0 and _dragging:
		draw_circle(_held_at + Vector2(10, s2 * 0.7), s2 * 0.4, Color(0, 0, 0, 0.28))
		WasteArt.draw(self, str(_items()[_held].kind), _held_at + Vector2(0, -12), s2 * 1.18, 0.0)
