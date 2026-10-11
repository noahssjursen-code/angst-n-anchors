class_name BoatAudioSystem
extends Node3D

## Per-boat audio: engine, bow thruster, hull wash, and throttle one-shots.
##
## Spawned as a child of BoatBody. Finds sibling components by name automatically.
##
## File layout (all under res://resources/audio/ship/):
##   engines/<audio_bank>/  engine_idle_{n}.wav  engine_load_{n}.wav
##                          engine_start_{n}.wav engine_stop_{n}.wav
##   Hulls with no preset use the compact inline-six bank.
##   thruster/ bow_thruster_{n}.wav
##   hull/     hull_creak_{n}.wav
##   controls/ throttle_click_{n}.wav

## Volume ceilings per layer (dB).
@export var engine_db   : float = -6.0
@export var thruster_db : float = -18.0
@export var creak_db    : float = -22.0
@export var oneshot_db  : float = -8.0

## Exponential-smoothing time constant for parameter tracking.
@export var smooth_time: float = 0.25

const _AUDIO_ROOT := "res://resources/audio/ship"

# --- Looped players ---
var _engine_idle : SpatialSoundEmitter
var _engine_load : SpatialSoundEmitter
var _thruster    : SpatialSoundEmitter
var _hull_creak  : SpatialSoundEmitter

# --- One-shot pools ---
var _start_pool  : Array[SpatialSoundEmitter] = []
var _stop_pool   : Array[SpatialSoundEmitter] = []
var _click_pool  : Array[SpatialSoundEmitter] = []

# --- Smoothed parameters ---
var _throttle_s   : float = 0.0   # abs(propulsion throttle), 0..1
var _thruster_s   : float = 0.0   # abs(lateral_input), 0..1
var _engine_gain_s: float = 0.0   # 0=stopped, 1=running; independent of camera or ownership

# --- Helm / start-sound state ---
var _helm_active     : bool  = false
var _heard_running   : bool  = false

# --- Throttle click ---
var _last_stage_throttle: float = 0.0
var _rpm_ratio: float = 1.0
var _engine_dir: String = ""
var _placement_wait := 0.0

const _STAGE_CLICK_THRESH : float = 0.08
const _ENGINE_FADE_TIME   : float = 2.0   # seconds to fade machinery state


func _ready() -> void:
	var lo := _AUDIO_ROOT
	# Pick one variant randomly for each continuous layer — rotation mid-session
	# would be jarring for engine sounds, so we commit to one per session.
	_thruster    = _load_loop_variant(lo + "/thruster", "bow_thruster")
	_hull_creak  = _load_loop_variant(lo + "/hull",     "hull_creak")
	_click_pool = _load_oneshots(lo + "/controls", "throttle_click")

	for p: SpatialSoundEmitter in [_thruster, _hull_creak]:
		if p != null:
			p.source_db = -80.0
			p.play()
	_bind_engine_from_parent()

	# Helm state contributes to the existing machinery-running presentation.
	var ctrl := get_parent().get_node_or_null("BoatController") as BoatController
	if ctrl != null:
		ctrl.helm_activated.connect(_on_helm_activated)
		ctrl.helm_deactivated.connect(_on_helm_deactivated)


