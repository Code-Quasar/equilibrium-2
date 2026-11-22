class_name SortingGame
extends EmergencyGame
## SORTING OVERLOAD · precision slicing. The server's pattern director throws waste
## across the sorting line; swipe through the recyclables and keep the blade off
## contaminated items and hazards. Hits are found segment by segment, so a fast swipe
## never skips an object; each counts once. Each material breaks its own way.

const CLASS := {"plastic_bottle": 0, "aluminum_can": 0, "cardboard": 0, "glass_bottle": 0,
	"greasy_packaging": 1, "battery": 2, "medical_waste": 2}
const MATERIAL := {"plastic_bottle": "plastic", "aluminum_can": "metal", "cardboard": "paper", "glass_bottle": "glass"}
const FIELD := 1000.0
const LAUNCH_Y := 1080.0
const TOP := 0.11                    # share of the height kept for the legend strip
const MAX_BITS := 220

var _trail: Array = []               # [point, age] of the current swipe
var _last := Vector2(-1, -1)
var _swiping := false
var _stroke_hits := 0                # objects cut by the current swipe
var _halves: Array = []
var _bits: Array = []                # fragments: {at, v, rot, spin, life, kind, color, size}
var _marks: Array = []               # red crosses over hazards hit
var _shake := 0.0
var _beam := 0.0
var cut := {}                        # tests only: ids cut locally


func _objects() -> Array:
	return ev.get("challenge", {}).get("objects", [])


## Field units (1000 x 1000) to this control and back; the legend strip is kept free.
func _to_screen(v: Vector2) -> Vector2:
	var top := size.y * TOP
	return Vector2(v.x / FIELD * size.x, top + v.y / FIELD * (size.y - top))


func _to_field(v: Vector2) -> Vector2:
	var top := size.y * TOP
	return Vector2(v.x / maxf(size.x, 1.0) * FIELD, (v.y - top) / maxf(size.y - top, 1.0) * FIELD)


## The same parabola the server uses.
static func position(o: Dictionary, ms: int) -> Variant:
	var t := ms - int(o.launch_ms)
	if t < 0 or t > int(o.flight_ms):
		return null
	var u := float(t) / float(o.flight_ms)
	return Vector2(float(o.x0) + float(int(o.x1) - int(o.x0)) * u, LAUNCH_Y - 4.0 * (LAUNCH_Y - float(o.apex)) * u * (1.0 - u))


func _radius() -> float:
	return float(ev.get("pacing", {}).get("hit_radius", 70))


func tick(delta: float) -> void:
	_beam += delta * (1.0 if now_ms() < int(ev.get("pacing", {}).get("phase_c_ms", 16000)) else 2.6)
	for p in _trail:
		p[1] += delta
	_trail = _trail.filter(func(p): return p[1] < 0.16)
	for h in _halves:
		h.life -= delta
		h.at += h.v * delta
		h.v.y += 900.0 * delta
		h.rot += h.spin * delta
	_halves = _halves.filter(func(h): return h.life > 0.0)
	for b in _bits:
		b.life -= delta
		b.at += b.v * delta
		b.v.y += (260.0 if b.kind == "paper" else 760.0) * delta
		b.v.x *= 0.985
		b.rot += b.spin * delta
	_bits = _bits.filter(func(b): return b.life > 0.0)
	for m in _marks:
		m.life -= delta
	_marks = _marks.filter(func(m): return m.life > 0.0)
	_shake = maxf(0.0, _shake - delta * 2.5)


func _gui_input(e: InputEvent) -> void:
	if not active():
		_swiping = false
		return
	if e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		_swiping = e.pressed
		_last = e.position
		if e.pressed:
			_trail = [[e.position, 0.0]]
			_stroke_hits = 0
		accept_event()
	elif (e is InputEventScreenDrag or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT)) and _swiping:
		var p: Vector2 = e.position
		if p.distance_to(_last) > 2.0:
			if p.distance_to(_last) > 60.0:
				sound("swipe")
			_cut(_last, p)
			_last = p
			_trail.append([p, 0.0])
		accept_event()


## Every object this stretch of the swipe crosses now is cut (once).
func _cut(a: Vector2, z: Vector2) -> void:
	var ms := now_ms()
	var fa := _to_field(a).clamp(Vector2.ZERO, Vector2(FIELD, FIELD))
	var fz := _to_field(z).clamp(Vector2.ZERO, Vector2(FIELD, FIELD))
	for o in _objects():
		var id := int(o.id)
		if done.has(id):
			continue
		var at: Variant = position(o, ms)
		if at == null:
			continue
		if Geometry2D.get_closest_point_to_segment(at, fa, fz).distance_to(at) > _radius():
			continue
		done[id] = true
		cut[id] = true
		var cls: int = CLASS.get(str(o.kind), 1)
		var outcome := "correct" if cls == 0 else ("incorrect" if cls == 1 else "hazard")
		send("emergency_slice", {"item": id, "t_ms": ms, "x1": int(fa.x), "y1": int(fa.y), "x2": int(fz.x), "y2": int(fz.y)}, outcome)
		_effects(o, _to_screen(at), (z - a).normalized(), cls)


