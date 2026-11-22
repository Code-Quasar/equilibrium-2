class_name EdgePulse
extends ColorRect
## A soft red glow at the screen edges that pulses three times, about two
## seconds in all, when a crisis strikes. It never covers the middle of the
## screen and never takes input. With reduced motion it glows once, gently.

const SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform float aspect = 2.0;
uniform vec4 tint : source_color = vec4(0.86, 0.13, 0.09, 1.0);
void fragment() {
	vec2 d = min(UV, 1.0 - UV);
	float edge = min(d.x * aspect, d.y);
	float a = smoothstep(0.16, 0.0, edge) * strength;
	COLOR = vec4(tint.rgb, a * 0.75);
}
"""

var _tween: Tween


func _init() -> void:
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	var sh := Shader.new()
	sh.code = SHADER
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = sh
	visible = false


func play(reduced := false) -> void:
	var vp := get_viewport_rect().size
	(material as ShaderMaterial).set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	if _tween:
		_tween.kill()
	visible = true
	_strength(0.0)
	_tween = create_tween()
	if reduced:
		_tween.tween_method(_strength, 0.0, 0.45, 0.6).set_trans(Tween.TRANS_SINE)
		_tween.tween_method(_strength, 0.45, 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	else:
		for i in 3:
			_tween.tween_method(_strength, 0.0, 0.85, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_tween.tween_method(_strength, 0.85, 0.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): visible = false)


## Tests only: whether the pulse is playing.
func playing() -> bool:
	return visible and _tween != null and _tween.is_running()


func _strength(x: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("strength", x)
