class_name WorldSound
extends RefCounted
## Short world sounds parented in the scene, at a real position.
## Missing files stay silent so a half-built library does not throw.

const ROOT := "res://resources/audio/world"
static var _last_variant: Dictionary = {}
static var _voices: Array[WeakRef] = []


static func play(path: String, at: Vector3, db: float = -6.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var stream := AudioLibrary.stream(path, false)
	if stream == null:
		return
	_voices = _voices.filter(func(ref: WeakRef): return ref.get_ref() != null)
	if _voices.size() >= 32:
		return
	var player := SpatialSoundEmitter.new()
	_voices.append(weakref(player))
	player.stream = stream
	player.source_db = db
	var distances := AudioLibrary.distance_profile(path)
	player.unit_size = distances.x
	player.max_distance = distances.y
	player.bus = AudioLibrary.bus(path)
	tree.current_scene.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


static func play_set(folder: String, base: String, at: Vector3, db: float = -6.0) -> void:
	var options: Array[String] = []
	for i in range(1, 6):
		var path := "%s/%s/%s_%d.wav" % [ROOT, folder, base, i]
		if ResourceLoader.exists(path):
			options.append(path)
	if options.is_empty():
		return
	var key := folder + "/" + base
	var previous := str(_last_variant.get(key, ""))
	if options.size() > 1:
		options.erase(previous)
	var chosen := options[randi() % options.size()]
	_last_variant[key] = chosen
	play(chosen, at, db)


static func loop_on(parent: Node3D, path: String, node_name: String) -> AudioStreamPlayer3D:
	var existing := parent.get_node_or_null(node_name) as AudioStreamPlayer3D
	if existing != null:
		return existing
	if not ResourceLoader.exists(path):
		return null
	var stream := AudioLibrary.stream(path, true)
	if stream == null:
		return null
	var player := SpatialSoundEmitter.new()
	player.name = node_name
	player.stream = stream
	player.source_db = -80.0
	var distances := AudioLibrary.distance_profile(path)
	player.unit_size = distances.x
	player.max_distance = distances.y
	player.bus = AudioLibrary.bus(path)
	parent.add_child(player)
	player.play()
	return player


static func drive(player: AudioStreamPlayer3D, amount: float, ceiling_db: float) -> void:
	if player == null:
		return
	var gain := -80.0 if amount < 0.03 else ceiling_db + linear_to_db(clampf(amount, 0.001, 1.0))
	if player is SpatialSoundEmitter:
		(player as SpatialSoundEmitter).source_db = gain
	else:
		player.volume_db = gain
