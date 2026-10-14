class_name GullCallAudio
extends Node3D
## Individual mono point source; shared clips and bounded concurrent voices.
## Calls are derived from bird identity/shared time, not new per-frame randomness.
const ROOT := "res://resources/audio/wildlife/gulls/"
const VARIANTS := {"contact": 4, "long": 3, "quiet": 3, "alarm": 2}
const MAX_VOICES := 8
static var _voices: Array[WeakRef] = []
static var _envelopes: Dictionary = {}
var enabled := true:
	set(value):
		enabled = value
		if not value and is_instance_valid(emitter): emitter.stop()
var gain_db := -3.0
var emitter: SpatialSoundEmitter
var last_clip := ""
var _last_block := -1
var _last_time := -1.0
var _heard_alarm := false

func _ready() -> void:
	if _envelopes.is_empty():
		var envelope_file := "res://resources/audio/wildlife/gulls/envelopes.json"
		if FileAccess.file_exists(envelope_file):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(envelope_file))
			if parsed is Dictionary: _envelopes = parsed
	emitter = SpatialSoundEmitter.new()
	emitter.name = "GullVoice"
	emitter.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	emitter.unit_size = 8.0
	emitter.max_distance = 140.0
	emitter.max_db = 0.0
	emitter.panning_strength = 1.3
	emitter.emission_angle_enabled = true
	emitter.emission_angle_degrees = 70.0 # Half-angle: a broad 140-degree forward cone.
	emitter.emission_angle_filter_attenuation_db = -3.0
	add_child(emitter)
	_voices.append(weakref(emitter))

static func call_for(seconds: float, profile: GullProfile, resting: bool) -> Dictionary:
	var block := int(floor(seconds / 24.0))
	var identity := posmod(profile.bird_id * 104729 + roundi(profile.phase_offset * 100000.0) + 761, 2147483647)
	var code := posmod((identity + block * 48271) * 48271, 2147483647)
	var category := "contact"
	if resting and code % 3 != 0: category = "quiet"
	elif code % 4 == 0: category = "long"
	return {"block": block, "at": float(block) * 24.0 + 2.0 + float(code % 1600) / 100.0,
		"silent": code % 5 < (2 if resting else 1), "category": category,
		"variant": 1 + posmod(identity + block, int(VARIANTS[category])),
		# Quantize inaudible precision so JSON round-trips preserve the call exactly.
		"pitch": snappedf(clampf(1.0 + (1.0 - profile.maturity()) * 0.05 + (1.0 - profile.size_scale) * 0.15 + (float(code % 9) - 4.0) * 0.008, 0.90, 1.12), 0.0001)}

func tick(seconds: float, profile: GullProfile, resting: bool, alarm: bool = false) -> void:
	if not enabled or not is_visible_in_tree():
		emitter.stop()
		_last_time = seconds
		return
	if alarm and not _heard_alarm:
		play_call("alarm", 1 + posmod(profile.bird_id, 2), 1.0, true)
	_heard_alarm = alarm
	var call := call_for(seconds, profile, resting)
	if seconds < _last_time: _last_block = -1
	if seconds >= float(call.at) and _last_block != int(call.block):
		_last_block = int(call.block)
		# A client entering range must not replay old calls from the current block.
		if not call.silent and (seconds - float(call.at) < 0.25 or (_last_time >= 0.0 and _last_time <= float(call.at))):
			play_call(call.category, call.variant, call.pitch)
	_last_time = seconds

func play_call(category: String, variant: int, pitch: float = 1.0, interrupt: bool = false) -> bool:
	if not enabled or not is_visible_in_tree() or not VARIANTS.has(category): return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > emitter.max_distance: return false
	if emitter.playing and not interrupt: return false
	var playing := 0
	for i in range(_voices.size() - 1, -1, -1):
		var voice: Variant = _voices[i].get_ref()
		if not is_instance_valid(voice): _voices.remove_at(i)
		elif voice != emitter and voice.playing: playing += 1
	if playing >= MAX_VOICES: return false
	var clip := ROOT + "%s_%02d.wav" % [category, clampi(variant, 1, VARIANTS[category])]
	var stream := AudioLibrary.stream(clip)
	if stream == null: return false
	emitter.stop()
	emitter.stream = stream
	emitter.bus = AudioLibrary.bus(clip)
	emitter.pitch_scale = pitch
	emitter.source_db = gain_db
	emitter.play()
	last_clip = clip
	return true

func _process(_delta: float) -> void:
	if emitter.playing:
		var camera := get_viewport().get_camera_3d()
		if not enabled or not is_visible_in_tree() or camera == null or camera.global_position.distance_to(global_position) > emitter.max_distance:
			emitter.stop()

func beak_amount() -> float:
	if not is_instance_valid(emitter) or not emitter.playing: return 0.0
	var values: Array = _envelopes.get(last_clip.get_file().get_basename(), [])
	if values.is_empty(): return 0.0
	var frame := emitter.get_playback_position() * 50.0
	var index := clampi(int(frame), 0, values.size()-1)
	return lerpf(float(values[index]), float(values[mini(index+1,values.size()-1)]), fposmod(frame,1.0))

func _exit_tree() -> void:
	if is_instance_valid(emitter): emitter.stop()
	for i in range(_voices.size() - 1, -1, -1):
		var voice: Variant = _voices[i].get_ref()
		if not is_instance_valid(voice) or voice == emitter:
			_voices.remove_at(i)
