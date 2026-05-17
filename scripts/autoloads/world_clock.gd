extends Node

## Authoritative world time. 1 real minute = 1 game hour → 24-minute days.
## Drives WeatherLighting.time_of_day every frame.
##
## Multiplayer sync: server calls get_sync_token(), clients call apply_sync_token()
## with the received dict. From that point both sides compute identical time_of_day.

signal day_changed(day_number: int)

## 24 real minutes per game day.
const DAY_LENGTH_REAL_SECONDS := 1440.0
## 60 real seconds per game hour.
const SECONDS_PER_GAME_HOUR   := 60.0

var _epoch_unix: float = 0.0
var _last_day:   int   = 0


func _ready() -> void:
	_epoch_unix = 0.0  # Unix origin — time_of_day flows from real Unix time by default
	_last_day   = get_day_number()
	_push_to_weather()


func _process(_delta: float) -> void:
	_push_to_weather()
	var day := get_day_number()
	if day != _last_day:
		_last_day = day
		day_changed.emit(day)


## Anchor the clock to a specific Unix epoch (call this when loading a saved world).
func initialize(epoch_unix: float) -> void:
	_epoch_unix = epoch_unix
	_last_day   = get_day_number()


## 0.0–1.0 position through the current game day.
## 0/1 = midnight, 0.25 = 6 am, 0.5 = noon, 0.75 = 6 pm.
func get_time_of_day() -> float:
	var elapsed := Time.get_unix_time_from_system() - _epoch_unix
	return fmod(elapsed, DAY_LENGTH_REAL_SECONDS) / DAY_LENGTH_REAL_SECONDS


## Total elapsed game-hours since epoch.
func get_game_hours_elapsed() -> float:
	return (Time.get_unix_time_from_system() - _epoch_unix) / SECONDS_PER_GAME_HOUR


## Integer game-day number, 0-indexed from epoch.
func get_day_number() -> int:
	return int((Time.get_unix_time_from_system() - _epoch_unix) / DAY_LENGTH_REAL_SECONDS)


## Sync token for multiplayer hand-off. Server serialises this; clients apply it.
func get_sync_token() -> Dictionary:
	return { "epoch": _epoch_unix }


## Apply a token received from the server so this client's clock matches the world.
func apply_sync_token(token: Dictionary) -> void:
	if token.has("epoch"):
		initialize(float(token["epoch"]))


func _push_to_weather() -> void:
	var weather := get_node_or_null("/root/WeatherLighting")
	if weather != null:
		weather.time_of_day = get_time_of_day()
