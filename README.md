# EQUILIBRIUM

### Deterministic circular-economy strategy game

Four cities compete for one region of 8,000 residents over a 20-minute match. Each city builds housing, jobs, services and power, and turns its waste into materials and energy through a Collection → Sorting → Recycling chain. Residents move toward the most satisfying cities, and the city with the most residents at the end wins.

Satisfaction combines Environment, employment, housing, power reliability and public services. Every economic choice reaches the same objective through it: what a city builds, how it treats its waste, how it powers itself and what it trades with rivals.

## Features

- Fixed one-second ticks, seeded command ordering, atomic commands and transactional ticks.
- Twelve building types in Small, Medium and Large tiers, with hard Collection → Sorting → Recycling/Biogas prerequisites.
- Progressive valorization: Collection salvages some recyclables, Sorting reuses more, Recycling recovers the most, and each unit counts once.
- A physical waste ledger, one material inventory, priced inputs, landfill fees and an emissions levy.
- Staffing, prioritized electricity, biogas power, Environment stocks and pairwise Satisfaction-driven migration.
- Four Foundations, four announced regional crises and fixed-price electricity and treatment contracts with escrow.
- ECO EMERGENCIES: three server-validated recycling minigames per match (routing, slicing, repair); the winner's boost raises one stage of their own recovery chain for 90 seconds.
- An authoritative WebSocket server with lobby, draft, reconnection, bots and per-seat views.

## Requirements

- Godot 4.7.2
- Python 3.9 or later for the static checker, the terminal client and the socket tests

## Run

A complete match with demonstration Foundations and no commands, printing the canonical state:

```sh
godot --headless --path . --script simulation/headless_runner.gd -- 42 1200
```

To host a multiplayer match, see the [server](server/README.md).

## Layout

- `simulation/` — the authoritative engine (see [architecture](docs/architecture.md))
- `config/balance/B2_1.json` — the live ruleset numbers
- `server/` — the WebSocket match host
- `shared/` — protocol v1 and its schema
- `client/` — terminal and graphical clients
- `tests/`, `tools/` — test suites and static checks

## Documentation

- [Game specification](docs/specification.md) — the rules the engine implements
- [Architecture](docs/architecture.md), [deterministic execution](docs/deterministic-execution.md), [engine interface](docs/engine-interface.md)
- [Testing](docs/testing.md)

## Testing

```sh
godot --headless --path . --script tests/run_all.gd
python3 tools/check_repository.py
```
