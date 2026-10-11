extends Node

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	check(ShipyardPlaytestMode.active(), "Use an isolated test session")
	check(not PlayerSession._persistent_io_enabled, "Captain saves stay isolated")
	check(get_node_or_null("/root/LoadingGate") == null, "No loading screen autoload")
	check(get_node_or_null("/root/Tutorial") == null, "No tutorial overlay autoload")
	check(str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty(), "No deleted title scene remains configured")
	var chart: MapOverlay = GameMenu._map
	var minimap: HelmMinimap = GameMenu._minimap
	check(minimap.source == chart, "Minimap shares the retained chart")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Headless display servers do not support capture. Check restoration of the
	# actual prior mode; rendered runs exercise captured -> visible -> captured.
	var original_mouse_mode := Input.mouse_mode
	var event := InputEventAction.new()
	event.action = "open_map"
	event.pressed = true
	GameMenu._unhandled_input(event)
	check(chart.is_visible_in_tree() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "M opens the chart with mouse access")
	check(not get_tree().paused, "Chart does not pause gameplay")
	event.action = "ui_cancel"
	GameMenu._unhandled_input(event)
	check(not chart.is_visible_in_tree() and Input.mouse_mode == original_mouse_mode, "Escape closes the chart and restores mouse mode")
	GameMenu._unhandled_input(event)
	check(GameMenu._screen == GameMenu.Screen.NONE and not get_tree().paused, "Escape does not open a removed menu")
	minimap.set_helm_active(true)
	check(minimap.visible, "Minimap remains available at the helm")
	minimap.set_modal_hidden(true)
	check(not minimap.visible, "Minimap hides under the full chart")
	minimap.set_modal_hidden(false)
	minimap.set_helm_active(false)
	for type in [HarbourMasterNpc, CargoAgentNpc, ShipwrightNpc, CraneOperatorNpc]:
		var npc: NpcInteractable = type.new()
		add_child(npc)
		await get_tree().process_frame
		npc._on_interact()
		check(Input.mouse_mode == original_mouse_mode, "NPC without UI cannot trap the cursor")
		check(npc.find_children("*", "Control", true, false).is_empty(), "NPC has no screen or prompt controls")
		check(npc.find_children("*", "CanvasLayer", true, false).is_empty(), "NPC has no hidden dialogue layer")
		npc.queue_free()
	await get_tree().process_frame
	var body := BoatBody.new()
	add_child(body)
	var helm := BoatController.new()
	body.add_child(helm)
	helm.activate()
	check(helm.find_children("*", "CanvasLayer", true, false).is_empty(), "Helming creates no ship HUD")
	helm.deactivate()
	body.queue_free()
	await get_tree().process_frame
	var editor := ShipyardBrickEditor.new()
	add_child(editor)
	await get_tree().process_frame
	check(editor.find_child("TopBar", true, false) != null, "Shipyard editor toolbar remains")
	check(editor.find_child("PartsPalette", true, false) != null, "Shipyard editor parts palette remains")
	check(editor.find_child("BuildViewport", true, false) != null, "Shipyard editor build viewport remains")
	editor.queue_free()
	await get_tree().process_frame
	print("GAME UI REMOVAL ", "PASS" if failures.is_empty() else "FAIL", ": map input/minimap, NPCs, helm, editor shell, save isolation")
	get_tree().quit(0 if failures.is_empty() else 1)
