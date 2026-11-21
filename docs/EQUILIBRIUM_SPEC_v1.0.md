# EQUILIBRIUM
## Definitive Game Design & Simulation Specification v1.0

**Status:** Structural design freeze; integrated numerical reference build **B1** for implementation and testing.  
**Date:** 17 November 2026  
**Target:** Four-player deterministic competitive circular-economy simulation engine.  
**Validation boundary:** B1 is the frozen live numerical configuration. Finite testing does not prove perfect competitive balance or the absence of every exploit.

---

## 0. Game model

> **Grow the region's most attractive city.** Build homes and jobs, turn trash into useful materials and clean energy, and make smart deals with competing cities. Residents move toward the best-run cities. **The city with the most residents after 20 minutes wins.**

The authoritative state exposes Environment, Development, Satisfaction, Population and Money, together with electricity, waste, construction and contract state. Recovered materials are managed automatically. Player commands build or upgrade facilities, change the waste policy, enable or disable facilities, and create or accept market offers. There is no turn system, road network, personnel allocation, research tree or combat system.

### 0.1 Design freeze — what is in v1

| Dimension | Binding decision |
|---|---|
| Match | Exactly 1,200 fixed simulation seconds; no turns |
| Players | Four human-controlled cities; test bots allowed |
| Victory | Most residents, with exactly 4,000 regional residents |
| City state | Environment, Development, Satisfaction, population and money |
| City map | 6×6, one-tile buildings |
| Buildings | **11 types**, level 1 and level 2 only |
| Projects | Two simultaneously, **no queue** |
| Waste | Recyclable, organic, residual; automatic collection/sorting and processing |
| Circular outputs | Recovered material credits and biogas-generated electricity |
| Trade | **One** market, **two** services: waste treatment and electricity |
| Rivalry | Shared migration, market competition, expiring contracts, live ranking |
| Direct sabotage | **Absent in v1**; no inspection or disruption cards |
| Policy | One toggle: Reduce Waste |
| Events | Smog, Waste Surge, Power Shortage, final 2050 crisis |
| Tech | Development unlocks upgrades and biogas |
| Core engine | Deterministic authoritative fixed-timestep simulation |

### 0.2 Excluded mechanics

Separate sorting buildings, separate reuse buildings, additional prevention buildings, material-to-material player trades, regional-government bounty auctions, sabotage cards, defense cards, manual energy allocation, manual workers, manual waste routing, land purchases, zoning, roads, adjacency bonuses, extra building tiers, random disasters, construction queue, detailed waste chemistry, dynamic commodity exchanges, debt, population births/deaths, live bidding for unrelated global prizes. They are **not** implied by this specification.

---

## 1. Match, time, victory and interaction rhythm

- Match time is integer `tick` 0–1200 inclusive, with exactly **1200 state transitions**. Tick `t` advances state on interval `[t, t+1)`. Final state is `time=1200`.
- There are four cities, each starting at **1,000** residents; the total is always **4,000**.
- Each city has **500 founding residents who never migrate**. The remaining **2,000** residents migrate regionally. Minimum visible city population is 500. The limit is a guard against irreversible elimination, not a separately displayed resource.
- First migration occurs at `t=80`; then `100,120,...,1200` (57 scheduled migrations). No special duplicate final migration.
- Population changes only at discrete 20-second migration boundaries.
- Highest population at `t=1200` wins. Ties: higher effective Satisfaction (unrounded), then higher Environment (unrounded), then higher cash. A remaining exact tie is shared.
- A player can build/upgrade twice concurrently, change one prevention policy, and engage in trade without pausing the simulation.
- Buildings, contracts, and crises finish at exact authoritative timestamps. A project with completion `>1200` cannot be started, except optional explicit sandbox/test mode. Projects completing exactly at `1200` confer no post-match benefit and are therefore also blocked in ranked mode.

## 2. The four Foundations

Each Foundation defines a starting identity. All cities can eventually construct every building. The v1 default is a **unique four-card draft** with randomized draft order; cards are removed once selected. The server also supports the `allow_duplicate_foundations` configuration option. Each Foundation provides exactly the tabled starting package; **no additional invisible boosts**.

| Foundation | Completed starting building | Starting money | Early identity |
|---|---|---:|---|
| **Industrial Legacy** | One L1 Factory | **480** | Jobs/cash now; tight energy, extra waste |
| **Circular Foundation** | One L1 Recycling Center | **620** | Recovery from household waste immediately; spare capacity for trade |
| **Energy Pioneer** | One L1 Renewable Plant | **520** | Surplus electricity, trade leverage, clean expansion |
| **Investment District** | None | **900** | Maximum flexibility and no specialized asset |

Starting Foundation structures occupy one grid cell and never consume a construction slot or a payment at match start. Each city's other baseline infrastructure is identical. Free buildings **are included** in jobs, pollution, energy, maintenance, progression and waste calculations.

Industrial starts with immediate income and employment, whereas Energy begins with generation capacity whose value depends on demand or trade. These differences are intentional strategic properties, not additional hidden modifiers.

---

## 3. Starting state and units

| Variable | Per city at match start, before Foundation |
|---|---:|
| Population | **1000** |
| Founding population | **500** |
| Money | Foundation-dependent (§2) |
| Recovered materials | **0** |
| Housing capacity | **1200** |
| Public-service capacity | **1200** residents |
| Base employment opportunities | **560** jobs |
| Municipal electricity generation | **145 E** |
| Municipal/household electricity demand | **85 + 0.02 × population E** (105 E initially) |
| Base Recovery Hub throughput (combined collection/sorting) | **60 waste/min** |
| Base landfill disposal throughput | **50 waste/min** |
| Base recycling, biogas | **0** |
| Ambient air damage `A` | **8** |
| Accumulated landfill damage `L` | **5** |
| Uncollected/collected waste inventories | **0** |
| Environment | **87** |
| Initial effective Satisfaction | **86.65** with no Foundation |
| Construction slots | **2** |
| Tiles available | **36** |

