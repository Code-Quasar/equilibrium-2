class_name CityBadge
extends Control
## The round badge in the HUD corner: the stage number inside a ring that
## fills as the stage's rounds go by.

var stage := 1
var progress := 0.0  # 0..1 through the current stage
var urgent := false  # the stage's event hits this round


func _ready() -> void:
	custom_minimum_size = Vector2(78, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(new_stage: int, new_progress: float, is_urgent: bool) -> void:
	stage = new_stage
	progress = new_progress
	urgent = is_urgent
	queue_redraw()


func _draw() -> void:
	var c := size / 2
	var r := minf(size.x, size.y) / 2 - 2
	draw_circle(c, r, Color(0.07, 0.11, 0.14, 0.75))
	draw_arc(c, r - 4, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 48, Color("#e85d4a") if urgent else Color("#ff7a93"), 7, true)
	var tex := UI.art.badge("badge")
	var inner := r - 10
	draw_texture_rect(tex, Rect2(c - Vector2(inner, inner), Vector2(inner, inner) * 2), false)
	var font := get_theme_default_font()
	var txt := str(stage)
	var fs := 30
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string_outline(font, c + Vector2(-w / 2, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.3, 0.05, 0.12))
	draw_string(font, c + Vector2(-w / 2, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
