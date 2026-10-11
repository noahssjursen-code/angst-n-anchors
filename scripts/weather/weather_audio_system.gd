class_name WeatherAudioSystem
extends Node

## Independent sea, wind and rain stems driven by supported local weather.
##
## Each sound "slot" supports multiple variants named {base}_{n}.wav (n = 1, 2, 3 …).
## Variants loop continuously at -80 dB until activated. Every 40–120 seconds the slot
## randomly crossfades to a different variant, preventing repetition fatigue.
##
## Layer structure:
##   Ocean (4 slots):  calm_seas → choppy_seas → rough_seas → stormy_seas  (wave_intensity)
##   Wind  (2 slots):  wind_light  ↔  wind_gale                            (wind_force)
##   Rain  (3 slots):  rain_drizzle → rain_moderate → rain_heavy           (rain_amount)
##   Atmosphere (4 slots): calm / wet / dry gale / wet gale from rain × wind
##   Thunder: one-shot pool driven by thunder_intensity (heavy rain + wind, not every shower)
##
## File naming:
##   {base}_1.wav, {base}_2.wav, … (numbered variants)
##   or {base}.wav (single variant fallback)
##
## All files live in res://resources/audio/ per AGENTS.md layout.


# ---------------------------------------------------------------------------
# VariantSlot — owns N variants of one sound, rotates between them silently.
# ---------------------------------------------------------------------------
class VariantSlot:
	var players: Array[AudioStreamPlayer] = []

	var _cur      : int   = 0
	var _next     : int   = -1      # -1 = not crossfading
	var _xfade_t  : float = 0.0
	var _switch_cd: float = 0.0

	const XFADE_DUR      : float = 3.5   # seconds for one variant to replace another
	const SWITCH_MIN     : float = 40.0  # minimum seconds before considering a switch
	const SWITCH_MAX     : float = 120.0 # maximum seconds before a switch is forced


	func load_variants(parent: Node, dir: String, base: String) -> void:
		# Try numbered variants: {base}_1.wav … {base}_8.wav, then un-numbered fallback.
		var found: Array[String] = []
		for i in range(1, 9):
			var p := "%s/%s_%d.wav" % [dir, base, i]
			if ResourceLoader.exists(p):
				found.append(p)
		if found.is_empty():
			var p := "%s/%s.wav" % [dir, base]
			if ResourceLoader.exists(p):
				found.append(p)

		for path in found:
			var stream := AudioLibrary.stream(path, true)
			if stream == null:
				continue
			var pl := AudioStreamPlayer.new()
			pl.stream    = stream
			pl.bus       = AudioLibrary.bus(path)
			pl.volume_db = -80.0
			pl.autoplay  = false
			parent.add_child(pl)
			pl.play()
			players.append(pl)

		if not players.is_empty():
			_switch_cd = randf_range(SWITCH_MIN, SWITCH_MAX)


	## Advance the rotation timer and crossfade state. Call every frame.
	func tick(delta: float) -> void:
		if players.size() <= 1:
			return
		if _next >= 0:
			_xfade_t += delta
			if _xfade_t >= XFADE_DUR:
				# Crossfade complete — commit.
				players[_cur].volume_db = -80.0
				_cur  = _next
				_next = -1
				_switch_cd = randf_range(SWITCH_MIN, SWITCH_MAX)
		else:
			_switch_cd -= delta
			if _switch_cd <= 0.0:
				_begin_next_variant()


	## Set the overall volume for this slot (dB). Distributes across active/crossfading variants.
	func apply_volume(target_db: float) -> void:
		if players.is_empty():
			return
		# When the layer is inaudible, skip blend math and silence everything.
		if target_db <= -79.0:
			for p: AudioStreamPlayer in players:
				p.volume_db = -80.0
			return
		if _next < 0:
			# No rotation in progress — all volume to the current variant.
			for i in range(players.size()):
				players[i].volume_db = target_db if i == _cur else -80.0
		else:
			# Constant-power crossfade between _cur and _next.
			var blend := clampf(_xfade_t / XFADE_DUR, 0.0, 1.0)
			var amp_cur  := cos(blend * PI * 0.5)
			var amp_next := sin(blend * PI * 0.5)
			for i in range(players.size()):
				if i == _cur:
					if amp_cur < 1e-4:
						players[i].volume_db = -80.0
					else:
						players[i].volume_db = target_db + linear_to_db(amp_cur)
				elif i == _next:
					if amp_next < 1e-4:
						players[i].volume_db = -80.0
					else:
						players[i].volume_db = target_db + linear_to_db(amp_next)
				else:
					players[i].volume_db = -80.0


	func is_empty() -> bool:
		return players.is_empty()


	func _begin_next_variant() -> void:
		var candidates: Array[int] = []
		for i in range(players.size()):
			if i != _cur:
				candidates.append(i)
		_next    = candidates[randi() % candidates.size()]
		_xfade_t = 0.0