**Units and interpretation:** `credits` (money), `waste units` (abstract material mass), `material units` (same mass-equivalent bookkeeping unit), and `E` (a continuous **power capacity** unit). Every waste throughput is `waste units/min`, income and expense are `credits/min`, air-damage rates are `environment points/min`. A contract for electricity quotes **credits per E-minute**, meaning 1 E supplied continuously for 1 minute. A contract for treatment quotes **credits per waste unit actually processed**. Energy units are not energy inventory; production and demand balance instantaneously. Authoritative calculations use fixed-point integers; presentation may round values. Population is an exact integer.

**Municipal income:** `100 + 0.07 × population` credits/min, earned regardless of optional-building finances.  
**Municipal upkeep:** `25` credits/min; must be paid from municipal earnings first (at the minimum 500 residents, 135 credits/min income exceeds it).  
**Starting household waste:** `0.04 × population` waste/min (40 at 1000).  
**Landfill variable disposal fee:** `1.20 credits / unit actually disposed`. This is the cost of treatment/disposal, not a transfer to another player. Landfill buildings add throughput but do not remove that unit cost.

The neutral municipality therefore starts with approximately `(100+70)-25-40×1.2 = 97 credits/min` operating surplus, provided collection and disposal operate. All Foundation-specific differences enter the same formulas.

---

## 4. The complete building roster, Level 1

**Table key:** `Cost` credits; `Time` seconds; `Upkeep` credits/min when funded; `Jobs` potential employment; `E` consumption/production capacity; `Money` added income credits/min at full operation; `Waste` added waste/min at full operation; `Air` air-damage points/min (before natural recovery); `Special` capabilities. A dash means zero. Income from municipal taxation is **not** included in any building value.

| Building | Cost | Time | Upkeep | Jobs | E | Money | Waste | Air | Special |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| **1. Residential District** | 150 | 22 | 5 | 0 | 0 | 0 | 0 | 0 | +450 housing |
| **2. Factory** | 260 | 38 | 24 | 300 | −38 | +155 | +30 | +2.20 | Industrial income/jobs |
| **3. Commercial District** | 190 | 28 | 12 | 200 | −22 | +90 | +10 | +0.25 | Lower-impact income/jobs |
| **4. Public Services Center** | 175 | 28 | 10 | 60 | −12 | 0 | 0 | 0 | +550 service capacity |
| **5. Recovery Hub** | 170 | 26 | 9 | 80 | −12 | 0 | 0 | 0 | +55 collection **and** sorting/min |
| **6. Recycling Center** | 180 | 34 | 9 | 100 | −16 | 0 | 0 | 0 | 35 recyclable/min, automatic reuse of up to first 10 |
| **7. Biogas Facility** | 225 | 42 | 10 | 90 | −8 | 0 | 0 | 0 | 30 organic/min → 3 E per (unit/min) processed |
| **8. Landfill** | 100 | 20 | 8 | 40 | −4 | 0 | 0 | 0 | +55 disposal/min; unit disposal fee applies |
| **9. Fossil Power Plant** | 175 | 32 | 17 | 50 | **+125** | 0 | 0 | **+2.80** | Fast, dirty power |
| **10. Renewable Power Plant** | 265 | 42 | 11 | 60 | **+100** | 0 | 0 | 0 | Clean power |
| **11. Green Space** | 130 | 20 | 5 | 20 | 0 | 0 | 0 | **−1.50** | Air cleanup only; cannot erase waste or landfill damage |

**Zero-E structures** do not require electricity. Power plants are self-starting and do not require imported power. The Recycling Center *includes reuse*; there is no player-facing mode selector. Housing creates additional household waste/energy/service demand **only when people actually move in**, not as an automatic fixed cost of an empty apartment.

### 4.1 Level 2 — exact one-time upgrades

All listed changes are **additions to Level 1**, not replacements. A Level 2 plant's total effect is its L1 effect plus its upgrade delta. Upgrade projects consume one construction slot; L1 remains active until completion. Upgrades cannot stack or be restarted on a Level 2 building.

| Building | Upgrade cost | Time | ΔUpkeep | ΔJobs | ΔE | ΔMoney | ΔWaste | ΔAir | Additional effect |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Residential | 95 | 18 | +3 | 0 | 0 | 0 | 0 | 0 | +350 housing |
| Factory | 180 | 32 | +12 | +140 | −16 | +85 | +12 | +0.90 | Better output per tile |
| Commerce | 115 | 23 | +6 | +120 | −9 | +54 | +5 | +0.12 | Cleaner expansion |
| Public Services | 95 | 20 | +5 | +30 | −4 | 0 | 0 | 0 | +350 service capacity |
| Recovery Hub | 100 | 22 | +5 | +40 | −6 | 0 | 0 | 0 | +45 collection/sorting/min |
| Recycling | 120 | 26 | +5 | +50 | −8 | 0 | 0 | 0 | +25 processing/min, +6 reuse/min |
| Biogas | 135 | 30 | +5 | +45 | −4 | 0 | 0 | 0 | +20 organic/min; same conversion yield |
| Landfill | 65 | 18 | +4 | +20 | −2 | 0 | 0 | 0 | +45 disposal/min |
| Fossil | 125 | 25 | +9 | +25 | **+90** | 0 | 0 | +2.00 | Stronger but dirtier |
| Renewable | 175 | 30 | +6 | +30 | **+80** | 0 | 0 | 0 | More clean power |
| Green Space | 75 | 20 | +2 | +10 | 0 | 0 | 0 | **−0.90** | More air cleanup |

**Upgrade accessibility:** Development ≥20 unlocks Residential, Commerce, Services, Hub, Landfill, and Green Space upgrades. Development ≥45 unlocks construction of Biogas. Development ≥70 unlocks Factory, Recycling, Biogas, Fossil, and Renewable upgrades. The building's own L1 prerequisite is required for its upgrade. All *Level 1* buildings other than Biogas are available at `t=0`. Foundation free buildings do not bypass upgrade thresholds.

### 4.2 Building economics: sanity checks, not balance proof

