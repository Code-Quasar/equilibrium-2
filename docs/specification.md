# EQUILIBRIUM — Game Specification (B2.1)

This document defines the rules the authoritative engine implements. The live numbers are in [`config/balance/B2_1.json`](../config/balance/B2_1.json); this document names them where they define structure and otherwise refers to the configuration. Where the two disagree, the structure here wins and the configuration must be corrected.

## 1. Match and victory

- Four cities, one per seat. A match is exactly 1,200 one-second ticks; tick `t` advances state over `[t, t+1)` and the final state has `tick = 1200`.
- The region holds exactly 8,000 residents, 2,000 per city at the start. Population changes only through migration.
- The city with the most residents at tick 1,200 wins. Ties break by higher exact Satisfaction, then higher Environment, then more cash. A remaining exact tie shares the rank.
- There are no turns. A city may run at most two construction or upgrade projects at once, with no queue.

## 2. Foundations

Seats draft one unique Foundation each. Human seats choose first, in a seeded random order; bot seats then choose, also in seeded order, from the Foundations left. Each Foundation is only its starting package; there are no ongoing modifiers.

| Foundation | Completed starting buildings | Cash |
|---|---|---:|
| Industrial Legacy | Factory S | 413 |
| Circular Foundation | Collection Center S, Sorting Center S | 393 |
| Energy Pioneer | Renewable Power Plant S | 395 |
| Investment District | none | 660 |

Every city also starts with the baseline homes (section 3), which come first. Starting buildings occupy plots from 0 upward, operate from the first tick and obey every prerequisite rule. They pay upkeep like any other building.

## 3. Units and starting city

Money is in credits, waste and materials in mass units, electricity in E (a capacity, not a stock), pollution in Environment points. Rates are per game minute. The engine stores every non-count quantity as an integer number of micro-units (10⁻⁶) and carries the exact remainder of every per-second conversion, so no fraction of any flow is ever lost.

Every city starts with three completed Medium Residential Districts (2,280 homes for its 2,000 residents), 2,300 service capacity, 1,000 municipal jobs, 100 E municipal generation, municipal demand of `43 + 0.01 × population` E, 40 units/min municipal waste collection, 38 units/min municipal landfill, air burden 3, landfill damage 1, 30 materials and no waste. Taxes are 0.055 credits per resident per minute; municipal upkeep is 31 credits per minute, and the starting homes pay their own 7 each.

Residents are counted at an 8,000-resident scale: housing, job and service capacities are twice the reference figures and per-resident rates (taxes, electricity, household waste) half, so the economy per city is that of the 4,000-resident reference.

## 4. Buildings

There are twelve building types, each in Small, Medium and Large tiers: Residential District, Factory, Commercial District, Public Services Center, Park, Collection Center, Sorting Center, Recycling Center, Biogas Facility, Landfill, Fossil Power Plant and Renewable Power Plant.

A tier's values are totals, not increments: a Medium Collection Center collects 45 units/min, not 23 + 45. Each building occupies one of the city's 36 plots at any tier.

### 4.1 Prerequisites

| Building | Requires a completed, owned |
|---|---|
| Sorting Center | Collection Center |
| Recycling Center | Collection Center and Sorting Center |
| Biogas Facility | Collection Center and Sorting Center |

- Any tier of the required building counts. A building under construction does not, municipal infrastructure does not, and another city's building does not.
- Prerequisites are checked when a command is admitted and again when it executes. A rejected command changes nothing: no credits, materials, plot or project slot.
- Reasons are machine-readable: `requires_collection_center`, `requires_sorting_center`, `prerequisite_under_construction`.
- A disabled prerequisite still counts; it simply stops processing.
- The last completed building of a type cannot be demolished while any building or project that requires it exists (`dependent_buildings_exist`).
- Buying treatment services never satisfies a prerequisite.

### 4.2 Construction lifecycle

