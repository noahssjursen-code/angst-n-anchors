class_name WalkingHud
extends Control

## On-foot edge HUD. It exposes balance, active passage, and manifest state
## without occupying the centre of the world view.

var _view: Node
var _currency: BrandCurrency
var _passage_panel: BrandPanel
var _passage_label: BrandLabel
var _manifest_panel: BrandPanel
var _manifest_label: BrandLabel
var _refresh_elapsed := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = BrandTheme.shared()
	_build()
	_view = get_node_or_null("/root/LocalPlayerView")
	if _view != null:
		if not _view.marks_changed.is_connected(_on_marks_changed):
			_view.marks_changed.connect(_on_marks_changed)
		if not _view.contracts_changed.is_connected(_on_contracts_changed):
			_view.contracts_changed.connect(_on_contracts_changed)
		if not _view.helm_changed.is_connected(_on_helm_changed):
			_view.helm_changed.connect(_on_helm_changed)
		_currency.set_amount(_view.get_marks())
	_refresh()


func _build() -> void:
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stack.offset_left = BrandTokens.SPACE_LG
	stack.offset_top = BrandTokens.SPACE_LG
	stack.offset_right = 420.0
	stack.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	add_child(stack)

	var account := BrandPanel.new(BrandPanel.Variant.DARK_RULED)
	stack.add_child(account)
	_currency = BrandCurrency.new(0, true)
	account.add_child(_currency)

	_passage_panel = BrandPanel.new(BrandPanel.Variant.DARK)
	_passage_panel.visible = false
	stack.add_child(_passage_panel)
	_passage_label = BrandLabel.new("", BrandLabel.Role.INVERSE_DATA)
	_passage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passage_panel.add_child(_passage_label)

	_manifest_panel = BrandPanel.new(BrandPanel.Variant.DARK)
	_manifest_panel.visible = false
	stack.add_child(_manifest_panel)
	_manifest_label = BrandLabel.new("", BrandLabel.Role.INVERSE_DATA)
	_manifest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_manifest_panel.add_child(_manifest_label)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.5:
		_refresh_elapsed = 0.0
		_refresh_passage()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_refresh()


func _on_marks_changed(balance: int) -> void:
	_currency.set_amount(balance)


func _on_contracts_changed(_contracts: Array) -> void:
	_refresh_manifest()


func _on_helm_changed(_boat: Node) -> void:
	_refresh()


func _refresh() -> void:
	if _view == null:
		return
	_currency.set_amount(_view.get_marks())
	_refresh_passage()
	_refresh_manifest()


func _refresh_passage() -> void:
	if _view == null:
		return
	var autopilot := _view.get_autopilot_snapshot() as Dictionary
	var active := bool(autopilot.get("active", false))
	_passage_panel.visible = active
	if not active:
		return
	var watch := autopilot.get("bridge_watch", {}) as Dictionary
	if bool(watch.get("alarm_active", false)):
		_passage_label.text = tr("BRIDGE WATCH ALARM · RETURN TO BRIDGE")
		_passage_label.add_theme_color_override(&"font_color", BrandTokens.ALERT_TINT)
		_passage_panel.variant = BrandPanel.Variant.DARK_RULED
		return
	_passage_panel.variant = BrandPanel.Variant.DARK
	var destination_id := str(autopilot.get("destination_port_id", ""))
	var destination := str(_view.get_port_display_name(destination_id)).to_upper()
	var remaining := float(autopilot.get("remaining_distance_m", 0.0))
	_passage_label.text = "%s · %s · %s" % [
		tr("AUTOPILOT"),
		destination,
		BrandFormat.distance_metres(remaining),
	]
	_passage_label.add_theme_color_override(&"font_color", BrandTokens.OK_LIGHT)


func _refresh_manifest() -> void:
	if _view == null:
		return
	var contracts := _view.get_active_contracts() as Array
	_manifest_panel.visible = not contracts.is_empty()
	if contracts.is_empty():
		return
	var first := contracts[0] as Dictionary
	var destination := str(
		_view.get_port_display_name(str(first.get("destination_port_id", "")))
	).to_upper()
	_manifest_label.text = "%s · %d · %s" % [
		tr("ACTIVE MANIFEST"),
		contracts.size(),
		destination,
	]
