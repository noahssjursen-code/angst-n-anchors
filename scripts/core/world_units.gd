class_name WorldUnits
extends RefCounted

## Single source of truth for world scale.
## 1 Godot unit = 1 metre. No feel multipliers, no 2× bandages.

const METRE := 1.0

## Standing captain / NPC height (metres).
const PLAYER_HEIGHT_M := 1.8

## Default shipyard brick / deck grid cell edge (metres).
## Workboat is 30×24 m — cell is 1.0 m so the grid stays 30×24 (not 60×48).
const DECK_CELL_M := 1.0