- **Construct** any tier directly, on a chosen free plot or the lowest free one. The price is the tier's credits plus its materials; stocked materials are used first, and any shortfall is bought at 6 credits per unit. Everything is paid when the command executes. A project must finish before tick 1,200.
- **Upgrade** Small → Medium → Large at the configured incremental credits, materials and time. The building keeps operating at its current tier until the upgrade completes.
- **Cancel** a project to recover 80% of its credits and all of its material units (into stock). A cancelled construction frees its plot; a cancelled upgrade leaves the building at its current tier.
- **Demolish** a completed building to recover 10% of its tier's credits and no materials. Demolition is rejected if it would leave enabled housing below the current population.
- **Move** a building, finished or not, to any free plot of its city. Only its plot changes: its project, operation and stored remainders stay with it. Plot order still decides priority within a type.
- **Disable** a building to stop its output, demand and jobs from that tick. It pays 20% standby upkeep. Re-enabling is free after a 10-second cooldown.

## 5. Operation each tick

1. **Funding.** Enabled, completed buildings pay full upkeep, Residential Districts first, then in staffing priority order, plot order within a type. A Fossil Power Plant's emission levy is part of its operating cost. A building that cannot pay in full does not operate this tick and pays standby upkeep if it can, like a disabled building.
2. **Electricity.** Supply is municipal generation, funded plants and the biogas power produced last tick. Municipal demand is served first, then building classes in the configured priority (collection, sorting, recycling, biogas, landfill, services, plant auxiliaries, factories, commerce), prorated within a class. A building's power share is delivered ÷ requested. Funded buildings request their full nominal demand even when idle. Surplus is neither stored nor sold except through contracts.
3. **Staffing.** The first `min(population, 1,000)` residents fill municipal jobs. The rest staff funded, powered buildings in staffing priority order, plot order within a type, up to each building's job slots. A building's staff share is workers ÷ slots. Unpowered buildings employ nobody. Residential Districts and Parks have no jobs and need no workers. Power plants generate their rating regardless of staffing.
4. Each building's operating fraction is `min(power share, staff share)`. Output systems scale nameplate capacity by it; feedstock and cash may lower it further.

Taxes cover the municipal upkeep at any population the migration floor allows. Upkeep the treasury cannot pay is recorded as unpaid; the treasury never goes negative.

## 6. Production and materials

- Factories and Commercial Districts earn their gross income scaled by their realized fraction. Their waste and air emissions scale with the same fraction.
- A Factory consumes materials in proportion to output, stocked materials first, buying any shortfall at 6 credits.
- Every emitted air point costs a 2-credit levy.
- A Factory or Commercial District runs at the largest fraction, up to its operating fraction, whose purchases and levy the treasury can pay that second.
- Materials have one inventory, capped at 500 units. Stock above the cap is sold at 2 credits per unit at the end of each tick, and players may sell stock at the same price. Purchased materials are consumed immediately and never stored. Because buying costs 6 and selling pays 2, there is no arbitrage.

## 7. Waste and progressive valorization

Waste is recyclable, organic or residual. Households generate 0.015 units per resident per minute (50/30/20). Factories and Commercial Districts generate per their tier at their own compositions. Each unit always sits in exactly one place: the street, the dedicated mixed buffer (cap 300), a sorted stream (recyclable cap 250, organic cap 250), the disposal queue, or a sink (recovered materials, digested organics, landfill, export).

Each second, in order:

