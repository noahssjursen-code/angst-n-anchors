class_name WalkAnimator
extends RefCounted

## Procedural walk-cycle driver for the articulated NPC rig.
##
## No skeleton, no Animation resource — just rotates the four limb
## `MeshTransformer` nodes (arm_left/right, leg_left/right) around their
## joints with a sine wave whose phase is the walker's *cumulative
## distance walked* (in metres). That way two NPCs walking at different
## speeds bob their legs at different visible rates without us caching
## any state.
##
## Usage (from WalkingNpc):
##     var anim := WalkAnimator.new()
##     anim.attach(self)                  # caches references to limb parts
##     ...
##     anim.update(distance_walked_m)     # call each frame
##
## Determinism: `distance_walked_m` is a pure function of (port_seed,
## npc_index, time), so two clients computing it independently get the
## same limb angles. No replication needed.

## Peak swing angle of arms/legs (radians). 0.35 rad ≈ 20° feels relaxed
## walk; 0.55 (≈ 32°) feels brisk/striding.
const SWING_AMPLITUDE_RAD : float = 0.42

## How many full leg-swing cycles per metre walked. Real humans take ~0.7
## steps per metre, so one full cycle (left+right) per ~1.4 m ≈ 0.71.
const CYCLES_PER_M : float = 0.65

## Arms swing slightly less than legs.
const ARM_AMPLITUDE_FACTOR : float = 0.80

var _arm_left:  Node3D
var _arm_right: Node3D
var _leg_left:  Node3D
var _leg_right: Node3D
var _ready:     bool = false


## Caches limb references from the NPC's assembler. Call once after the
## assembler has built (post `super._ready()` + a deferred frame).
func attach(npc: NpcBase) -> void:
	if npc == null or npc.assembler == null:
		return
	_arm_left  = npc.assembler.get_part("arm_left")
	_arm_right = npc.assembler.get_part("arm_right")
	_leg_left  = npc.assembler.get_part("leg_left")
	_leg_right = npc.assembler.get_part("leg_right")
	_ready = _arm_left != null and _arm_right != null and _leg_left != null and _leg_right != null


func is_ready() -> bool:
	return _ready


## Drive the walk cycle from cumulative distance walked. The phase is
## `distance × CYCLES_PER_M × TAU` so cycle rate is locked to gait, not
## frame rate or wall-clock — pause the walker, the legs stop mid-step.
func update(distance_walked_m: float) -> void:
	if not _ready:
		return
	var phase := distance_walked_m * CYCLES_PER_M * TAU
	# Legs: left forward when right back (opposite phase). Rotate around X
	# (pitch) — positive X = swing forward.
	var leg_swing := sin(phase) * SWING_AMPLITUDE_RAD
	_leg_left.rotation  = Vector3(-leg_swing,  0.0, 0.0)
	_leg_right.rotation = Vector3( leg_swing,  0.0, 0.0)
	# Arms: opposite to legs (right arm forward when right leg back). Slightly
	# smaller amplitude — limp swing rather than military march.
	var arm_swing := sin(phase) * SWING_AMPLITUDE_RAD * ARM_AMPLITUDE_FACTOR
	_arm_left.rotation  = Vector3( arm_swing,  0.0, 0.0)
	_arm_right.rotation = Vector3(-arm_swing,  0.0, 0.0)
