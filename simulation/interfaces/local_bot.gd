extends RefCounted
## Ordinary-command schedule for explicitly unoccupied local seats.
## Grants no resources or special rules and does not automate disconnected seats.
const PLAN = ["commercial_district", "renewable_power_plant", "recycling_center",
	"residential_district", "public_services_center", "recovery_hub", "biogas_facility"]