1. **Generate** household waste.
2. **Dedicated collection.** Collection Centers, in plot order, take street waste proportionally by category up to their capacity and the mixed buffer's free room. Each directly salvages its tier's fraction (8%, 10%, 12%) of the recyclable mass it handled into materials. The rest enters the mixed buffer.
3. **Municipal collection** takes up to 40 units/min of what remains on the street into the disposal queue. It recovers nothing and never feeds sorting.
4. **Sorting.** Sorting Centers take mixed waste proportionally and capture recyclables and organics at their tier's rates. They directly reuse a fraction of the captured recyclables (16%, 18%, 20%) as materials, store the rest in the sorted streams, and send missed mass to disposal. Sorted mass beyond a stream's cap goes to disposal, never back to sorting.
5. **Treatment contracts** (section 10) use the seller's treatment capacity first.
6. **Recycling.** Recycling Centers turn sorted recyclables into materials at their tier's yield (80%, 83%, 86%); rejects go to disposal.
7. **Biogas.** Biogas Facilities digest sorted organics. Residue (20%, 18%, 15%) goes to disposal, and the digestion yields `60 × units per second × E coefficient` of electricity next tick only. No feedstock means no biogas power.
8. **Landfill** takes the disposal queue first, then unsorted mixed waste as a bypass. It is limited by 38 units/min of municipal capacity plus funded Landfills, and by the 0.85-credit fee per unit the treasury can pay. Unpaid waste waits.

Recovery accumulates through the stages and is never credited twice. For 100 units of pure recyclable waste through Small facilities:

| Built chain | Recovered materials | Unrecovered |
|---|---:|---:|
| Collection only | 8 | 92 (in the mixed buffer) |
| Collection + Sorting | 8 + 11.776 = 19.776 | 61.824 sorted, 18.4 missed |
| Collection + Sorting + Recycling | 8 + 11.776 + 49.4592 = 69.2352 | 18.4 missed + 12.3648 rejects |

Throughput always remains limited by capacity, staffing, power, funding and the waste actually present.

## 8. Environment

`Environment = clamp(100 − air − landfill damage − pressure + min(4.5, amenity), 0, 100)`.

- **Air** (cap 80) gains this second's emissions and loses 0.12 points/min of natural recovery, then Park cleanup.
- **Landfill damage** (cap 60) gains 0.045 points per landfilled unit. Park cleanup the air no longer needs (air already at 0) repairs it instead, so when a city's Parks outweigh its emissions and landfilling, Environment rises until it reaches 100. Natural recovery never reduces it.
- **Pressure** (cap 45) is recomputed from waste present now: 0.16 × street + 0.045 × mixed buffer + 0.025 × (sorted streams + disposal queue).
- **Amenity** is the sum of operating Parks' amenity, scaled by their operating fraction.

## 9. Satisfaction and migration

`Satisfaction = 0.35 × Environment + 20 × min(1, employed/P) + 15 × min(1, housing/(1.15 P)) + 15 × reliability + 15 × min(1, services/(1.15 P))`, clamped to 0–100.

- Housing counts funded Residential Districts, including the starting homes.
- Services count the municipal baseline, scaled by its staffing and power, plus operating service buildings.
- Reliability is domestic power delivered over power requested.
- The same exact value drives migration. It is first computed at the end of tick 0.

**Migration** happens after the ticks ending at 80, 100, …, 1,180 (56 pulses, none at 1,200), using a frozen post-tick snapshot:

- Every ordered pair whose Satisfaction gap exceeds 0.75 proposes `floor(8 × (gap − 0.75))` movers.
- Pairs are served by decreasing gap, then destination, then source.
- Each city sends at most 60 and receives at most 150 per pulse. A sender keeps at least 700 residents, and a receiver accepts only up to its free housing.
- A resident moves at most once per pulse; the region always holds 8,000.

## 10. Marketplace

Cities may trade electricity, recyclable treatment and organic treatment at fixed prices: 0.22 credits per E-minute, 0.75 and 0.70 credits per waste unit.

- **Offers.** A seller publishes a rate, at most 40 E for electricity and at most 3 open offers per city. The rate cannot exceed the spare capacity the seller demonstrated in the previous tick, net of its own needs and existing contracts.
- **Acceptance.** A buyer accepts an offer for 60–300 s (default 120), with at most 2 active contracts and one live contract per seller and service. The contract must end by tick 1,200. The buyer's escrow pre-authorizes the maximum fee.
- **Delivery.** Each second only real delivery is paid from escrow:
  - Electricity flows after the seller's municipal demand and before its optional loads, up to the buyer's actual deficit.
  - The buyer exports only sorted stock beyond its own treatment capacity that second. The seller treats it immediately with its own plants, before its own stock, and keeps the materials, biogas power and rejects.
  - Imports are never stored, so nothing can be re-exported.
