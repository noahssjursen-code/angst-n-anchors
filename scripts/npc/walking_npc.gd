class_name WalkingNpc
extends NpcBase

## Ambient walker — wanders a deterministic loop around the port to make the
## dock feel alive. Position is `AmbientPopulation.local_transform_at(...)` so
## two clients with the same seed + clock see the walker in bit-identical
## places without any replication. Add a dozen per port for free.
##
## Configured by `PortPlot._build_walkers()`: assign `port_seed`, `npc_index`,
## and `port_radius` before adding to the tree. _process polls the field every
## frame and applies the transform locally — no physics, no nav-mesh, no
## animation rig. A tiny vertical bob fakes a step cadence.

@export var port_seed:    int   = 0
@export var npc_index:    int   = 0
@export var port_radius:  float = 50.0
## Local-space anchor for the patrol loop centre. Usually the
## `PortFacilities.position` within the port plot.
@export var anchor_offset: Vector3 = Vector3.ZERO

## How fast the visual bob cycles relative to walk speed (cycles per metre).
const BOB_CYCLES_PER_M : float = 0.55
const BOB_AMPLITUDE    : float = 0.045


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
	# Ambient walkers are intangible — player walks through them, no physics
	# collisions disrupt the boat or the dock. The visual is everything.
	call_deferred("_clear_collisions")


func _clear_collisions() -> void:
	collision_layer = 0
	collision_mask  = 0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var t := Time.get_ticks_msec() * 0.001
	var xform := AmbientPopulation.local_transform_at(port_seed, npc_index, t, port_radius)
	# Tiny vertical bob to suggest stepping. Cycles with distance walked, not
	# wall-clock time, so faster walkers visibly bob faster.
	var bob := sin(t * AmbientPopulation.walk_speed_for(port_seed, npc_index)
				   * BOB_CYCLES_PER_M * TAU) * BOB_AMPLITUDE
	xform.origin   += anchor_offset
	xform.origin.y += bob
	transform = xform
