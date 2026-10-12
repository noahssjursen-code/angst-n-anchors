extends Node

const HelmMinimapScript := preload("res://scripts/ui/chart/helm_minimap.gd")
enum Screen { NONE, MAP, PANEL, CATCH }
var _screen: Screen = Screen.NONE
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _helm_active := false
var _helm_cursor_released := false
var _gameplay := false
var _hud_layer: CanvasLayer
var _menu_layer: CanvasLayer
var _map: MapOverlay
var _minimap
var _panel: VoyagePanel
var _hud: VoyageHud
var _catch_library: CatchLibrary
var _loading: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer=5
	add_child(_hud_layer)
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer=20
	add_child(_menu_layer)
	_map = MapOverlay.new()
	_map.close_requested.connect(func():_set_screen(Screen.NONE))
	_menu_layer.add_child(_map)
	_minimap = HelmMinimapScript.new()
	_minimap.name="HelmMinimap"
	_minimap.setup(_map)
	_hud_layer.add_child(_minimap)
	# LocalPlayerView loads after this autoload.
	call_deferred("_build_voyage_ui")
	get_tree().node_added.connect(_on_node_added)
	_set_screen(Screen.NONE)
	set_gameplay_hud_visible(false)

func _build_voyage_ui() -> void:
	_hud = VoyageHud.new()
	_hud_layer.add_child(_hud)
	_panel = VoyagePanel.new()
	_panel.close_requested.connect(func():_set_screen(Screen.NONE))
	_panel.chart_requested.connect(func():_set_screen(Screen.MAP))
	_panel.message_requested.connect(notify)
	_menu_layer.add_child(_panel)
	PlayerSession.marks_changed.connect(_account_updated)

func _account_updated(_balance: int) -> void:
	var ledger: Array = LocalPlayerView.get_company_summary().get("recent_transactions",[])
	if not ledger.is_empty():
		notify(str(ledger[0].get("description","Account updated"))+" · "+PlayerData.format_money(int(ledger[0].get("amount_marks",0))))

func is_modal_open() -> bool:
	return _screen != Screen.NONE or get_tree().get_first_node_in_group("passenger_terminal_panel") != null

func set_gameplay_hud_visible(value: bool) -> void:
	_gameplay = value
	if is_instance_valid(_hud_layer): _hud_layer.visible=value

func open_service(npc: NpcInteractable) -> void:
	if not is_instance_valid(_panel): return
	_set_screen(Screen.PANEL)
	_panel.selected=""
	_panel.show_service(npc)

func open_catch_library(hold_id: String) -> void:
	if LocalPlayerView.get_catch_library(hold_id).is_empty(): return
	_set_screen(Screen.CATCH)
	if is_instance_valid(_catch_library): _catch_library.free()
	_catch_library=CatchLibrary.new();_catch_library.hold_id=hold_id
	_catch_library.close_requested.connect(func():_set_screen(Screen.NONE))
	_menu_layer.add_child(_catch_library)

func open_tablet() -> void:
	_set_screen(Screen.PANEL)
	_panel.show_tablet()

func _input(event: InputEvent) -> void:
	if is_instance_valid(_loading):
		get_viewport().set_input_as_handled()
		return
	if event.is_echo(): return
	var focused := get_viewport().gui_get_focus_owner()
	if (focused is LineEdit or focused is TextEdit) and not event.is_action_pressed("ui_cancel"):
		return
	if event.is_action_pressed("ui_cancel"):
		if is_modal_open(): _set_screen(Screen.NONE)
		elif _gameplay:
			_set_screen(Screen.PANEL)
			_panel.show_pause()
		else: return
	elif event.is_action_pressed("open_map") and (_gameplay or _screen == Screen.MAP):
		_set_screen(Screen.MAP if _screen!=Screen.MAP else Screen.NONE)
	elif event.is_action_pressed("open_journal") and _gameplay:
		if _screen==Screen.PANEL: _set_screen(Screen.NONE)
		else: open_tablet()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_C and _helm_active and not is_modal_open():
		_toggle_helm_cursor()
	else: return
	get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if is_modal_open(): get_viewport().set_input_as_handled()

