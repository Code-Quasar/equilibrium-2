# Network terminal client

Python 3.9+ with `websockets==15.0.1`. This client only sends intentions and prints authoritative results.

From the repository root:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r client/terminal/requirements.txt
.venv/bin/python client/terminal/client.py --url ws://127.0.0.1:9080 --create --session-file /tmp/equilibrium-seat0.json
```

The host receives a `lobby_created` message with the join code. Each additional human starts an independent terminal client:

```sh
.venv/bin/python client/terminal/client.py --url ws://127.0.0.1:9080 --join JOIN_CODE --session-file /tmp/equilibrium-seat1.json
```

Use distinct private session files for additional clients. Stop joining after the desired 1, 2, 3 or 4 humans. Every human enters `ready`; the host then enters `start`. Unoccupied seats become bots at that point. `lobby_state` displays controller, readiness and host identity. When `draft_state.turn_seat` matches your seat, choose an identifier from `available_foundations`:

```text
ready
start
foundation circular_foundation
```

The Foundation above is illustrative; choose an available one on your turn. When `match_started` arrives, commands include:

```text
action construct {"building_type":"collection_center","size":"S","tile":6}
action upgrade {"building_id":0}
action publish_offer {"type":"electricity","rate":5000000}
action accept_offer {"id":0,"duration":120}
action sell_materials {"amount":5000000}
```

Quantities are integer micro-units (5 E = 5000000). Affordability, ownership, prerequisites and marketplace capacity remain engine decisions, and each view's `own_city.build_options` says why a building cannot start. Each action prints admission and execution receipts. Views print tick, population, money, materials, Environment and Satisfaction; `--json` prints complete filtered messages. `quit` disconnects without stopping a running match.

To rejoin during draft or gameplay:

```sh
.venv/bin/python client/terminal/client.py --url ws://127.0.0.1:9080 --rejoin --session-file /tmp/equilibrium-seat0.json
```

Credentials are saved with mode 0600 and omitted from terminal output. Treat these files as secrets; do not commit them. A waiting-lobby disconnect releases the seat, so join again instead. During the Foundation draft the seat is reserved for the server's reconnection grace period; if it expires, the incomplete draft is cancelled. Use the real socket integration harness under `tests/integration/network_authority.py` for automated scripted operation.
