# Engine interface

## Match API

Instantiate `simulation/match.gd`:

```gdscript
initialize(match_id: String, seed_value: int, foundations: Array) -> String
submit(raw: Variant, authenticated_player: int) -> Dictionary
preview(player_id: int, kind: String, payload: Dictionary) -> String
build_options(player_id: int) -> Dictionary
step(validate_each_phase: bool = true) -> Dictionary
snapshot() -> Dictionary
serialize() -> String
```

- `initialize` takes four unique Foundation identifiers in seat order and returns `""` or an error.
- `submit` queues a validated envelope and returns `{"status": "queued"}` or a rejection.
- `preview` checks a command against a copy of the current state; it neither reserves anything nor guarantees later execution.
- `build_options` reports, for every building type and size, `""` if it can be started now or the reason it cannot, such as `requires_sorting_center` or `insufficient_funds`.
- `step` advances one second and returns each queued command's result.
- `snapshot` returns a deep copy, and `serialize` the canonical payload.

`simulation/interfaces/lifecycle.gd` runs the unique Foundation draft first. Draft commands are `select_foundation` with a `foundation` payload; the fourth pick creates the match.

## Commands

Payload fields and types are exact; unknown fields are rejected. Quantities are integer micro-units.

| Command | Payload |
|---|---|
| `construct` | `building_type`, `size` (`S`, `M`, `L`), optional `tile` 0–35 |
| `upgrade`, `cancel_project`, `demolish`, `disable`, `enable` | `building_id` |
| `sell_materials` | `amount` |
| `publish_offer` | `type` (`electricity`, `recyclable`, `organic`), `rate` |
| `accept_offer` | `id`, optional `duration` in seconds (default 120) |
| `withdraw_offer`, `cancel_contract` | `id` |

Rejections are lowercase identifiers. Some examples: `requires_collection_center`, `requires_sorting_center`, `prerequisite_under_construction`, `dependent_buildings_exist`, `housing_below_population`, `construction_slots_full`, `not_enough_time`, `insufficient_funds`, `insufficient_seller_capacity`, `contract_limit`.

## State

A snapshot holds the match identity, tick and status, the current crisis state, the four cities, the market, the migration record and the final result. Each city holds:

- population, cash, materials and their ledgers;
- the waste inventories and per-tick and cumulative flows;
- buildings with their operating record for the tick, and projects;
- power, employment, capacities, Environment terms and Satisfaction components.

The online server sends each seat only `projections/player_view.gd`'s allowlisted view, including its `build_options`.

The configuration, state keys, command identifiers and phase list are compatibility boundaries for replays. There is no save-migration or arbitrary state-loading interface.
