class_name Art
extends RefCounted
## Loads the generated art bundle (tools/artgen) and rasterizes SVGs on first
## use, at a resolution that stays sharp when the map is zoomed in.

const SPRITE_SCALE := 3.0

var manifest: Dictionary = {}
var _sprite_svg: Dictionary = {}
var _icon_svg: Dictionary = {}
var _badge_svg: Dictionary = {}
var _badges: Dictionary = {}
var _sprites: Dictionary = {}
var _icons: Dictionary = {}


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art.json"))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("art.json is missing; run tools/artgen/gen.py")
		return
	manifest = data["manifest"]["sprites"]
	_sprite_svg = data["sprites"]
	_icon_svg = data["icons"]
	_badge_svg = data.get("badges", {})


## The sprite texture, drawn SPRITE_SCALE times larger than the 1x art.
func sprite(name: String) -> Texture2D:
	if not _sprites.has(name):
		_sprites[name] = _raster(_sprite_svg.get(name, ""), SPRITE_SCALE)
	return _sprites[name]


## A 48 px white icon, meant to be tinted with modulate.
func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = _raster(_icon_svg.get(name, ""), 1.0)
	return _icons[name]


## A coloured 128 px badge (round button bases, HUD icons, the status bubble).
func badge(name: String) -> Texture2D:
	if not _badges.has(name):
		_badges[name] = _raster(_badge_svg.get(name, ""), 2.0)
	return _badges[name]


func info(name: String) -> Dictionary:
	return manifest.get(name, {})


func _raster(svg: String, scale: float) -> Texture2D:
	if svg == "":
		return null
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
