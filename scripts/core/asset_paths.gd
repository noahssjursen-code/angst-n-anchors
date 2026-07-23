class_name AssetPaths
extends RefCounted

## Centralised constant table for asset paths that appear in multiple files.
## Single source of truth means renaming or relocating an asset is a one-line
## change here instead of hunting through every NPC + UI script.

# ── Character meshes ─────────────────────────────────────────────────────────
const CHARACTER_BASE_DIR := "res://resources/data/meshes/characters/"
const NPC_BASE_MESH      := CHARACTER_BASE_DIR + "npc_base.json"
const NPC_CHARACTER_STUDY_MODEL := "res://resources/data/models/characters/npc_character_study.json"
const ICELANDER_SWEATER_PROOF_MODEL := "res://resources/data/models/characters/prototypes/icelander_sweater.json"

# ── Hats (referenced by NPC subclasses and the character creator) ────────────
const HAT_FLAT_CAP   := CHARACTER_BASE_DIR + "hat_flat_cap.json"
const HAT_PEAKED_CAP := CHARACTER_BASE_DIR + "hat_peaked_cap.json"

# ── Vessels (hand-authored scenes; no hull JSON catalog) ─────────────────────
const VESSEL_SCENE_DIR := "res://scenes/vessels/"

# ── Dock + lighthouse + foghorn meshes ───────────────────────────────────────
const DOCK_BOLLARD       := "res://resources/data/meshes/docks/docking_bollard.json"
const DOCK_PLANK         := "res://resources/data/meshes/docks/dock.json"
const DOCK_CONCRETE_PIER := "res://resources/data/meshes/docks/concrete_pier.json"

# ── Light fixture models ─────────────────────────────────────────────────────
const LIGHT_NAV_PORT      := "res://resources/data/lights/nav_light_port.json"
const LIGHT_NAV_STARBOARD := "res://resources/data/lights/nav_light_starboard.json"
const LIGHT_NAV_MASTHEAD  := "res://resources/data/lights/nav_light_masthead.json"
const LIGHT_NAV_STERN     := "res://resources/data/lights/nav_light_stern.json"
const LIGHT_WORK          := "res://resources/data/lights/work_light.json"

# ── Save / cache ─────────────────────────────────────────────────────────────
const USER_SAVE_DIR        := "user://save/"
const USER_PLAYER_SAVE     := USER_SAVE_DIR + "player.json"
const USER_SETTINGS_PATH   := "user://settings.cfg"
const USER_ORDERS_DIR      := "user://shipwright_orders/"
