# Authoritative online server

The root Godot 4.7.2 project hosts one private lobby/match per process. One to four human WebSocket clients own distinct seats. When the ready host starts, empty seats become deterministic server bots. All four seats draft through the existing lifecycle; every action uses the existing engine envelope and validator.

## Run

From the repository root:

```sh
godot --headless --path . --log-file /tmp/equilibrium-server.log --script server/main.gd -- --bind 127.0.0.1 --port 9080 --seed 42 --stop-file /tmp/equilibrium-server.stop
```

Choose a stop-file path that does not already exist. Create it to request graceful shutdown:

```sh
touch /tmp/equilibrium-server.stop
```

The stop file is a local operator control, never a network message. Remove an old stop file before a subsequent run. The listener address and port are configurable; use a LAN interface or `0.0.0.0` only when intentionally exposing it. WS loopback is tested. WSS requires an external TLS endpoint; LAN, Android and cross-network internet operation have not been tested.

See the [terminal client](../client/terminal/README.md) and [protocol artifacts](../shared/README.md).

## Ownership and timing

A single event loop drains input before stepping due ticks. `Time.get_ticks_msec()` supplies the monotonic clock. Ticks retain their one-second economic meaning. At most four overdue ticks run per iteration; remaining debt is retained. No client can advance time. A failed engine tick stops the session and reports failure. At tick 1200 the scheduler stops and final results are published.

Before start, a disconnected player releases its seat and credential. The lowest connected occupied seat becomes host; the last departure closes the lobby. During play, seats remain reserved and the human is never replaced by a bot. During drafting, a disconnected human has 30 seconds to rejoin by default; expiry cancels and cleans the incomplete draft and invalidates its credentials. The operator may set `--draft-grace-ms MILLISECONDS` to a value of at least 100.

Rejoin credentials expire after two hours, rotate on rejoin, and revoke the former socket. Rejoin sends the current view/draft plus receipts for the latest 64 actions; retry an older identical action to retrieve its retained receipts. At most 4096 distinct actions are retained per seat for the session. There is no process-crash persistence.

Bots follow `bot_controller.gd`'s fixed plan: one Small construction every 90 ticks, in an order that respects the Collection → Sorting → Recycling/Biogas prerequisites, submitted only if the engine preview permits it. They are minimal opponents, not competitive AI. Bots receive no grants and never control human seats.

## ECO EMERGENCIES developer mode

To try the three emergencies without waiting for their windows, start a server with a fixed schedule (start ticks; the draft takes the first seconds):

```sh
godot --headless --path . --script server/main.gd -- --port 9080 --dev-emergencies collection_crisis@25,sorting_overload@75,recycling_breakdown@125
```

`--dev-cash N` adds N credits to every city's starting cash, for demos and recordings. Both are operator command-line options only, never network messages, so no player can trigger them. Views then carry `public.developer_mode = true` (clients label it). The server's output logs every emergency phase change with the authoritative scores, result and boosts, for example `EMERGENCY tick=62 em1 collection_crisis results scores=[330, 0, 0, 0] ...`. Bots do not take part in emergencies.

## Checks

```sh
godot --headless --path . --log-file /tmp/equilibrium-online-tests.log --script tests/integration/online_foundation.gd
python3 tools/check_repository.py
```

After installing the terminal requirements in a virtual environment, run real socket cases separately (set `GODOT` if the executable is not on `PATH`):

```sh
python tests/integration/network_authority.py --humans 2
python tests/integration/network_authority.py --humans 1
python tests/integration/network_authority.py --humans 3
python tests/integration/network_authority.py --humans 4
python tests/integration/network_authority.py --humans 0
python tests/integration/network_authority.py --marketplace
python tests/integration/network_authority.py --draft-disconnect
python tests/integration/network_authority.py --terminal
```

`--humans 0` selects transport/host-departure edge tests; it is not a supported zero-human lobby. Each case launches a real server, creates independent WebSocket connections and requests graceful shutdown. It fails nonzero on assertion, timeout, server script error or abnormal shutdown.

`--terminal` launches the actual terminal program with piped input, exercises lobby creation, readiness, drafting and a construction action, checks private credential-file permissions and verifies clean exit with stdin still open.

The complete injected-clock test is separate and may take longer than 30 seconds. It executes all 1200 real engine ticks without waiting for wall-clock seconds:

```sh
godot --headless --path . --log-file /tmp/equilibrium-online-completion.log --script tests/integration/online_completion.gd
```

## Limitations

The server hosts one lobby and one match per process, and a completed match requires a process restart before another lobby can be hosted. Bots provide basic deterministic opposition rather than competitive play. There are no user accounts or process-crash recovery.

Loopback WebSocket operation is covered by the fixtures above. LAN, WSS, Android and independent-network operation have not been validated. Full-duration matches over continuously connected WebSocket clients have also not been validated.
