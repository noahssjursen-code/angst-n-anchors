extends Node

const AUDIT_SCRIPT := preload("res://scripts/apps/vessel_registration_audit.gd")

var _failures := PackedStringArray()


func _ready() -> void:
	var app: CanvasLayer = AUDIT_SCRIPT.new()
	add_child(app)
	await get_tree().process_frame
	_check(app.find_child("RegistrationAuditRoot", true, false) != null, "audit app root exists")
	_check(app.find_child("RegistrationList", true, false) != null, "legal-code list exists")
	_check(app.find_child("LegalCodeEditor", true, false) != null, "legal-code editor exists")
	_check(app.find_child("AuditAllButton", true, false) != null, "batch audit action exists")
	_check(
		app.find_child("AssignRegistrationButton", true, false) != null,
		"selected prebuilt can receive paperwork",
	)
	var audits := app.find_child("VesselAuditList", true, false) as ItemList
	_check(audits != null and audits.item_count >= 1, "official vessel paperwork is scanned")
	var status := app.find_child("AuditStatus", true, false) as Label
	_check(status != null and "certified" in status.text, "batch certification summary is shown")
	app.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("Vessel registration audit UI: legal editor and paperwork scan passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("Vessel registration audit UI: " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
