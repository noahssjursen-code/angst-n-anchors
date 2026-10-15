extends "res://tests/custom_port_editor_test.gd"

func _run() -> void:
	if not ShipyardPlaytestMode.active():get_tree().quit(1);return
	for asset in ["bollard","quay_bollard"]:
		for target in [Vector3(8,0,.1),Vector3(8,0,15.9),Vector3(.1,0,8),Vector3(15.9,0,8),
			Vector3(.1,0,.1),Vector3(15.9,0,.1),Vector3(.1,0,15.9),Vector3(15.9,0,15.9)]:
			var record:=_base()
			for x in [4,12]:
				for z in [4,12]:record.placements.append(CATALOG.placement("floor-%d-%d"%[x,z],"foundation_8m",Vector3(x,0,z)))
			var editor:=_new_editor(record)
			var before:=editor.state.to_dict()
			var proposal:=editor.preview(asset,target,45)
			check(proposal.ok,"%s base is supported at edge/corner %s: %s"%[asset,target,proposal.get("errors",[])])
			check(editor.state.to_dict()==before,"Bollard preview leaves data unchanged")
			check(proposal.ok and editor.place(proposal).ok,"Full authority accepts supported edge base")
			if asset=="quay_bollard" and target==Vector3(8,0,.1):
				check(is_equal_approx(float(proposal.placement.position_m[2]),.75),"Existing authored tee bollard keeps its .75m inset")
			if asset=="bollard" and target==Vector3(8,0,.1):
				check(is_equal_approx(float(proposal.placement.position_m[2]),1.05),"Legacy 2m base has .05m support clearance")
	print("CUSTOM PORT BOLLARD SNAP ","PASS" if failures.is_empty() else "FAIL"," checks=",count," failures=",failures.size())
	for failure in failures:push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
