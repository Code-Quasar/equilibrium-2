class_name Thumbs
extends Node
## Pictures of buildings for cards and menus, rendered once from the same 3D
## models the map uses. get() returns a texture at once; its image fills in a
## few frames later, and every place showing it updates by itself.

const SIZE := Vector2i(256, 192)

var _tex := {}           # "type:size" -> ImageTexture
var _queue: Array = []
var _vp: SubViewport
var _job: Node3D
var _frames := 0


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.4
	cam.rotation_degrees = Vector3(-30, 45, 0)
	cam.position = cam.transform.basis.z * 20.0 + Vector3(0, 0.75, 0)
	_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.8
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.45
	_vp.add_child(env)


func get_thumb(type: String, size := "S") -> Texture2D:
	var key := "%s:%s" % [type, size]
	if not _tex.has(key):
		var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
		_tex[key] = ImageTexture.create_from_image(img)
		_queue.append([type, size, key])
	return _tex[key]


func _process(_delta: float) -> void:
	if _job == null:
		if _queue.is_empty():
			return
		var q: Array = _queue.pop_front()
		_job = Models.compose(q[0], q[1])
		_job.set_meta("key", q[2])
		_vp.add_child(_job)
		_frames = 0
		return
	_frames += 1
	if _frames < 3:
		return
	var img := _vp.get_texture().get_image()
	(_tex[_job.get_meta("key")] as ImageTexture).update(img)
	_job.queue_free()
	_job = null