- **Closing.** Either party may cancel at any time. Expiry and cancellation release the unused escrow.
- Cash and mass transfers are conserved exactly between cities.

## 11. Regional crises

| Crisis | Announced | Active | Effect on new flows |
|---|---:|---|---|
| Smog Alert | 255 | [300, 390) | emissions ×1.5, natural air recovery ×0.5 |
| Waste Surge | 555 | [600, 690) | household ×1.5, factory ×1.25, commercial ×1.2 waste |
| Power Shortage | 855 | [900, 990) | municipal generation ×0.55 |
| EQUILIBRIUM 2050 | 1,140 | none | final-result theme only |

Stocks a crisis created persist after it ends.

## 12. ECO EMERGENCIES

Three short competitive recycling challenges per match, one for each stage of the chain. The configuration's `emergencies` section holds every number below; `enabled: false` removes them and leaves the match exactly as without them.

| Event | Stage | Challenge | Winner's boost |
|---|---|---|---|
| `collection_crisis` | Collection | Route each item on a conveyor to its bin | Collection Surge: Collection Center rate ×1.3 |
| `sorting_overload` | Sorting | Slice flying recyclables; avoid contaminated and hazardous items | Precision Boost: Sorting Center rate ×1.3 |
| `recycling_breakdown` | Recycling | Keep a shredder → filter → press line running | Recovery Surge: Recycling Center rate ×1.3 |

**Schedule.** At match creation the server draws, from the match seed, an order of the three types and one start tick in each window: [210, 270], [510, 570], [810, 870]. Each event runs announcement (2 s), joining (6 s), countdown (3 s), play (25 s), then results (5 s); the configuration rejects windows that could overlap or run past the match. The city simulation never pauses.

**Taking part.** Every player sees the announcement and may respond or carry on with the city; declining costs nothing. A player may also join late, during play, and enters at the current time. Only participants may act and be ranked.

**One challenge for all.** Every item, flight path and fault comes from the event's seed, so all four players face the same challenge at the same times, independent of their city, device or connection. The view carries the challenge from the announcement to the end of the results. Each round has three phases (by default 0–7 s, 7–16 s, 16–25 s; 0–6, 6–15, 15–25 s for recycling):

- **Routing:** single items far apart, then a faster belt with occasional close pairs, then the fastest belt with pairs and bursts of three. Items are never closer than 450 ms (a finger apart), and no item follows one of the same kind.
- **Slicing:** a pattern director throws seeded patterns — solo, double toss and high arc from the start; recyclable burst, hazard mix and crossfire from the middle phase; speed burst and precision gap in the finale — never the same pattern twice in a row, and each new phase opens with a hazard mix. Every item to avoid keeps at least 160 field units from every recyclable in flight while both are on screen (a later recyclable steps aside; an item that cannot be placed is left out), so a careful swipe can always avoid it. The first phase has nothing to avoid.
- **Recycling line:** each player runs the same deterministic line model (`simulation/systems/plant_model.gd`, shared byte for byte with the client) in 100 ms steps. Shredder jams stop its output; a 1 s buffer then drains and the line starves. Filter pressure rises (faster each phase) and surges; above the green band (600‰) efficiency falls, and at the top the filter blocks for 2 s. Press alignment drifts; efficiency falls with the offset. Line efficiency = min(shredder supply, filter, press).

