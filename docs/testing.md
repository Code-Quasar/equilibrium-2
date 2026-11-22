# Testing

Use Godot 4.7.2 from the repository root.

## Complete suite

```sh
godot --headless --path . --script tests/run_all.gd
```

Each suite runs in its own Godot process; a nonzero exit, a script or parse error, or a `FAIL` line fails the run. After the suites, `tests/replay/scenario.gd` plays a scripted 1,200-tick match twice, with reversed command submission, and the two canonical serializations must be byte-identical.

| Suite | Covers |
|---|---|
| `tests/rules/config_test.gd` | Every B2.1 number against an independent transcription of the catalogue; rejection of malformed or inconsistent configurations |
| `tests/rules/construction_test.gd` | Foundations and starting homes, the Collection → Sorting → Recycling/Biogas prerequisites, S/M/L prices and totals, upgrades (production continues until the new tier takes over), cancellation, demolition, disabling, moving, rejected commands leaving no trace |
| `tests/rules/waste_test.gd` | The exact 8 → 19.776 → 69.2352 reference chain, the 2,000-resident minute, partial operation, caps, municipal isolation, biogas timing, landfill fees and order |
| `tests/rules/economy_test.gd` | Taxes and upkeep, homes funded first, factory inputs and affordability, staffing (Parks need no workers), electricity priority, Environment (Parks repair landfill damage once the air is clean), Satisfaction, crises, material sales |
| `tests/rules/migration_test.gd` | The pairwise rule, its limits, the schedule and the final ranking |
| `tests/rules/market_test.gd` | Offers, escrow, real-delivery payments, limits, cancellation, expiry, waste treatment between two chains |
| `tests/rules/emergencies_test.gd` | ECO EMERGENCIES: schedule (types, windows, no overlap, seeded order, injection), lifecycle and late joins; belt phases and spacing; the pattern director's determinism, variety (four or more families a round, all eight across matches), play area, avoidable hazards and clean first phase; the recycling line model (each machine, overcorrection, timing, bottleneck, no farming) and its balance (a skilled player above 85 % line efficiency, an idle one collapsing); every rejection, ranking ties, the boost's player, stage, exact duration and expiry, no free materials or bypass, no stacking, identical cities when nobody plays, deterministic replay, three events in a full match |
| `tests/integration/online_foundation.gd` | Protocol and schema agreement, occupancy with humans drafting before bots, determinism, view privacy, draft disconnects |
| `tests/integration/online_emergencies.gd` | ECO EMERGENCIES through the server with four humans: the same event and challenge for everyone, join and decline, server scores, no score submission, duplicate actions, late join, disconnect and rejoin, winner and boost in every view |
| `tests/integration/online_completion.gd` | A full 1,200-tick match through the server application on an injected clock |

Every engine step in these suites validates all invariants after every phase. Run one suite with `godot --headless --path . --script tests/rules/waste_test.gd`.

## Static check

```sh
python3 tools/check_repository.py
```

This checks resource paths, dependency boundaries, `.gd.uid` pairing, documentation links and the shape of the B2.1 configuration. It uses only the Python standard library.

## Real sockets

`tests/integration/network_authority.py` launches a real server and drives it over WebSockets: `--humans 1..4`, `--humans 0` (transport edges), `--marketplace`, `--draft-disconnect` and `--terminal`. It needs the pinned `websockets` package from `client/terminal/requirements.txt`. Set `GODOT` if the Godot executable is not on `PATH`.
