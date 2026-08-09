class_name WorldUnits
extends RefCounted

## Single source of truth for world scale.
## 1 Godot unit = 1 metre. No feel multipliers, no 2× bandages.

const METRE := 1.0

## Standing captain / NPC height (metres).
const PLAYER_HEIGHT_M := 1.8

## Default shipyard brick / deck grid cell edge (metres).
## A 30×24 m deck stays a 30×24 grid at the 1 m cell scale.
const DECK_CELL_M := 0.5
