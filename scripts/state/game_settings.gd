extends Node

## Autoload — register as "GameSettings".
## User-tunable graphics, audio, and input settings. Persisted to
## user://settings.cfg so they survive restart.
##
## User preferences are client-local. The world-generation context below is a
## session hand-off populated by server selection, not a persisted preference.

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
# V-Sync is not guaranteed in the editor's embedded game window. A finite
# default also stops release builds from converting every spare GPU cycle into
# frames above the display's refresh rate. Players can still opt into uncapped.
var max_fps:        int        = 120

# ── Input ─────────────────────────────────────────────────────────────────────
var mouse_sensitivity: float = 1.0           # multiplier applied to player.gd's base sensitivity
var invert_mouse_y:    bool  = false

# ── Chart / helm minimap ──────────────────────────────────────────────────────
var chart_weather_enabled: bool = false
var chart_fishing_enabled: bool = false
var chart_profile: int = 0
var minimap_collapsed: bool = false

# ── Session world context ────────────────────────────────────────────────────
## Offline default or authoritative server-selected generation seed/version.
## These are intentionally not written to settings.cfg.
var map_generation_seed: int = 42
var map_generation_version: int = 5
var map_layout_checksum: String = ""


func set_world_generation_context(seed: int, version: int, checksum: String = "") -> void:
	map_generation_seed = seed
	map_generation_version = maxi(version, 1)
	map_layout_checksum = checksum


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings(path: String = CFG_PATH) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return
	master_volume     = float(cfg.get_value("audio",    "master",        master_volume))
	sfx_volume        = float(cfg.get_value("audio",    "sfx",           sfx_volume))
	music_volume      = float(cfg.get_value("audio",    "music",         music_volume))
	window_mode       = int(cfg.get_value("graphics",  "window_mode",   window_mode)) as WindowMode
	vsync_enabled     = bool(cfg.get_value("graphics", "vsync",         vsync_enabled))
	var saved_max_fps := int(cfg.get_value("graphics", "max_fps", max_fps))
	# Before this marker existed, 0 was the shipped default rather than
	# necessarily a deliberate choice. Migrate that legacy default once.
	if saved_max_fps == 0 and not cfg.has_section_key("graphics", "fps_cap_user_selected"):
		max_fps = 120
	else:
		max_fps = saved_max_fps
	mouse_sensitivity = float(cfg.get_value("input",   "mouse_sens",    mouse_sensitivity))
	invert_mouse_y    = bool(cfg.get_value("input",    "invert_mouse_y", invert_mouse_y))
	chart_weather_enabled = bool(cfg.get_value("chart", "weather", chart_weather_enabled))
	chart_fishing_enabled = bool(cfg.get_value("chart", "fishing", chart_fishing_enabled))
	chart_profile = int(cfg.get_value("chart", "profile", chart_profile))
	minimap_collapsed = bool(cfg.get_value("chart", "minimap_collapsed", minimap_collapsed))

	# Override saved setting if Godot was launched with windowed CLI flags
	var force_windowed := false
	for arg in OS.get_cmdline_args():
		if arg == "--windowed" or arg == "-w" or "mode=0" in arg:
			force_windowed = true
			break
	if force_windowed:
		window_mode = WindowMode.WINDOWED


func save_settings(path: String = CFG_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",    "master",         master_volume)
	cfg.set_value("audio",    "sfx",            sfx_volume)
	cfg.set_value("audio",    "music",          music_volume)
	cfg.set_value("graphics", "window_mode",    int(window_mode))
	cfg.set_value("graphics", "vsync",          vsync_enabled)
	cfg.set_value("graphics", "max_fps",        max_fps)
	cfg.set_value("graphics", "fps_cap_user_selected", true)
	cfg.set_value("input",    "mouse_sens",     mouse_sensitivity)
	cfg.set_value("input",    "invert_mouse_y", invert_mouse_y)
	cfg.set_value("chart",    "weather",        chart_weather_enabled)
	cfg.set_value("chart",    "fishing",        chart_fishing_enabled)
	cfg.set_value("chart",    "profile",        chart_profile)
	cfg.set_value("chart",    "minimap_collapsed", minimap_collapsed)
	cfg.save(path)


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
