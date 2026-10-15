class_name PlayerPortPlot
extends PortPlot

## Service adapter for the existing custom-port presenter. No second geometry
## builder or fleet: deployment still runs through HarbourDeploy/WorldGateway.
var document:Dictionary={}
var presenter:CustomPortPresenter

func _ready()->void:
	add_to_group("port_plot")

func attach(source:CustomPortPresenter)->void:
	presenter=source
	document=source.record
	port_id=str(document.id)
	port_label=str(document.name)
	var harbour:=HarbourController.new()
	harbour.setup(port_id)
	add_child(harbour)
	var berth_number:=0
	for key in source.berth_nodes:
		berth_number+=1
		var slot:QuayBerthSlot=source.berth_nodes[key]
		slot.berth_id=port_id+"/"+str(key).get_slice(":berth:",1)
		slot.set_meta("display_name","Quay %d"%berth_number)
		slot.family="general"
		slot.station_id=slot.berth_id
		slot.add_to_group("quay_berth_slot")
		for post in slot.bollards():post.set_meta("berth_id",slot.berth_id)
		harbour.register_berth(slot)
	harbour.activate()
	var master:=HarbourMasterNpc.new()
	master.port_id=port_id
	master.position=CustomPortCatalog.vector3(document.get("spawn_local_m",[5,1,43]))
	add_child(master)
	PortCatalog.register_port(port_id,port_label,global_position,get_spawn_position(),"",[],200,200)

func get_spawn_position()->Vector3:
	return to_global(CustomPortCatalog.vector3(document.get("spawn_local_m",[5,1,43]))+Vector3.UP*.8)

func _exit_tree()->void:
	var harbour:=harbour_controller()
	if harbour!=null:harbour.deactivate()