Assuming adequate workforce/power/collection/disposal and **all marginal waste is landfilled**: L1 Factory net contribution is `155−24−30×1.2 = +95 credits/min`; Commerce is `90−12−10×1.2 = +66 credits/min`. Simple cash paybacks: `260/95 ≈ 2.74 min`, `190/66 ≈ 2.88 min`. Factory earns more and provides more jobs, but uses more energy, landfilling, and air-damage budget; Commercial is cheaper and cleaner. These are *conditional upper-level approximations*, not guaranteed returns during actual play.

At 1,000 residents, household recyclable waste = 18/min. A L1 Recycling Center automatically reuses 10 at 95% yield and recycles the remaining 8 at 80% yield: `9.5+6.4=15.9 material/min`; `2.1` units become residual. Relative to fully landfilling the 18 original units, avoided disposal is 15.9 units/min, saving `15.9×1.2=19.08 credits/min`. If all materials were liquidated at 0.8 each, value is `12.72 credits/min`; minus 9 upkeep gives **22.8 credits/min** marginal benefit, equivalent to approximately **7.9 min simple payback** before power opportunity costs, staffing, and timing of auto-sales. The early-game material buffer (§6) delays some realized cash; do not claim instant cash payback.

---

## 5. Workforce, employment, operating cash and bankruptcy

**No worker-assignment gameplay.** The engine uses abstract job opportunities for Satisfaction and a single deterministic staffing factor to limit unrealistic unlimited production.

1. `J_potential = 560 + Σ(job_slots of funded, finished, enabled buildings)`.
2. `staffing = min(1, Population / max(1, J_potential))`.
3. Municipal services are guaranteed, irrespective of staffing. For player-built buildings, productive capacity, income, variable waste, pollution and added job contribution multiply by `staffing`; electric consumption required to operate those capacities multiplies by staffing before rationing. (Construction, housing capacity, service capacity, fixed upkeep and tiles are not scaled.)
4. Electricity throttling applies a *further* factor from §8 to power-dependent buildings. Realized jobs for the Satisfaction score are `min(Population, 560 + Σ(jobs × staffing × electricity_factor × enabled_factor))`. The base 560 jobs are employment opportunities, not an additional operating-cost charge.
5. Buildings that cannot be funded contribute **zero** jobs, income, throughput, emissions and electricity generation. Completed structures physically remain on the grid when unfunded, but **unfunded housing does not contribute enabled housing capacity**, and unfunded public services do not contribute enabled service capacity. Existing residents are never deleted; they simply cannot receive new migrants while housing is inadequate.

### 5.1 Payment/operation precedence

At each tick, municipal income arrives first; then pay municipal upkeep; then reserve any contract-related payments due; then activate funded optional buildings in **oldest-construction-first order, tie by building ID**; pay each full tick's fixed maintenance **before** its operation. A building whose upkeep cannot be paid is inactive this tick, pays nothing, and earns nothing. It automatically retries on the next tick. The grid remains occupied. Free optional power plants do not generate power when their maintenance is unpaid. Funding eligibility is determined before computing output, so no earn-first-pay-later exploit.

Waste disposal charges are taken **as units are actually disposed**, capped by available money; unpaid waste stays in inventory. Market transfers pay only against actual delivery. Municipal income is strictly greater than mandatory municipal upkeep even with only 500 residents, preventing a permanent zero-money softlock. The player can also disable completed optional buildings to avoid maintenance (no construction cost refund). Disabling does not remove the building or its tile; re-enabling is free with a 10-second cooldown (prevents 1-second fee dodging). A disabled housing building still physically exists, but **its housing capacity is suspended**; existing residents are not deleted, and migration cannot add residents beyond enabled housing.

### 5.2 Facility funding and power stability

The global staffing factor is calculated once from the current funded/enabled building set. Power supply is then calculated once; there is no iterative power/biogas feedback within a tick. A facility's throughput can be fractionally throttled but never exceed `(nameplate capacity × staffing × power_factor)`. A temporarily unfunded, disabled, or unpowered building cannot earn Development throughput credit.

---

## 6. The waste and circular-economy model

### 6.1 Generation and composition

| Source | Waste/min at full activity | Recyclable | Organic | Residual |
|---|---:|---:|---:|---:|
| Households | `0.04×population` | 45% | 35% | 20% |
| Factory L1 | 30 | 50% | 10% | 40% |
| Commerce L1 | 10 | 60% | 25% | 15% |

Level 2 building waste deltas have the same composition as the corresponding Level 1. Industrial/commercial generation is multiplied by its realized operating efficiency. Household waste is not worker- or power-dependent. Waste prevention and crises act on **new generation only**, never erase existing inventory. The uncollected waste is stored by its three categories.

### 6.2 Inventory and order

For each city maintain `uncollected[type]`, `sorted[type]`, cumulative `recovered_materials_generated`, cumulative `waste_disposed`, cumulative `organic_converted`, and `material_inventory`. There is **no separate unsorted-collected stock**: a Recovery Hub collects and sorts together at one throughput. All collection is one-way; waste cannot be counted in two categories or cities.

For each tick (rates divided by 60):

1. **Generate waste** and add it to uncollected inventory.
2. **Collect and sort:** up to active Recovery Hub throughput, proportionally from the three uncollected categories (deterministic fractional allocation, not priority that permanently starves one stream). Move it atomically into sorted inventories.
3. **Execute reserved export treatment:** real sorted recyclable/organic waste from buyer is consumed directly by seller's available reserved Recycling/Biogas throughput, **without entering seller's uncollected storage**. Seller receives resulting materials or deferred biogas output; all processing rejects become seller's sorted residual waste. No already-imported waste can be re-exported.
4. **Process local sorted recyclable:** automatic reuse then industrial recycling; any capacity already committed and delivered to contracts is unavailable locally.
5. **Process local sorted organic:** convert in operating Biogas plants within capacity.
6. **Dispose:** landfills treat sorted residual first, then remaining organic, then remaining recyclable, up to the city's enabled capacity and affordable unit fees. Everything not processed remains sorted in stock for a later tick.

A contract cannot export more sorted material than the buyer actually owns; the transfer and treatment occur atomically, so there is no phantom waste transit. For simplicity, a buyer exports **only waste exceeding its own currently available processing capacity** for that category; local processing capacity is never unnecessarily idled to subsidize a rival. Reserved imports are processed before the seller's local waste in the reserved capacity. Contracts are normally accepted only for currently spare capacity. A seller taking on a contract and then expanding locally may disadvantage its own treatment until expiration; the contract preview warns of committed capacity.

