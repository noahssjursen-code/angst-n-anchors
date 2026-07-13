# Game data layout

Structured JSON lives under `resources/data/`.

## `meshes/`

Category subfolders keep large flat lists manageable. Prefer **`res://` paths** in assemblies (see `ModelAssembler`) so parts can live in any subfolder.

| Folder | Contents |
|--------|----------|
| `ships/` | Hulls, deck houses, railings, hand-authored tanker pieces |
| `docks/` | Quay pieces, bollards, piers |
| `port_buildings/` | Harbour master, warehouse, town tiles, warehouse scene props |
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

## `vessels/prebuilt/`

Source-controlled deck-grid vessel presets exported from the shipyard's
debug-only **DEV · Save official prebuilt JSON** button.

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
is automatically appended to the shipwright catalog as a ready-built purchase;
buying one skips the deck editor and commissions a fresh owned copy. Player-owned
vessel records remain in `user://save/player.json`.
