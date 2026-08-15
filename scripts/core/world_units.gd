class_name WorldUnits
extends RefCounted

## Single source of truth for world scale.
## 1 Godot unit = 1 metre. No feel multipliers, no 2× bandages.

const METRE := 1.0

## Standing captain / NPC height (metres).
const PLAYER_HEIGHT_M := 1.8

## Default shipyard brick / deck grid cell edge (metres). TWO CELLS PER METRE:
## a 30 × 24 m deck is a 60 × 48 grid, not a 30 × 24 one.
##
## This line said *"A 30×24 m deck stays a 30×24 grid at the 1 m cell scale"* —
## a comment stating 1.0 immediately above a constant that is 0.5. Read the
## constant, never this sentence; and before writing "changing DECK_CELL_M is
## safe", read the consumer list below, because it is not one subsystem.
##
## WHO CONSUMES THIS, measured 2026-08-15 (REALITY.md §4d):
##  - `DeckGrid` / `StructurePlan.cell_*_plan` — cell↔metre conversion.
##  - `BrickCatalog.size_m` = footprint × DeckGrid.CELL_M. **Halving this
##    constant halves every brick in the game**; a `railing` is 0.5 m tall.
##  - `PieceKit.node_plan` / `StructurePlan.piece_node_plan` — a piece placement
##    resolves to `cell × DECK_CELL_M`, so structure plans carrying `pieces[]`
##    DO move with this constant even though walls/decks/stairs/edges/items do
##    not. Measured on probe_piece_house: doubling the node term doubled the
##    resolved item AABB from (2,0,12)+(6,5.5,13.5) to (4,0,24)+(12,11,27).
##  - `resources/data/parts/structure_pieces.json` carries `cell_m: 0.5` and
##    `PieceKit.parse_document` reports an error if the two disagree — but it
##    reports and continues, it does not refuse to load.
##  - NOT consumed by `BuildingGrid.CELL_M`, which is an independent 1.0. That
##    disagreement is a factor of exactly 2.000 and is an open defect, not a
##    convention.
const DECK_CELL_M := 0.5
