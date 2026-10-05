class_name ShipyardPlaytestMode
extends RefCounted

const SCENE := "res://scenes/showcases/shipyard_playtest.tscn"
const MARINE_AUDIT_SCENE := "scenes/showcases/marine_asset_audit_showcase.tscn"
const FLAG := "--shipyard-playtest"
static var child_pid := -1

## Available before any autoload _ready: a sandbox must never open a captain/session.
static func active() -> bool:
	if OS.get_cmdline_user_args().has(FLAG):
		return true
	for arg in OS.get_cmdline_args():
		if arg.replace("\\", "/").ends_with("scenes/showcases/shipyard_playtest.tscn"):
			return true
		if arg.replace("\\", "/").ends_with(MARINE_AUDIT_SCENE):
			return true
	return false

static func snapshot_path() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(FLAG)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

static func launch(draft: Dictionary) -> String:
	if child_pid > 0 and OS.is_process_running(child_pid):
		return "A playtest is already open. Close its window before starting another."
	var folder := OS.get_cache_dir().path_join("angst-n-anchors-playtest")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return "Could not create the temporary playtest snapshot."
	var path := folder.path_join("draft-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write the temporary playtest snapshot."
	file.store_string(JSON.stringify(draft))
	file.close()
	var args := PackedStringArray(["--windowed", "--resolution", "1280x800"])
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array([SCENE, "--", FLAG, path])
	if OS.get_cmdline_user_args().has("--verify-playtest-launch"):
		args.append("--verify-playtest")
	child_pid = OS.create_process(OS.get_executable_path(), args)
	if child_pid <= 0:
		DirAccess.remove_absolute(path)
		return "Could not start the playtest window."
	return ""
