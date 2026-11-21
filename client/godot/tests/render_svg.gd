extends SceneTree
## Renders SVG files to PNG at a given size, to look at brand artwork.
##   godot --headless --path client/godot --script res://tests/render_svg.gd -- in.svg out.png 512
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.new()
	var svg := FileAccess.get_file_as_string(a[0])
	img.load_svg_from_string(svg, float(a[2]) / 256.0)
	img.save_png(a[1])
	quit()