## What a cut looks like and sounds like, by material; hazards never celebrate.
func _effects(o: Dictionary, sp: Vector2, dir: Vector2, cls: int) -> void:
	var rules: Dictionary = ev.get("scoring", {})
	var kind := str(o.kind)
	var normal := Vector2(-dir.y, dir.x)
	if cls != 0:
		pop(sp, "−%d" % int(rules.get("hazard" if cls == 2 else "incorrect", 15)), false)
		_marks.append({"at": sp, "life": 0.7})
		flash(Color("#ff3b30"))
		_shake = 1.0
		_stroke_hits = 0
		sound("hazard" if cls == 2 else "wrong")
		UI.haptic(60)
		return
	_stroke_hits += 1
	var material: String = MATERIAL.get(kind, "plastic")
	if material != "glass":
		for side in [-1.0, 1.0]:
			_halves.append({"kind": kind, "at": sp + normal * side * 8.0, "v": normal * side * 240.0 + dir * 140.0 + Vector2(0, -140),
				"rot": 0.0, "spin": side * 6.0, "life": 0.65})
	match material:
		"plastic":
			_burst(sp, "plastic", Color("#8fd3ff"), 10, 4.0, 260.0)
			sound("slice_plastic")
		"metal":
			_burst(sp, "metal", Color("#d7dee3"), 9, 6.0, 330.0)
			_burst(sp, "glint", Color.WHITE, 1, 26.0, 0.0)
			sound("slice_metal")
		"paper":
			_burst(sp, "paper", Color("#c98d4c"), 12, 6.0, 200.0)
			sound("slice_paper")
		"glass":
			_burst(sp, "glass", Color("#7fe0a8"), 16, 7.0, 360.0)
			_burst(sp, "glint", Color("#e9fff4"), 2, 22.0, 60.0)
			sound("slice_glass")
	pop(sp, "+%d" % int(rules.get("correct", 10)), true)
	UI.haptic(12)
	if _stroke_hits >= 2:
		pop(sp + Vector2(0, -44), "DOUBLE!" if _stroke_hits == 2 else ("TRIPLE!" if _stroke_hits == 3 else "×%d!" % _stroke_hits), true)
		sound("multi")


func _burst(at: Vector2, kind: String, color: Color, n: int, size: float, speed: float) -> void:
	for i in n:
		if _bits.size() >= MAX_BITS:
			_bits.pop_front()
		var a := randf() * TAU
		_bits.append({"at": at, "v": Vector2(cos(a), sin(a)) * randf_range(speed * 0.4, speed) + Vector2(0, -80), "rot": randf() * TAU,
			"spin": randf_range(-9.0, 9.0), "life": randf_range(0.45, 0.8) if kind != "glint" else 0.35, "kind": kind, "color": color,
			"size": size * randf_range(0.7, 1.2)})


