class_name Models
extends RefCounted
## Which Kenney models (CC0, assets/kenney) make up each building, road piece,
## tree and car. A building is a small scene on its 2×2 site: a list of
## [model, x, z, turn in degrees, scale], with x and z in cells from the
## site's centre.

const ROOT := "res://assets/kenney/"

const BUILDINGS := {
	"residential_district": [
		[["suburban/building-type-a", -0.1, -0.15, 0, 1.0], ["suburban/tree-small", 0.7, 0.65, 0, 1.0], ["suburban/planter", -0.7, 0.75, 0, 1.0]],
		[["suburban/building-type-n", 0.0, -0.1, 0, 1.05], ["suburban/tree-large", 0.75, 0.75, 0, 0.8]],
	],
	"commercial_district": [
		[["commercial/building-a", -0.45, -0.1, 0, 1.0], ["commercial/building-c", 0.45, -0.1, 0, 1.0], ["commercial/detail-parasol-a", 0.0, 0.7, 0, 1.0]],
		[["commercial/building-skyscraper-a", 0.0, 0.0, 0, 1.15]],
	],
	"public_services_center": [
		[["commercial/building-i", 0.0, -0.1, 0, 1.25], ["suburban/tree-small", -0.75, 0.75, 0, 1.0], ["suburban/tree-small", 0.75, 0.75, 0, 1.0]],
		[["commercial/building-n", 0.0, 0.0, 0, 0.82]],
	],
	"factory": [
		[["industrial/building-c", 0.0, 0.0, 0, 0.9]],
		[["industrial/building-l", 0.0, 0.0, 0, 0.95]],
	],
	"recovery_hub": [
		[["industrial/building-h", -0.25, -0.3, 0, 1.0], ["cars/garbage-truck", 0.55, 0.45, 90, 0.3], ["roads/dumpster", -0.6, 0.65, 0, 1.0]],
		[["industrial/building-q", 0.0, -0.25, 0, 0.88], ["cars/garbage-truck", -0.45, 0.65, 90, 0.3], ["cars/garbage-truck", 0.45, 0.65, 90, 0.3]],
	],
	"recycling_center": [
		[["industrial/building-t", 0.0, -0.25, 0, 1.0], ["industrial/shipping-container-a", -0.6, 0.65, 90, 1.0], ["industrial/shipping-container-b", 0.0, 0.65, 90, 1.0], ["industrial/shipping-container-c", 0.6, 0.65, 90, 1.0]],
		[["industrial/building-r", 0.0, -0.3, 0, 0.8], ["factory/conveyor-long", 0.0, 0.5, 0, 0.6], ["industrial/shipping-container-a", -0.7, 0.75, 90, 1.0], ["industrial/shipping-container-c", 0.7, 0.75, 90, 1.0]],
	],
	"biogas_facility": [
		[["industrial/detail-tank-large", -0.2, -0.1, 0, 0.85], ["industrial/detail-tank", 0.6, 0.6, 90, 0.9]],
		[["industrial/detail-tank-large", -0.45, -0.45, 0, 0.7], ["industrial/detail-tank-large", 0.45, 0.35, 0, 0.7], ["industrial/chimney-small", 0.7, -0.7, 0, 1.0]],
	],
	"landfill": [
		[["roads/construction-fence", 0.0, -0.9, 0, 1.0], ["factory/box-large", -0.4, -0.2, 20, 0.8], ["factory/box-wide", 0.3, 0.1, -10, 0.8], ["cars/tractor-shovel", 0.4, 0.6, 30, 0.3]],
		[["roads/construction-fence", 0.0, -0.9, 0, 1.0], ["roads/construction-fence", -0.9, 0.0, 90, 1.0], ["factory/box-large", -0.3, -0.3, 20, 1.0], ["factory/box-large", 0.4, -0.1, -15, 0.9], ["cars/tractor-shovel", -0.3, 0.6, 30, 0.3], ["cars/truck-flat", 0.6, 0.6, 90, 0.28]],
	],
	"fossil_power_plant": [
		[["industrial/building-e", -0.1, 0.1, 0, 0.9], ["industrial/chimney-large", 0.55, -0.55, 0, 0.7]],
		[["industrial/building-f", -0.1, 0.15, 0, 0.9], ["industrial/chimney-large", 0.55, -0.6, 0, 0.75], ["industrial/chimney-medium", -0.65, -0.65, 0, 1.0]],
	],
	"renewable_power_plant": [
		[["industrial/solar-panel-landscape-group", 0.0, -0.45, 0, 1.15], ["industrial/solar-panel-landscape-group", 0.0, 0.45, 0, 1.15]],
		[["industrial/windmill", -0.5, -0.4, 0, 0.9], ["industrial/windmill", 0.5, -0.4, 0, 0.9], ["industrial/solar-panel-landscape-group", 0.0, 0.55, 0, 1.15]],
	],
	"green_space": [
		[["nature/tree_oak", -0.5, -0.5, 0, 0.8], ["nature/tree_default", 0.5, -0.3, 40, 0.7], ["nature/plant_bushLarge", -0.4, 0.5, 0, 0.8], ["nature/flower_redA", 0.4, 0.5, 0, 1.6], ["nature/flower_yellowA", 0.1, 0.2, 0, 1.6]],
		[["nature/tree_oak", -0.6, -0.6, 0, 0.85], ["nature/tree_oak", 0.6, -0.5, 60, 0.8], ["nature/tree_default", -0.5, 0.55, 20, 0.7], ["nature/path_stone", 0.2, 0.2, 0, 1.2], ["nature/plant_bushLarge", 0.6, 0.6, 0, 0.8], ["nature/flower_purpleA", -0.1, -0.1, 0, 1.6]],
	],
}

