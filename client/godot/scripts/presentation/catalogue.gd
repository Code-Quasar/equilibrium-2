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
