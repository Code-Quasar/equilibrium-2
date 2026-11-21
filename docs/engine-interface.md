# Engine interface

## Direct match API

Instantiate `simulation/match.gd` and use these production methods:

```gdscript
initialize(match_id: String, seed_value: int, foundations: Array) -> String
submit(raw: Variant, authenticated_player: int) -> Dictionary
preview(player_id: int, kind: String, payload: Dictionary) -> String
step(validate_each_phase: bool = true) -> Dictionary
snapshot() -> Dictionary
serialize() -> String
```

`initialize` requires four valid Foundation identifiers. It returns an empty string on success or an error identifier. `submit` queues a validated command envelope. `preview` validates a copy and never reserves resources or guarantees later execution. `step` advances exactly one second. `snapshot` returns a deep copy. `serialize` returns the canonical deterministic payload.

Use `simulation/interfaces/lifecycle.gd` when unique-Foundation drafting is required before match initialization. Draft commands use `select_foundation` with a single `foundation` string payload.

## Match envelopes and payloads

Envelope keys are `match_id`, `player_id`, `command_seq`, `command_id`, `command_type`, `payload` and `server_received_tick`. Payload field counts and types are exact; unrelated fields are rejected.

| Command | Payload |
|---|---|
| `construct` | `building_type`; optional complete-match `tile` from 0–35 |
| `upgrade`, `disable`, `enable`, `demolish`, `cancel_project` | owned `building_id` |
| `set_reduce_waste` | boolean `enabled` |
| `publish_offer` | `type`, `rate`, `price` |
| `request_quotes` | `type`, `rate` |
| `submit_quote` | `type`, `rate`, `price`, `request_id` |
| `withdraw_offer`, `accept_quote`, `renew_contract`, `cancel_contract` | offer or contract `id` |

Service types are `recyclable`, `organic` and `electricity`. Rates and prices are positive integer micro-units constrained by B1 and authoritative need/capacity checks.

## Local JSON-lines adapter

`tools/local_match.gd` hosts `simulation/interfaces/local_protocol.gd`. It reads one JSON object per line from standard input and writes responses prefixed by `@RESULT `. Start it with:

```sh
godot --headless --path . --script tools/local_match.gd -- 42 4
```

Optional arguments are seed, human-seat count (`2`, `3` or `4`) and the literal `admin`. Protocol requests require `v: 1`, a nonnegative integer `id` and an `op` string. Supported operations are `snapshot`, `seat`, `command`, `preview`, `advance`, `replay` and `quit`. JSON numbers must be finite exact integers within ±(2^53−1).

The adapter provides a local integration boundary without multiplayer authentication. It exposes authoritative state, accepts ordinary commands and delegates gameplay rules to the simulation.

## State and compatibility

Snapshots contain match/city state, contracts, offers, events, migration and final results. The local projection adds rankings, next boundaries, capacity details and read-only insights. Canonical serialization additionally contains pending work, RNG and registration metadata.

Schema version `1`, semantic scopes, command identifiers, state keys and canonical ordering are compatibility boundaries. Replays require a compatible engine and B1. There is no general snapshot-restoration or save-migration API.
