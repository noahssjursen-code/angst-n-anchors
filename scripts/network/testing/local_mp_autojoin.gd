extends Node

## Development launcher only. The launcher authenticates against loopback and
## passes a short-lived handoff through the child environment, never CLI tokens.
const BASE_URL := "http://127.0.0.1:8080"
static var _launch_consumed := false
var _menu
var _handoff: Dictionary
var _joining := false
var _new_captain: Dictionary = {}
var _onboarding_saved := false
var _failed := false


func start(menu: Control) -> void:
	# Returning to the menu must not consume the one-time handoff again.
	if _launch_consumed: return
	_launch_consumed = true
	_menu = menu
	var raw := OS.get_environment("ANGST_MP_TEST_SESSION")
	OS.unset_environment("ANGST_MP_TEST_SESSION")
	var parsed: Variant = JSON.parse_string(raw)
	if not OS.is_debug_build() or NetworkClientStorageScope.current_slot().is_empty() or parsed is not Dictionary:
		_fail("Missing isolated localhost test session. Use start-mp-clients.ps1.")
		return
	_handoff = parsed
	if str(_handoff.get("base_url", "")) != BASE_URL:
		_fail("Automatic test login is restricted to localhost:8080.")
		return
	if not RemoteAccountCredentialStore.set_session(BASE_URL, str(_handoff.get("access_token", "")), _handoff.get("account", {})):
		_fail("Could not save the isolated test account session.")
		return
	_handoff.erase("access_token")
	ServerConfig.use_preset("local")
	DisplayServer.window_set_title("Angst 'n Anchors · " + str(_handoff.get("captain_name", "MP test")))
	_menu._captains.remote.captains_listed.connect(func(_rows: Array): call_deferred("_roster_ready"))
	_menu._captains.error_message.connect(_fail)
	_menu._show_page(_menu.Page.MULTIPLAYER)
	_menu._captains.configure_remote(_menu, BASE_URL)
	print("MP AUTOJOIN: authenticated ", NetworkClientStorageScope.current_slot(), " on localhost")
	get_tree().create_timer(90.0).timeout.connect(func():
		if is_instance_valid(_menu) and not _menu._sailing:
			_fail("Automatic join timed out. Check the server and client log.")
	)


func _roster_ready() -> void:
	if _joining or _failed:
		return
	if not _menu._captains.has_remote_account():
		_fail("Test account authentication expired. Run the launcher again.")
		return
	_joining = true
	var service = _menu._captains
	var captain_name := str(_handoff.get("captain_name", "MP Test Captain"))
	for entry: Dictionary in service.entries():
		if str(entry.get("display_name", "")) == captain_name:
			service.select(str(entry.id))
			_menu._on_mp_sail(str(entry.id))
			return
	# First run follows the normal company/starter-vessel onboarding path.
	var seed := WorldBootstrap.apply_mp_world_options(_handoff.get("world_options", {}))
	if seed <= 0:
		_fail("Local server returned invalid world settings.")
		return
	PlayerSession.save_completed.connect(func(success: bool):
		if not success:
			_fail("Initial test captain save failed; automatic join stopped.")
			return
		_onboarding_saved = true
		_try_sail_new_captain()
	, CONNECT_ONE_SHOT)
	service.captain_created.connect(func(entry: Dictionary):
		print("MP AUTOJOIN: created test captain ", captain_name)
		_new_captain = entry
		_try_sail_new_captain()
	, CONNECT_ONE_SHOT)
	service.create_remote_onboarded(captain_name, CharacterAppearance.default_appearance(),
		"port-home", seed, captain_name + " Shipping", Color("2f7f83"), "general_cargo")


func _try_sail_new_captain() -> void:
	if _failed or not _onboarding_saved or _new_captain.is_empty():
		return
	# Finish onboarding requests before synchronous world loading can stall HTTP.
	var captain_id := str(_new_captain.id)
	_new_captain = {}
	VesselSync.ensure_vessel_registered(PlayerSession, PlayerSession.data.active_vessel.duplicate(true), func(record: Dictionary):
		if record.is_empty():
			_fail("Initial test vessel registration failed; automatic join stopped.")
			return
		_menu._on_mp_sail(captain_id)
	)


func _fail(message: String) -> void:
	_failed = true
	push_error("MP AUTOJOIN: " + message)
	if is_instance_valid(_menu):
		_menu._mp_status.text = message
