#!/usr/bin/env python3
"""Exports the read-only display catalogue for the graphical client.

Protocol v1 carries no catalogue message, so the client shows building prices,
build times, capacities, prerequisites, Foundation packages, the crisis
schedule and contract prices from a copy generated here from the live B2.1
file. It records the source's SHA-256 so the client test fails if the copy
drifts. The client never uses these numbers to decide anything: the server
validates every action, and each player view says which buildings can start.

    python3 client/godot/tools/export_catalogue.py
"""
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
SOURCE = os.path.join(ROOT, "config", "balance", "B2_1.json")
OUT = os.path.join(HERE, "..", "data", "catalogue.json")

raw = open(SOURCE, "rb").read()
b = json.loads(raw)
out = {
    "source": "config/balance/B2_1.json",
    "source_sha256": hashlib.sha256(raw).hexdigest(),
    "match_seconds": b["match"]["duration_seconds"],
    "grid": [b["world"]["building_grid_width"], b["world"]["building_grid_height"]],
    "construction_slots": b["construction"]["simultaneous_projects_max"],
    "materials": {
        "buy_price": b["economy"]["external_virgin_material_buy_price_credits_per_unit"],
        "sell_price": b["economy"]["external_material_sell_price_credits_per_unit"],
        "capacity": b["economy"]["material_inventory_capacity_units"],
    },
    "landfill_fee": b["economy"]["landfill_fee_credits_per_waste_unit"],
    "housing_slack": b["satisfaction"]["housing_satisfaction_slack_multiplier"],
    "services_slack": b["satisfaction"]["services_satisfaction_slack_multiplier"],
    "migration": {"first": b["migration"]["first_event_tick"], "last": b["migration"]["last_event_tick"],
                  "interval": b["migration"]["event_interval_seconds"]},
    "foundations": {k: {"buildings": [{"type": s["id"], "size": s["tier"]} for s in v["starting_buildings"]],
                        "cash": v["starting_cash_credits"]} for k, v in b["foundations"].items()},
    "buildings": b["buildings"],
    "reserve": b["resource_reserve"],
    "crises": [{k: c[k] for k in ("id", "announce_tick", "start_tick", "end_tick_exclusive")} for c in b["crises"]],
    "market": {
        "prices": {"electricity": b["market"]["prices"]["electricity_credits_per_capacity_minute"],
                   "recyclable": b["market"]["prices"]["recyclable_treatment_credits_per_waste_unit"],
                   "organic": b["market"]["prices"]["organic_treatment_credits_per_waste_unit"]},
        "min_duration": b["market"]["min_duration_seconds"],
        "default_duration": b["market"]["default_duration_seconds"],
        "max_duration": b["market"]["max_duration_seconds"],
        "max_offers": b["market"]["max_open_offers_per_city"],
        "max_contracts": b["market"]["max_active_contracts_per_buyer"],
        "electricity_max": b["market"]["electricity_capacity_units_per_contract_max"],
    },
}
with open(OUT, "w", newline="\n") as f:
    json.dump(out, f, indent=1, sort_keys=True)
    f.write("\n")
print("wrote", os.path.relpath(OUT, ROOT), "from B2.1", out["source_sha256"][:12])
