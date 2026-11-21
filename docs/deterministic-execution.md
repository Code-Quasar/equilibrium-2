# Deterministic execution

The simulation advances in explicit one-second ticks, independent of wall-clock time, scenes, rendering and network transport. Authoritative money, material, waste, power and score quantities are integers using the B1 micro-unit scale; population, IDs and ticks are integers.

## Commands and transactions

Every match command contains `match_id`, `player_id`, `command_seq`, `command_id`, `command_type`, `payload` and `server_received_tick`. The authenticated player is supplied separately. Commands sort by receipt tick, seed-rotated player order and sequence.

Submission validates envelope shape and identity, then queues a copy. Execution revalidates game conditions against earlier commands in the same tick. Duplicate IDs are idempotent only when their identity matches; sequence conflicts and stale sequences are rejected. A rejected gameplay command records its result without leaking partial state or RNG changes.

Each tick runs against deep-copied state and RNG. A phase error rejects the entire tick, leaving authoritative state, pending commands and RNG untouched. Successful publication atomically commits the candidate.

## Phase order

The semantic phase list lives in `simulation/core/pipeline.gd`. In summary, a tick applies event boundaries and construction completion; executes commands; resolves municipal finance, reservations, facility funding, workforce, power, production, waste collection and treatment; updates environment and scores; performs scheduled migration; closes contracts; advances time; validates and publishes.

Observable ordering is binding. In particular, maintenance is paid before output, electricity contracts settle against realized supply, biogas processed this tick becomes available next tick, migration uses the common post-tick score snapshot, and contracts use half-open `[start_tick, end_tick)` delivery.

## Arithmetic and randomness

Rate conversion retains integer carry residues. Do not replace floor, ceiling or fixed-point boundaries with floating-point approximations. Migration uses its separately versioned Q12 exponential approximation.

The explicit Park–Miller RNG starts from the supplied seed and uses rejection sampling for bounded draws. Drafting consumes this RNG; fixed events do not. Projections and snapshots consume no randomness.

## Canonical serialization

The canonical encoder supports null, booleans, integers, strings, arrays and string-keyed dictionaries. Dictionary keys sort lexicographically and arrays retain order; floats are rejected. Serialization includes full state, pending commands, RNG algorithm/state, the B1 snapshot, system manifest, registered command types and start status.

Carries, queues, reservations, ledgers and RNG state affect future execution and cannot be omitted from equivalence checks. Replay tests reconstruct matches from commands and compare complete canonical output after 1,200 ticks. Arbitrary saved-state loading is not a supported interface.

The exact tick contract and invariants remain normative in sections 19–20 of the [specification](EQUILIBRIUM_SPEC_v1.0.md).
