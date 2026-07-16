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
| `props/` | Fuel station pad, portable props |
| `cargo/` | Cubed container mesh |
| `cranes/` | Bulk / provision crane part meshes |
| `terrain/` | Island / landmass meshes |

Authoring rules and mesh recipes: [`meshes/GUIDE.md`](meshes/GUIDE.md).

## `models/`

Multi-part assemblies (`ModelAssembler` root JSON with a `parts` array).

| Folder | Contents |
|--------|----------|
| `ships/` | Vessel assemblies (e.g. tanker, bulk carrier) |
| `buildings/` | Composed structures (lighthouse, foghorn building) |
| `cargo/` | Container cube assembly |
| `dockyard/` | Quay cranes (bulk grab, provision T-crane) |

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
| `res://scenes/apps/shipyard_brick_editor.tscn` | Paint decks on official hulls; Save official prebuilt JSON |
| `res://scenes/apps/vessel_registration_audit.tscn` | Edit vessel law and audit official registration paperwork |

Inspect-only fixtures live under `scenes/showcases/` (port / player / cargo / ship).

The catalog starts empty. Building blueprints use the same
`BrickCatalog` kit as vessel decks; marine-only bricks are filtered via
`ship_only`. Authoring pads start at 32×16×32 m and grow as you build —
there is no fixed building size ceiling. Optional per-cell `"color": [r,g,b]` overrides the brick’s catalog colour.
Floor bricks are surfaces: they share a cell with walls/props via an optional
`"surface"` object on the content cell (erase removes content first, then floor).

## `ports/`

`modules/catalog.json` contains data-only port module templates used for the
foundation root (and reserved for later growth). It contains no meshes or
gameplay functionality.

Trade imports/exports are derived by `PortTradeProfile`. `PortLayoutGenerator`
traces the coast, fits a foundation, and stores `berth_plan` (asphalt pads +
dedicated quays) on the initial `PortLayoutGraph`. Later growth persists that
graph; it does not alter this template catalog or regenerate a finished harbour
shape from the seed.

## `vessels/prebuilt/`

Source-controlled finished store ships authored by the
**Shipyard brick editor** app
(`scenes/apps/shipyard_brick_editor.tscn`).

```json
{
  "format_version": 2,
  "id": "testvik_ferry",
  "name": "Testvik Ferry",
  "hull_id": "hull_45x16_cat",
  "registration_id": "passenger_vessel",
  "price_marks": 42000,
  "shaft_power_kw": 18000,
  "brick_layout": {
    "hull_id": "hull_45x16_cat",
    "cells": {},
    "container_pads": [],
    "bulk_holds": []
  }
}
```

These files are game-owned presets and should be committed. Every valid preset
is listed in the shipwright catalog as a ready-built purchase. Player-owned
vessel records remain in `user://save/player.json`.

`vessels/registrations/catalog.json` is the versioned legal code. Registrations
inherit the general-vessel checklist and define typed count, capacity, equipment
rating, and placement rules. Hull budgets are absolute physical ceilings;
registration limits may only tighten them. Use the registration audit app to edit
the catalog and certify every prebuilt. Do not hand-author a stored “passed” flag.

`vessels/hulls/catalog.json` contains reusable geometry components only:
dimension-based `hull_id`, L×B×depth/draft, form, and optional default power.
It never contains product names, prices, roles, or brick capabilities. Multiple
prebuilts may reference the same hull with different layouts and shaft power.

## Engine apps

Runnable Godot apps for authoring (not in-game UI). Scripts in `scripts/apps/`;
scenes in `scenes/apps/`.

| Scene | Script | Writes |
|-------|--------|--------|
| `building_brick_editor.tscn` | `BuildingBrickEditor` | `resources/data/buildings/*.json` |
| `shipyard_brick_editor.tscn` | `ShipyardBrickEditor` | `resources/data/vessels/prebuilt/*.json` |
| `vessel_registration_audit.tscn` | `VesselRegistrationAudit` | registration catalog; audits prebuilts |

## Showcases

Inspect-only fixtures under `scenes/showcases/` (port / player / cargo / ship).
They do not write game data.
