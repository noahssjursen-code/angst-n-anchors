extends SceneTree

## Fast architecture guard for the branded UI layer.

const ACTIVE_SURFACES := [
	"res://scripts/ui/main_menu.gd",
	"res://scripts/ui/game_menu.gd",
	"res://scripts/ui/settings_panel.gd",
	"res://scripts/ui/character_creator_panel.gd",
	"res://scripts/ui/company_setup_panel.gd",
	"res://scripts/ui/company_panel.gd",
	"res://scripts/ui/map_overlay.gd",
	"res://scripts/ui/ship_hud.gd",
	"res://scripts/ui/walking_hud.gd",
	"res://scripts/ui/loading_gate.gd",
	"res://scripts/npc/dialogue_panel.gd",
	"res://scripts/npc/shipwright_catalog_panel.gd",
	"res://scripts/port/crane_operator_panel.gd",
	"res://scripts/weather/weather_hud.gd",
	"res://scripts/weather/weather_debug_presets.gd",
	"res://scripts/apps/structure_studio.gd",
	"res://scripts/apps/vessel_registration_audit.gd",
]

const FORBIDDEN_LEGACY := [
	"HudStyle",
	"UiBuilder",
	"MenuActionButton",
	"ThemeDB.fallback_font",
]

var _failures := PackedStringArray()


func _initialize() -> void:
	_check(FileAccess.file_exists(BrandTokens.PALETTE_PATH), "generated palette is present")
	_check(BrandTokens.all_colors().size() >= 40, "palette exposes the complete token set")
	for path in [
		BrandTheme.FONT_DISPLAY_BOLD,
		BrandTheme.FONT_DISPLAY_SEMIBOLD,
		BrandTheme.FONT_UI,
		BrandTheme.FONT_DATA,
	]:
		_check(FileAccess.file_exists(path), "font exists: %s" % path)
	_check(
		FileAccess.file_exists("res://resources/ui/brand/mark-glyph.svg"),
		"custom currency mark is present",
	)
	_check(
		FileAccess.file_exists("res://resources/ui/brand/mark-glyph-brass.svg"),
		"inverse currency mark is present",
	)

	var theme := BrandTheme.shared()
	for variation in [
		&"BrandSurfacePanel",
		&"BrandRuledPanel",
		&"BrandDarkRuledPanel",
		&"BrandToolbarPanel",
		&"BrandPrimaryButton",
		&"BrandLoudButton",
		&"BrandDangerButton",
	]:
		var item := &"panel" if "Panel" in String(variation) else &"normal"
		_check(theme.has_stylebox(item, variation), "theme variation exists: %s" % variation)

	var button := BrandButton.new("TEST", BrandButton.Variant.PRIMARY)
	_check(
		button.custom_minimum_size.y >= BrandTokens.MIN_HIT_TARGET,
		"interactive controls meet the minimum hit target",
	)
	button.free()

	for path in ACTIVE_SURFACES:
		_check(FileAccess.file_exists(path), "active UI surface exists: %s" % path)
		var source := FileAccess.get_file_as_string(path)
		for forbidden in FORBIDDEN_LEGACY:
			_check(
				not forbidden in source,
				"%s has no legacy dependency %s" % [path.get_file(), forbidden],
			)

	if _failures.is_empty():
		print("Branded UI system contract: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Branded UI system contract: " + failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
