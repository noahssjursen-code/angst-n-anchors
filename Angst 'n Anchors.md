# Angst 'n Anchors — Game Direction

This document defines the product direction. It describes what the game is trying to become without pretending that every system already exists. Current implementation contracts belong in [ARCHITECTURE.md](ARCHITECTURE.md) and [AGENTS.md](AGENTS.md).

## One-sentence pitch

**Start as a working captain in a cold maritime world, then build a persistent shipping company whose crews, vessels, routes, and coastal businesses continue operating beyond the ship you personally command.**

## Player fantasy

Taking the helm is the beginning, not the entire career.

The player starts close to the work: one ship, limited money, and direct responsibility for getting cargo safely between ports. Every expansion should grow naturally from that experience. A second vessel creates the need for a hired crew. More crews create the need for planned routes, wages, maintenance, and oversight. Reliable traffic creates the opportunity to own useful land, process goods, sell fuel, and influence a region.

The result should feel like a maritime life that gradually becomes a maritime enterprise.

## Four pillars

### 1. Tactile seafaring

Ships are real places in the world. The player handles weather, navigation, speed, berthing, cargo, and the character of a custom-built vessel. Travel takes time and the sea should feel large.

The game must preserve reasons to captain a vessel after automation becomes available: difficult passages, urgent work, unusual cargo, new-route discovery, emergencies, inspections, social voyages, or simply the pleasure of sailing.

### 2. A company built from physical assets

Growth is visible in the world. The company owns named ships, employs crews, pays operating costs, holds contracts, and eventually owns coastal land and facilities. A vessel is not merely an upgrade number; it is a designed, registered, persistent asset that can be commanded, assigned, sold, damaged, maintained, and recognized by other players.

### 3. A living commercial world

Ports and regions should have material needs and productive strengths. Companies compete for contracts, capacity, infrastructure, timing, and access. Long-term success comes from understanding the network and making commitments that rivals cannot easily displace.

The primary conflict is economic. Regional dominance should emerge from player and NPC decisions rather than from a scripted conquest screen.

### 4. Slow social play with strategic pressure

Long voyages provide quiet time for conversation, shared travel, and watching a working world pass by. Ports and shipping lanes are social spaces. Players can cooperate, trade, coordinate, and form alliances.

Under that calm surface is a competitive company game that rewards planning away from the helm: which route to enter, which ship to build, whom to hire, where to invest, and which agreement to secure before a rival does.

## The progression arc

### Working captain

- Own or operate one vessel.
- Take individual jobs and learn ports, cargo, weather, and navigation.
- Earn enough to survive and improve the ship.

### Owner-operator

- Name and establish a company.
- Keep a financial ledger and reputation.
- Customize or commission vessels for particular work.
- Choose between personally taking a job and delegating it.

### Fleet manager

- Own multiple vessels.
- Hire non-physical crew records, assign qualifications, and pay wages.
- Create repeatable services or contract routes.
- Monitor location, cargo, costs, delays, and incidents.
- Intervene personally when a route or vessel needs attention.

### Coastal industrialist

- Acquire coastline land.
- Build processing, storage, repair, and refuelling facilities.
- Connect production to the company's shipping network.
- Negotiate durable trade relationships and create regional advantages.
- Compete with mature companies for capacity and influence.

## One simulation, two modes

Single-player and multiplayer should not become separate games.

### Single-player

The local game is authoritative. NPC companies use the same economic opportunities, vessel records, crew costs, route plans, and infrastructure rules available to the player. They should create a believable established market rather than exist only as decorative traffic.

### Multiplayer

The server is authoritative. Player and NPC companies persist while individual players are offline. Clients receive the company and world state they are allowed to know, plus vessel snapshots required for local presentation. A player returning to the world sees the consequences of plans that continued in their absence.

### Shared rule

Ownership changes decision-making, not physics or economics. A player company and an NPC company should be represented by compatible data and judged by the same core rules. This is essential for fairness, deterministic testing, save compatibility, and future server authority.

## Company model direction

A company should eventually be expressible as serializable authoritative data:

- identity: id, name, owner type, branding, home region
- finances: cash, income, operating expenses, wages, asset value
- reputation and commercial relationships
- vessel ledger: ownership, configuration, condition, assignment, location
- workforce: crew records, qualifications, wages, availability, assignments
- commitments: contracts, scheduled services, cargo obligations, deadlines
- holdings: land, storage, processing, repair, and fuel facilities
- activity log: deliveries, costs, incidents, changes, and decisions

Presentation must not become the authority. The company screen, world vessels, and map markers are views of these records. This allows the same model to run locally in single-player or on a persistent multiplayer server.

## Offline operation without becoming an idle game

Offline progress should execute decisions the player already made. It should not produce value without costs, capacity limits, or risk.

A crew can continue a funded and valid assignment while the owner is away. The simulation accounts for travel time, wages, fuel, cargo, berth access, and failures. Returning players should receive a readable account of what happened and be able to change the plan.

The strategic game is therefore about setting up robust operations, not pressing a reward button after a timer.

## Near-term company slice

The first useful company pass should stay small and data-first:

1. Company creation with a required name and stable id.
2. A ledger for cash, income, expenses, and recent transactions; no debt initially.
3. A vessel registry showing owned, active, idle, and personally commanded ships.
4. Non-physical crew records with wage, qualification, and vessel assignment.
5. A repeatable route or service plan that a qualified crew can operate.
6. A company activity feed explaining earnings, costs, delays, and stopped operations.
7. Deterministic persistence that can run under local authority now and server authority later.

NPC competitor strategy, physical crew characters, property, factories, and complex finance should build on this model rather than be bundled into its first implementation.

## Design guardrails

- Do not make the company layer a detached spreadsheet game; decisions must produce visible ships, cargo, workers, and facilities in the world.
- Do not make automation strictly better than captaining. Delegation trades direct control for wages, constraints, and operational risk.
- Do not give NPC companies hidden rules that invalidate player strategy. Difficulty should come from goals, resources, knowledge, and decision quality.
- Do not simulate distant presentation at full fidelity. Authoritative data can be lightweight while nearby vessels receive richer local representation.
- Do not confuse persistence with constant per-frame simulation. Advance distant operations analytically or at coarse intervals, then materialize them when relevant.
- Do not promise a completed economy in public documentation until the playable systems support it.

## Current foundation

The present repository focuses on foundations: modular vessels, vessel compliance, sailing physics, deterministic world and port generation, ocean and weather, terrain streaming, cargo data, player persistence, and deterministic maritime traffic-network work.

Company creation, hired crews, commercial route execution, rival companies, land ownership, factories, and the complete player-driven economy remain planned gameplay. The next systems should preserve the authority and serialization boundaries needed for both single-player and persistent multiplayer.
