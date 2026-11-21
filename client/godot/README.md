# EQUILIBRIUM graphical client

A landscape, touch-first Godot client for the authoritative EQUILIBRIUM server. It is a separate Godot project. It shares no `res://` code with the root project and talks to the server only through protocol v1, as JSON over WebSocket. The look (isometric buildings, paper panels, HUD badges) carries over from the earlier EQUILIBRIUM Android UI.

## Run

```sh
# 1. Server (root project, unchanged)
godot --headless --path . --script server/main.gd -- --bind 0.0.0.0 --port 9080 --seed 42 --stop-file /tmp/eq.stop

# 2. Client, on this computer
godot --path client/godot

# 3. Android build (needs export templates and the Android SDK)
godot --headless --path client/godot --export-debug Android outputs/equilibrium-client.apk
```

In the client, enter the server address: `ws://127.0.0.1:9080` on this computer, `ws://<LAN IP>:9080` from a phone on the same network, or `ws://10.0.2.2:9080` from the Android emulator. Then:

1. The host taps **Create game**, gets a join code and taps **I'm ready**.
2. Other players tap **Join** with the code, then **I'm ready**.
3. The host taps **Start match**. Empty seats become bots, everyone drafts a Foundation in the server's order, and the city screen opens when the match starts.

The server hosts one lobby per process; restart it for another match. To stop it, `touch` the stop file.

## How it works

```
touch → screen (scripts/app.gd, scripts/ui/*) → Session.act / intent methods
      → Link (scripts/net/link.gd): WebSocket, hello/welcome, correlation ids, RTT
      → server validates and executes → action_ack (admission, execution), player_view every tick
      → Session (scripts/state/session.gd): newest view_seq wins, receipts update actions
      → screens redraw from Session only
```

- **Link**: the socket, the handshake, `correlation_id`s and round-trip/jitter measurement (shown as `LIVE nn ms`). It also turns Godot's float JSON numbers back into integers.
- **Session**: the client's only state, built from server messages: seat, lobby, draft, latest `player_view`, and every action's status (`sending → queued → applied/rejected`). An action is never shown as done before its execution receipt. Rejoin credentials are written to `user://session.cfg` the moment `seat_assigned` arrives. They are never displayed or logged. If the connection drops during the draft or play, the view is marked STALE, actions pause, and Session rejoins every 3 s with the saved credential. Resuming the app on Android also triggers a rejoin.
- **Presentation** (`scripts/presentation/catalogue.gd`): names, plain-language roles, sprite mapping, error wording and number formatting. Protocol v1 has no catalogue message, so costs, build times, unlock thresholds, Foundation packages, the announced event schedule and market price bands come from `data/catalogue.json`. `tools/export_catalogue.py` exports that file from `config/balance/B1.json` and records B1's SHA-256, and the test fails if they drift. The client only displays these numbers; the server decides every action.
- **Screens**: the menu, lobby, draft and results live in `app.gd`. The city screen is `ui/play.gd`, kept to plain numbers with no reports:
  - **Top left:** Satisfaction %, residents and rank, then six need counters: Homes, Jobs, Power and Services as have/need, Street waste, and Environment %. A counter turns red when short; tap it to see what to build.
  - **Top right:** cash, recovered materials and time left.
  - **On the map:** a bubble over each building shows what it lacks: a road, power, workers, money, waste collection, or that it is switched off.
  - **Bottom:** a build bar (drag a building up onto the map), Roads, Trade, Rivals, and the Reduce Waste policy. Tapping a building opens a small card.
- **Open map and roads** (`presentation/city_layout.gd`, `ui/city_map.gd`, `ui/traffic.gd`): the city is an isometric landscape with a winding river, floodplain and woods. One **main road** crosses it, bridging the river, and it cannot be removed.
  - **Roads:** with **Roads → Draw**, drag on the map to lay roads; **Erase** removes them. Roads are free, and a road not joined to the main road shows red.
  - **Placement:** drag a building from **Build** anywhere on open land (each one reserves a 4×4 site, room for its Level 2), or tap **Place** and drag its ghost. The client sends the engine one of its 36 free site numbers.
  - **Saving:** the design is saved on the device per match and seat. A building with no spot on this device (a Foundation building, or a match continued from another phone) is placed beside the main road.
  - **Road rule:** a building works only when it touches a road joined to the main road. Once a building is finished without a connection, the client sends the engine's real `disable` command; when a road connects it, the client sends `enable`. So the engine really stops counting it. Unconnected buildings show grey with a red road bubble.
    - The server itself has no roads, so this rule lives in the client: a modified client could skip it, and the engine's bot cities do not follow it.
    - A switched-off building also pays no upkeep, as in the engine.
  - **Traffic:** cars follow the real population and working workplaces, queue behind each other and wait at junctions, so busy roads jam. Traffic itself changes nothing in the game.
  - **Tests:** `tests/road_rule.gd` checks the map rules and, against a real server, that an unconnected building is switched off by the engine and switched back on once a road reaches it.

