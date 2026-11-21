class_name Models
extends RefCounted
## Which Kenney models (CC0, assets/kenney) make up each building, road piece,
## tree and car. A building is a small scene on its 2×2 site, one per size
## (S, M, L): a list of [model, x, z, turn in degrees, scale], with x and z in
## cells from the site centre.

const ROOT := "res://assets/kenney/"

const BUILDINGS := {
	"residential_district": {
		"S": [["suburban/building-type-a", -0.1, -0.15, 0, 1.0], ["suburban/tree-small", 0.7, 0.65, 0, 1.0], ["suburban/planter", -0.7, 0.75, 0, 1.0]],
		"M": [["suburban/building-type-n", 0.0, -0.1, 0, 1.05], ["suburban/tree-large", 0.75, 0.75, 0, 0.8]],
		"L": [["suburban/building-type-n", -0.4, -0.35, 0, 0.85], ["suburban/building-type-u", 0.45, 0.35, 0, 0.85], ["suburban/tree-large", -0.7, 0.7, 0, 0.7]],
	},
	"commercial_district": {
		"S": [["commercial/building-a", -0.45, -0.1, 0, 1.0], ["commercial/building-c", 0.45, -0.1, 0, 1.0], ["commercial/detail-parasol-a", 0.0, 0.7, 0, 1.0]],
		"M": [["commercial/building-skyscraper-a", 0.0, 0.0, 0, 1.15]],
		"L": [["commercial/building-skyscraper-b", -0.4, -0.35, 0, 1.0], ["commercial/building-skyscraper-e", 0.45, 0.4, 0, 0.95]],
	},
	"public_services_center": {
		"S": [["commercial/building-i", 0.0, -0.1, 0, 1.25], ["suburban/tree-small", -0.75, 0.75, 0, 1.0], ["suburban/tree-small", 0.75, 0.75, 0, 1.0]],
		"M": [["commercial/building-n", 0.0, 0.0, 0, 0.82]],
		"L": [["commercial/building-n", -0.3, -0.3, 0, 0.78], ["commercial/building-i", 0.5, 0.45, 0, 0.95], ["suburban/tree-small", -0.75, 0.75, 0, 1.0]],
	},
	"factory": {
		"S": [["industrial/building-c", 0.0, 0.0, 0, 0.9]],
		"M": [["industrial/building-l", 0.0, 0.0, 0, 0.95]],
		"L": [["industrial/building-l", -0.3, -0.25, 0, 0.82], ["industrial/building-c", 0.5, 0.5, 0, 0.6], ["industrial/chimney-large", 0.7, -0.7, 0, 0.7]],
	},
	"park": {
		"S": [["nature/tree_oak", -0.5, -0.5, 0, 0.8], ["nature/tree_default", 0.5, -0.3, 40, 0.7], ["nature/plant_bushLarge", -0.4, 0.5, 0, 0.8], ["nature/flower_redA", 0.4, 0.5, 0, 1.6], ["nature/flower_yellowA", 0.1, 0.2, 0, 1.6]],
		"M": [["nature/tree_oak", -0.6, -0.6, 0, 0.85], ["nature/tree_oak", 0.6, -0.5, 60, 0.8], ["nature/tree_default", -0.5, 0.55, 20, 0.7], ["nature/path_stone", 0.2, 0.2, 0, 1.2], ["nature/plant_bushLarge", 0.6, 0.6, 0, 0.8], ["nature/flower_purpleA", -0.1, -0.1, 0, 1.6]],
		"L": [["nature/tree_oak", -0.7, -0.7, 0, 0.9], ["nature/tree_oak", 0.65, -0.6, 60, 0.85], ["nature/tree_oak", -0.65, 0.65, 120, 0.85], ["nature/tree_default", 0.7, 0.7, 20, 0.75], ["nature/path_stone", 0.0, 0.0, 0, 1.4], ["nature/plant_bushLarge", 0.0, -0.75, 0, 0.8], ["nature/flower_redA", 0.35, 0.3, 0, 1.6], ["nature/flower_purpleA", -0.3, -0.25, 0, 1.6], ["nature/flower_yellowA", 0.3, -0.3, 0, 1.6]],
	},
	"collection_center": {
		"S": [["industrial/building-h", -0.25, -0.3, 0, 1.0], ["cars/garbage-truck", 0.55, 0.45, 90, 0.3], ["roads/dumpster", -0.6, 0.65, 0, 1.0]],
		"M": [["industrial/building-h", -0.25, -0.35, 0, 1.0], ["cars/garbage-truck", 0.55, 0.3, 90, 0.3], ["cars/garbage-truck", 0.55, 0.75, 90, 0.3], ["roads/dumpster", -0.7, 0.55, 0, 1.0], ["roads/dumpster", -0.3, 0.75, 0, 1.0]],
		"L": [["industrial/building-q", 0.0, -0.3, 0, 0.88], ["cars/garbage-truck", -0.55, 0.6, 90, 0.3], ["cars/garbage-truck", 0.0, 0.6, 90, 0.3], ["cars/garbage-truck", 0.55, 0.6, 90, 0.3], ["roads/dumpster", 0.75, -0.75, 0, 1.0]],
	},
	"sorting_center": {
		"S": [["industrial/building-d", 0.0, -0.3, 0, 0.9], ["factory/conveyor-long", 0.0, 0.5, 0, 0.5], ["factory/box-small", -0.65, 0.7, 0, 1.0]],
		"M": [["industrial/building-o", 0.0, -0.3, 0, 0.9], ["factory/conveyor-long", 0.0, 0.5, 0, 0.55], ["factory/box-small", -0.7, 0.75, 0, 1.0], ["factory/box-small", 0.7, 0.75, 30, 1.0]],
		"L": [["industrial/building-o", -0.3, -0.35, 0, 0.85], ["industrial/building-d", 0.55, 0.25, 0, 0.6], ["factory/conveyor-long", -0.3, 0.6, 0, 0.5], ["factory/hopper-square", 0.65, -0.65, 0, 0.6], ["factory/box-small", -0.75, 0.8, 0, 1.0]],
	},
	"recycling_center": {
		"S": [["industrial/building-t", 0.0, -0.25, 0, 1.0], ["industrial/shipping-container-a", -0.6, 0.65, 90, 1.0], ["industrial/shipping-container-b", 0.0, 0.65, 90, 1.0], ["industrial/shipping-container-c", 0.6, 0.65, 90, 1.0]],
		"M": [["industrial/building-r", 0.0, -0.3, 0, 0.8], ["factory/conveyor-long", 0.0, 0.5, 0, 0.6], ["industrial/shipping-container-a", -0.7, 0.75, 90, 1.0], ["industrial/shipping-container-c", 0.7, 0.75, 90, 1.0]],
		"L": [["industrial/building-r", -0.3, -0.35, 0, 0.75], ["industrial/building-t", 0.5, 0.3, 0, 0.6], ["industrial/shipping-container-a", -0.7, 0.75, 90, 1.0], ["industrial/shipping-container-b", -0.15, 0.75, 90, 1.0]],
	},
	"biogas_facility": {
		"S": [["industrial/detail-tank-large", -0.2, -0.1, 0, 0.85], ["industrial/detail-tank", 0.6, 0.6, 90, 0.9]],
		"M": [["industrial/detail-tank-large", -0.45, -0.45, 0, 0.7], ["industrial/detail-tank-large", 0.45, 0.35, 0, 0.7], ["industrial/chimney-small", 0.7, -0.7, 0, 1.0]],
		"L": [["industrial/detail-tank-large", -0.5, -0.5, 0, 0.65], ["industrial/detail-tank-large", 0.5, -0.45, 0, 0.65], ["industrial/detail-tank-large", -0.45, 0.5, 0, 0.65], ["industrial/detail-tank", 0.55, 0.55, 90, 0.9], ["industrial/chimney-small", 0.0, 0.0, 0, 1.0]],
	},
	"landfill": {
		"S": [["roads/construction-fence", 0.0, -0.9, 0, 1.0], ["factory/box-large", -0.4, -0.2, 20, 0.8], ["factory/box-wide", 0.3, 0.1, -10, 0.8], ["cars/tractor-shovel", 0.4, 0.6, 30, 0.3]],
		"M": [["roads/construction-fence", 0.0, -0.9, 0, 1.0], ["roads/construction-fence", -0.9, 0.0, 90, 1.0], ["factory/box-large", -0.3, -0.3, 20, 1.0], ["factory/box-large", 0.4, -0.1, -15, 0.9], ["cars/tractor-shovel", -0.3, 0.6, 30, 0.3], ["cars/truck-flat", 0.6, 0.6, 90, 0.28]],
		"L": [["roads/construction-fence", 0.0, -0.9, 0, 1.0], ["roads/construction-fence", -0.9, 0.0, 90, 1.0], ["roads/construction-fence", 0.9, 0.0, 90, 1.0], ["factory/box-large", -0.35, -0.35, 20, 1.0], ["factory/box-large", 0.35, -0.3, -15, 1.0], ["factory/box-wide", 0.0, 0.15, 5, 1.0], ["cars/tractor-shovel", -0.4, 0.65, 30, 0.3], ["cars/truck-flat", 0.5, 0.65, 90, 0.28]],
	},
	"fossil_power_plant": {
		"S": [["industrial/building-e", -0.1, 0.1, 0, 0.9], ["industrial/chimney-large", 0.55, -0.55, 0, 0.7]],
		"M": [["industrial/building-f", -0.1, 0.15, 0, 0.9], ["industrial/chimney-large", 0.55, -0.6, 0, 0.75], ["industrial/chimney-medium", -0.65, -0.65, 0, 1.0]],
		"L": [["industrial/building-f", -0.1, 0.2, 0, 0.95], ["industrial/chimney-large", 0.6, -0.6, 0, 0.8], ["industrial/chimney-large", -0.6, -0.65, 0, 0.8], ["industrial/chimney-medium", 0.7, 0.7, 0, 1.0]],
	},
	"renewable_power_plant": {
		"S": [["industrial/solar-panel-landscape-group", 0.0, -0.45, 0, 1.15], ["industrial/solar-panel-landscape-group", 0.0, 0.45, 0, 1.15]],
		"M": [["industrial/windmill", -0.5, -0.4, 0, 0.9], ["industrial/windmill", 0.5, -0.4, 0, 0.9], ["industrial/solar-panel-landscape-group", 0.0, 0.55, 0, 1.15]],
		"L": [["industrial/windmill", -0.6, -0.5, 0, 0.85], ["industrial/windmill", 0.0, -0.5, 0, 0.85], ["industrial/windmill", 0.6, -0.5, 0, 0.85], ["industrial/solar-panel-landscape-group", 0.0, 0.5, 0, 1.15]],
	},
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


## A building's models at a size, around the origin, sized for a 2×2 site (foot cells).
static func compose(type: String, size: String, foot := 2.0) -> Node3D:
	var root := Node3D.new()
	var parts: Array = BUILDINGS.get(type, {}).get(size, [])
	for part in parts:
		var n := spawn(part[0])
		n.position = Vector3(float(part[1]) * foot / 2.0, 0, float(part[2]) * foot / 2.0)
		n.rotation_degrees.y = float(part[3])
		n.scale = Vector3.ONE * float(part[4])
		root.add_child(n)
	return root
