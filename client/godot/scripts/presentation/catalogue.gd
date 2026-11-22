class_name Catalogue
extends RefCounted
## Display text and number formatting. Names, descriptions and error wording
## live here; figures (prices, build times, capacities, prerequisites, the
## crisis schedule) come from data/catalogue.json, exported from the live B2.1
## file, and are shown for orientation only: the server decides every action.

const MICRO := 1000000.0

## Building identity: name and short role. The order is the build bar's order.
const BUILDINGS := {
	"residential_district": ["Residential District", "Homes: the only way to take in more residents"],
	"commercial_district": ["Commercial District", "Jobs and income with little waste or smoke"],
	"factory": ["Factory", "Many jobs and income; uses materials, power, makes waste and smoke"],
	"public_services_center": ["Public Services Center", "Service capacity for Satisfaction"],
	"park": ["Park", "Cleans the air and adds amenity; cannot clear waste or landfill damage"],
	"collection_center": ["Collection Center", "Collects street waste and salvages some recyclables"],
	"sorting_center": ["Sorting Center", "Sorts collected waste and reuses part of the recyclables"],
	"recycling_center": ["Recycling Center", "Turns sorted recyclables into materials"],
	"biogas_facility": ["Biogas Facility", "Turns sorted organic waste into electricity"],
	"landfill": ["Landfill", "Takes what is left, for a fee and lasting damage"],
	"fossil_power_plant": ["Fossil Power Plant", "Fast, cheap, dirty power"],
	"renewable_power_plant": ["Renewable Power Plant", "Clean power"],
}
const SIZES := {"S": "Small", "M": "Medium", "L": "Large"}
const NEXT_SIZE := {"S": "M", "M": "L"}

const FOUNDATIONS := {
	"industrial_legacy": ["Industrial Legacy", "Starts with a Factory: jobs and income now, but it eats materials and power and makes waste."],
	"circular_foundation": ["Circular Foundation", "Starts with a Collection and a Sorting Center: recovers materials from the first minute, and can build a Recycling Center at once."],
	"energy_pioneer": ["Energy Pioneer", "Starts with a Renewable Power Plant: spare clean power to grow on or to sell."],
	"investment_district": ["Investment District", "No building, the most cash: the most flexible opening."],
}

const EVENTS := {
	"smog_alert": ["Smog Alert", "Emissions count 50 % more and the air recovers at half speed"],
	"waste_surge": ["Waste Surge", "Much more household and business waste"],
	"power_shortage": ["Power Shortage", "The municipal grid gives 45 % less power"],
	"equilibrium_2050": ["EQUILIBRIUM 2050", "The final reckoning: the match ends"],
}

const SERVICES := {"electricity": "Electricity", "recyclable": "Recyclable treatment", "organic": "Organic treatment"}
const WASTE := ["Recyclable", "Organic", "Residual"]

const ERRORS := {
	"insufficient_funds": "Not enough money",
	"insufficient_materials": "Not that many materials in stock",
	"construction_slots_full": "Both construction slots are busy",
	"requires_collection_center": "Needs a finished Collection Center first",
	"requires_sorting_center": "Needs a finished Sorting Center first",
	"prerequisite_under_construction": "Its required building is still being built",
	"dependent_buildings_exist": "Other buildings depend on it",
	"housing_below_population": "Residents would lose their homes",
	"tile_occupied": "That site is taken",
	"no_free_tile": "No free site left",
	"not_enough_time": "It would not finish before the match ends",
	"maximum_size": "Already Large",
	"already_upgrading": "Already being upgraded",
	"not_complete": "Still under construction",
	"cancel_project_first": "Cancel its project first",
	"no_active_project": "No project to cancel",
	"reactivation_cooldown": "It was switched off too recently",
	"already_enabled": "Already on",
	"already_disabled": "Already off",
	"building_not_owned": "Not your building",
	"invalid_join_code": "No open lobby with that code",
	"city_eliminated": "Your city is out of resources and can no longer act",
	"city_name_taken": "Another player already took that city name",
	"invalid_city_name": "City names use 2–20 letters, digits, spaces, ' or -",
	"lobby_full": "That lobby is full",
	"lobby_started": "That match has already started",
	"lobby_exists": "This server already hosts a lobby: join it with its code",
	"host_only": "Only the host can start",
	"not_ready": "Everyone must be ready first",
	"not_draft_turn": "Not your turn to choose",
	"foundation_taken": "That Foundation was just taken",
	"invalid_phase": "Not possible right now",
	"authentication_failed": "Your seat could not be restored",
	"rate_limited": "Too many requests",
	"insufficient_seller_capacity": "Not enough spare capacity to sell",
	"offer_limit": "You already have the most open offers allowed",
	"offer_unavailable": "That offer is gone",
	"offer_not_owned": "Not your offer",
	"contract_limit": "You already hold the most contracts allowed",
	"duplicate_contract": "You already buy that from this city",
	"contract_unavailable": "That contract has ended",
	"contract_not_owned": "Not your contract",
	"self_contract": "You cannot trade with yourself",
	"invalid_rate": "Amount outside the allowed range",
	"invalid_duration": "Contracts last 1 to 5 minutes",
	"timeout": "The server did not answer",
	"refused": "The server refused the connection",
	"bad_address": "That server address is not valid",
	"connection_lost": "Connection lost",
	"not_connected": "Not connected",
	"session_replaced": "Your seat was opened on another device",
	"server_shutdown": "The server shut down",
}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalogue.json"))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


