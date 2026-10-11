class_name SpatialSoundEmitter
extends AudioStreamPlayer3D
## Local presentation only. The active camera is both the listener and ray origin.
## Source gain is separate from obstruction gain so machinery updates cannot erase it.
var source_db := -80.0:
	set(value):
		source_db = value
		volume_db = source_db - 7.0 * obstruction
var obstruction := 0.0
var obstruction_enabled := true
var _target := 0.0
var _probe_wait := 0.0

func _ready() -> void:
	_probe_wait = float(get_instance_id() % 11) * 0.02

func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not playing or source_db < -65.0:
		return
	_probe_wait -= delta
	if _probe_wait <= 0.0:
		_probe_wait = 0.25
		_target = _probe(camera) if obstruction_enabled else 0.0
	obstruction = lerpf(obstruction, _target, 1.0 - exp(-delta / 0.18))
	volume_db = source_db - 7.0 * obstruction
	attenuation_filter_cutoff_hz = lerpf(5000.0, 900.0, obstruction)

func _probe(camera: Camera3D) -> float:
	var distance := camera.global_position.distance_to(global_position)
	if distance < 0.3 or (max_distance > 0.0 and distance > max_distance):
		return 0.0
	var excluded: Array[RID] = []
	# Ignore the enclosing hull collider and the listener's own body. Separate
	# cabin walls/decks still obstruct the ray; characters do not silence machinery.
	for start: Node in [self, camera]:
		var ancestor := start.get_parent()
		while ancestor != null:
			if ancestor is CollisionObject3D:
				excluded.append((ancestor as CollisionObject3D).get_rid())
			ancestor = ancestor.get_parent()
	var toward := (global_position - camera.global_position).normalized()
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position + toward * 0.1, global_position - toward * 0.1, 1 | 4, excluded)
	return 0.0 if get_world_3d().direct_space_state.intersect_ray(query).is_empty() else 1.0