### 6.3 Recycling and reuse yield

Each L1 Recycling Center can process **35 recyclable units/min in total**. Of the first `min(actual input, 10)` units/min processed through it, **95%** becomes recovered material (reuse/repair), and 5% becomes residual rejects. Of the remaining processed recyclable waste, **80%** becomes recovered material and 20% residual. L2 capacity is 60/min and reuse-first slice is 16/min. Multiple plants operate in building-ID order on the total sorted pool. No manual mode switching.

### 6.4 Biogas conversion and electricity lag

A L1 Biogas Facility processes up to 30 organic units/min. Each processed organic unit creates `0.1` residual-waste units and `0.9` units of abstract material mass converted to the declared `organic_conversion_sink` (biogas/digestate outputs not tracked as additional player resources). Energy production for the **next** tick is `3 E × actual organic processing rate in waste/min`; e.g. processing 14 organic/min creates **42 E next tick**. L2 throughput is 50/min with unchanged energy yield. No same-tick self-powering. If processing ceases, that deferred generation becomes zero on the next tick.

### 6.5 Landfill and the financial reason to recycle

Base disposal is 50/min. Each L1 Landfill adds 55/min; the L2 upgrade adds another 45/min to that building, for 100/min from a fully upgraded Landfill. All landfilled waste incurs 1.20 credits/unit including municipal base disposal. It exits inventories and increases the cumulative `disposed` tally, while creating landfill environmental damage (§9). If no landfill funds/throughput are available, waste accumulates visibly. Recycling earns value through *both* avoided landfill charges and recovered materials, while its residual rejects still require disposal.

### 6.6 Recovered materials

- One recovered-material unit can replace **one credit** of a construction or upgrade price, up to **25% of that project's listed price**. Always consume the maximum available eligible materials when starting the project.
- Maintain a **20-unit material reserve** for future construction. At the end of each tick, material inventory above 20 is **automatically sold at 0.80 credits/unit**; any income from sale arrives *after* building operation and cannot fund a construction command that has already been processed that tick.
- Materials are never directly traded between players.
- Material credits are atomic: they cannot simultaneously be used in construction and sold. Sold units are removed permanently; processing remainders are carried in fixed-point integers.

---

## 7. One Waste Reduction policy; no policy menu jungle

A single citywide switch, **Reduce Waste: ON/OFF**, in the Waste panel. Initial OFF. Changing it has a **60-second** cooldown. While ON, apply the following per-tick modifiers before waste generation:

- Household waste `×0.75`.
- Factory waste `×0.90`, but Factory money income also `×0.90`.
- Commerce waste `×0.90`, but Commerce money income also `×0.95`.
- Extra policy operating expense: **18 credits/min**, paid before policy effects. If the policy fee cannot be paid, policy becomes OFF for that tick; a player can switch it OFF explicitly. A failed fee does not create a new cooldown.

This is **situational** by construction. At 1,000 residents with no factories, household waste saved is 10/min, saving only 12 credits/min of landfill disposal vs 18 credits/min policy expense, so leaving it permanently ON is not a free-money exploit. Under waste overload/crises it can be worthwhile for its environmental protection and reduced disposal. This policy does **not** retrospectively remove waste already in storage.

---

## 8. Electricity: one balance, one automatic allocation

### 8.1 Supply and demand

- Own power: municipal base `145 E` plus funded/self-starting fossil/renewable generation plus `biogas_output_from_previous_tick`.
- Demand: municipal `85 + 0.02×population E` plus funded building demands (adjusted by staffing), excluding power generators.
- Exports and imports are *real delivered power* through §12 contracts. Imported power can serve domestic demand but **cannot be re-exported**.
- Surplus electricity is not stored or automatically monetized; only contracts create revenue from exported power. A city need not buy power if it already has enough; idle capacity alone is not an income source.

### 8.2 Rationing, order, and power-cost consistency

When own supply plus valid imports is insufficient, allocate capacity, in priority order, to: (1) municipal demand; (2) Recovery Hubs and Landfills; (3) Biogas and Recycling; (4) Public Services; (5) Commerce; (6) Factories. Within a tier, allocate proportionally to electricity requested by that tier, using exact fixed-point fractional allocations. Under-supplied buildings operate proportionally below staffed capacity. Generators themselves are powered by their own fuel/source, not by this allocation. An energy contract can export only own generation remaining after forecast own demand at acceptance; actual delivery at each tick cannot exceed remaining own generated power after municipal essential allocation and any earlier committed contractual export. If local demand later rises, the seller's optional loads may be throttled; the player was warned when committing spare capacity.

**Reliability for Satisfaction** = `electricity_delivered_to_municipal_and_eligible_building_loads / electricity_requested_by_municipal_and_eligible_building_loads`, clamped [0,1]. Contracted exports are **not** counted in domestic satisfaction; only real domestic supply is.

**Stability rule:** No instantaneous iterative recalculation between biogas energy, power, and organic throughput. The sequence is electricity from prior biogas → allocation → organic processing → next-tick energy. The deferred energy value is overwritten each tick, not added to a permanent stock.

---

## 9. Environment

Track three independent internal sources of harm, summed into a single Environment score:

- `A` = air pollution **stock**, clamped [0,40]. Initially 8. Each minute, apply `+2.20 per operational Factory L1 +0.25 per Commerce L1 +2.80 per Fossil L1 −1.50 per Green Space L1 −0.30 natural recovery`. Level 2 deltas are in §4.1. Factory/Commerce emissions scale with realized staffing/electricity. Power plant emissions scale with funding/staffing (not plant dispatch) and output; Green Space cleanup only affects `A`. The stock cannot go negative.
- `L` = persistent landfill impact **stock**, clamped [0,35]. Initially 5. Add `0.030 × actual waste units landfilled` per minute-equivalent (i.e. per-unit disposed over time); subtract `0.15` per minute of natural recovery. Green Spaces **do not** remove `L`. No landfill processing → no added landfill impact.
- `W` = current visible waste-overflow burden, **not a permanently integrated stock**: `min(45, 0.18×total_uncollected_waste + 0.05×total_sorted_untreated_waste)`. Waste that has been collected and safely sorted is less harmful than trash on streets. W clears promptly when backlogs are actually processed. No separate waste-pollution accumulator.

