extends Node
## Shared navigation instrument. No fishing equipment or catch authority required.
var history: Array = []
var elapsed := 0.0
var view := SonarDisplay.VIEW_FULL
var _schools:Node3D
var _sequence:=0

func snapshot() -> Dictionary:
	return {"sonar_view":true,"sounder":true,"view":view,"history":history.duplicate(),"ping_age_s":elapsed,"ping_interval_s":.5,"stream_id":get_instance_id()}
func _process(delta: float) -> void:
	var ship := get_parent()
	if LocalPlayerView.get_active_ship() != ship: return
	if not is_instance_valid(_schools):
		_schools=preload("res://scripts/ship/fishing_school_renderer.gd").new();add_child(_schools)
		add_child(preload("res://scripts/ship/fishing_school_gizmos.gd").new())
	if LocalPlayerView.is_helming() and not GameMenu.is_modal_open() and Input.is_action_just_pressed("fishing_sounder"):
		view = (view + 1) % 3
	if FishingField.habitat == null: return
	elapsed += delta
	if elapsed < .5: return
	elapsed = 0
	var at := Vector2(ship.global_position.x,ship.global_position.z)
	var ping:=FishingField.habitat.ping(at,WorldClock.get_game_hours_elapsed())
	_sequence+=1;ping["sequence"]=_sequence
	history.append(ping)
	# 90 visible intervals plus their preceding sample for interpolation.
	if history.size() > 91: history.pop_front()
