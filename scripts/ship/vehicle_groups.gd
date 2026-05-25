extends RefCounted

## Source of truth for the runtime groups that vehicle-side components use
## to declare themselves to the network layer.
##
## Background: Replicators shouldn't enumerate concrete classes
## (`is BoatCamera`, `is BridgeInteractable`, ...) to decide what to strip
## from remote visuals and where to wire pilot-board signals. With these groups,
## the vehicle components opt in instead — the network layer stays vehicle-agnostic.
##
## Join the relevant groups in your script's `_init()` (not `_ready`):
## the remote visual strip walks the freshly-built subtree before it enters
## the scene tree, so anything joining a group later than `_init` will be missed.
##
## Usage:
##     const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")
##     func _init() -> void:
##         add_to_group(VehicleGroups.SHIP_OWNER_ONLY)

## Tag any node that should be removed from a remote (non-owner) visual.
## Use for cameras, input controllers, engine audio, board prompts — anything
## that only makes sense for the local player who actually owns or pilots the vehicle.
const SHIP_OWNER_ONLY := "ship_owner_only"

## Tag any node that, when its `player_boarded` / `player_exited` signals
## fire on a locally-owned vehicle, should cause the NetworkManager to
## mark the local player as occupying that vehicle (so other clients hide
## the avatar while boarded, and show it again on exit). Implies the node
## also exposes both signals.
const BOARDING_HIDES_OCCUPANT := "boarding_hides_occupant"