func _set_screen(screen: Screen) -> void:
	var was_modal := is_modal_open()
	if screen!=Screen.CATCH and is_instance_valid(_catch_library):
		_catch_library.queue_free();_catch_library=null
	_screen=screen
	var modal := is_modal_open()
	if modal and not was_modal:
		_prev_mouse_mode=Input.mouse_mode
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	elif not modal and was_modal:
		Input.mouse_mode=_prev_mouse_mode
	_menu_layer.visible=modal
	_map.visible=screen==Screen.MAP
	if is_instance_valid(_panel):
		_panel.visible=screen==Screen.PANEL
		if screen!=Screen.PANEL:
			_panel.npc=null
			_panel.page=""
			VoyageStyle.clear(_panel._body)
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(), screen==Screen.MAP)
	if screen==Screen.MAP: _map.open_navigation()
	_minimap.set_modal_hidden(modal)
	if is_instance_valid(_hud):
		_hud.modal=modal
		_hud.present(LocalPlayerView.get_voyage_snapshot())

func notify(text: String) -> void:
	if is_instance_valid(_hud): _hud.notify(text)
	if _screen==Screen.PANEL and is_instance_valid(_panel): _panel._feedback.text=text

func _on_node_added(node: Node) -> void:
	if node is BoatController:
		if not node.helm_activated.is_connected(_on_helm_on): node.helm_activated.connect(_on_helm_on)
		if not node.helm_deactivated.is_connected(_on_helm_off): node.helm_deactivated.connect(_on_helm_off)
	if node is HarbourMasterNpc:
		node.deployment_finished.connect(func(_ok: bool,message: String):
			if is_instance_valid(_panel) and _panel.visible and _panel.npc == node:
				_panel.show_service(node)
			notify(message))
	if node is QuayEquipmentJob:
		node.job_completed.connect(func(_context: Dictionary,_report: Dictionary):notify("Cargo operation complete. Check your manifest and account."))
		node.job_stopped.connect(func(_context: Dictionary):
			var text := "Transfer stopped. Cargo already moved stays transferred."
			if node is BulkCraneEquipmentJob or node is ProvisionCraneEquipmentJob:
				if not str(node.last_failure).is_empty(): text="Transfer stopped: "+str(node.last_failure)
			notify(text))
	if node.has_signal("boot_finished"):
		node.connect("boot_finished",_world_ready,CONNECT_ONE_SHOT)

func show_loading() -> void:
	if is_instance_valid(_loading): _loading.queue_free()
	_loading=VoyageStyle.label("Preparing the coast…\nBuilding nearby terrain, harbour and vessel services.",28,VoyageStyle.LIGHT)
	_loading.mouse_filter=Control.MOUSE_FILTER_STOP
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_stylebox_override("normal",VoyageStyle.box(VoyageStyle.DARK))
	_hud_layer.add_child(_loading)
	set_gameplay_hud_visible(true)

func _world_ready() -> void:
	hide_loading()
	set_gameplay_hud_visible(true)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func hide_loading() -> void:
	if is_instance_valid(_loading): _loading.queue_free()
	_loading=null

func set_loading_stage(text: String) -> void:
	if is_instance_valid(_loading): _loading.text=text

func _on_helm_on() -> void:
	_helm_active=true
	_helm_cursor_released=Input.mouse_mode==Input.MOUSE_MODE_VISIBLE
	_minimap.set_helm_active(true)

func _on_helm_off() -> void:
	_helm_active=false
	if _helm_cursor_released and not is_modal_open(): Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	_helm_cursor_released=false
	_minimap.set_helm_active(false)

func _toggle_helm_cursor() -> void:
	_helm_cursor_released=Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if _helm_cursor_released else Input.MOUSE_MODE_CAPTURED
