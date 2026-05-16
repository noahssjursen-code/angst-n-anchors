# Angst 'n Anchors

A maritime trading game set on the Norwegian coast in the early 1980s. You start with a busted skiff and some pocket money. The sea is already busy with ships that aren't yours. You intend to change that.

"Angst" is a real English word — borrowed from German, fully absorbed. It means low-grade dread, anxiety, the feeling that things could go wrong at any moment. That's the texture of being a small operator in a world where bigger players have already carved up the routes.

---

## The Core Loop

Ports buy things and sell things. Your job is to be in the right place with the right cargo at the right price.

Every port has exports (surplus, sells cheap) and imports (shortage, pays well). You buy low, sail, sell high. The catch is that everyone else is doing the same — and most of them started before you.

No production simulation. No animated lumber mills in the forest. The port just has fish. The other port just wants fish. You connect them.

---

## Setting

**Early 1980s. Norwegian fjord coast.**

Diesel engines. VHF radio. Paper charts. No GPS, no mobile phones. The harbour master knows every captain by name and has opinions about all of them.

The maritime world of this era runs on personal relationships and reputation. A shipping agent who trusts you gets you the contract. A harbour master who respects you finds a berth when the dock looks full. A chandler who's seen you pay on time extends credit in a bad week.

The ports are working ports — coal and iron ore on the bulk berths, timber and general cargo at the derricks, the occasional container on the newer gantry cranes. Fuel pontoons at the end of the quay. The harbour master office overlooking the whole operation.

---

## What It Feels Like

**Euro Truck Simulator on water.** Early game is hands-on and physical. You are in the boat. You feel every delivery. You sail the route yourself, watch the fuel, check the weather over the VHF. The world has real distance. A run to the far coast takes time. That time matters.

**A living world you're entering late.** When you start, established shipping companies already run the major routes. The contract board has deals you can't afford or don't have the rep to take. Big haulers pass you in open water. You are not the protagonist of this world — yet. You're an interloper, picking up scraps and looking for the angle nobody else has found.

**Relaxing with a current of dread underneath.** Most of the time, sailing is calm. The sea is beautiful. A good run is satisfying in a quiet way. But you have a contract with a deadline. Your hull took a hit in last night's weather. A rival just took your berth. The angst is always there — not loud, just present.

---

## Ports

The port is the center of everything.

Each port is a procedurally generated layout on a rectangle of ground — one side of the rectangle is always the dock face, flush against the water. No piers extending out; ships come alongside.

**The dock** is the working core:
- Berth slots sized to the port's maximum permitted ship class
- One crane per berth, typed to the cargo that berth handles
- A cargo apron behind each crane where goods stage before trucking
- A fuel point at the quay end

**The port buildings** sit behind the dock:
- Harbour Master office — the first stop for any captain entering port
- Shipping Agent — contracts, paperwork, connections
- Chandlery — stores, provisions, small equipment
- Marine Engineer — repairs and maintenance
- Customs & Excise (larger ports) — bonded cargo, inspection
- Warehouse — covered storage for cargo awaiting clearance or collection
- Town — the civilian world behind the working port

Ports range from small coastal landings (one general berth, a harbour master in a shed, a chandlery) to medium working ports (two or three typed berths, customs office, full facilities) to large industrial ports (container gantries, bulk grab cranes, the works).

**Port size determines everything:** what ship classes can dock, what cargo types are handled, how many berths are available, what facilities exist.

---

## Cargo

Cargo comes in tiers. Handling it requires the right equipment at the right berth.

| Tier | Examples | How it moves |
|------|----------|--------------|
| **Bulk** | Coal, iron ore, grain | Grab/bucket crane, conveyor — poured in, scooped out |
| **Break-bulk** | Timber bundles, drums, bagged goods | Derrick crane, sling lifts — unit loads, irregular shapes |
| **General cargo** | Palletised crates, packaged goods | Standard crane, forklift — the current player-carry mechanic |
| **Container** | ISO containers | Gantry crane — standardised, fastest throughput |

A port's accepted cargo types come directly from its berth configuration. A port with one general berth and one bulk berth accepts general cargo and bulk — that's it. Bring the wrong cargo type to the wrong port and the harbour master turns you away.

The current player-carry (crate) system is general cargo tier — a working placeholder until crane mechanics are built. The data model is the same; only the delivery mechanism changes.

---

## Ship Classes

Ships have a class that determines where they can dock.

