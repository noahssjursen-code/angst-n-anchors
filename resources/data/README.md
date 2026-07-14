# Game data layout

Structured JSON lives under `resources/data/`.

## `meshes/`

Category subfolders keep large flat lists manageable. Prefer **`res://` paths** in assemblies (see `ModelAssembler`) so parts can live in any subfolder.

| Folder | Contents |
|--------|----------|
| `ships/` | Hulls, deck houses, railings, hand-authored tanker pieces |
| `docks/` | Quay pieces, bollards, piers |
| `foghorn/` | Foghorn kit meshes (tower, horn, roof, …) |
| `lighthouse/` | Lighthouse kit meshes |
| `characters/` | NPC body, hats |
| `props/` | Crates, fuel station pad, portable props |
| `terrain/` | Island / landmass meshes |

Authoring rules and mesh recipes: [`meshes/GUIDE.md`](meshes/GUIDE.md).

## `models/`

Multi-part assemblies (`ModelAssembler` root JSON with a `parts` array).

| Folder | Contents |
|--------|----------|
| `ships/` | Vessel assemblies (e.g. tanker, bulk carrier) |
| `buildings/` | Composed structures (lighthouse, foghorn building) |

Other game data (ports, contracts, themes) stays in sibling folders under `resources/data/` as before.

## `buildings/`

Source-controlled voxel-building blueprints. The **filename stem is the
blueprint id** — do not invent separate typed ids. Each JSON stores metadata
plus sparse brick-grid instructions; no generated mesh vertices.

```json
{
  "format_version": 1,
  "id": "example_workshop",
  "display_name": "Example Workshop",
  "role": "harbour_master",
  "grid_size": [32, 16, 32],
  "cells": {
    "2,0,1": { "brick_id": "foundation", "yaw": 0 },
    "2,1,1": { "brick_id": "block", "yaw": 0, "color": [0.62, 0.32, 0.24] },
    "3,0,1": { "brick_id": "block_door", "yaw": 0 }
  }
}
```

Authoring apps (run the scene directly in Godot — under `scenes/apps/`):

| Scene | Purpose |
|-------|---------|
| `res://scenes/apps/building_brick_editor.tscn` | Paint bricks, Save / Save As into this folder |
| `res://scenes/apps/port_slot_editor.tscn` | Place service slots on the default port and attach a building JSON |
| `res://scenes/apps/shipyard_brick_editor.tscn` | Paint decks on official hulls; Save official prebuilt JSON |

Inspect-only fixtures live under `scenes/showcases/` (port / player / cargo / ship).

The catalog starts empty. Building blueprints use the same
`BrickCatalog` kit as vessel decks; marine-only bricks are filtered via
`ship_only`. Authoring pads start at 32×16×32 m and grow as you build —
there is no fixed building size ceiling. Optional per-cell `"color": [r,g,b]` overrides the brick’s catalog colour.
Floor bricks are surfaces: they share a cell with walls/props via an optional
`"surface"` object on the content cell (erase removes content first, then floor).

## `ports/`

Default-port service layout authored by the port slot editor.

`default_service_slots.json` — array of slots (`harbour_master`, `shipwright`,
future roles…). Each slot has a pad pose plus an optional `blueprint_id` that
names a file under `buildings/` (stem only, no path).

## `vessels/prebuilt/`

Source-controlled deck-grid vessel presets authored by the
**Shipyard brick editor** app
(`scenes/apps/shipyard_brick_editor.tscn`).

```json
{
  "format_version": 1,
  "id": "testvik_ferry",
  "name": "Testvik Ferry",
  "hull_id": "passenger_catamaran",
  "scene_path": "res://scenes/vessels/passenger_catamaran.tscn",
  "price_marks": 0,
  "brick_layout": {
    "hull_id": "passenger_catamaran",
    "cells": {},
    "cargo_zones": []
  }
}
```

These files are game-owned presets and should be committed. Every valid preset
is listed in the shipwright catalog as a ready-built purchase. Player-owned
vessel records remain in `user://save/player.json`.

## Engine apps

Runnable Godot apps for authoring (not in-game UI). Scripts in `scripts/apps/`;
scenes in `scenes/apps/`.

| Scene | Script | Writes |
|-------|--------|--------|
| `building_brick_editor.tscn` | `BuildingBrickEditor` | `resources/data/buildings/*.json` |
| `port_slot_editor.tscn` | `PortSlotEditor` | `resources/data/ports/default_service_slots.json` |
| `shipyard_brick_editor.tscn` | `ShipyardBrickEditor` | `resources/data/vessels/prebuilt/*.json` |

## Showcases

Inspect-only fixtures under `scenes/showcases/` (port / player / cargo / ship).
They do not write game data.