func _draw() -> void:
	var w := size.x
	var h := size.y
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 6.0
	draw_set_transform(off)
	# The sorting hall: deep gradient, sweeping light beams, the line below.
	var bands := 10
	for i in bands:
		draw_rect(Rect2(0, h * i / bands, w, h / bands + 1), Color("#1a1440").lerp(Color("#0b1622"), float(i) / bands))
	for k in 3:
		var x := fmod(_beam * 90.0 + k * w * 0.45, w * 1.4) - w * 0.2
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 70, 0), Vector2(x - 160, h), Vector2(x - 230, h)]), Color(0.6, 0.5, 1.0, 0.05))
	var finale := now_ms() >= int(ev.get("pacing", {}).get("phase_c_ms", 16000)) and active()
	if finale:
		draw_rect(Rect2(0, 0, w, h), Color(1, 0.75, 0.2, 0.05 + 0.03 * sin(_beam * 4.0)))
	draw_rect(Rect2(0, h - 22, w, 22), Color("#24203d"))
	var c := fmod(_beam * 60.0, 30.0)
	var xx := -30.0 + c
	while xx < w:
		draw_colored_polygon(PackedVector2Array([Vector2(xx, h - 18), Vector2(xx + 10, h - 11), Vector2(xx, h - 4), Vector2(xx + 6, h - 11)]), Color(1, 0.8, 0.3, 0.35))
		xx += 30.0
	# Legend strip: what to cut, what to avoid.
	var top := h * TOP
	draw_rect(Rect2(0, 0, w, top), Color(0, 0, 0, 0.28))
	var font := UI.font(500)
	var fs := int(clampf(top * 0.36, 11.0, 15.0))
	draw_string(font, Vector2(12, top * 0.66), "SLICE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#69e0b4"))
	var ic := top * 0.8
	var px := 12.0 + font.get_string_size("SLICE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + ic * 0.7
	for k in ["plastic_bottle", "aluminum_can", "cardboard", "glass_bottle"]:
		WasteArt.draw(self, k, Vector2(px, top * 0.5), ic, 0.0)
		px += ic * 1.1
	px += ic * 0.6
	draw_string(font, Vector2(px, top * 0.66), "AVOID", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ff8a7a"))
	px += font.get_string_size("AVOID", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + ic * 0.7
	for k in ["greasy_packaging", "battery", "medical_waste"]:
		WasteArt.draw(self, k, Vector2(px, top * 0.5), ic, 0.0)
		px += ic * 1.1
	# Objects in flight.
	var ms := now_ms()
	var s := clampf(minf(w, h) * 0.16, 56.0, 108.0)
	for o in _objects():
		if done.has(int(o.id)):
			continue
		var at: Variant = position(o, ms)
		if at == null:
			continue
		var sp := _to_screen(at)
		var cls: int = CLASS.get(str(o.kind), 1)
		if cls == 2:
			var k2 := 0.5 + 0.5 * sin(float(ms) / 90.0)
			draw_circle(sp, s * 0.62, Color(1, 0.2, 0.15, 0.12 + 0.1 * k2))
			draw_arc(sp, s * 0.62, 0, TAU, 32, Color(1, 0.3, 0.2, 0.55 + 0.35 * k2), 4.0, true)
		elif cls == 1:
			draw_arc(sp, s * 0.6, 0, TAU, 32, Color(1, 0.7, 0.2, 0.5), 3.0, true)
		var spin := float(int(o.get("spin", 1))) * 0.9 + (1.0 if int(o.id) % 2 == 0 else -1.0)
		WasteArt.draw(self, str(o.kind), sp, s, float(ms - int(o.launch_ms)) / 1000.0 * spin)
	for hv in _halves:
		WasteArt.draw(self, hv.kind, hv.at, s * 0.82, hv.rot, clampf(hv.life * 1.7, 0.0, 1.0))
	# Fragments by material.
	for b in _bits:
		var a := clampf(b.life * 2.0, 0.0, 1.0)
		var col: Color = Color(b.color, a)
		match b.kind:
			"metal", "glass":
				var r: float = b.size
				var pts := PackedVector2Array()
				for k3 in 3:
					var ang: float = b.rot + TAU * k3 / 3.0 + (0.6 if k3 == 1 else 0.0)
					pts.append(b.at + Vector2(cos(ang), sin(ang)) * r * (1.4 if k3 == 0 else 0.7))
				draw_colored_polygon(pts, col)
			"paper":
				draw_set_transform(b.at + off, b.rot)
				draw_rect(Rect2(-b.size / 2.0, -b.size / 3.0, b.size, b.size * 0.66), col)
				draw_set_transform(off)
			"glint":
				var r2: float = b.size * (1.0 + (0.35 - b.life))
				draw_line(b.at - Vector2(r2, 0), b.at + Vector2(r2, 0), col, 3.0)
				draw_line(b.at - Vector2(0, r2), b.at + Vector2(0, r2), col, 3.0)
			_:
				draw_circle(b.at, b.size * 0.6, col)
	for m in _marks:
		var r3 := s * 0.45
		var k4: float = clampf(m.life * 1.6, 0.0, 1.0)
		draw_line(m.at - Vector2(r3, r3), m.at + Vector2(r3, r3), Color(1, 0.25, 0.2, k4), 9.0)
		draw_line(m.at - Vector2(r3, -r3), m.at + Vector2(r3, -r3), Color(1, 0.25, 0.2, k4), 9.0)
	# The blade's trail: a bright core over a soft glow, thinning with age.
	if _trail.size() >= 2:
		for i in range(1, _trail.size()):
			var a2: Array = _trail[i - 1]
			var z: Array = _trail[i]
			var k5 := 1.0 - float(z[1]) / 0.16
			draw_line(a2[0], z[0], Color(0.6, 0.95, 1.0, 0.32 * k5), 18.0 * k5 + 2.0, true)
			draw_line(a2[0], z[0], Color(1, 1, 1, 0.95 * k5), 5.0 * k5 + 1.0, true)
	draw_set_transform(Vector2.ZERO)