| Class | Name | Length |
|-------|------|--------|
| 0 | Launch / Tender | < 10 m |
| 1 | Coastal Trader | 10 – 30 m |
| 2 | Short Sea Coaster | 30 – 60 m |
| 3 | Handysize Feeder | 60 – 100 m |
| 4 | Deep Sea Freighter | 100 m+ |

Every dock has a maximum ship class. A small coastal landing doesn't want a deep sea freighter in the berth. The harbour master enforces this — and the berth indicators on the water tell you at a glance how big a slot is before you commit.

Berth count is derived from dock length and ship class. A dock built for Coastal Traders fits more ships than one sized for Handysize Feeders. A longer dock automatically has more berths.

---

## The Harbour Master

The harbour master is not an obstacle — he's a relationship.

Before entering a port you contact him on VHF (channel 12 or 16 depending on the port). You tell him your vessel name, your class, your intended cargo. He tells you if there's a berth and what it'll cost. You don't just sail in and tie up wherever you like. This is Norway in 1983.

At the harbour master office you can:
- Request a berth (see what's free, get one assigned, be told no if your class is too large)
- Pay harbour dues
- Ask what cargo types and ship classes the port accepts

Berths have state: **free**, **reserved**, **occupied**. In multiplayer, two captains can't be assigned the same berth — the harbour master mediates. The reservation system is designed with this in mind from the start.

---

## The Contract System

Beyond spot trading there's a live board of posted deals — real opportunities and real obligations.

- **Spot offers** — take it or leave it, short window
- **Delivery contracts** — binding, deadline, penalty if missed
- **Supply agreements** — steady volume over weeks, locks your capacity
- **Tenders** — port authority posts a job, companies bid

Miss a deadline: financial penalty and reputation damage. A port that doesn't trust you won't offer you anything good. A port that relies on you becomes a relationship.

---

## A World Already in Motion

When you start the game, other shipping companies are already running routes, holding contracts, occupying berths. You'll see their ships on the water. You'll see their names on contracts you can't touch yet.

This isn't hostile — it's just true. The opportunity is to find the gaps: the island no one's bothering with, the cargo type the big operators consider too small-margin, the route slightly too risky for a company with something to lose.

---

## Progression Arc

**Early — One boat, one captain (you).** You walk the dock, talk to the harbour master, check the board. Take whatever pays. Load, sail, unload. Watch the credits climb.

**Middle — Small fleet.** A second hull, a hired captain. Suddenly two problems instead of one — payroll, coordination, scheduling. You take contracts that need reliability, not just availability.

**Late — Shipping company.** Your name is on the contract board. Port authorities have opinions about you. You personally sail when you want to, not because you have to.

No win state. No end screen. The sea does not run out of cargo.

---

## Technical Foundation

- **Godot 4.6**, GDScript only, Jolt Physics, Forward Plus renderer, D3D12 on Windows
- **Primitives only** — all in-world geometry is BoxMesh, PlaneMesh, CylinderMesh etc. built in code. No imported 3D meshes or texture files for in-world objects. Muted, functional, consistent style.
- **Data-driven** — ports, cargo, contracts, ship classes defined in data, not hardcoded logic
- **Event-driven state** — `GameState` autoload with typed sub-states (`PlayerState`, `ShipState`, `ContractState`, `WorldState`); systems post changes, others subscribe
- **Multiplayer-aware from the start** — berth reservation, harbour master mediation, state model designed for shared sessions before multiplayer is implemented

---

## Current Implementation State

The port system is the most developed area:

- `PortPlot` — `@tool` Node3D procedural port layout (ground, buildings, spawn point, all from component defs array)
- `PortDock` — self-contained dock system (quay, typed berths, typed cranes, cargo aprons, fuel point); driven by `dock_length` and `max_ship_class`
- `ShipClass` — 5-tier ship classification with lengths, beams, berth count logic
- `CargoBerthType` — GENERAL / BULK / CONTAINER with distinct crane visuals per type
- `ContractRegistry` — autoload, single source of truth for ports, contracts, spawn positions
- `Contract`, `CargoItem`, `CargoManifest` — contract data model, working end-to-end
- `HarbourMasterNpc` — in-port dialogue (berth request, vessel info, dues stub); VHF planned
- Player carry mechanic — general cargo placeholder until crane systems are built
- `GameState` sub-states — event-driven, no polling
- Debug overlay (F3), map overlay (M) with zoom/pan

**Next areas:** seeded world generation, VHF radio, crane interaction system, multiplayer berth reservation.