Then:

`Environment = clamp(100 − A − L − W, 0, 100)`.

This ensures **immediate overflow consequences and long-term landfill/air consequences** without counting the same waste twice. Parks cannot offset the physical presence of garbage, and last-minute factories create direct air/waste pressure immediately rather than only after the match ends. Pollution rates above are balance candidates, not real-world emission estimates.

Event multipliers (§15) may temporarily modify the **effective air contribution** to Environment or new waste generation. They do **not** retroactively mutate A or L.

---

## 10. Satisfaction: one source of truth

At every tick, recompute numerical Satisfaction. **The same exact effective Satisfaction is used for migration.** Clients may round or smooth presentation, but must not maintain a second score for population decisions.

| Component | Formula | Maximum |
|---|---|---:|
| Environment | `35 × Environment/100` | 35 |
| Employment | `20 × min(1, realized_jobs / max(1,population))` | 20 |
| Housing | `15 × min(1, enabled_housing / (1.15 × max(1,population)))` | 15 |
| Power reliability | `15 × electricity_reliability` | 15 |
| Public services | `15 × min(1, enabled_operating_service_capacity / (1.15 × max(1,population)))` | 15 |
| **Total** | **Sum, clamped 0–100** | **100** |

There is **no arbitrary time decay** and no extra generic penalties for waste or air: they already influence Environment. Reduced industrial activity legitimately lowers employment and production; this is a real second-order consequence, not another arbitrary penalty. Housing is a **hard immigration ceiling**; services are a *soft* satisfaction capacity. Growing cities face increasing waste, electricity and service requirements, limiting runaway leads naturally.

