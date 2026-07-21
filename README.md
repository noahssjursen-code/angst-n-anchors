# Angst 'n Anchors

**Start as a working captain. Build a maritime company that keeps moving when you leave the helm.**

Angst 'n Anchors is a maritime sandbox set among cold fjords, exposed coasts, and working harbours. The player begins with one vessel and direct responsibility for every voyage. Over time, that hands-on shipping work grows into a company of custom ships, hired crews, scheduled routes, coastal property, and industry.

The intended destination is a persistent world with two compatible forms:

- In single-player, the player competes and trades with simulated NPC companies.
- In multiplayer, player companies share an always-running server world, alongside NPC companies where appropriate.

Both modes are intended to use the same company, vessel, crew, route, and economy rules. The difference is who owns the decisions and where the authoritative simulation runs.

## The game in four ideas

### Sail the ship

Voyages are physical and deliberate. Weather, navigation, vessel handling, berthing, cargo, and distance should make each ship feel like a place rather than a menu token.

### Build the company

Money earned at sea becomes new vessels, crew wages, better equipment, new routes, and eventually land-based facilities. Ships are constructed block-by-block and remain useful assets whether the player commands them personally or assigns them to a crew.

### Compete through the economy

The long game is about securing reliable trade, understanding regional demand, controlling useful infrastructure, and outplanning rivals. Competition is primarily commercial and psychological: contracts, capacity, timing, relationships, and regional leverage matter more than combat.

### Share a slow, social world

Long passages create breathing room. Sea lanes and ports become natural places to meet, talk, cooperate, trade, and form alliances. The pace is intentionally calm at the helm and strategically demanding between voyages.

## Progression

The broad progression is:

**Captain → owner-operator → fleet manager → coastal industrialist**

Hands-on sailing remains valuable throughout. The player can take difficult or urgent work, open new routes, respond to problems, test a new vessel, or simply captain a ship because that is the part they enjoy. Automation expands the player's reach; it does not replace the maritime game.

## Current development focus

The repository currently contains the technical and playable foundations rather than the complete economy described above:

- physics-driven modular vessels assembled from data
- block-based vessel construction and compliance rules
- deterministic world, coastline, port, weather, and ocean systems
- streamed terrain and performance-oriented presentation
- data-driven cargo foundations
- authoritative, deterministic maritime traffic-network foundations
- player persistence and multiplayer-facing state seams
- single-player company onboarding with three certified starter careers
- company identity, ledger-backed money, owned inventory, and warehouse-lease foundations

Dynamic markets, hired crews, persistent commercial routes, land ownership, factories, and rival-company simulation are product direction, not claims about completed gameplay.

## Development

- Engine: Godot 4.6
- Language: GDScript
- Physics: Jolt
- Renderer: Forward Plus

Open `project.godot` in Godot 4.6. Feature inspection scenes live under `scenes/showcases/`; authoring tools live under `scenes/apps/`.

For deeper context, see:

- [Game direction](Angst%20'n%20Anchors.md)
- [Architecture](ARCHITECTURE.md)
- [Contributor and agent guidance](AGENTS.md)
- [Save format](SAVE_FORMAT.md)

## Status

Angst 'n Anchors is in active development. Systems, data formats, controls, and the playable loop are still changing.

## License

Copyright © 2026 Noah S. Sjursen. All rights reserved.
