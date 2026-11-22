#!/usr/bin/env python3
"""Static checks: resources, dependency boundaries, script UIDs, documentation links, B2.1 shape."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDINGS = {
    "residential_district", "factory", "commercial_district", "public_services_center", "park",
    "collection_center", "sorting_center", "recycling_center", "biogas_facility", "landfill",
    "fossil_power_plant", "renewable_power_plant",
}
FOUNDATIONS = {"industrial_legacy", "circular_foundation", "energy_pioneer", "investment_district"}
SCRIPT_FOLDERS = ("simulation", "server", "shared", "tests", "tools")


def main() -> int:
    errors: list[str] = []

    for folder in SCRIPT_FOLDERS:
        for source in (ROOT / folder).rglob("*.gd"):
            text = source.read_text(encoding="utf-8")
            references = re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', text)
            references += re.findall(r'^extends "res://([^"\n]+)"', text, re.MULTILINE)
            for path in references:
                if not (ROOT / path).is_file():
                    errors.append(f"Missing resource in {source.relative_to(ROOT)}: {path}")
            if folder == "simulation" and re.search(r"res://(?:server|shared|tests|tools|client)/", text):
                errors.append(f"Simulation depends outside the engine: {source.relative_to(ROOT)}")
            if not Path(str(source) + ".uid").is_file():
                errors.append(f"Missing UID: {source.relative_to(ROOT)}")

    for uid in ROOT.rglob("*.gd.uid"):
        if any(part in {".git", ".godot", ".venv"} for part in uid.parts):
            continue
        if not uid.with_suffix("").is_file():
            errors.append(f"Orphaned UID: {uid.relative_to(ROOT)}")

    pages = [ROOT / "README.md", *(ROOT / "docs").rglob("*.md"), ROOT / "server/README.md", ROOT / "shared/README.md"]
    for page in pages:
        for target in re.findall(r"\]\(([^)]+)\)", page.read_text(encoding="utf-8")):
            if "://" in target or target.startswith(("#", "/")):
                continue
            destination = target.split("#", 1)[0]
            if destination and not (page.parent / destination).exists():
                errors.append(f"Broken link in {page.relative_to(ROOT)}: {target}")

    config = json.loads((ROOT / "config/balance/B2_1.json").read_text(encoding="utf-8"))
    if config.get("version") != "B2.1":
        errors.append("Active configuration is not B2.1")
    if set(config.get("buildings", {})) != BUILDINGS:
        errors.append("B2.1 building catalogue does not contain exactly the twelve identifiers")
    if set(config.get("foundations", {})) != FOUNDATIONS:
        errors.append("B2.1 foundation catalogue does not contain exactly the four identifiers")
    for name, building in config.get("buildings", {}).items():
        if set(building) != {"required_completed_buildings", "S", "M", "L"}:
            errors.append(f"B2.1 {name} must define prerequisites and S, M, L tiers")
    if [b.get("id") for b in config["foundations"]["circular_foundation"]["starting_buildings"]] != ["collection_center", "sorting_center"]:
        errors.append("Circular Foundation must start with Collection then Sorting")
    if sorted(p.name for p in (ROOT / "config/balance").iterdir()) != ["B2_1.json"]:
        errors.append("config/balance must hold only the live B2.1 configuration")

    # The recycling line model runs on the server and in the client: one file, two copies.
    shared = ROOT / "simulation/systems/plant_model.gd"
    copy = ROOT / "client/godot/scripts/ui/emergency/plant_model.gd"
    if shared.read_bytes() != copy.read_bytes():
        errors.append("client/godot/scripts/ui/emergency/plant_model.gd must be identical to simulation/systems/plant_model.gd")

    if errors:
        print("\n".join(errors))
        return 1
    print("PASS: resources, dependency boundaries, UIDs, links, B2.1 configuration shape and the shared plant model")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
