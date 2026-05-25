extends Node

## Manages raw UDP socket I/O and HTTP queries with the game server.
## Does not maintain high-level game state; only transports raw byte packets.

signal packet_received(msg_type: int, payload: PackedByteArray)
signal connection_status_changed(connected: bool)

var _udp_peer: PacketPeerUDP = null
var _udp_connected: bool = false
var _udp_server_host: String = ""
var _udp_server_port: int = 7777
var _connect_requested: bool = false

var _health_http_req: HTTPRequest = null


func _ready() -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.connect("changed", _on_server_config_changed)
	_refresh_server_endpoints()


func _on_server_config_changed() -> void:
	_refresh_server_endpoints()
	if _connect_requested:
		_rebind_connection()


func _refresh_server_endpoints() -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config == null:
		return
	_udp_server_host = config.get("udp_host")
	_udp_server_port = int(config.get("udp_port"))


func request_connect() -> void:
	_connect_requested = true
	_rebind_connection()


func _rebind_connection() -> void:
	_close_udp_socket()
	_refresh_server_endpoints()
	if _connect_requested:
		ensure_udp_peer()


func _process(_delta: float) -> void:
	_poll_udp()


func ensure_udp_peer() -> void:
	if not _connect_requested:
		return
	if _udp_peer != null:
		return
	_udp_peer = PacketPeerUDP.new()
	var err := _udp_peer.connect_to_host(_udp_server_host, _udp_server_port)
	if err != OK:
		push_warning("NetworkClient: UDP connect failed to %s:%d err=%d" % [_udp_server_host, _udp_server_port, err])
		_udp_peer = null
		_set_connected(false)
	else:
		_set_connected(true)


func close_connection() -> void:
	_connect_requested = false
	_close_udp_socket()


func _close_udp_socket() -> void:
	if _udp_peer != null:
		_udp_peer.close()
		_udp_peer = null
	_set_connected(false)


func _set_connected(val: bool) -> void:
	if _udp_connected != val:
		_udp_connected = val
		connection_status_changed.emit(val)


func is_connected_to_host() -> bool:
	return _udp_connected


func send_packet(packet: PackedByteArray) -> void:
	if not _connect_requested:
		return
	ensure_udp_peer()
	if _udp_peer == null:
		return
	var err := _udp_peer.put_packet(packet)
	if err != OK:
		push_warning("NetworkClient: Failed to send UDP packet, err=%d" % err)


func _poll_udp() -> void:
	if _udp_peer == null:
		return
	while _udp_peer.get_available_packet_count() > 0:
		var packet := _udp_peer.get_packet()
		if packet.size() < 2:
			continue
		# Byte 0 is version, Byte 1 is MsgType
		var msg_type := int(packet[1])
		packet_received.emit(msg_type, packet)


## Tests connectivity using a quick HTTP healthz / world-snapshot ping.
## The callback takes two arguments: success: bool, response_code: int
func test_http_connection(callback: Callable) -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config == null:
		callback.call(false, 0)
		return
	
	if _health_http_req != null and is_instance_valid(_health_http_req):
		_health_http_req.queue_free()
	
	_health_http_req = HTTPRequest.new()
	add_child(_health_http_req)
	_health_http_req.timeout = 2.0
	
	_health_http_req.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			var ok := (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
			callback.call(ok, response_code)
			_health_http_req.queue_free()
			_health_http_req = null
	)
	
	var url := "%s/healthz" % config.call("get_http_base_url")
	var err := _health_http_req.request(url)
	if err != OK:
		callback.call(false, 0)
		_health_http_req.queue_free()
		_health_http_req = null
