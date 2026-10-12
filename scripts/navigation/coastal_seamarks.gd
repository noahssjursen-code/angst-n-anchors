class_name CoastalSeamarks
extends Node3D
## Seeded fixed Norwegian perches. The pointer marks a deeper side, not a
## vessel-specific safe channel. Geometry is shared and streamed near observers.
const MODEL := "res://resources/models/navigation/jernstang.glb"
const SPACING_M := 450.0
const VIEW_RADIUS_M := 2600.0
var records: Array[Dictionary] = []
var _instances: Dictionary = {}
var _elapsed := 1.0
var _worker: Thread

func configure_async(layout: WorldLayout, ports: Array) -> void:
	if _worker!=null: _worker.wait_to_finish()
	_worker=Thread.new()
	_worker.start(plan.bind(layout,ports.duplicate()))

func _exit_tree() -> void:
	if _worker!=null: _worker.wait_to_finish(); _worker=null

func configure(layout: WorldLayout, ports: Array) -> void:
	records = plan(layout, ports)

static func plan(layout: WorldLayout, ports: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Mark submerged rock formations beside usable water, never generic beaches.
	for feature in layout.rock_features():
		if feature.get("kind", "crest") != "crest": continue
		var at: Vector2 = feature.position
		var best_direction := Vector2.ZERO
		var best_score := -INF
		# Walk out to the shallow boundary, not the centre of the formation.
		for i in 16:
			var direction := Vector2.from_angle(float(i)*TAU/16.0)
			var candidate: Vector2 = feature.position
			for distance in range(2,81,2):
				var sample_at: Vector2 = feature.position + direction * distance
				if layout.sample_water_depth(sample_at) > 4.0: break
				candidate = sample_at
			var depth := layout.sample_water_depth(candidate)
			if depth < 1.5 or depth > 4.0 or layout.sample_signed_distance(candidate) < 80: continue
			if not deeper_side(layout,candidate,direction): continue
			if not passage_clear(layout,candidate,direction): continue
			var score := layout.sample_water_depth(candidate+direction*60)
			if score > best_score:
				best_score = score
				best_direction = direction
				at = candidate
		if best_direction == Vector2.ZERO: continue
		var excluded := false
		for port in ports:
			var p: Vector3 = port.world_position
			if at.distance_to(Vector2(p.x,p.z)) < 450.0:
				excluded = true
				break
		for mark in result:
			if at.distance_to(mark.position) < SPACING_M:
				excluded = true
				break
		if excluded: continue
		result.append({"id":"perch-%d-%d-%d" % [layout.seed,roundi(at.x),roundi(at.y)],
			"position":at,"direction":best_direction,"depth_m":layout.sample_water_depth(at),"kind":"submerged_rock"})
	return result

static func deeper_side(layout: WorldLayout, at: Vector2, direction: Vector2) -> bool:
	var previous := layout.sample_water_depth(at)
	for distance in [25.0,50.0,100.0,160.0]:
		var center: Vector2 = at + direction * distance
		var depth := layout.sample_water_depth(center)
		if layout.is_land(center) or depth < previous: return false
		previous = depth
		for side in [-1.0,1.0]:
			var p: Vector2 = center + Vector2(-direction.y,direction.x)*distance*0.25*side
			var clearance := 3.0 if distance < 50 else 5.0
			if layout.is_land(p) or layout.sample_water_depth(p) < clearance: return false
	return previous >= 12.0


## A 60 m wide passage 30-90 m on the indicated side, with 180 m of
## approach in BOTH directions. All samples use the final combined terrain,
## including neighbouring ridges and shores, not just this feature's shape.
## This is a 6 m design-depth passage, not clearance for every vessel/draft.
static func passage_clear(layout: WorldLayout, at: Vector2, direction: Vector2) -> bool:
	var along := Vector2(-direction.y,direction.x)
	for offset in range(30,91,10):
		for distance in range(-180,181,10):
			var p := at + direction * offset + along * distance
			if layout.is_land(p) or layout.sample_water_depth(p) < 6.0: return false
	return true


func _process(delta: float) -> void:
	if _worker!=null:
		if _worker.is_alive(): return
		records=_worker.wait_to_finish(); _worker=null
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	var observer := WorldReference.visual_position(get_viewport())
	var center := Vector2(observer.x,observer.z)
	for record in records:
		var id: String = record.id
		var nearby := center.distance_to(record.position) < VIEW_RADIUS_M
		if nearby and not _instances.has(id):
			var pole := instantiate_mark(record)
			add_child(pole)
			_instances[id] = pole
		elif not nearby and _instances.has(id):
			_instances[id].queue_free()
			_instances.erase(id)

static func instantiate_mark(record: Dictionary) -> Node3D:
	var pole := (load(MODEL) as PackedScene).instantiate() as Node3D
	var at: Vector2 = record.position
	var direction: Vector2 = record.direction
	pole.position = Vector3(at.x,WaveSurface.WATER_LEVEL,at.y)
	# Authored +X is the pointer. Godot yaw maps +X to (cos(yaw),-sin(yaw)).
	pole.rotation.y = atan2(-direction.y,direction.x)
	pole.set_meta("seamark_id",record.id)
	return pole
