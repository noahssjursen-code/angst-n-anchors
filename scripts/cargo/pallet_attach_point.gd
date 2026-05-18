class_name PalletAttachPoint
extends Node3D

## Invisible positional marker at one corner of a Pallet — the crane's chains
## anchor here. Visual highlighting moved to PalletNode (a single halo per
## eligible pallet, instead of 4 corner rings).

const GROUP := "pallet_attach_point"

## The PalletNode this socket belongs to.
var pallet_node: Node3D = null
## 0..3 — used by the crane to position chains consistently.
var corner_index: int = 0


func _ready() -> void:
	add_to_group(GROUP)
