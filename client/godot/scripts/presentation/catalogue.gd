class_name Catalogue
extends RefCounted
## Display text and number formatting. Names, descriptions and error wording
## live here; figures (costs, build times, unlocks, the event schedule) come
## from data/catalogue.json, exported from the frozen B1 file, and are shown
## for orientation only: the server decides every action.

const MICRO := 1000000.0

## Building identity: name, short role, menu group and the sprite family it is
## drawn with (Level 1 uses the small sprite, Level 2 the medium one).
const BUILDINGS := {
	"residential_district": ["Residential District", "Homes for 450 residents", "city", "residential"],
	"commercial_district": ["Commercial District", "Jobs and cleaner income", "city", "commercial"],
	"factory": ["Factory", "Many jobs and income; dirty, power-hungry, extra waste", "city", "small_factory"],
	"public_services_center": ["Public Services Center", "Service capacity for satisfaction", "city", "hospital"],
	"recovery_hub": ["Recovery Hub", "Collects street waste and sorts it", "circular", "recovery_hub"],
	"recycling_center": ["Recycling Center", "Recyclables → recovered materials", "circular", "recycling_center"],
	"biogas_facility": ["Biogas Facility", "Organic waste → electricity", "circular", "biogas_plant"],
	"landfill": ["Landfill", "Residual waste disposal, damages the environment", "circular", "landfill"],
	"fossil_power_plant": ["Fossil Power Plant", "Fast, cheap, dirty power", "energy", "fossil_plant"],
	"renewable_power_plant": ["Renewable Power Plant", "Clean power", "energy", "renewable_plant"],
	"green_space": ["Green Space", "Cleans the air", "energy", "park"],
}
const GROUPS := [["city", "City"], ["circular", "Circular economy"], ["energy", "Energy & nature"]]

const FOUNDATIONS := {
	"industrial_legacy": ["Industrial Legacy", "Starts with a Factory: jobs and cash now, tight power, extra waste.", "small_factory_m"],
	"circular_foundation": ["Circular Foundation", "Starts with a Recycling Center: turns household recyclables into materials from the first minute.", "recycling_center_m"],
	"energy_pioneer": ["Energy Pioneer", "Starts with a Renewable Power Plant: surplus clean power to grow on or to sell.", "renewable_plant_m"],
	"investment_district": ["Investment District", "No building, the most cash: the most flexible opening.", "commercial_m"],
}

const EVENTS := {
	"smog_alert": ["Smog Alert", "Air pollution hits harder"],
	"waste_surge": ["Waste Surge", "Much more household and business waste"],
	"power_shortage": ["Power Shortage", "Less municipal electricity"],
	"equilibrium_2050": ["EQUILIBRIUM 2050", "More waste, less power, worse air at once"],
}

const SERVICES := {"recyclable": "Recyclable treatment", "organic": "Organic treatment", "electricity": "Electricity"}
const WASTE := ["Recyclable", "Organic", "Residual"]

const ERRORS := {
	"insufficient_funds": "Not enough money",
	"construction_slots_full": "Both construction slots are busy",
	"development_locked": "Needs more Development",
	"tile_occupied": "That tile is taken",
	"no_free_tile": "No free tile left",
	"not_enough_time": "It would not finish before the match ends",
	"maximum_level": "Already at the highest level",
	"already_upgrading": "Already being upgraded",
	"not_complete": "Still under construction",
	"cancel_project_first": "Cancel its project first",
	"no_active_project": "No project to cancel",
	"policy_cooldown": "The policy was changed too recently",
	"already_set": "Already set that way",
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
	"no_eligible_buyer_need": "Nobody needs that service right now",
	"insufficient_seller_capacity": "Not enough spare capacity to sell",
	"offer_unavailable": "That offer is gone",
	"quote_window_closed": "The quote window has closed",
	"selection_window_closed": "The selection window has closed",
	"contract_limit": "Contract limit reached",
	"self_contract": "You cannot trade with yourself",
	"invalid_rate": "Rate outside the allowed range",
	"invalid_price": "Price outside the allowed band",
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


static func group(t: String) -> String:
	return BUILDINGS.get(t, ["", "", "city"])[2]


static func sprite(t: String, level: int) -> String:
	var base: String = BUILDINGS.get(t, ["", "", "", "commercial"])[3]
	return "%s_%s" % [base, "m" if level >= 2 else "s"]


static func spec(t: String) -> Dictionary:
	return data().get("buildings", {}).get(t, {})


static func event_name(id: String) -> String:
	return EVENTS.get(id, [id.capitalize()])[0]


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


## Why a finished building is not running, in a word or two.
static func state_text(b: Dictionary) -> String:
	if not b.get("enabled", true):
		return "switched off"
	if not b.get("funded", true):
		return "unfunded"
	var pf: Variant = b.get("power_factor_micro")
	if pf != null and int(pf) < 1000000:
		return "low power"
	return "idle"


static func ordinal(n: int) -> String:
	return "#%d" % n
