class_name AudioReviewStore
extends RefCounted

var state_path: String
var votes: Dictionary = {}
var last_error := ""

func _init(path := "user://audio_reviews/decisions.json") -> void:
	state_path = path
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("votes") is Dictionary:
			votes = parsed.votes
		else:
			last_error = "Previous review file could not be read."

func decision(entry: Dictionary) -> Dictionary:
	var key := str(entry.rel) + ":" + str(entry.sha256)
	return votes.get(key, {"verdict": "unreviewed", "note": "", "reviewed_at_utc": ""})

func set_decision(entry: Dictionary, verdict: String, note: String) -> void:
	if verdict not in ["approved", "denied", "unreviewed"]:
		return
	var key := str(entry.rel) + ":" + str(entry.sha256)
	votes[key] = {"verdict": verdict, "note": note,
		"reviewed_at_utc": Time.get_datetime_string_from_system(true) + "Z"}

func save() -> bool:
	return _write_json(state_path, {"schema_version": 1, "votes": votes})

func report(entries: Array[Dictionary]) -> Dictionary:
	var clips: Array[Dictionary] = []
	var counts := {"approved": 0, "denied": 0, "unreviewed": 0}
	for entry in entries:
		var vote := decision(entry)
		var verdict := str(vote.verdict)
		counts[verdict] += 1
		clips.append({"file": entry.rel, "sha256": entry.sha256,
			"title": entry.title, "loop": entry.loop,
			"duration_seconds": entry.get("duration_seconds", 0.0),
			"verdict": verdict, "note": str(vote.note),
			"reviewed_at_utc": str(vote.reviewed_at_utc)})
	return {"schema_version": 1, "report_type": "angst_n_anchors_audio_review",
		"exported_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"library_root": "res://resources/audio", "summary": counts, "clips": clips}

func export_report(path: String, entries: Array[Dictionary]) -> bool:
	return _write_json(path, report(entries))

func _write_json(path: String, data: Dictionary) -> bool:
	last_error = ""
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "Cannot create report folder: " + directory
		return false
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write review file: " + absolute
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, absolute) != OK:
		last_error = "Could not finish saving review file: " + absolute
		return false
	return true
