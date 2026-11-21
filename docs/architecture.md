# Architecture

EQUILIBRIUM is a headless Godot simulation. Production code has no dependency on scenes, rendering, tests or tools.

## Composition

`simulation/match.gd` extends the transactional core engine and composes the complete match:

- `core/` owns balance loading, state, fixed-point arithmetic, seeded randomness, command envelopes, ordered phases, invariants and canonical serialization.
- `systems/` owns buildings, finance, municipal/local/regional economy, power, waste, environment, marketplace, events and migration.
- `interfaces/` owns deterministic Foundation drafting, local sessions and a JSON-lines adapter.
- `projections/` contains read-only insights derived from snapshots.

Systems register command handlers and phase callbacks during initialization. The engine supplies a candidate state for each tick; only a fully validated tick replaces authoritative state. The pipeline and registered semantic system IDs are serialized, so ordering is part of deterministic compatibility.

## State and ownership

The match owns identity, tick, seed, RNG state, pending commands, city state, ledgers, contracts, events and final results. Each city owns buildings, projects, finance, capacities, resource inventories, environmental stocks and Development peaks. Shared market and migration records use stable integer IDs and ordered arrays.

Buildings own placement, project lifecycle and completion. Finance owns funding and reservations. Economy coordinates staffing and production. Power, waste and environment own their respective transformations. Market owns offers, commitments, settlement and closure. Migration owns conservative regional population movement.

## Dependency boundaries

Production may depend only on other files under `simulation/` and the live B1 configuration. Tests reuse production systems but never become production dependencies. Tools are adapters or static checks; they contain no authoritative rules.

New transports should use the existing lifecycle, command and snapshot boundaries. New gameplay behavior requires an approved specification/configuration change plus invariant and replay coverage. Avoid alternate rules implementations in clients, projections or test harnesses.

## Authorities

- [Structural specification](EQUILIBRIUM_SPEC_v1.0.md)
- [Live numerical configuration](../config/balance/B1.json)
- [Deterministic execution](deterministic-execution.md)
- [Engine interface](engine-interface.md)
