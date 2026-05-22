class_name BoatAudioSystem
extends Node

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

func _init() -> void:
	add_to_group(VehicleGroups.SHIP_OWNER_ONLY)


## Per-boat audio: engine, bow thruster, hull wash, and throttle one-shots.
##
## Spawned as a child of BoatBody. Finds sibling components by name automatically.
##
## File layout (all under res://resources/audio/ship/):
##   engine/   engine_idle_{n}.wav   engine_load_{n}.wav
##             engine_start_{n}.wav  engine_stop_{n}.wav
##   thruster/ bow_thruster_{n}.wav
##   hull/     hull_creak_{n}.wav
##   controls/ throttle_click_{n}.wav

## Volume ceilings per layer (dB).
@export var engine_db   : float = -12.0
@export var thruster_db : float = -18.0
@export var creak_db    : float = -22.0
@export var oneshot_db  : float = -8.0

## Exponential-smoothing time constant for parameter tracking.
@export var smooth_time: float = 0.25

const _AUDIO_ROOT := "res://resources/audio/ship"

# --- Looped players ---
var _engine_idle : AudioStreamPlayer
var _engine_load : AudioStreamPlayer
var _thruster    : AudioStreamPlayer
var _hull_creak  : AudioStreamPlayer

# --- One-shot pools ---
var _start_pool  : Array[AudioStreamPlayer] = []
var _stop_pool   : Array[AudioStreamPlayer] = []
var _click_pool  : Array[AudioStreamPlayer] = []

# --- Smoothed parameters ---
var _throttle_s   : float = 0.0   # abs(propulsion throttle), 0..1
var _thruster_s   : float = 0.0   # abs(lateral_input), 0..1
var _engine_gain_s: float = 0.0   # 0=silent (docked), 1=boarded; fades slowly

# --- Helm / start-sound state ---
var _helm_active     : bool  = false
var _start_cutoff_t  : float = 0.0   # count down; kills start pool when it hits 0

# --- Throttle click ---
var _last_stage_throttle: float = 0.0

const _STAGE_CLICK_THRESH : float = 0.08
const _ENGINE_FADE_TIME   : float = 2.0   # seconds to fade engine out after leaving helm


func _ready() -> void:
	var lo := _AUDIO_ROOT
	# Pick one variant randomly for each continuous layer — rotation mid-session
	# would be jarring for engine sounds, so we commit to one per session.
	_engine_idle = _load_loop_variant(lo + "/engine",   "engine_idle")
	_engine_load = _load_loop_variant(lo + "/engine",   "engine_load")
	_thruster    = _load_loop_variant(lo + "/thruster", "bow_thruster")
	_hull_creak  = _load_loop_variant(lo + "/hull",     "hull_creak")

	_start_pool = _load_oneshots(lo + "/engine",   "engine_start")
	_stop_pool  = _load_oneshots(lo + "/engine",   "engine_stop")
	_click_pool = _load_oneshots(lo + "/controls", "throttle_click")

	for p: AudioStreamPlayer in [_engine_idle, _engine_load, _thruster, _hull_creak]:
		if p != null:
			p.volume_db = -80.0
			p.play()

	# Connect to helm signals so start/stop fire on boarding, not throttle changes.
	var ctrl := get_parent().get_node_or_null("BoatController") as BoatController
	if ctrl != null:
		ctrl.helm_activated.connect(_on_helm_activated)
		ctrl.helm_deactivated.connect(_on_helm_deactivated)