At P=1000 with neutral baseline, `E=87`, jobs=560, sufficient housing/service/power, Satisfaction = `35×0.87 + 20×0.56 +15+15+15 = 86.65`. With a fully staffed starting Factory and no pollution change yet, initial satisfaction rises to **92.65** (the Factory's +300 jobs fill 860/1000 positions), but its operational emissions and waste pressures immediately begin acting in subsequent ticks.

---

## 11. Development: functional, trackable, non-farmable progression

Development is a **cumulative measure of demonstrated city capability**: it should reward what the city *has been able to operate*, not how many duplicate structures have been bought. There is no research tree and no Development-based population bonus. `Development = max(previous Development, round_to_2_decimals(current_capability_score))`, capped at 100. Progress is permanent: the player earns infrastructure know-how, even if a structure is later demolished.

`capability_score` is the sum of four capped categories computed from *the maximum previously demonstrated functional capacity or actual processed output* (not simply the active count today):

- **Urban (20 points):** `10×clamp((peak_enabled_housing −1200)/800,0,1)` plus `10×clamp((peak_operating_service_capacity −1200)/700,0,1)`.
- **Employment/economy (25):** `25×clamp((peak_realized_jobs−560)/600,0,1)`. The peak is recorded only after an operational tick, not at a construction preview.
- **Circular capability (35):** `35×clamp(cumulative_waste_diverted_from_landfill / 400,0,1)`. Diverted waste is recovered-material mass (from reuse/recycling) plus organic mass genuinely converted through biogas; **not** gross waste collected, disposed, or merely transferred to another city. Seller processing claims the diversion, not the buyer. No counter is incremented twice.
- **Energy capability (20):** `20×clamp((peak_operational_own_generation −145)/180,0,1)`. Operational excludes imported generation and requires funded plants; biogas from a completed prior interval counts when it becomes available.

The peak maxima are permanent, one-way records. Repeated demolition/reconstruction cannot grant more points than demonstrating a strictly higher peak; processing an actual new unit of waste can add circular credit once. None of these values can be bought directly. Unlocks are **20, 45, and 70** (§4.1). Development remains a progress record after all unlocks and never directly changes migration or victory.

---

## 12. Population migration: exact, conservative, no teleportation

Migration runs at times `80,100,120,...,1200` seconds. Each city has **500 permanent** residents and therefore the mobile pool is **2,000**. Use current authoritative Satisfaction `S_i` and the stable softmax:

`w_i = exp((S_i−S_max)/20)`; `target_i = 500 + 2000 × w_i / Σ w_j`.

Subtracting `S_max` is numerically safe and cancels in the ratio. At equal Satisfaction every city targets exactly 1,000. A city +6 Satisfaction over three equal rivals targets about **1,121** total residents (not instant arrivals). Housing caps receiving, not the target calculation; existing overcrowded residents are never deleted.

At each migration instant:

1. Compute all targets from **one common state snapshot**.
2. `offer_i = max(0, P_i − max(500,target_i))` and `demand_i = max(0, min(target_i−P_i, enabled_housing_i−P_i))` (real-valued intermediate quantities).
3. Limit each sending city to **25 residents** and each receiving city to **30**, with an **overall regional maximum of 50 moves** for the entire migration instant.
4. Allocate flow from eligible senders to eligible receivers proportionally to remaining target gaps using a **deterministic largest-remainder algorithm**. Handle fractional caps by flooring hard per-city integer quotas; carry a fair rotating tie-breaker seeded by `match_id` and migration-step index instead of permanently favoring low player IDs. Residents may be transferred directly in a 4×4 flow matrix; no self-transfer.
5. A transfer is committed only when both sender quota and receiving capacity remain. Stop if no legal sender/receiver pair exists. No additional “final migration” at match end.

**Invariants:** `ΣP_i=4000`, `P_i≥500`, integers only, no receiver exceeds available housing, total transfers per event ≤50. City populations may stay above housing if buildings are disabled/demolished; such cities can lose residents but cannot gain until capacity returns. Never manufacture a resident to fill an unused housing slot. The exact allocation algorithm is tested with exhaustive small-population cases and random property tests.

**Comeback design:** leads create extra municipal tax but also larger waste, housing, power and service demand; smaller cities have lower requirements and always retain founding population and guaranteed municipal income. No hidden last-place bonus.

---

## 13. The only marketplace: voluntary waste treatment and electricity

### 13.1 Offers and quote requests

A buyer may request quotes for **10 seconds** and select a provider during the following **10-second** selection window; otherwise the request expires. A seller may publish a standing offer that an eligible buyer can accept immediately. Market operations do not pause the simulation. There are no external rewards, phantom waste, cash gifts, material exchange or unrelated auctions.

### 13.2 Contract template

- Exactly **90 seconds** duration, clipped at match end; cannot start if less than 20 seconds remain.
- Contains `id, buyer, seller, type (recyclable/organic/electricity), reserved_rate, unit_price, start_tick, end_tick, status`.
- A city may maintain **two outgoing and two incoming contracts maximum** across types combined. One live contract per `(buyer,seller,type)` tuple. Commands violating these limits are rejected.
- Acceptance requires a **5-credit booking fee** paid immediately from buyer to seller. If the seller is unable to deliver at acceptance despite its published offer, acceptance is rejected and no fee is charged.
- Buyer must currently own sorted eligible waste or forecast eligible generation ≥5 units/min for a waste contract. For electricity the buyer must forecast a meaningful deficit (at least **5 E**). Validation rejects contracts without qualifying need. Seller must demonstrate spare available processing/own generated power after its own predicted needs and earlier reservations. Requested rate cannot exceed that spare.
- The agreed **rate is reserved**. Seller cannot double-commit it. Valid contracted imported waste is processed before seller's own local waste *within its reserved capacity*. In power contracts, imports serve the buyer's load, not resale; export reservations cannot exceed own generation.
- **Actual delivery, not promised delivery, generates usage charges**. If buyer cannot provide waste/demand, seller has kept the booking fee but earns no usage fee. If seller's usable capacity falls, buyer receives/pay only actually delivered quantity.
- **Auto-release:** if a contract delivers zero for 15 consecutive seconds, terminate it, free reservation, and impose **90-second recontract cooldown for the same buyer–seller–type**; does not refund a valid booking fee. This rule prevents repeated cost-free capacity blocking. If seller is in continuous inability to deliver from the first second despite a valid buyer request, refund booking fee and terminate after 15 seconds.
- Either participant may cancel an active contract during the next command phase, before delivery. Seller cancellation refunds the original booking fee exactly once, including after partial service; buyer cancellation retains it. Completed usage and delivery remain settled. Cancellation clears renewal consent. Contract renewal requires fresh mutual acceptance. The engine emits a 30-second advance expiry notification. Disconnections do not invalidate contract accounting; contracts continue until expiry, cancellation, or auto-release.

### 13.3 Prices and atomic accounting

**Waste treatment:** recyclable: **0.60–1.60 credits/unit**; organic: **0.40–1.40 credits/unit**, allowed step 0.10. **Electricity:** **0.15–0.45 credits/(E-minute)**, step 0.05. `Standard` default rates are recyclable **1.00**, organic **0.80**, electricity **0.30**. Price bands prohibit free gifts and wildly noncommercial transfer pricing, although they cannot prevent all deliberate alliances. Money transfers are **conservative between cities**, aside from the fixed external municipal income and landfill disposal sink.

A waste treatment tick is **one transaction**: verify buyer's sorted available exportable surplus, seller's reserved working processing capacity, buyer's funds, and no recycled/imported-inventory duplication → consume buyer waste → produce seller recovered materials or next-tick biogas and seller-owned rejects → debit buyer usage charge, credit seller identical amount. If payment cannot cover full projected volume, deliver only the affordable fraction; fixed-point precision applies. Rejected material belongs to seller and must be landfilled or stored there. Imported material is processed *immediately*, never queued for resale.

An electricity tick is likewise one transaction: verify seller's net own available generation and reserved capacity, buyer's unmet domestic load, funds, and other accepted export claims → deliver up to feasible E and credit/debit an equal amount. No imported electricity may be exported onward. If no actual buyer load, nothing is delivered or billed.

All attempts use authoritative server IDs, current-state validation and single execution. Two buyers accepting the same capacity at once cannot both obtain it. The seller is responsible for seller-side operating costs and residual waste.

### 13.4 Why players should trade at all

Spare waste capacity can be monetized without buying another facility; outsourcing can bridge an imminent crisis or avoid an expensive building with a 20–40-second delay. Power can be purchased for 90 seconds when building a permanent plant would not pay off before the match ends. Self-sufficiency remains feasible but costs construction time, space and capital.

---

## 14. Construction, placement, upgrades, disabling, and demolition

- Grid 6×6, all 36 tiles available immediately, one active building or project per tile; no map edges, adjacency, roads, land purchase or district expansion.
- **Auto-place** on next valid tile using deterministic aesthetically grouped layout; optional manual placement is a cosmetic override only. No hidden adjacency value.
- Two simultaneous active build or upgrade projects. **No queue**. Building prices are paid atomically at command acceptance; materials are consumed then; projects end after exact number of ticks. No partial output before completion. L1 operates normally during its L2 upgrade.
- Cancel active construction: refund **50% of money actually paid** and **zero** materials. Repeated cancellation cannot create cash/materials. Demolish completed building: refund **0** (prevents dismantle arbitrage). Building IDs are never reused; structural score cannot be double-farmed.
- Disabling an existing completed building stops optional upkeep and production after the **next tick**; reactivation has a **10-second cooldown**, no fee. Disabling or demolishing housing reduces enabled immigration capacity but does not delete existing residents.
- A construction or upgrade project that cannot produce value before final tick is rejected in ranked mode with “Not enough time to finish.” The same applies to new contracts with fewer than 20 seconds remaining.
- No paid instant-complete, no construction speed buffs, no third queue slot, no roads or building synergies from tile placement.

---

## 15. Regional events: visible, deterministic, answerable

Events are **fixed and announced 60 seconds early**. An event modifies the specified systems and expires exactly as scheduled.

| Event | Warning | Active interval | Precise effect |
|---|---|---|---|
| **Smog Alert** | 05:30 | **06:30–07:45** | Effective air stock contribution in Environment becomes `1.40×A` (air itself unchanged). |
| **Waste Surge** | 10:00 | **11:00–12:30** | New household waste `×1.60`, Factory waste `×1.10`, Commerce waste `×1.20`; uncollected-waste contribution uses `0.25×U` instead of `0.18×U`. |
| **Power Shortage** | 14:30 | **15:30–16:45** | Municipal electricity generation reduces from 145 to **100 E**; local fossil, renewable and biogas generation unaffected. |
| **EQUILIBRIUM 2050** | 17:00 | **18:00–19:00** | New household waste `×1.30`, municipal generation **115 E**, effective air contribution `1.15×A`. |

At event end, transient multipliers disappear but **real generated waste, generated pollution and their accumulated consequences persist**. No event automatically creates or deletes residents. Late-crisis pressure tests existing strategies but ends one minute before the match so recovery remains possible. Energy specialists have a meaningful regional shortage opportunity.

**Counterplay:** Smog—clean energy/green spaces/reduce industrial operating loads; Waste Surge—Recovery Hub, recycling, contracted capacity, prevention; Power Shortage—build power, purchase electricity, reduce optional industrial demand by disabling facilities; final—combine existing responses.

---

## 16. Engine scope

The engine owns rules, validation, deterministic state transitions and public state data. Presentation, onboarding, accessibility, animation, input layout and client-specific previews are outside this specification. A client may derive explanations and forecasts, but it cannot mutate authoritative state or introduce mechanics.

---

## 17. Strategic model

Population is the sole primary victory metric. Housing, employment, services, power, waste, environment, Development, contracts and fixed events create the economic constraints around it. Staffing, waste routing, material recovery and power allocation are automatic under the rules below. Development unlocks capabilities but does not directly score victory.

The v1 engine includes no sabotage, gifting, manual dispatch, manual staffing or discretionary contract breaking. Clients and network layers must expose enough authoritative state to reconcile population transfers, resource flows, construction, contracts and final ranking.

---

## 18. Competitive interaction constraints

- All four cities are competitors sharing a conserved regional population.
- Market payments and transferred resources come from the participating cities; there is no external trade subsidy.
- Prices are positive and bounded. Players cannot gift cash or materials.
- Reserved capacity cannot be sold twice, and imported waste cannot be re-exported.
- A seller may decline a new or renewed contract, but an active agreement follows the authoritative expiry and cancellation rules.
- Self-sufficiency and trade are both legal strategies. The engine does not guarantee either is optimal.
- Direct sabotage is absent from v1.

---

## 19. Server-authoritative deterministic tick contract

Every player action is a command with `match_id, player_id, monotonically_increasing_command_seq, unique_command_id, command_type, payload, server_received_tick`. Clients never set population, income, inventory, contract settlement or scoring directly. Network messages may be retried: the engine applies each command ID at most once. Commands from multiple players at the same tick are sorted by `(server_received_tick, player_id_rotated_by_match_seed, command_seq)`. Commands affecting the same slot/capacity are committed atomically and subsequent commands see the updated state. Ties rotate by match seed to avoid persistent ID advantage. **Do not trust client clock timestamps for market deadlines.**

### 19.1 Exact per-second phase order

```text
for tick = 0..1199:
  01  Freeze authoritative start-of-tick snapshot; identify interval [t,t+1).
  02  Apply any event start/end effective on this interval.
  03  Finish construction projects scheduled to complete at t.
      They become eligible to operate during [t,t+1).
  04  Deduplicate, order and validate player commands, construction payments,
      policy toggles, offers, acceptance and capacity reservations atomically.
  05  Credit guaranteed municipal income; pay mandatory municipal upkeep.
  06  Determine which enabled facilities can pay this tick's full fixed upkeep.
      Deduct fixed upkeep BEFORE computing any production or power.
  07  Compute funded building workforce factor and own-generation potential,
      including deferred biogas power from previous tick only.
  08  Validate existing electricity reservations and allocate actual real power
      and imports once, with municipal essentials first and fixed tier ordering.
  09  Apply staffing/power factors; compute actual factory/commerce production
      and associated money income and waste; apply prevention/event modifiers.
  10  Generate household waste; collect-and-sort through Recovery Hubs.
  11  Validate and atomically execute funded contracted processing and payments
      using sorted inventories, remaining plant capacity, and available funds.
  12  Process remaining LOCAL recyclable and organic inventories, producing
      material, seller-owned residue and NEXT-tick biogas output.
  13  Landfill residual first, then organic, then recyclable, charging per unit.
  14  Auto-sell recovered-material inventory above the 20-unit buffer.
  15  Update air stock A, landfill stock L, overflow W and Environment.
  16  Calculate effective jobs and service/housing capacities and Satisfaction;
      update permanent Development from actual completed operational outputs.
  17  If t+1 ∈ {80,100,...,1200}: execute exactly one migration using
      the common post-tick satisfaction snapshot and housing caps.
  18  Resolve contract zero-service timers, expiries and notification triggers.
  19  Increment authoritative time by one; if time==1200: freeze final state.
  20  Publish minimal new state, events and ledger-backed transfer notifications.
```

Implementation may reorganize these phases internally, but cannot change observable ordering without updating the spec and replay tests. **Special case:** Electricity contracts must be settled with the actual generation/demand allocation in phase 08, not later using unrealized promised capacity. All financial credits/debits occur only once and prior to any subsequent action that can spend them. Power generated by organic processing in phase 12 is available **next tick**, never in phase 08 of the same tick. Exact expiration uses `[start_tick,end_tick)`; a contract ending at 1200 does not deliver at `t≥1200`.

### 19.2 Data state (reference)

```text
GameState { tick, seed, status, applied_command_ids, foundations[4], cities[4],
            contracts[], offers[], event_schedule, transfer_ledger[], final_result? }
CityState { population, money, materials, founding_population, buildings[<=36],
            project_slots[2], disabled_states, cooldowns, housing, service_capacity,
            job_capacity, power_supply, power_demand, previous_biogas_E,
            uncollected[R,O,X], sorted[R,O,X], air_A, landfill_L, environment,
            development, satisfaction, waste_diverted_cumulative,
            peak_housing, peak_services, peak_jobs, peak_generation, policy,
            contract_reservations, incoming/outgoing_contract_ids }
```

Money/material/waste are internally **fixed-point** integers with at least **1,000,000 micro-units** per displayed unit; retain exact carry residues for per-second rate conversion. Scores use deterministic fixed-point math or a versioned deterministic numerical implementation; never round source waste before multiplying by conversion factors. Only final display numbers are rounded. Any stochastic cosmetic elements use separate seeds and must not affect game outcome.

### 19.3 Disconnect/reconnect

Disconnect does not freeze the global match or cancel valid commitments. A disconnected city continues its existing buildings, policy and contracts without new active decisions; no AI construction or free protective actions appear. Rejoining fetches a full authoritative state and deduplicated command acknowledgments. At match end, server freezes final result and rejects every subsequent command. For ranked play, all players must receive consistent snapshots and a deterministic replay log.

---

## 20. Invariants and exploit regression tests

**Must hold after every tick**, including events, disconnections and 0-credit states:

1. `Σ population = 4,000`, every population is integer and ≥500; migration conservation holds with capacity constraints.
2. Money/material/waste inventories ≥0; resource transfers cannot be executed twice; refund ≤amount actually paid.
3. Every generated waste unit is accounted for as uncollected, sorted, exported-and-processed, material recovered, organic-conversion sink, or landfilled sink, with explicit residue fractions. The per-tick mass-ledger error is zero at fixed-point precision.
4. Electricity domestic use + exports ≤ own physical generation + valid imports; **exports ≤ own generation**, no import-re-export cycle.
5. Per-building throughput ≤ staffed and power-supplied nameplate; multiple contracts never allocate same capacity.
6. No output/earnings from an optional building whose maintenance was not paid. No production occurs before a project's completion tick.
7. 0–100 scores, no NaNs or division by zero; household waste remains well-defined at minimum population.
8. Foundation packages are created once; demolish/rebuild does not grant new free starting buildings or reset Development peaks.
9. Two projects maximum, no occupied-tile double build, no concurrent upgrade duplicates, no multi-refund or duplicate command effects.
10. One final migration; zero economic mutations after `time=1200`.
11. Contract booking fee exactly once; usage payments equal service volume × price; zero-service release/cooldown; no phantom waste delivery.
12. Reconnecting a client or replaying commands preserves the exact authoritative result.

**Adversarial bot cases:** build only Factories, only Commerce, only Landfill, only Renewable Plants, hoard cash, delete/disable all optional buildings, recycle and sell every unit, occupy all grid cells, issue simultaneous construction orders, spam canceled builds, overbid capacity, accept duplicate quotes, route A→B→A waste, energy A→B→C→A, place policies around each tick boundary, use construction discounts during auto-sale, cause energy/biogas oscillation, induce bankruptcy deliberately, force max housing demand, trigger all contracts to expire at crisis start, submit actions at `t=1199`, disconnect/reconnect during acceptance, issue duplicated client retries.

---

## 21. Numerical authority and validation boundary

The exact live numerical authority is [`../config/balance/B1.json`](../config/balance/B1.json). Structural rules in this specification take precedence if they conflict with configuration or implementation. Numerical changes require deterministic replay, accounting and conservation validation; balance conclusions require evidence from the tested strategies and contexts. Finite simulation cannot prove universal competitive equilibrium.

---

## 22. Acceptance scenarios (developer-readable)

**Scenario A — neutral opening.** At `t=0`, P=1000, uncollected/sorted=0, Environment=87, Satisfaction=86.65, electricity supply=145 E, municipal demand=105 E, generated household waste=40/min, base recovery=60/min, base landfill=50/min. Baseline operating margin ≈97 credits/min. No arrival until 80 seconds.

**Scenario B — recycling household waste.** With a staffed, powered L1 Recycling Center, 18 recyclable/min are processed: reuse of 10 yields 9.5 materials, conventional recycling of 8 yields 6.4; rejects=2.1; materials=15.9. The other household waste streams are organic14 and residual8; landfill load after recycling is `14+8+2.1=24.1/min` rather than 40/min. All 40 mass units accounted for: 15.9 recovered +24.1 landfilled. (Material can be sold subject to 20-unit buffer.)

**Scenario C — industry with insufficient collection.** L1 Factory increases generated waste from 40 to 70/min. With baseline Recovery Hub 60/min and no prevention, uncollected stock grows by at most 10/min if collection stays staffed and powered. That waste must not vanish merely because Landfill still has capacity.

**Scenario D — power.** With Factory alone, total nameplate demand initially 105+38=143 E, under municipal generation145, so it runs fully (if funded and staffed). Add a Recycling Center and demand rises to159 E; with no extra plant, optional production must be proportionally throttled according to priority. Never allocate 159 E from145 E.

**Scenario E — migration.** Four equal Satisfaction scores and populations of 1000 each yield targets of 1000 and no movement. If one city gains +6 Satisfaction, its unconstrained target is approximately 1121, but a single migration event can give it **at most 30 residents** and the four-city total stays 4000.

**Scenario F — zero money.** When optional maintenance cannot be funded, optional building produces no jobs, money, energy or waste, while guaranteed municipal income continues. The city becomes able to fund something again without bailout.

**Scenario G — waste contract.** A exports 10 sorted recyclable mass units to B for immediate processing. B recovers the specified material yield, and its waste inventory receives rejects; A loses exactly10, not20, and pays only for the10 processed. The seller pays any landfill cost for rejects. If contract duplicated with same command ID, no second transfer occurs.

**Scenario H — events/ending.** At 20:00 server applies only the scheduled regular migration at t=1200 and freezes state. Ending an event at 19:00 restores the normal multiplier but does not erase damage and cannot create an extra migration instant.

---

## 23. Structural authority

This document defines the v1 structural rules: eleven building types, automatic recovery and processing, no direct sabotage, inter-city service contracts, conservative migration and exact economic accounting. B1 supplies the live numerical values. Implementations must not invent unspecified mechanics or duplicate the numerical authority.