**Actions and validation.** Players send actions, never scores or efficiencies: `emergency_route {event, item, bin, t_ms}`, `emergency_slice {event, item, t_ms, x1, y1, x2, y2}` (a swipe segment on the 1000 × 1000 field) and `emergency_repair {event, machine, answer, t_ms}` (shredder: direction × 1000 + pulled distance, which must match the jam's direction and reach its release distance; filter: valve 0, 1 or 2, releasing 150, 300 or 550‰; press: a tap, right when the fixed oscillating marker is inside the safe band, ±90‰ narrowing to ±65‰), plus `emergency_join {event}`. The server advances the player's line to the action's time and applies it there; actions cannot go back before what it already simulated, and an intervention with nothing to fix is refused without effect. The server rejects unknown events, events not in play, non-participants, unknown items, items already handled, impossible choices, swipes that do not cross the object at that time, and more than 12 actions per player per second. Repeated action ids return the original receipt and never act twice.

**Time.** `t_ms` is milliseconds since play started. The server accepts it only between 1,500 ms before and 250 ms after the second in which it received the action, within the item's own window. The same bound applies to every player; arrival order never decides anything.

**Scoring.** Never below zero; missed items score nothing.

| Challenge | Right | Wrong | Hazard | Streak bonus |
|---|---:|---:|---:|---|
| Routing | +10 | −10 | — | +25 every 5 in a row |
| Slicing | +10 | −15 (contaminated) | −25 | +25 every 5 in a row |
| Recycling line | +15 per repair | −10 (wrong direction or short pull is not counted as a repair; overcorrecting a valve below 150‰, or missing the press band) | — | +20 for every 5 s in a row above 90 % line efficiency |

The recycling score also earns 10 points a second at full line efficiency (the line's efficiency integrated over the round), so keeping the line running matters more than the number of repairs. A large valve, or overcorrecting, halves the filter's throughput for 1.2 s; a valve that relieves pressure but leaves it above the green band helps and scores nothing.

**Result.** At the tick play ends, participants are ranked by score, then fewest wrong actions, then most right actions, then seat. The top player wins if their score is above zero; otherwise nobody does.

**Boost.** The winner's stage rate is multiplied for 90 ticks from the next tick. It acts only inside that stage's own rate: it creates no waste or materials, needs operating buildings of that stage (a city without them gains nothing), and keeps every cap, staffing and power rule. A new boost of the same stage replaces the old one; boosts never stack. A shared meter counts all players' right actions; it is information only.

## 13. Tick order

```text
begin                  crisis state for [t, t+1); per-tick ledgers reset
construction           projects due at t complete and operate from t
commands               ordered by receipt tick, seed-rotated seat, sequence; each atomic
emergencies            results frozen and boosts awarded at the end of play; expired boosts dropped
municipal_budget       taxes, then municipal upkeep
funding                upkeep and fossil levy: homes, then staffing priority order
power_generation       own generation (incl. last tick's biogas) and requests
power_contracts        electricity deliveries and payments
power_allocation       municipal first, then priority classes
staffing               municipal jobs, then buildings
production             factories and commerce: inputs, levy, income, waste
collection_and_sorting household waste, collection, municipal fleet, sorting, budgets
treatment_contracts    contracted recyclable and organic treatment
local_treatment        recycling and biogas on local stock
landfill               disposal queue, then unsorted bypass, within fees
material_overflow      stock above 500 sold
environment            air, landfill damage, pressure, amenity
satisfaction           capacities and Satisfaction
migration              at ticks ending 80, 100, ..., 1180
contract_expiry        contracts ending at t+1 close and release escrow
advance_time           t+1; at 1200 the final result is frozen
```

## 14. Invariants

After every phase:

- Population totals 8,000 and every city keeps at least 700 residents.
- Cash, available cash, materials and every inventory are non-negative.
- Every city's cash ledger and material ledger reconcile.
- Every city's waste mass reconciles: generated + imported = held + recovered + digested + landfilled + exported.
- Electricity reconciles, and exports never exceed own generation.
- Inventories respect their caps; materials respect theirs at the end of each tick.
- Every building has its prerequisites. Plots are unique, there are at most two projects, and every project matches its building.
- Contract cash and mass transfers are conserved. Escrow equals the maximum fee less payments while active, and nothing once closed.

- Emergency scores are non-negative and only participants have any; each player holds at most one boost per stage, lasting exactly the configured time.

A tick that breaks an invariant is rejected whole.
