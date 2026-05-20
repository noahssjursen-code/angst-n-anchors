class_name WalkingNpc
extends NpcBase

## Ambient walker — wanders a deterministic loop around the port to make the
## dock feel alive. Position is `AmbientPopulation.local_transform_at(...)` so
## two clients with the same seed + clock see the walker in bit-identical
## places without any replication. Add a dozen per port for free.
##
## Inherits NpcBase (Node3D — no collider, no physics overhead), so the
## player passes straight through. Configure via port_seed / npc_index /
## port_radius before adding to the tree; _process polls AmbientPopulation
## each frame and drives the WalkAnimator from cumulative distance walked.

@export var port_seed:    int   = 0
@export var npc_index:    int   = 0
@export var port_radius:  float = 50.0
## Local-space anchor for the patrol loop centre. Usually the
## `PortFacilities.position` within the port plot.
@export var anchor_offset: Vector3 = Vector3.ZERO

var _anim: WalkAnimator
## Precomputed patrol loop: waypoints, segment lengths, perimeter, walk speed.
## Pure function of (port_seed, npc_index, port_radius) — captured once at
## ready so the per-frame path is just a segment-walk + lerp.
var _loop_data: Dictionary


func _ready() -> void:
	# Walker visual variety: each gets a slightly different palette derived
	# from its own (port_seed, npc_index). Deterministic — same walker looks
	# the same on every client.
	var rng := RandomNumberGenerator.new()
	rng.seed = port_seed ^ ((npc_index + 1) * 0x12345789) ^ 0xC010C010  # 'COLO'
	skin_color     = Color.from_hsv(rng.randf_range(0.05, 0.10), 0.45, rng.randf_range(0.55, 0.80))
	clothing_color = Color.from_hsv(rng.randf(),                 0.45, rng.randf_range(0.30, 0.65))
	trousers_color = Color.from_hsv(rng.randf(),                 0.30, rng.randf_range(0.18, 0.40))
	super._ready()
	_loop_data = AmbientPopulation.build_loop(port_seed, npc_index, port_radius)
	# NpcBase builds synchronously now → animator can attach in the same frame.
	_anim = WalkAnimator.new()
	_anim.attach(self)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var t := Time.get_ticks_msec() * 0.001
	var xform := AmbientPopulation.transform_along_loop(_loop_data, t)
	# Walk cycle: cumulative distance = speed × time. Locks gait visually to
	# patrol speed without any per-walker state.
	var dist  : float = float(_loop_data["speed"]) * t
	if _anim != null and _anim.is_ready():
		_anim.update(dist)
	xform.origin += anchor_offset
	transform = xform
