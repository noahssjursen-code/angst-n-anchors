class_name PersonalFishingEquipment
extends Node
## One local player's portable rig; vessel supplies the catch destination.
var station:RodFishingStation
var _uid:=""
func _ready()->void:
	PersonalInventory.changed.connect(_equipment_changed)
	call_deferred("_equipment_changed")
func can_change()->bool:
	return not is_instance_valid(station) or station.session.phase in ["stowed","landed","charging"]
func _equipment_changed()->void:
	var equipped:=PlayerInventoryState.selected(PersonalInventory.snapshot()) if PersonalInventory.ready_for_use or not WorldGateway.is_remote() else {}
	var uid:=str(equipped.get("uid",""))
	if uid==_uid:return
	if is_instance_valid(station):
		station.working=false;station.session.recover();station._carry(false)
		remove_child(station);station.queue_free();station=null
	_uid=uid
	if str(equipped.get("item_id","")) not in ["fishing_rod","harpe"]:return
	station=RodFishingStation.new();station.name="PersonalRod"
	station.personal_player=get_parent() as CharacterBody3D
	station.authored_station=load("res://resources/models/fishing_items/spinning_rod.glb").instantiate()
	station.add_child(station.authored_station);add_child(station)
	station.set_equipment(str(equipped.item_id))
	station.working=true;station._carry(true)
func _physics_process(_delta:float)->void:
	if not is_instance_valid(station):return
	var player:=get_parent()
	station._boat=player.standing_vessel()
	if player.is_vehicle_occupied():
		if station.working:station.working=false;station.session.recover();station._carry(false)
	elif not station.working:
		station.working=true;station._carry(true)
