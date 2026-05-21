extends Node

## Autoload — register as "GameSettings".
## User-tunable graphics, audio, and input settings. Persisted to
## user://settings.cfg so they survive restart.
##
## MP-readiness: settings are purely client-local. Nothing here affects the
## simulation, so no per-player sync work is required when the network layer
## arrives.

signal settings_changed

const CFG_PATH := "user://settings.cfg"

# ── Audio ─────────────────────────────────────────────────────────────────────
var master_volume: float = 1.0
var sfx_volume:    float = 1.0
var music_volume:  float = 0.7

# ── Graphics ──────────────────────────────────────────────────────────────────
enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }
var window_mode:    WindowMode = WindowMode.WINDOWED
var vsync_enabled:  bool       = true
var max_fps:        int        = 0           # 0 = uncapped

# ── Input ─────────────────────────────────────────────────────────────────────
var mouse_sensitivity: float = 1.0           # multiplier applied to player.gd's base sensitivity
var invert_mouse_y:    bool  = false


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		return
	master_volume     = float(cfg.get_value("audio",    "master",        master_volume))
	sfx_volume        = float(cfg.get_value("audio",    "sfx",           sfx_volume))
	music_volume      = float(cfg.get_value("audio",    "music",         music_volume))
	window_mode       = int(cfg.get_value("graphics",  "window_mode",   window_mode)) as WindowMode
	vsync_enabled     = bool(cfg.get_value("graphics", "vsync",         vsync_enabled))
	max_fps           = int(cfg.get_value("graphics",  "max_fps",       max_fps))
	mouse_sensitivity = float(cfg.get_value("input",   "mouse_sens",    mouse_sensitivity))
	invert_mouse_y    = bool(cfg.get_value("input",    "invert_mouse_y", invert_mouse_y))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",    "master",         master_volume)
	cfg.set_value("audio",    "sfx",            sfx_volume)
	cfg.set_value("audio",    "music",          music_volume)
	cfg.set_value("graphics", "window_mode",    int(window_mode))
	cfg.set_value("graphics", "vsync",          vsync_enabled)
	cfg.set_value("graphics", "max_fps",        max_fps)
	cfg.set_value("input",    "mouse_sens",     mouse_sensitivity)
	cfg.set_value("input",    "invert_mouse_y", invert_mouse_y)
	cfg.save(CFG_PATH)


# ── Apply ─────────────────────────────────────────────────────────────────────

func apply_all() -> void:
	_apply_audio()
	_apply_graphics()
	settings_changed.emit()


func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("SFX",    sfx_volume)
	_set_bus_volume("Music",  music_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := linear_to_db(maxf(linear, 0.0001))
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _apply_graphics() -> void:
	match window_mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = maxi(max_fps, 0)