static func error_text(code: String) -> String:
	return ERRORS.get(code, "")


static func building_name(t: String) -> String:
	return BUILDINGS.get(t, [t.capitalize()])[0]


static func role(t: String) -> String:
	return BUILDINGS.get(t, ["", ""])[1]


static func size_name(size: String) -> String:
	return SIZES.get(size, size)


## A tier's figures as exported; a figure a tier does not list is zero.
static func tier(t: String, size: String) -> Dictionary:
	return data().get("buildings", {}).get(t, {}).get(size, {})


static func figure(t: String, size: String, key: String) -> float:
	return float(tier(t, size).get(key, 0))


## The incremental price of upgrading to size: {additional_credits, additional_materials, seconds}.
static func upgrade_to(t: String, size: String) -> Dictionary:
	var from: String = {"M": "S", "L": "M"}.get(size, "")
	return tier(t, size).get("upgrade_from_" + from, {}) if from != "" else {}


static func requires(t: String) -> Array:
	return data().get("buildings", {}).get(t, {}).get("required_completed_buildings", [])


## Credits, materials and seconds as one short line, e.g. "💰 125 + 9 mat · ⏱ 0:25".
static func price_text(credits: float, materials: float, seconds: int) -> String:
	return "💰 %s + %s mat · ⏱ %s" % [fmt(credits), fmt(materials), clock(seconds)]


## The six city metrics a building changes, for the build bar and placement:
## [key, badge, name]. Values come from impact().
const METRICS := [
	["housing", "homes", "Housing"],
	["jobs", "jobs", "Jobs"],
	["power", "power", "Electricity"],
	["pollution", "pollution", "Pollution"],
	["resources", "materials", "Resources"],
	["money", "coin", "Money"],
]