## Audit: earlier UI against the final engine

| Element of the earlier UI | Verdict | Now |
|---|---|---|
| Isometric sprites, palette, paper panels, HUD badges, fonts (`ui.gd`, `art.gd`, art bundle) | **Keep** | Reused unchanged; Recovery Hub art added |
| City map: open terrain, river, forests, roads, traffic | **Adapt** | Open map with a fixed main road and player-drawn roads; buildings go anywhere; the road rule is enforced through the engine's disable/enable |
| Power range, S/M/L footprints, rotation, roads as a rule | **Remove** | The final engine has 36 one-building sites, no roads or power range |
| Building drawer and drag placement | **Adapt** | Drag one of the 11 final buildings anywhere onto open land (`construct` with a free `tile`) |
| 12 buildings × S/M/L | **Replace** | 11 final buildings × 2 levels; Level 1 uses the S sprite, Level 2 the M sprite |
| Plan queue, End Round, actions per round, round countdown | **Remove** | Real-time: 1,200 one-second server ticks, at most 2 construction slots |
| Attractiveness (6 parts), cards, events per stage, floods | **Remove** | Satisfaction (5 parts), Development, 4 announced crises, no cards |
| Recycling credits / biogas (our earlier waste chain) | **Replace** | The engine's own collection → sorting → recycling / biogas / landfill, recovered materials and policy |
| Contracts by proposal and counteroffer | **Replace** | The real marketplace: request quotes, quote, publish, accept, withdraw, renew, cancel |
| HTTP polling, rooms with 5-letter codes | **Replace** | WebSocket protocol v1, the server's join code, ready/start, rejoin tokens |
| Region view | **Adapt** | Rivals: public rankings, Satisfaction, Environment, Development |
| Results screen | **Adapt** | Final rankings and winners from `match_finished`, plus your circular-economy totals |
| Upgrade / switch off / switch on / demolish / cancel project, Reduce Waste policy, crisis timeline, live/stale and latency indicator | **Add** | New |

## Tests

```sh
# real server on 9080, fresh process
godot --headless --path client/godot --script res://tests/two_players.gd -- ws://127.0.0.1:9080
# windowed: screenshots of every screen (needs a fresh server and a display)
godot --path client/godot --script res://tests/capture.gd -- ws://127.0.0.1:9080 /tmp/shots 1170x540
```

`two_players.gd` runs two client sessions through the real server and makes 19 checks. They cover:

- B1 hash, create and join, the not-ready start refusal, and the draft with an out-of-turn attempt.
- Both players reaching gameplay, with each view limited to the player's own city.
- A construction with its admission and execution receipts, and an occupied-tile rejection with its reason.
- A market request, seat isolation, and a dropped connection followed by an automatic rejoin of the same seat.

`capture.gd` saves the menu, lobby, draft, city, build list, building panel, Waste & Power, Market, Rivals, Events and results screens. The results screen uses a labelled test fixture, because a real final result takes 20 minutes.

## Limitations

- **Godot version:** built and tested with Godot 4.7.2; the project declares 4.5 features and uses no newer APIs, but it has not been opened in 4.5.1.
- **Android:** the APK exports (package `com.equilibrium.client`, INTERNET permission). It has **not** been installed or launched on a device or emulator.
- **No preview or catalogue messages:** protocol v1 has neither, so the client cannot preview an action. Affordability hints come from the B1 display copy; the server's receipt is the final word.
- **Not exercised end to end:** a full 20-minute match, a completed trade between two humans, and network play over LAN or 5G.
- **Join codes:** the server's are 16 hexadecimal characters. Sharing by copy and paste works; typing one is long.
