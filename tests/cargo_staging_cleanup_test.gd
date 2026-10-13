extends Node3D

var failures := 0
func check(value: bool, label: String) -> void:
 print("CARGO CLEANUP ", "PASS " if value else "FAIL ", label)
 if not value: failures += 1

func _ready() -> void:
 assert(ShipyardPlaytestMode.active())
 call_deferred("run")

func run() -> void:
 var replication := CargoManifestReplication.new()
 add_child(replication)
 replication.set_process(false)
 var port := HarbourController.new()
 port.setup("test-port")
 add_child(port)
 replication.port_lookup = func(_id: String): return port
 var crane := ProvisionCrane.new()
 add_child(crane)
 var job := ProvisionCraneEquipmentJob.new()
 job.setup("test-crane", "provision_crane", "test-berth")
 add_child(job)
 job.bind_crane(crane)
 var berth := QuayBerthSlot.new()
 berth.setup("test-berth", "general", "general", [], 60.0, 20.0)
 add_child(berth)
 port.register_berth(berth)
 port.register_equipment(job, "test-berth")
 var suspended := ContainerNode.new()
 add_child(suspended)
 var hook_unit := ContainerUnit.new()
 hook_unit.id = "hook"
 suspended.setup(hook_unit, true)
 check(crane.attach_container(suspended), "fixture container attached to real crane")
 job.replication_context = {"vessel_id":"ship", "operation_id":"old-job"}
 var yard := CargoSlotPadComponent.new()
 yard.deck_width_m = 20
 yard.deck_length_m = 20
 yard.affects_boat_cargo_mass = false
 yard.is_quay_yard_pad = true
 add_child(yard)
 for id in ["removed", "keep"]:
  var unit := ContainerUnit.new()
  unit.id = id
  yard.add_container(unit)
 var boat := BoatBody.new()
 boat.freeze = true
 add_child(boat)
 var aboard := ContainerNode.new()
 boat.add_child(aboard)
 var unit := ContainerUnit.new()
 unit.id = "aboard"
 aboard.setup(unit, true)
 replication._clear_removed_staging({"cleared_item_ids":["removed", "aboard", "hook"]})
 check(yard.get_containers().size() == 1 and yard.get_containers()[0].id == "keep", "only cleared shore cargo is removed and pad released")
 check(crane.get_attached_container() == null and suspended.is_queued_for_deletion() and job.replication_context.is_empty(), "cleared hook releases container and old crane context")
 check(not aboard.is_queued_for_deletion(), "aboard cargo survives stale cleanup")
 replication._clear_removed_staging({"cleared_item_ids":["removed", "aboard", "hook"]})
 check(yard.get_containers().size() == 1, "duplicate cleanup is harmless")
 await get_tree().process_frame
 get_tree().quit(1 if failures else 0)
