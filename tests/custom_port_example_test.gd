extends Node

func _ready() -> void:
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"fixture"}
	var plots: Array=[{"id":"plot-west","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12.0}]
	var state:=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	for error in state.validation_errors: push_error(error)
	if not state.validation_errors.is_empty(): get_tree().quit(1); return
	var berths:=state.derived_berths()
	print("CUSTOM_PORT_EXAMPLE placements=",snapshot.placements.size()," berths=",JSON.stringify(berths))
	assert(berths.size()>=2,"The authored harbour needs several real berth choices.")
	var presenter:=CustomPortPresenter.new()
	add_child(presenter)
	presenter.load_record(state.to_dict(),berths)
	await get_tree().process_frame
	assert(presenter.placement_nodes.size()==snapshot.placements.size())
	assert(presenter.cargo_nodes.size()==3)
	print("CUSTOM_PORT_EXAMPLE_PASS reconstructed=",presenter.placement_nodes.size()," finite_container_lots=",presenter.cargo_nodes.size())
	get_tree().quit()