func _process(delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return

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
	_engine_gain_s = lerpf(_engine_gain_s, 1.0 if _helm_active else 0.0, k_fade)

	# --- Engine start cutoff timer ---
	if _start_cutoff_t > 0.0:
		_start_cutoff_t -= delta
		if _start_cutoff_t <= 0.0:
			for p: AudioStreamPlayer in _start_pool:
				p.stop()

	# --- One-shot: throttle click on discrete stage change ---
	if absf(stage_target - _last_stage_throttle) >= _STAGE_CLICK_THRESH:
		_fire_oneshot(_click_pool)
		_last_stage_throttle = stage_target

	# --- Engine layer: constant-power blend idle ↔ load, gated by helm ---
	var e_db   := engine_db + linear_to_db(maxf(_engine_gain_s, 0.00001))
	var blend  := _throttle_s
	var amp_idle := cos(blend * PI * 0.5)
	var amp_load := sin(blend * PI * 0.5)
	if _engine_idle != null:
		_engine_idle.volume_db = e_db + linear_to_db(maxf(amp_idle, 0.00001))
	if _engine_load != null:
		_engine_load.volume_db = e_db + linear_to_db(maxf(amp_load, 0.00001))

	# --- Bow thruster: fades in above 2% input ---
	var thr_gain := smoothstep(0.02, 0.15, _thruster_s)
	if _thruster != null:
		_thruster.volume_db = thruster_db + linear_to_db(maxf(thr_gain, 0.00001)) \
			if thr_gain > 0.001 else -80.0

	# --- Hull creak: driven by wave intensity + angular velocity (roll/pitch stress) ---
	# Waves stress the hull structurally; rotation means the hull is actively flexing.
	var wave_t    := clampf(WaveSurface.wave_intensity / 3.40, 0.0, 1.0)
	var ang_t     := clampf(body.angular_velocity.length() / 1.2, 0.0, 1.0)
	var creak_t   := clampf(maxf(wave_t * 0.6, ang_t), 0.0, 1.0)
	var creak_gain := smoothstep(0.15, 0.55, creak_t)
	if _hull_creak != null:
		_hull_creak.volume_db   = creak_db + linear_to_db(maxf(creak_gain, 0.00001)) \
			if creak_gain > 0.001 else -80.0
		_hull_creak.pitch_scale = lerpf(0.92, 1.08, creak_t)



# ---------------------------------------------------------------------------
# Helm event handlers
# ---------------------------------------------------------------------------

func _on_helm_activated() -> void:
	_helm_active    = true
	_fire_oneshot(_start_pool)
	_start_cutoff_t = 2.0   # hard-cut start sound after 2 s


func _on_helm_deactivated() -> void:
	_helm_active = false
	_fire_oneshot(_stop_pool)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _fire_oneshot(pool: Array[AudioStreamPlayer]) -> void:
	if pool.is_empty():
		return
	var idle: Array[AudioStreamPlayer] = []
	for p: AudioStreamPlayer in pool:
		if not p.playing:
			idle.append(p)
	if idle.is_empty():
		return
	var p := idle[randi() % idle.size()]
	p.volume_db   = oneshot_db + randf_range(-2.0, 1.0)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


## Discovers all numbered variants ({base}_1, _2, …) and picks one randomly.
func _load_loop_variant(dir: String, base: String) -> AudioStreamPlayer:
	var candidates: Array[String] = []
	for i in range(1, 9):
		var path := "%s/%s_%d.wav" % [dir, base, i]
		if ResourceLoader.exists(path):
			candidates.append(path)
	if candidates.is_empty():
		return null
	var chosen := candidates[randi() % candidates.size()]
	var stream := ResourceLoader.load(chosen) as AudioStream
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream    = stream
	p.bus       = "Master"
	p.volume_db = -80.0
	p.autoplay  = false
	p.finished.connect(p.play)
	add_child(p)
	return p


func _load_oneshots(dir: String, base: String) -> Array[AudioStreamPlayer]:
	var pool: Array[AudioStreamPlayer] = []
	for i in range(1, 9):
		var path := "%s/%s_%d.wav" % [dir, base, i]
		if not ResourceLoader.exists(path):
			continue
		var stream := ResourceLoader.load(path) as AudioStream
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream    = stream
		p.bus       = "Master"
		p.volume_db = -80.0
		p.autoplay  = false
		add_child(p)
		pool.append(p)
	return pool
