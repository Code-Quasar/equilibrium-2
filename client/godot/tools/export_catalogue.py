#!/usr/bin/env python3
"""Exports the read-only display catalogue for the graphical client.

The server's protocol v1 carries no catalogue message, so the client shows
building costs, build times, unlocks, Foundation packages, the announced
event schedule and market price bands from a copy generated here from the
frozen B1 file. It records B1's SHA-256 so the client test fails if the copy
drifts. The client never uses these numbers to decide anything: the server
validates every action.

    python3 client/godot/tools/export_catalogue.py
"""
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
B1 = os.path.join(ROOT, "config", "balance", "B1.json")
OUT = os.path.join(HERE, "..", "data", "catalogue.json")

raw = open(B1, "rb").read()
b = json.loads(raw)
keep_l = ["cost_micro", "duration_seconds", "upkeep_micro_per_minute", "jobs", "demand_micro_E", "generation_micro_E",
          "income_micro_per_minute", "air_micro_per_minute", "housing", "services", "collection_per_minute",
          "recycling_per_minute", "reuse_per_minute", "treatment_per_minute", "waste_per_minute"]
out = {
    "source": "config/balance/B1.json",
    "source_sha256": hashlib.sha256(raw).hexdigest(),
    "match_seconds": b["match_seconds"],
    "grid": [b["grid_width"], b["grid_height"]],
    "construction_slots": b["construction_slots"],
    "material_discount_percent": b["economy"]["material_discount_percent"],
    "policy": {k: b["economy"][k] for k in ("policy_cooldown_seconds", "policy_fee_micro_per_minute")},
    "migration": {"first": b["migration_first_second"], "interval": b["migration_interval_seconds"]},
    "foundations": b["foundations"],
    "buildings": {k: {"l1": {f: v["l1"].get(f, 0) for f in keep_l},
                      "upgrade": {f: v["upgrade_delta"].get(f, 0) for f in keep_l},
                      "build_unlock_micro": v["build_unlock_micro"],
                      "upgrade_unlock_micro": v["upgrade_unlock_micro"]} for k, v in b["buildings"].items()},
    "events": [{k: e[k] for k in ("id", "warning", "start", "end")} for e in b["events"]],
    "market": {"prices": b["market"]["prices"], "duration": b["market"]["duration"],
               "contract_limit": b["market"]["contract_limit"], "quote_seconds": b["market"]["quote_seconds"],
               "selection_seconds": b["market"]["selection_seconds"]},
}
with open(OUT, "w") as f:
    json.dump(out, f, indent=1, sort_keys=True)
    f.write("\n")
print("wrote", os.path.relpath(OUT, ROOT), "from B1", out["source_sha256"][:12])
