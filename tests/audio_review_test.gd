extends Node

var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("AUDIO REVIEW FAIL " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var unique := str(Time.get_ticks_usec())
	var state_path := "user://audio_reviews/test-" + unique + ".json"
	var report_path := "user://audio_reviews/report-test-" + unique + ".json"
	var review = load("res://scenes/showcases/audio_library_showcase.tscn").instantiate()
	review.review_state_path = state_path
	add_child(review)
	await get_tree().process_frame
	check(review._entries.size() == AudioLibrary.entries().size(), "Every clip has a review row")
	check(not review._playlist, "Review stays on selected clip")
	review._approve_button.pressed.emit()
	check(review._review_store.decision(review._entries[0]).verdict == "approved", "Approve button")
	review._play(1, true)
	review._review_note.text = "Too synthetic.\nKeep the water; remove the metallic ringing. Æ Ø Å \"test\""
	review._on_review_note_changed()
	review._deny_button.pressed.emit()
	check(review._review_store.decision(review._entries[1]).verdict == "denied", "Deny button")
	check(review._list.get_item_text(review._row_for_entry[1]).begins_with("[NO]"), "Decision visible in clip list")
	var saved := AudioReviewStore.new(state_path)
	check(saved.decision(review._entries[0]).verdict == "approved", "Approval persists")
	check(saved.decision(review._entries[1]).note == review._review_note.text, "Notes persist exactly")
	var changed: Dictionary = review._entries[0].duplicate()
	changed.sha256 = "replacement-file-hash"
	check(saved.decision(changed).verdict == "unreviewed", "Replacement needs a fresh decision")
	review._export_report(ProjectSettings.globalize_path(report_path), false)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	check(report is Dictionary, "Export is readable JSON")
	if report is Dictionary:
		check(report.clips.size() == review._entries.size(), "Report includes every clip")
		check(report.summary.approved == 1 and report.summary.denied == 1, "Report counts decisions")
		check(report.clips[1].note == review._review_note.text, "Report preserves multiline notes")
		check(report.clips[1].sha256 == review._entries[1].sha256, "Report identifies exact audio version")
	review._next_unreviewed()
	check(review._index == 2, "Next unreviewed skips reviewed clips")
	review._review_note.grab_focus()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_P
	review._unhandled_input(key)
	check(not review._playlist, "Typing notes does not trigger playback shortcuts")
	review._review_note.release_focus()
	review._play(1, true)
	if OS.get_cmdline_user_args().has("--capture"):
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		check(review._status.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "Playback footer fits window")
		var folder := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		var capture := folder.path_join("audio-review-" + unique + ".png")
		check(get_viewport().get_texture().get_image().save_png(capture) == OK, "Review screenshot archived")
		print("AUDIO_REVIEW_CAPTURE ", capture)
	review._set_verdict("unreviewed")
	check(review._review_store.decision(review._entries[1]).verdict == "unreviewed", "Reset verdict")
	review.queue_free()
	for frame in 4:
		await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
	print("AUDIO REVIEW ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
