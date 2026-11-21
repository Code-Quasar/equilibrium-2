# Architecture

EQUILIBRIUM's rules run in a headless Godot simulation with no dependency on scenes, rendering, wall-clock time, the network layer or tests. The multiplayer server hosts that simulation; clients only send intentions and display projections.

## Simulation

`simulation/match.gd` is the authoritative match. It loads the ruleset, owns the state and runs each tick as an explicit, ordered list of phases on a candidate copy. The candidate replaces the authoritative state only when every phase and invariant has passed.

| Path | Owns |
|---|---|
| `core/balance.gd` | Loading and validating `config/balance/B2_1.json` into integer micro-units |
| `core/match_state.gd` | The initial state and the cross-cutting invariants |
| `core/arithmetic.gd` | Exact fixed-point products, per-second carries and proportional allocation |
| `core/canonical.gd`, `core/command_envelope.gd`, `core/seeded_random.gd` | Canonical encoding, command envelopes and ordering, the draft RNG |
| `systems/buildings.gd` | The S/M/L catalogue, prerequisites, construction commands, project completion |
| `systems/operations.gd` | Municipal budget, funding, electricity allocation, staffing |
| `systems/production.gd` | Factory and commercial output, material input, emission levy |
| `systems/waste.gd` | Generation, collection, sorting, recycling, biogas, landfill and the mass ledger |
| `systems/materials.gd`, `systems/finance.gd` | The material inventory and the cash ledger |
| `systems/environment.gd`, `systems/satisfaction.gd` | Environment stocks and the Satisfaction score |
| `systems/events.gd`, `systems/migration.gd` | Regional crises, pairwise migration and final ranking |
| `systems/market.gd` | Offers, contracts, escrow and settlement |
| `interfaces/lifecycle.gd` | The Foundation draft that precedes a match |
| `projections/player_view.gd` | The allowlisted view one seat may see |

Systems are plain objects holding the configuration. Each phase is a function `(state, context) -> error` that mutates only the candidate state it is given. Commands map to a validator and an executor; the executor revalidates.

## Multiplayer

`server/` hosts one lobby and match per process over WebSocket (`websocket_transport.gd`, `application.gd`). A monotonic scheduler steps one tick per second, and the command gateway turns client actions into engine envelopes and receipts. Bots fill empty seats through the same commands. `shared/` holds the versioned protocol and its strict JSON decoder.

## Dependency boundaries

Production code under `simulation/` depends only on `simulation/` and the live configuration. The server depends on the simulation and `shared/`; tests depend on everything; nothing depends on tests or tools. `tools/check_repository.py` enforces these boundaries statically.

## Authorities

- [Game specification](specification.md)
- [Live configuration](../config/balance/B2_1.json)
- [Deterministic execution](deterministic-execution.md)
- [Engine interface](engine-interface.md)