func _process(delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return

	_placement_wait -= delta
	if _placement_wait <= 0.0:
		_placement_wait = 0.25
		_update_emitter_positions(body)
	var prop   := body.get_node_or_null("PropulsionComponent")
	var thr    := body.get_node_or_null("BowThrusterComponent")
	var ctrl   := body.get_node_or_null("BoatController")

	var raw_throttle := absf(float(prop.get("throttle")))      if prop else 0.0
	var raw_lateral  := absf(float(thr.get("lateral_input"))) if thr  else 0.0

	# Commanded stage value — used for throttle click detection.
	var stage_target := absf(float(ctrl.get("_throttle"))) if ctrl != null else 0.0

	# --- Exponential smoothing ---
	var k      := 1.0 - exp(-delta / maxf(smooth_time, 0.001))
	var k_fade := 1.0 - exp(-delta / maxf(_ENGINE_FADE_TIME, 0.001))
	_throttle_s    = lerpf(_throttle_s,    raw_throttle,                           k)
	_thruster_s    = lerpf(_thruster_s,    raw_lateral,                            k)
	var turning := prop != null and bool(prop.get("engine_running"))
	# Machinery keeps idling in neutral after the captain leaves the helm.
	if body is BoatBody and (body as BoatBody).get_fuel_fraction() <= 0.0:
		turning = false
	if turning and not _heard_running:
		_fire_oneshot(_start_pool)
	if _heard_running and not turning:
		_fire_oneshot(_stop_pool)
	_heard_running = turning
	_engine_gain_s = lerpf(_engine_gain_s, 1.0 if turning else 0.0, k_fade)

	# --- One-shot: throttle click on discrete stage change ---
	if absf(stage_target - _last_stage_throttle) >= _STAGE_CLICK_THRESH:
		_fire_oneshot(_click_pool)
		_last_stage_throttle = stage_target

	# --- Engine layer: constant-power blend idle ↔ load, driven by machinery state ---
	var e_db   := engine_db + linear_to_db(maxf(_engine_gain_s, 0.00001))
	var blend  := _throttle_s
	var amp_idle := cos(blend * PI * 0.5)
	var amp_load := sin(blend * PI * 0.5)
	var pitch := clampf(_rpm_ratio * lerpf(0.96, 1.04, _throttle_s), 0.70, 1.50)
	if _engine_idle != null:
		_engine_idle.source_db = e_db + linear_to_db(maxf(amp_idle, 0.00001))
		_engine_idle.pitch_scale = pitch
	if _engine_load != null:
		_engine_load.source_db = e_db + linear_to_db(maxf(amp_load, 0.00001))
		_engine_load.pitch_scale = pitch

	# --- Bow thruster: fades in above 2% input ---
	var thr_gain := smoothstep(0.02, 0.15, _thruster_s) if turning else 0.0
	if _thruster != null:
		_thruster.source_db = thruster_db + linear_to_db(maxf(thr_gain, 0.00001)) \
			if thr_gain > 0.001 else -80.0

	# --- Hull creak: driven by wave intensity + angular velocity (roll/pitch stress) ---
	# Waves stress the hull structurally; rotation means the hull is actively flexing.
	var wave_t    := clampf(WaveSurface.wave_intensity / 3.40, 0.0, 1.0)
	var ang_t     := clampf(body.angular_velocity.length() / 1.2, 0.0, 1.0)
	var creak_t   := clampf(maxf(wave_t * 0.6, ang_t), 0.0, 1.0)
	var creak_gain := smoothstep(0.15, 0.55, creak_t)
	if _hull_creak != null:
		_hull_creak.source_db   = creak_db + linear_to_db(maxf(creak_gain, 0.00001)) \
			if creak_gain > 0.001 else -80.0
		_hull_creak.pitch_scale = lerpf(0.92, 1.08, creak_t)



# ---------------------------------------------------------------------------
# Helm event handlers
# ---------------------------------------------------------------------------

func _on_helm_activated() -> void:
	_helm_active    = true


func _on_helm_deactivated() -> void:
	_helm_active = false


## Installed machinery package. `audio_bank` selects the recording;
## shaft rpm pitches it against `audio_reference_rpm`.
func bind_engine(spec: Dictionary) -> void:
	var bank := str(spec.get("audio_bank", ""))
	if bank.is_empty():
		bank = "compact_i6"
	var dir := "%s/engines/%s" % [_AUDIO_ROOT, bank]
	if not ResourceLoader.exists(dir + "/engine_idle_1.wav"):
		dir = "%s/engines/compact_i6" % _AUDIO_ROOT
	_apply_rpm_ratio(spec)
	if dir == _engine_dir and _engine_idle != null:
		return
	_engine_dir = dir
	_release_player(_engine_idle)
	_release_player(_engine_load)
	_engine_idle = null
	_engine_load = null
	for player: SpatialSoundEmitter in _start_pool:
		_release_player(player)
	for player: SpatialSoundEmitter in _stop_pool:
		_release_player(player)
	_start_pool.clear()
	_stop_pool.clear()
	_engine_idle = _load_loop_variant(dir, "engine_idle")
	_engine_load = _load_loop_variant(dir, "engine_load")
	_start_pool = _load_oneshots(dir, "engine_start")
	_stop_pool = _load_oneshots(dir, "engine_stop")
	for player: SpatialSoundEmitter in [_engine_idle, _engine_load]:
		if player != null:
			player.source_db = -80.0
			player.play()


func _bind_engine_from_parent() -> void:
	var body := get_parent()
	var draft: Variant = body.get("draft") if body != null else null
	if draft is Dictionary:
		var spec := MarineEngineCatalog.resolve(str(draft.get("hull", "")), str(draft.get("engine_preset", "")))
		if not spec.is_empty():
			bind_engine(spec)
			return
	bind_engine({})


func _apply_rpm_ratio(spec: Dictionary) -> void:
	var reference := float(spec.get("audio_reference_rpm", spec.get("shaft_rpm", 0.0)))
	var shaft := float(spec.get("shaft_rpm", reference))
	if reference <= 1.0:
		_rpm_ratio = 1.0
	else:
		_rpm_ratio = clampf(shaft / reference, 0.72, 1.45)


func _release_player(player: SpatialSoundEmitter) -> void:
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _fire_oneshot(pool: Array[SpatialSoundEmitter]) -> void:
	if pool.is_empty():
		return
	var idle: Array[SpatialSoundEmitter] = []
	for p: SpatialSoundEmitter in pool:
		if not p.playing:
			idle.append(p)
	if idle.is_empty():
		return
	var p := idle[randi() % idle.size()]
	p.source_db   = oneshot_db + randf_range(-2.0, 1.0)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


## Discovers all numbered variants ({base}_1, _2, …) and picks one randomly.
func _load_loop_variant(dir: String, base: String) -> SpatialSoundEmitter:
	var candidates: Array[String] = []
	for i in range(1, 9):
		var path := "%s/%s_%d.wav" % [dir, base, i]
		if ResourceLoader.exists(path):
			candidates.append(path)
	if candidates.is_empty():
		return null
	var chosen := candidates[randi() % candidates.size()]
	var stream := AudioLibrary.stream(chosen, true)
	if stream == null:
		return null
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var p := SpatialSoundEmitter.new()
	p.stream    = stream
	p.bus       = AudioLibrary.bus(chosen)
	_configure_range(p, chosen)
	p.source_db = -80.0
	p.autoplay  = false
	add_child(p)
	return p


func _load_oneshots(dir: String, base: String) -> Array[SpatialSoundEmitter]:
	var pool: Array[SpatialSoundEmitter] = []
	for i in range(1, 9):
		var path := "%s/%s_%d.wav" % [dir, base, i]
		if not ResourceLoader.exists(path):
			continue
		var stream := AudioLibrary.stream(path, false)
		if stream == null:
			continue
		var p := SpatialSoundEmitter.new()
		p.stream    = stream
		p.bus       = AudioLibrary.bus(path)
		_configure_range(p, path)
		p.source_db = -80.0
		p.autoplay  = false
		add_child(p)
		pool.append(p)
	return pool


func _configure_range(player: SpatialSoundEmitter, path: String) -> void:
	var profile := AudioLibrary.distance_profile(path)
	player.unit_size = profile.x
	player.max_distance = profile.y
	player.max_db = 0.0


func _update_emitter_positions(body: Node3D) -> void:
	var length_m := 15.0
	var draft: Variant = body.get("draft")
	var engine_at := Vector3(0, -0.5, 3)
	if body is BoatBody:
		length_m = maxf((body as BoatBody).length_m, 1.0)
		engine_at = Vector3(0, -0.5, length_m * 0.25)
	var installed := body.get_node_or_null("InstalledEngine") as Node3D
	if installed != null:
		engine_at = to_local(installed.global_position)
	elif draft is Dictionary:
		var mount: Variant = draft.get("engine_position")
		if mount is Vector3:
			engine_at = mount
	var helm_at := Vector3(0, 1.5, -length_m * 0.15)
	var stations := body.find_children("*", "BridgeInteractable", true, false)
	if not stations.is_empty():
		helm_at = to_local((stations[0] as Node3D).global_position)
	for player: SpatialSoundEmitter in [_engine_idle, _engine_load]:
		if player != null: player.position = engine_at
	for player: SpatialSoundEmitter in _start_pool + _stop_pool:
		player.position = engine_at
	for player: SpatialSoundEmitter in _click_pool:
		player.position = helm_at
	if _thruster != null: _thruster.position = Vector3(0, -0.4, -length_m * 0.4)
	if _hull_creak != null: _hull_creak.position = Vector3(0, -0.3, 0)
