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

- **Air** (cap 80) gains this second's emissions and loses 0.12 points/min of natural recovery plus Park cleanup.
- **Landfill damage** (cap 60) gains 0.045 points per landfilled unit and never decays. Parks do not reduce it.
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

## 12. Tick order

```text
begin                  crisis state for [t, t+1); per-tick ledgers reset
construction           projects due at t complete and operate from t
commands               ordered by receipt tick, seed-rotated seat, sequence; each atomic
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

## 13. Invariants

After every phase:

- Population totals 8,000 and every city keeps at least 700 residents.
- Cash, available cash, materials and every inventory are non-negative.
- Every city's cash ledger and material ledger reconcile.
- Every city's waste mass reconciles: generated + imported = held + recovered + digested + landfilled + exported.
- Electricity reconciles, and exports never exceed own generation.
- Inventories respect their caps; materials respect theirs at the end of each tick.
- Every building has its prerequisites. Plots are unique, there are at most two projects, and every project matches its building.
- Contract cash and mass transfers are conserved. Escrow equals the maximum fee less payments while active, and nothing once closed.

A tick that breaks an invariant is rejected whole.