## What building t at size does to each metric, as {key: [short text, tone]}:
## tone 1 helps the city, -1 costs it, 0 neutral; text "_" when it does not apply.
## Figures are the exported B2.1 tier; the server decides every real outcome.
static func impact(t: String, size: String) -> Dictionary:
	var x := tier(t, size)
	var f := func(key: String) -> float: return float(x.get(key, 0))
	var out := {}
	out["housing"] = ["+%s homes" % fmt(f.call("housing_capacity")), 1] if f.call("housing_capacity") > 0 else ["_", 0]
	out["jobs"] = ["+%s jobs" % fmt(f.call("job_slots")), 1] if f.call("job_slots") > 0 else ["_", 0]
	if f.call("power_generated_capacity") > 0:
		out["power"] = ["+%s" % fmt(f.call("power_generated_capacity")), 1]
	elif t == "biogas_facility":
		out["power"] = ["−%s, makes up to +%s" % [fmt(f.call("power_demand_capacity")), fmt(f.call("biogas_organic_waste_per_min") * f.call("biogas_energy_capacity_per_organic_unit_per_min"))], 1]
	elif f.call("power_demand_capacity") > 0:
		out["power"] = ["−%s" % fmt(f.call("power_demand_capacity")), -1]
	else:
		out["power"] = ["_", 0]
	var bits := []
	var tone := 0
	if f.call("air_emissions_points_per_min") > 0:
		bits.append("+%s air/min" % _dec(f.call("air_emissions_points_per_min")))
		tone = -1
	if f.call("air_cleanup_points_per_min") > 0:
		bits.append("cleans %s air/min" % _dec(f.call("air_cleanup_points_per_min")))
		tone = 1
	if f.call("waste_generated_per_min") > 0:
		bits.append("+%s waste/min" % fmt(f.call("waste_generated_per_min")))
		tone = -1
	if t == "residential_district":
		bits.append("+%s waste/min from residents" % _dec(f.call("housing_capacity") * 0.03))
		tone = -1
	for k in [["collection_waste_per_min", "collects"], ["sorting_waste_per_min", "sorts"], ["recycling_waste_per_min", "recycles"], ["biogas_organic_waste_per_min", "digests"]]:
		if f.call(k[0]) > 0:
			bits.append("%s %s waste/min" % [k[1], fmt(f.call(k[0]))])
			tone = 1
	if f.call("landfill_waste_per_min") > 0:
		bits.append("buries %s waste/min, damages land" % fmt(f.call("landfill_waste_per_min")))
		tone = -1
	out["pollution"] = [", ".join(bits), tone] if not bits.is_empty() else ["_", 0]
	var res := ["−%s to build" % fmt(f.call("construction_materials"))]
	var rtone := -1
	if f.call("factory_materials_consumed_per_min") > 0:
		res.append("−%s/min" % fmt(f.call("factory_materials_consumed_per_min")))
	if f.call("recycling_waste_per_min") > 0:
		res.append("+≈%s/min recovered, slows the drain" % fmt(f.call("recycling_waste_per_min") * f.call("material_yield_fraction")))
		rtone = 1
	if f.call("sorting_direct_reuse_fraction") > 0 or f.call("collection_direct_reuse_fraction") > 0:
		res.append("recovers a little")
	if t == "renewable_power_plant" or t == "biogas_facility":
		res.append("clean power slows the drain")
		rtone = 1
	if t == "fossil_power_plant":
		res.append("dirty power speeds the drain")
	if t == "residential_district":
		res.append("residents draw on it")
	out["resources"] = [", ".join(res), rtone]
	var income: float = f.call("gross_income_credits_per_min")
	var upkeep: float = f.call("maintenance_credits_per_min")
	var net: float = income - upkeep
	var m := "−%s now, " % fmt(f.call("construction_credits"))
	m += ("%s%s/min (+%s income −%s upkeep)" % ["+" if net >= 0 else "−", fmt(absf(net)), fmt(income), fmt(upkeep)]) if income > 0 else "−%s/min upkeep" % fmt(upkeep)
	out["money"] = [m, 1 if net > 0 else -1]
	# Short forms for the narrow build cards.
	var short := {
		"housing": "+%s" % fmt(f.call("housing_capacity")) if f.call("housing_capacity") > 0 else "",
		"jobs": "+%s" % fmt(f.call("job_slots")) if f.call("job_slots") > 0 else "",
		"power": str(out["power"][0]).split(",")[0] if out["power"][0] != "_" else "",
		"pollution": "",
		"resources": "−%s%s" % [fmt(f.call("construction_materials")), " ↺" if rtone > 0 else ""],
		"money": "%s%s/min" % ["+" if net >= 0 else "−", fmt(absf(net))],
	}
	if f.call("air_emissions_points_per_min") > 0:
		short["pollution"] = "+%s air" % _dec(f.call("air_emissions_points_per_min"))
	elif f.call("air_cleanup_points_per_min") > 0:
		short["pollution"] = "−%s air" % _dec(f.call("air_cleanup_points_per_min"))
	elif f.call("landfill_waste_per_min") > 0:
		short["pollution"] = "land damage"
	elif out["pollution"][1] > 0:
		short["pollution"] = "−waste"
	elif out["pollution"][1] < 0:
		short["pollution"] = "+waste"
	for k in out:
		out[k].append(short.get(k, ""))
	return out


static func _dec(x: float) -> String:
	return String.num(x, 2).trim_suffix("0").trim_suffix(".") if absf(x - round(x)) > 0.001 else fmt(x)


static func event_name(id: String) -> String:
	return EVENTS.get(id, [id.capitalize()])[0]


## The crisis schedule entry for id, or {}.
static func crisis(id: String) -> Dictionary:
	for c in data().get("crises", []):
		if c["id"] == id:
			return c
	return {}


## A micro-unit amount as a short display number.
static func micro(v: Variant, decimals := 0) -> String:
	var x := float(v) / MICRO
	if decimals > 0:
		return String.num(x, decimals)
	return fmt(x)


static func fmt(n: float) -> String:
	var neg := n < 0
	var s := str(int(round(absf(n))))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("−" if neg else "") + s + out


static func clock(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	return "%d:%02d" % [seconds / 60, seconds % 60]