const TREES := ["nature/tree_default", "nature/tree_oak", "nature/tree_pineDefaultA", "nature/tree_detailed", "nature/tree_simple"]
const CARS := ["cars/sedan", "cars/taxi", "cars/hatchback-sports", "cars/suv", "cars/van", "cars/delivery", "cars/police", "cars/truck"]

## Road pieces by which of the four sides (N, E, S, W) connect, and the turn
## that fits the piece's own orientation.
const ROAD_STRAIGHT := "roads/road-straight"
const ROAD_BEND := "roads/road-bend"
const ROAD_T := "roads/road-intersection"
const ROAD_CROSS := "roads/road-crossroad"
const ROAD_END := "roads/road-end"
const ROAD_BRIDGE := "roads/road-bridge"
const CONE := "roads/construction-cone"

static var _cache := {}


static func scene(name: String) -> PackedScene:
	if not _cache.has(name):
		_cache[name] = load(ROOT + name + ".glb")
	return _cache[name]


static func spawn(name: String) -> Node3D:
	var s := scene(name)
	return s.instantiate() as Node3D if s else Node3D.new()


## The first mesh of a model and its transform, for MultiMesh forests.
static func mesh(name: String) -> Array:
	var n := spawn(name)
	var found := []
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != n:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		found = [mi.mesh, n.transform * t]
		break
	n.free()
	return found


## A building's models around the origin, sized for a 2×2 site (foot cells).
static func compose(type: String, level: int, foot := 2.0) -> Node3D:
	var root := Node3D.new()
	var sets: Array = BUILDINGS.get(type, [[]])
	var parts: Array = sets[clampi(level - 1, 0, sets.size() - 1)]
	for part in parts:
		var n := spawn(part[0])
		n.position = Vector3(float(part[1]) * foot / 2.0, 0, float(part[2]) * foot / 2.0)
		n.rotation_degrees.y = float(part[3])
		n.scale = Vector3.ONE * float(part[4])
		root.add_child(n)
	return root
