extends Node3D
## Water sources follow the hull. Machinery is owned exclusively by BoatAudio.


var _bow: AudioStreamPlayer3D
var _stern: AudioStreamPlayer3D
var _slap_wait := 1.5


func _process(_delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	if _bow == null:
		_bow = WorldSound.loop_on(self, "res://resources/audio/world/water/bow_wash_1.wav", "BowWash")
		_stern = WorldSound.loop_on(self, "res://resources/audio/world/water/stern_wash_1.wav", "SternWash")
	var length := float(body.get("length_m"))
	if length < 1.0:
		length = 15.0
	var stern_at := Vector3(0.0, -0.35, length * 0.40)
	if _bow != null:
		_bow.position = Vector3(0.0, 0.15, -length * 0.42)
	if _stern != null:
		_stern.position = stern_at
	var speed := body.linear_velocity.length()
	var wash := clampf(speed / 6.0, 0.0, 1.0)
	WorldSound.drive(_bow, wash, -16.0)
	WorldSound.drive(_stern, wash * 0.9, -18.0)
	_slap_wait -= _delta
	var wave := clampf(WaveSurface.wave_intensity / 3.4, 0.0, 1.0)
	if _slap_wait > 0.0 or wave < 0.22 or speed < 0.35:
		return
	var side := float(body.get("beam_m")) * 0.5
	if side < 0.2:
		side = 2.0
	WorldSound.play_set("water", "hull_slap", body.to_global(Vector3(side * (-1.0 if randf() < 0.5 else 1.0), 0.2, 0.0)), -12.0)
	_slap_wait = lerpf(9.0, 2.4, wave)
