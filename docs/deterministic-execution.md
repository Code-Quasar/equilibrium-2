# Deterministic execution

The simulation advances in explicit one-second ticks, independent of wall-clock time, scenes, rendering and network transport. Every authoritative quantity is an integer: money, materials, waste, electricity, pollution and scores in micro-units (10⁻⁶), and population, plots, IDs and ticks as counts.

## Commands and transactions

A command envelope holds `match_id`, `player_id`, `command_seq`, `command_id`, `command_type`, `payload` and `server_received_tick`; the authenticated seat is supplied separately. Commands in a tick are ordered by receipt tick, then seed-rotated seat, then sequence.

Submission validates the envelope and queues a copy. Duplicate IDs are idempotent only when their content matches, and sequence conflicts and stale sequences are rejected. Execution revalidates every command against the state left by the commands before it. A rejected command records its reason and leaves the state exactly as it was.

Each tick runs on a deep copy. If any phase fails or breaks an invariant, the whole tick is rejected and the authoritative state and pending commands are untouched.

## Phase order

The phase list in `simulation/match.gd` is binding and is part of the canonical serialization. [Specification §12](specification.md#12-tick-order) lists it. In particular:

- upkeep is paid before anything operates;
- electricity contracts settle against real supply and deficit before allocation;
- biogas processed in one tick powers only the next;
- each waste stage takes only mass the previous stage released;
- migration reads one frozen post-tick snapshot;
- contracts deliver over `[start_tick, end_tick)`.

## Arithmetic

Per-minute rates become per-second amounts with the exact remainder carried for each building and flow, so cumulative flows are exact. Products use overflow-safe integer arithmetic, and proportional splits use largest remainders with ties to the earliest index. Rounding points are deliberate: purchases and contract charges round up, sales round down, and fees carry their remainder. Do not replace them with floating-point approximations.

Ticks consume no randomness. The seeded Park–Miller RNG is used only to order the Foundation draft.

## Canonical serialization

The canonical encoder supports null, booleans, integers, strings, arrays and string-keyed dictionaries; keys are sorted and floats are rejected. `serialize()` covers the full state, pending commands, the normalized configuration, the phase list and the command types. Carries, escrow and ledgers affect future ticks and are part of equivalence.

The replay test runs a scripted 1,200-tick match in two processes with reversed submission order and requires byte-identical output.
