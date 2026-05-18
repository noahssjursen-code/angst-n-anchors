class_name WeatherAudioSystem
extends Node

## Four-layer weather audio driven by the 2D weather plane (precipitation × wind_force).
##
## Each sound "slot" supports multiple variants named {base}_{n}.wav (n = 1, 2, 3 …).
## Variants loop continuously at -80 dB until activated. Every 40–120 seconds the slot
## randomly crossfades to a different variant, preventing repetition fatigue.
##
## Layer structure:
##   Ocean (4 slots):  calm_seas → choppy_seas → rough_seas → stormy_seas  (wave_intensity)
##   Wind  (2 slots):  wind_light  ↔  wind_gale                            (wind_force)
##   Rain  (3 slots):  rain_drizzle → rain_moderate → rain_heavy           (rain_amount)
##   Atmosphere (4 slots): bilinear blend across the full precip × wind plane
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
			var stream := ResourceLoader.load(path) as AudioStream
			if stream == null:
				continue
			var pl := AudioStreamPlayer.new()
			pl.stream    = stream
			pl.bus       = "Master"
			pl.volume_db = -80.0
			pl.autoplay  = false
			parent.add_child(pl)
			pl.finished.connect(pl.play)  # restart on finish — no .import editing needed
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
@export var wind_db       : float = -8.0
@export var rain_db       : float = -10.0
@export var atmosphere_db : float = -12.0
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

var _atm_calm_clear   := VariantSlot.new()
var _atm_grey_drizzle := VariantSlot.new()
var _atm_dry_squall   := VariantSlot.new()
var _atm_full_storm   := VariantSlot.new()

var _thunder_pool    : Array[AudioStreamPlayer] = []
var _thunder_cooldown: float = 2.0

# Wave intensity window for ocean blend.
const _WAVE_CALM: float = 0.55
const _WAVE_GALE: float = 3.40

# Smoothed source parameters.
var _wave_t : float = 0.0
var _wind   : float = 0.0
var _precip : float = 0.0
var _rain   : float = 0.0
var _thunder: float = 0.0


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

	_atm_calm_clear.load_variants(self,   lo + "/atmosphere", "atm_calm_clear")
	_atm_grey_drizzle.load_variants(self, lo + "/atmosphere", "atm_grey_drizzle")
	_atm_dry_squall.load_variants(self,   lo + "/atmosphere", "atm_dry_squall")
	_atm_full_storm.load_variants(self,   lo + "/atmosphere", "atm_full_storm")

	_thunder_pool = _load_thunder_variants(no + "/thunder", "thunder")


func _process(delta: float) -> void:
	# --- Advance variant rotation timers ---
	for slot: VariantSlot in _all_slots():
		slot.tick(delta)

	# --- Read weather state ---
	var wl      := _weather()
	var wind_raw    := float(wl.get("wind_force"))        if wl else 0.0
	var precip_raw  := float(wl.get("precipitation"))     if wl else 0.0
	var rain_raw    := float(wl.get("rain_amount"))       if wl else 0.0
	var thunder_raw := float(wl.get("thunder_intensity")) if wl else 0.0
	var wave_raw   := clampf(
		(WaveSurface.wave_intensity - _WAVE_CALM) / (_WAVE_GALE - _WAVE_CALM), 0.0, 1.0)

	# --- Exponential smoothing ---
	var k := 1.0 - exp(-delta / maxf(smooth_time, 0.001))
	_wave_t  = lerpf(_wave_t,  wave_raw,    k)
	_wind    = lerpf(_wind,    wind_raw,    k)
	_precip  = lerpf(_precip,  precip_raw,  k)
	_rain    = lerpf(_rain,    rain_raw,    k)
	_thunder = lerpf(_thunder, thunder_raw, k)

	# --- Apply volumes ---
	_blend_sequential(
		[_ocean_calm, _ocean_choppy, _ocean_rough, _ocean_stormy],
		1.0, _wave_t, ocean_db)
	_blend_sequential(
		[_wind_light, _wind_gale],
		smoothstep(0.10, 0.38, _wind), _wind, wind_db)
	_blend_sequential(
		[_rain_drizzle, _rain_moderate, _rain_heavy],
		smoothstep(0.08, 0.40, _rain), _rain, rain_db)
	_blend_atmosphere(_precip, _wind)

	_update_thunder(delta, _thunder)


# ---------------------------------------------------------------------------
# Blend helpers — compute target_db then hand off to each VariantSlot
# ---------------------------------------------------------------------------

## Constant-power sequential N-tier blend.
## t=0 → all first slot; t=1 → all last slot; intermediate values crossfade between neighbours.
## Works for any number of slots ≥ 1.
func _blend_sequential(
		slots: Array, gain: float, t: float, max_db: float) -> void:
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


## Corner-focused bilinear blend across all four weather-plane corners.
## Near-clear weather forces only the calm slot so the compass centre is not a storm mix.
func _blend_atmosphere(p: float, w: float) -> void:
	if maxf(p, w) < 0.12:
		_atm_calm_clear.apply_volume(atmosphere_db)
		_atm_grey_drizzle.apply_volume(-80.0)
		_atm_dry_squall.apply_volume(-80.0)
		_atm_full_storm.apply_volume(-80.0)
		return

	var cc := pow((1.0 - p) * (1.0 - w), 2.0)
	var gd := pow(p * (1.0 - w), 2.0)
	var ds := pow((1.0 - p) * w, 2.0)
	var fs := pow(p * w, 2.0)
	var sum := cc + gd + ds + fs + 1e-6
	cc /= sum
	gd /= sum
	ds /= sum
	fs /= sum
	_atm_apply_weight(_atm_calm_clear, cc)
	_atm_apply_weight(_atm_grey_drizzle, gd)
	_atm_apply_weight(_atm_dry_squall, ds)
	_atm_apply_weight(_atm_full_storm, fs)


func _atm_apply_weight(slot: VariantSlot, weight: float) -> void:
	if weight < 0.01:
		slot.apply_volume(-80.0)
	else:
		slot.apply_volume(atmosphere_db + linear_to_db(weight))


# ---------------------------------------------------------------------------
# Thunder
# ---------------------------------------------------------------------------

func _update_thunder(delta: float, thunder: float) -> void:
	if _thunder_pool.is_empty():
		return
	if thunder < 0.12:
		_thunder_cooldown = randf_range(3.0, 8.0)
		return
	_thunder_cooldown -= delta
	if _thunder_cooldown > 0.0:
		return

	var idle: Array[AudioStreamPlayer] = []
	for p: AudioStreamPlayer in _thunder_pool:
		if not p.playing:
			idle.append(p)
	if idle.is_empty():
		_thunder_cooldown = 0.5
		return

	var p := idle[randi() % idle.size()]
	p.volume_db   = thunder_db + randf_range(-4.0, 2.0)
	p.pitch_scale = randf_range(0.88, 1.08)
	p.play()
	_thunder_cooldown = randf_range(2.0, 12.0) / maxf(thunder, 0.01)


func _load_thunder_variants(dir: String, base: String) -> Array[AudioStreamPlayer]:
	var pool: Array[AudioStreamPlayer] = []
	for i in range(1, 9):
		var path := "%s/%s_%02d.wav" % [dir, base, i]
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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _all_slots() -> Array[VariantSlot]:
	return [
		_ocean_calm, _ocean_choppy, _ocean_rough, _ocean_stormy,
		_wind_light, _wind_gale,
		_rain_drizzle, _rain_moderate, _rain_heavy,
		_atm_calm_clear, _atm_grey_drizzle, _atm_dry_squall, _atm_full_storm,
	]


func _weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