# ---------------------------------------------------------------------------
# Exported tuning
# ---------------------------------------------------------------------------

## Volume ceiling per layer (dB).
@export var ocean_db      : float = -18.0
@export var wind_db       : float = -18.0
@export var rain_db       : float = -10.0
@export var thunder_db    : float = -2.0

## How quickly the weather parameters are smoothed (seconds for ~63 % of change).
@export var smooth_time: float = 0.8

# ---------------------------------------------------------------------------
# Layer slots
# ---------------------------------------------------------------------------

const _AUDIO_ROOT := "res://resources/audio"

var _ocean_calm    := VariantSlot.new()
var _ocean_choppy  := VariantSlot.new()
var _ocean_rough   := VariantSlot.new()
var _ocean_stormy  := VariantSlot.new()

var _wind_light   := VariantSlot.new()
var _wind_gale    := VariantSlot.new()

var _rain_drizzle  := VariantSlot.new()
var _rain_moderate := VariantSlot.new()
var _rain_heavy    := VariantSlot.new()


var _thunder_pool    : Array[AudioStreamPlayer3D] = []
var _pending_thunder: Array[Dictionary] = []

# Wave intensity window for ocean blend.
const _WAVE_CALM: float = 0.33
const _WAVE_GALE: float = 1.10

# Smoothed source parameters.
var _wave_t : float = 0.0
var _wind   : float = 0.0
var _rain   : float = 0.0
var _roof_rain := VariantSlot.new()
var _shelter := 0.0
var _shelter_target := 0.0
var _shelter_wait := 0.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	var lo := _AUDIO_ROOT + "/looped"
	var no := _AUDIO_ROOT + "/normal"

	_ocean_calm.load_variants(self,   lo + "/ocean", "calm_seas")
	_ocean_choppy.load_variants(self, lo + "/ocean", "choppy_seas")
	_ocean_rough.load_variants(self,  lo + "/ocean", "rough_seas")
	_ocean_stormy.load_variants(self, lo + "/ocean", "stormy_seas")

	_wind_light.load_variants(self,  lo + "/wind",       "wind_light")
	_wind_gale.load_variants(self,   lo + "/wind",       "wind_gale")

	_rain_drizzle.load_variants(self,  lo + "/rain",     "rain_drizzle")
	_rain_moderate.load_variants(self, lo + "/rain",     "rain_moderate")
	_rain_heavy.load_variants(self,    lo + "/rain",     "rain_heavy")


	_thunder_pool = _load_thunder_variants(no + "/thunder", "thunder")
	_roof_rain.load_variants(self, lo + "/rain", "rain_on_roof")


func _process(delta: float) -> void:
	# --- Advance variant rotation timers ---
	for slot: VariantSlot in _all_slots():
		slot.tick(delta)

	# --- Read weather state ---
	var wl      := _weather()
	var wind_raw    := float(wl.get("wind_force"))        if wl else 0.0
	var rain_raw    := float(wl.get("rain_amount"))       if wl else 0.0
	var wave_raw   := clampf(
		(WaveSurface.wave_intensity - _WAVE_CALM) / (_WAVE_GALE - _WAVE_CALM), 0.0, 1.0)

	# --- Exponential smoothing ---
	var k := 1.0 - exp(-delta / maxf(smooth_time, 0.001))
	_wave_t  = lerpf(_wave_t,  wave_raw,    k)
	_wind    = lerpf(_wind,    wind_raw,    k)
	_rain    = lerpf(_rain,    rain_raw,    k)
	_update_shelter(delta)

	# Overhead cover muffles the open-air beds. The sea stays audible.
	var open_air := 1.0 - _shelter
	_blend_sequential(
		[_ocean_calm, _ocean_choppy, _ocean_rough, _ocean_stormy],
		lerpf(0.42, 1.0, open_air), _wave_t, ocean_db)
	_blend_sequential(
		[_wind_light, _wind_gale],
		smoothstep(0.10, 0.38, _wind) * lerpf(0.28, 1.0, open_air), _wind, wind_db)
	_blend_sequential(
		[_rain_drizzle, _rain_moderate, _rain_heavy],
		smoothstep(0.08, 0.40, _rain) * lerpf(0.18, 1.0, open_air), _rain, rain_db)
	# Independent sea, wind and rain stems replace composite atmosphere tracks.
	_apply_roof_rain()

	_update_pending_thunder(delta)


# ---------------------------------------------------------------------------
# Blend helpers — compute target_db then hand off to each VariantSlot
# ---------------------------------------------------------------------------

