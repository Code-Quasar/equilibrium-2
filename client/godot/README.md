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
      → Link (scripts/net/link.gd): WebSocket, hello/welcome (refuses a server whose ruleset differs from the catalogue's), correlation ids, RTT
      → server validates and executes → action_ack (admission, execution), player_view every tick
      → Session (scripts/state/session.gd): newest view_seq wins, receipts update actions
      → screens redraw from Session only
```

- **Link**: the socket, the handshake, `correlation_id`s and round-trip/jitter measurement (shown as `LIVE nn ms`). It also turns Godot's float JSON numbers back into integers.
- **Session**: the client's only state, built from server messages: seat, lobby, draft, latest `player_view`, and every action's status (`sending → queued → applied/rejected`). An action is never shown as done before its execution receipt. Rejoin credentials are written to `user://session.cfg` the moment `seat_assigned` arrives. They are never displayed or logged. If the connection drops during the draft or play, the view is marked STALE, actions pause, and Session rejoins every 3 s with the saved credential. Resuming the app on Android also triggers a rejoin.
- **Presentation** (`scripts/presentation/catalogue.gd`): names, plain-language roles, error wording and number formatting. Protocol v1 has no catalogue message, so prices, build times, capacities, prerequisites, Foundation packages, the crisis schedule and contract prices come from `data/catalogue.json`. `tools/export_catalogue.py` exports that file from `config/balance/B2_1.json` and records its SHA-256, and the test fails if they drift. The client only displays these numbers. Whether a building can start comes from the server: each `player_view` carries the seat's `build_options`, and the build bar shows their reasons ("Needs Collection", "Too costly", …). The server decides every action.
- **Screens**: the menu, lobby, draft and results live in `app.gd`. The city screen is `ui/play.gd`, kept to plain numbers with no reports:
  - **Top left:** Satisfaction %, residents and rank, then six need counters: Homes, Jobs, Power and Services as have/need, Street waste, and Environment %. A counter turns red when short; tap it to see what to build.
  - **Top right:** cash, recovered materials and time left.
  - **On the map:** a bubble over each building shows what it lacks: a road, power, workers, money, waste collection, or that it is switched off.
  - **Bottom:** a build bar with a Small / Medium / Large choice (drag a building up onto the map), Roads, Trade, Rivals, and Waste. Tapping a building opens a card with what its size does, how it is running (workers, power, operating share), and Upgrade, Switch off, Demolish or Cancel.
  - **Waste:** the recovery chain (Collection → Sorting → Recycling / Biogas, Landfill) with what is built and what each stage still needs, the waste waiting at every stage, materials recovered by stage, and selling materials.
  - **Trade:** publish spare electricity, recycling or organic treatment at the fixed price; accept a rival's offer for 1 to 5 minutes with the escrow it holds shown first; follow and cancel your contracts.
- **Open map and roads** (`presentation/city_layout.gd`, `ui/city_map.gd`, `ui/traffic.gd`): the city is an isometric landscape with a winding river, floodplain and woods. One **main road** crosses it, bridging the river, and it cannot be removed.
  - **Roads:** with **Roads → Draw**, drag on the map to lay roads; **Erase** removes them. Roads are free, and a road not joined to the main road shows red.
  - **Placement:** drag a building from **Build** anywhere on open land (each one reserves a 4×4 site, room for its Large size), or tap **Place** and drag its ghost. The client sends the engine one of its 36 free site numbers.
  - **Saving:** the design is saved on the device per match and seat. A building with no spot on this device (a Foundation building, or a match continued from another phone) is placed beside the main road.
  - **Road rule:** a building works only when it touches a road joined to the main road. Once a building is finished without a connection, the client sends the engine's real `disable` command; when a road connects it, the client sends `enable`. So the engine really stops counting it. Unconnected buildings show grey with a red road bubble.
    - The server itself has no roads, so this rule lives in the client: a modified client could skip it, and the engine's bot cities do not follow it.
    - A switched-off building pays the engine's 20 % standby upkeep.
  - **Traffic:** cars follow the real population and working workplaces, queue behind each other and wait at junctions, so busy roads jam. Traffic itself changes nothing in the game.
  - **Tests:** `tests/road_rule.gd` checks the map rules and, against a real server, that an unconnected building is switched off by the engine and switched back on once a road reaches it.

## Art and sound

The game uses Kenney asset packs (www.kenney.nl, CC0 public domain), copied into `assets/kenney/` with their licence files:

| Pack | Used for |
|---|---|
| City Kit Suburban, Commercial, Industrial | Homes, shops, services, factories, power plants, collection, sorting, recycling and biogas |
| City Kit Roads | Every road piece (straights, bends, junctions, ends, bridge) and construction cones |
| Car Kit | Traffic, garbage trucks, bulldozer at the landfill |
| Factory Kit | Conveyors, hoppers and crates (sorting, recycling, landfill) |
| Nature Kit | Forests and parks |
| UI Pack | Buttons, panels, round buttons, Kenney Future fonts |
| Interface Sounds | Button clicks |

- **3D map** (`ui/city_map.gd`): the map is a 3D scene seen through an orthographic isometric camera. `presentation/models.gd` lists which models make up each building at each size (Small, Medium, Large), and road pieces are chosen and turned from their neighbours (`tests/roads_view.gd` renders every road shape from above to check this).
- **Thumbnails** (`ui/thumbs.gd`): build cards and menus use pictures rendered once from the same 3D models.
- **Old art still used:** the HUD badges and the need-bubble icons still come from the earlier art bundle (`assets/art.json`), because the Kenney packs have no matching icons for homes, jobs, power and so on.

## Tests

```sh
# real server on 9080, fresh process
godot --headless --path client/godot --script res://tests/two_players.gd -- ws://127.0.0.1:9080
# windowed: screenshots of every screen (needs a fresh server and a display)
godot --path client/godot --script res://tests/capture.gd -- ws://127.0.0.1:9080 /tmp/shots 1170x540
```

`two_players.gd` runs two client sessions through the real server and makes 21 checks. They cover:

- The display catalogue's hash against the live B2.1 file, create and join, the not-ready start refusal, and the draft with an out-of-turn attempt.
- Both players reaching gameplay, with each view limited to the player's own city.
- A construction with its admission and execution receipts, and an occupied-tile rejection with its reason.
- A market offer, the server's build options in the view, seat isolation, and a dropped connection followed by an automatic rejoin of the same seat.

`capture.gd` saves the menu, lobby, draft, city, build list, placement, roads, building panel, Waste, Trade, Rivals, detail popovers, a rival visit and results screens. Two screens use labelled test fixtures: Trade with a rival's offer and an active contract, and the results, because a real final result takes 20 minutes. `road_rule.gd` (above) and `menu_shots.gd` (menus, How to Play, address validation) need no fixture.

## Limitations

- **Godot version:** Godot 4.7.2, the same version as the server and engine project.
- **Android:** the APK exports (package `com.equilibrium.client`, INTERNET permission). It has **not** been installed or launched on a device or emulator.
- **No catalogue message:** protocol v1 has none, so prices come from the exported B2.1 display copy. Which buildings can start comes from the view's `build_options`, one tick old; the server's receipt is the final word.
- **Not exercised end to end:** a full 20-minute match, a completed trade between two humans, and network play over LAN or 5G.
- **Join codes:** four digits, easy to read out and type. The code field accepts digits only.
