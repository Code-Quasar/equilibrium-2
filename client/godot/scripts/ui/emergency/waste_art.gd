class_name WasteArt
extends RefCounted
## The waste items of the ECO EMERGENCIES, drawn in code as small stickers: a
## white outline, flat colours and one highlight, so they read at a glance on a
## phone and match the game's flat, friendly look. No external artwork.

const NAMES := {
	"plastic_bottle": "Plastic bottle", "aluminum_can": "Aluminium can", "cardboard": "Clean cardboard",
	"glass_bottle": "Glass bottle", "banana_peel": "Banana peel", "apple_core": "Apple core",
	"food_scraps": "Food scraps", "dirty_tissue": "Used tissue", "greasy_packaging": "Greasy packaging",
	"mixed_waste": "Mixed waste", "battery": "Battery", "medical_waste": "Medical waste",
}
const OUTLINE := Color(1, 1, 1, 0.95)
const INK := Color("#22303a")


## Draws an item centred at p, about s pixels tall, turned by rot radians.
static func draw(ci: CanvasItem, kind: String, p: Vector2, s: float, rot := 0.0, alpha := 1.0) -> void:
	ci.draw_set_transform(p, rot, Vector2(s / 100.0, s / 100.0))
	var k := func(c: Color) -> Color: return Color(c, c.a * alpha)
	match kind:
		"plastic_bottle":
			_shape(ci, [Vector2(-18, -20), Vector2(-10, -34), Vector2(-10, -44), Vector2(10, -44), Vector2(10, -34), Vector2(18, -20),
				Vector2(20, 40), Vector2(14, 46), Vector2(-14, 46), Vector2(-20, 40)], k.call(Color("#8fd3ff")), alpha)
			ci.draw_rect(Rect2(-11, -52, 22, 10), k.call(Color("#2f7fd6")))
			ci.draw_rect(Rect2(-19, -2, 38, 18), k.call(Color("#ffffff")))
			ci.draw_rect(Rect2(-19, 2, 38, 8), k.call(Color("#2f7fd6")))
			ci.draw_line(Vector2(-9, -14), Vector2(-11, 34), k.call(Color(1, 1, 1, 0.7)), 4)
		"aluminum_can":
			_shape(ci, [Vector2(-24, -38), Vector2(24, -38), Vector2(24, 38), Vector2(-24, 38)], k.call(Color("#c9d2d9")), alpha)
			ci.draw_rect(Rect2(-24, -16, 48, 30), k.call(Color("#e8504a")))
			ci.draw_rect(Rect2(-20, -44, 40, 8), k.call(Color("#9aa6ad")))
			ci.draw_rect(Rect2(-20, 36, 40, 8), k.call(Color("#9aa6ad")))
			ci.draw_line(Vector2(-14, -30), Vector2(-14, 30), k.call(Color(1, 1, 1, 0.75)), 5)
		"cardboard":
			_shape(ci, [Vector2(-40, -22), Vector2(40, -22), Vector2(40, 34), Vector2(-40, 34)], k.call(Color("#c98d4c")), alpha)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-40, -22), Vector2(-28, -40), Vector2(0, -40), Vector2(0, -22)]), k.call(Color("#b07436")))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(40, -22), Vector2(28, -40), Vector2(0, -40), Vector2(0, -22)]), k.call(Color("#dba567")))
			ci.draw_rect(Rect2(-6, -22, 12, 56), k.call(Color("#e9cfa0")))
			ci.draw_line(Vector2(-30, 22), Vector2(-14, 22), k.call(INK), 3)
		"glass_bottle":
			_shape(ci, [Vector2(-8, -48), Vector2(8, -48), Vector2(8, -24), Vector2(20, -8), Vector2(20, 44), Vector2(-20, 44), Vector2(-20, -8), Vector2(-8, -24)], k.call(Color("#3aa86b")), alpha)
			ci.draw_rect(Rect2(-9, -54, 18, 8), k.call(Color("#c9a227")))
			ci.draw_rect(Rect2(-16, 6, 32, 20), k.call(Color("#f3ead2")))
			ci.draw_line(Vector2(-11, -4), Vector2(-11, 38), k.call(Color(1, 1, 1, 0.55)), 4)
		"banana_peel":
			var peel := [Vector2(-38, 10), Vector2(-20, -30), Vector2(0, -40), Vector2(8, -34), Vector2(-6, -18), Vector2(4, 0),
				Vector2(34, -22), Vector2(40, -14), Vector2(14, 18), Vector2(30, 40), Vector2(20, 44), Vector2(-4, 24), Vector2(-26, 38), Vector2(-34, 30)]
			_shape(ci, peel, k.call(Color("#f6d33c")), alpha)
			ci.draw_circle(Vector2(-4, 28), 7, k.call(Color("#8a5a22")))
			ci.draw_circle(Vector2(36, -18), 4, k.call(Color("#6b4219")))
			ci.draw_line(Vector2(-22, 4), Vector2(-6, -24), k.call(Color("#d9a91c")), 3)
		"apple_core":
			_shape(ci, [Vector2(-26, -40), Vector2(26, -40), Vector2(30, -26), Vector2(12, -14), Vector2(10, 14), Vector2(30, 26),
				Vector2(26, 40), Vector2(-26, 40), Vector2(-30, 26), Vector2(-10, 14), Vector2(-12, -14), Vector2(-30, -26)], k.call(Color("#f5e6b8")), alpha)
			ci.draw_rect(Rect2(-26, -40, 52, 12), k.call(Color("#d9443b")))
			ci.draw_rect(Rect2(-26, 28, 52, 12), k.call(Color("#d9443b")))
			ci.draw_line(Vector2(0, -40), Vector2(4, -54), k.call(Color("#6b4219")), 4)
			ci.draw_circle(Vector2(-3, -2), 3, k.call(INK))
			ci.draw_circle(Vector2(4, 6), 3, k.call(INK))
		"food_scraps":
			_shape(ci, [Vector2(-40, 6), Vector2(-30, -16), Vector2(-6, -26), Vector2(20, -22), Vector2(40, -4), Vector2(36, 20), Vector2(10, 30), Vector2(-24, 28)], k.call(Color("#9c6b3c")), alpha)
			ci.draw_circle(Vector2(-14, -6), 10, k.call(Color("#6fb24a")))
			ci.draw_circle(Vector2(14, -8), 9, k.call(Color("#e88a3a")))
			ci.draw_circle(Vector2(2, 12), 8, k.call(Color("#d9c24a")))
		"dirty_tissue":
			_shape(ci, [Vector2(-34, -10), Vector2(-20, -32), Vector2(4, -26), Vector2(26, -34), Vector2(36, -8), Vector2(28, 22), Vector2(6, 34), Vector2(-22, 28), Vector2(-38, 12)], k.call(Color("#f4f1ea")), alpha)
			ci.draw_line(Vector2(-18, -14), Vector2(8, 4), k.call(Color("#c8c2b4")), 3)
			ci.draw_line(Vector2(10, -18), Vector2(-6, 18), k.call(Color("#c8c2b4")), 3)
			ci.draw_circle(Vector2(14, 14), 6, k.call(Color("#b9a98a")))
		"greasy_packaging":
			_shape(ci, [Vector2(-42, -28), Vector2(42, -28), Vector2(42, 30), Vector2(-42, 30)], k.call(Color("#e8c48c")), alpha)
			ci.draw_rect(Rect2(-42, -28, 84, 10), k.call(Color("#cf9f5f")))
			ci.draw_circle(Vector2(-16, 6), 11, k.call(Color("#a8682a", 0.85)))
			ci.draw_circle(Vector2(18, 12), 8, k.call(Color("#a8682a", 0.8)))
			ci.draw_circle(Vector2(8, -6), 5, k.call(Color("#a8682a", 0.7)))
		"mixed_waste":
			_shape(ci, [Vector2(-30, -16), Vector2(-8, -30), Vector2(8, -30), Vector2(30, -16), Vector2(36, 24), Vector2(22, 40), Vector2(-22, 40), Vector2(-36, 24)], k.call(Color("#55606a")), alpha)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-8, -30), Vector2(0, -44), Vector2(8, -30)]), k.call(Color("#3d464e")))
			ci.draw_line(Vector2(-18, 0), Vector2(18, 4), k.call(Color("#7a8792")), 3)
		"battery":
			_shape(ci, [Vector2(-18, -38), Vector2(18, -38), Vector2(18, 42), Vector2(-18, 42)], k.call(Color("#2b2f36")), alpha)
			ci.draw_rect(Rect2(-18, -38, 36, 22), k.call(Color("#d98a2b")))
			ci.draw_rect(Rect2(-7, -46, 14, 8), k.call(Color("#9aa6ad")))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(4, -6), Vector2(-8, 14), Vector2(0, 14), Vector2(-4, 32), Vector2(9, 8), Vector2(1, 8)]), k.call(Color("#ffd23c")))
		"medical_waste":
			_shape(ci, [Vector2(-44, -10), Vector2(30, -10), Vector2(30, 10), Vector2(-44, 10)], k.call(Color("#e6f2fb")), alpha)
			ci.draw_rect(Rect2(-30, -6, 40, 12), k.call(Color("#e8504a", 0.8)))
			ci.draw_line(Vector2(30, 0), Vector2(52, 0), k.call(Color("#9aa6ad")), 3)
			ci.draw_rect(Rect2(-52, -14, 8, 28), k.call(Color("#9aa6ad")))
			ci.draw_rect(Rect2(-12, -34, 24, 24), k.call(Color("#ffffff")))
			ci.draw_rect(Rect2(-4, -30, 8, 16), k.call(Color("#d9302a")))
			ci.draw_rect(Rect2(-8, -26, 16, 8), k.call(Color("#d9302a")))
		_:
			ci.draw_circle(Vector2.ZERO, 30, k.call(Color("#9aa6ad")))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A filled polygon with the white sticker outline and a soft shadow.
static func _shape(ci: CanvasItem, pts: Array, fill: Color, alpha: float) -> void:
	var poly := PackedVector2Array(pts)
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(3, 5))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.18 * alpha))
	var ring := poly.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, Color(OUTLINE, OUTLINE.a * alpha), 9.0, true)
	ci.draw_colored_polygon(poly, fill)
	ci.draw_polyline(ring, Color(INK, 0.55 * alpha), 2.0, true)
