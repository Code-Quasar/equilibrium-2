class_name Smoke
extends Node2D
## Chimney smoke, cooling-tower steam or a landfill flare: a few soft puffs
## rising and fading, drawn by hand so it looks the same on every renderer.

var kind := "smoke"
var seed := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var n := 5 if kind != "flare" else 3
	for i in n:
		var p := fmod(_t / (2.4 if kind != "flare" else 0.8) + float(i) / n + seed, 1.0)
		var pos := Vector2(sin(p * 5.0 + i + seed * 9.0) * 2.0 + p * 7.0, -p * (26.0 if kind != "flare" else 8.0))
		var r := (1.6 + p * 4.5) * (1.4 if kind == "steam" else 1.0) * (0.5 if kind == "flare" else 1.0)
		var col: Color
		match kind:
			"steam":
				col = Color(1, 1, 1, (1.0 - p) * 0.7)
			"flare":
				col = Color(1, 0.6 - p * 0.3, 0.2, (1.0 - p) * 0.9)
			_:
				col = Color(0.36, 0.34, 0.32, (1.0 - p) * 0.6)
		draw_circle(pos, r, col)
