extends Node

## Server configuration and preset management.
## Persists chosen server IP and port configuration so players don't have to
## re-type them on every run.

signal changed

const PRESET_LOCAL := "local"
const PRESET_DIGITAL_OCEAN := "digital_ocean"
const PRESET_CUSTOM := "custom"

const PRESETS := {
	"local": {
		"label": "Local server",
		"udp_host": "127.0.0.1",
		"udp_port": 7777,
		"http_host": "127.0.0.1",
		"http_port": 8080,
	},
	"digital_ocean": {
		"label": "Digital Ocean",
		"udp_host": "159.203.0.0", # REPLACE_ME.example
		"udp_port": 7777,
		"http_host": "159.203.0.0", # REPLACE_ME.example
		"http_port": 8080,
	}
}

const CONFIG_PATH := "user://server_config.cfg"

var preset: String = PRESET_LOCAL
var udp_host: String = "127.0.0.1"
var udp_port: int = 7777
var http_host: String = "127.0.0.1"
var http_port: int = 8080

## Flag indicating if the current session is configured as multiplayer.
var is_multiplayer_mode: bool = false


func _ready() -> void:
	load_from_disk()


func use_preset(preset_name: String) -> void:
	if PRESETS.has(preset_name):
		preset = preset_name
		var data: Dictionary = PRESETS[preset_name]
		udp_host = String(data["udp_host"])
		udp_port = int(data["udp_port"])
		http_host = String(data["http_host"])
		http_port = int(data["http_port"])
		save_to_disk()
		changed.emit()


func use_custom(u_host: String, u_port: int, h_host: String, h_port: int) -> void:
	preset = PRESET_CUSTOM
	udp_host = u_host
	udp_port = u_port
	http_host = h_host
	http_port = h_port
	save_to_disk()
	changed.emit()


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "preset", preset)
	cfg.set_value("server", "udp_host", udp_host)
	cfg.set_value("server", "udp_port", udp_port)
	cfg.set_value("server", "http_host", http_host)
	cfg.set_value("server", "http_port", http_port)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("ServerConfig: Failed to save config to %s, err=%d" % [CONFIG_PATH, err])


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		# Fallback to local default if file doesn't exist
		use_preset(PRESET_LOCAL)
		return
	preset = String(cfg.get_value("server", "preset", PRESET_LOCAL))
	udp_host = String(cfg.get_value("server", "udp_host", "127.0.0.1"))
	udp_port = int(cfg.get_value("server", "udp_port", 7777))
	http_host = String(cfg.get_value("server", "http_host", "127.0.0.1"))
	http_port = int(cfg.get_value("server", "http_port", 8080))
	changed.emit()


func get_http_base_url() -> String:
	return "http://%s:%d" % [http_host, http_port]