## Constant-power sequential N-tier blend.
## t=0 → all first slot; t=1 → all last slot; intermediate values crossfade between neighbours.
## Works for any number of slots ≥ 1.
func _blend_sequential(
		slots: Array, gain: float, t: float, max_db: float) -> void:
	# If a louder step has no recording, keep the strongest file that does exist.
	slots = slots.filter(func(slot: VariantSlot): return not slot.is_empty())
	var n := slots.size()
	if n == 0:
		return
	if gain < 0.0015:
		for s: VariantSlot in slots:
			s.apply_volume(-80.0)
		return
	if n == 1:
		var lin1 := gain
		if lin1 < 1e-5:
			(slots[0] as VariantSlot).apply_volume(-80.0)
		else:
			(slots[0] as VariantSlot).apply_volume(max_db + linear_to_db(lin1))
		return

	# Map t into [0, n-1] and split into segment index + local blend.
	var seg_f := clampf(t, 0.0, 1.0) * float(n - 1)
	var idx   := mini(floori(seg_f), n - 2)
	var blend := seg_f - float(idx)          # 0..1 within this segment

	var amp_lo := cos(blend * PI * 0.5)      # fading out
	var amp_hi := sin(blend * PI * 0.5)      # fading in

	for i in range(n):
		var amp: float = 0.0
		if i == idx:
			amp = amp_lo
		elif i == idx + 1:
			amp = amp_hi
		var lin := gain * amp
		if lin < 1e-5:
			(slots[i] as VariantSlot).apply_volume(-80.0)
		else:
			(slots[i] as VariantSlot).apply_volume(max_db + linear_to_db(lin))


# ---------------------------------------------------------------------------
# Thunder
# ---------------------------------------------------------------------------

func _on_lightning_strike(intensity: float, distance_m: float, world_position := Vector3.INF) -> void:
	_pending_thunder.append({
		"delay": clampf(distance_m / 343.0, 0.15, 18.0),
		"intensity": intensity,
		"distance_m": distance_m,
		"position": world_position,
	})


func _update_pending_thunder(delta: float) -> void:
	for i in range(_pending_thunder.size() - 1, -1, -1):
		var event := _pending_thunder[i]
		event["delay"] = float(event.get("delay", 0.0)) - delta
		if float(event["delay"]) > 0.0:
			_pending_thunder[i] = event
			continue
		_play_thunder(float(event.get("intensity", 0.5)), float(event.get("distance_m", 1000.0)), event.get("position", Vector3.INF))
		_pending_thunder.remove_at(i)


func _play_thunder(intensity: float, distance_m: float, world_position := Vector3.INF) -> void:
	if _thunder_pool.is_empty():
		return
	var idle: Array[AudioStreamPlayer3D] = []
	for p: AudioStreamPlayer3D in _thunder_pool:
		if not p.playing:
			idle.append(p)
	if idle.is_empty():
		return

	var p := idle[randi() % idle.size()]
	if not world_position.is_finite():
		var camera := get_viewport().get_camera_3d()
		if camera == null: return
		world_position = camera.global_position + Vector3(0, 0, -distance_m)
	p.global_position = world_position
	p.volume_db = thunder_db + linear_to_db(maxf(intensity, 0.01))
	p.pitch_scale = randf_range(0.88, 1.08)
	p.play()


func _load_thunder_variants(dir: String, base: String) -> Array[AudioStreamPlayer3D]:
	var pool: Array[AudioStreamPlayer3D] = []
	for i in range(1, 9):
		var path := "%s/%s_%02d.wav" % [dir, base, i]
		if not ResourceLoader.exists(path):
			continue
		var stream := AudioLibrary.stream(path, false)
		if stream == null:
			continue
		var p := AudioStreamPlayer3D.new()
		p.stream    = stream
		p.bus       = AudioLibrary.bus(path)
		p.volume_db = -80.0
		p.unit_size = 500.0
		p.max_distance = 18000.0
		p.autoplay  = false
		add_child(p)
		pool.append(p)
	return pool


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _update_shelter(delta: float) -> void:
	_shelter_wait -= delta
	if _shelter_wait <= 0.0:
		_shelter_wait = 0.25
		_shelter_target = _probe_overhead()
	var blend := 1.0 - exp(-delta / 0.35)
	_shelter = lerpf(_shelter, _shelter_target, blend)


func _probe_overhead() -> float:
	var body := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if body == null or body.get_world_3d() == null:
		return 0.0
	var camera := get_viewport().get_camera_3d()
	var origin := camera.global_position if camera != null else body.global_position + Vector3.UP * 1.45
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.UP * 5.5)
	query.collision_mask = BoatBody.LAYER_WORLD | BoatBody.LAYER_BOAT_WALK | BoatBody.LAYER_BOAT_HULL
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return 0.0 if hit.is_empty() else 1.0


func _apply_roof_rain() -> void:
	var amount := _shelter * smoothstep(0.08, 0.45, _rain)
	_roof_rain.apply_volume(-16.0 + linear_to_db(amount) if amount >= 0.02 else -80.0)


func _all_slots() -> Array[VariantSlot]:
	return [
		_ocean_calm, _ocean_choppy, _ocean_rough, _ocean_stormy,
		_wind_light, _wind_gale,
		_rain_drizzle, _rain_moderate, _rain_heavy, _roof_rain,
	]


func _weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
