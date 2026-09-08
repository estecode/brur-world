class_name GpsClient
extends Node

## Owns native GPS process/TCP lifecycle and wire response delivery.
##
## Dependencies:
## - Uses GpsProtocol for deterministic response decoding.
## - Uses Godot OS/FileAccess/StreamPeerTCP only; no UI, route model or rendering dependency.

signal ready_changed(ready: bool)
signal busy_changed(busy: bool)
signal response_received(response: Dictionary)
signal protocol_error(error: String)
signal transport_status(message: String)

const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")
const DEFAULT_SERVER_BINARY: String = "res://bin/brur-gps-server"
const DEFAULT_GRAPH_PATH: String = "res://world_data/routing.brg"
const DEFAULT_SNAP_PATH: String = "res://world_data/routing_snap.brs"
const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 47741
const CONNECT_RETRY_SECONDS: float = 0.15

var _server_binary: String = DEFAULT_SERVER_BINARY
var _graph_path: String = DEFAULT_GRAPH_PATH
var _snap_path: String = DEFAULT_SNAP_PATH
var _host: String = DEFAULT_HOST
var _port: int = DEFAULT_PORT
var _server_pid: int = -1
var _peer: StreamPeerTCP
var _receive_buffer: String = ""
var _connect_retry_left: float = 0.0
var _ready: bool = false
var _busy: bool = false
var _parse_ms: float = 0.0

func configure(
	server_binary: String = DEFAULT_SERVER_BINARY,
	graph_path: String = DEFAULT_GRAPH_PATH,
	snap_path: String = DEFAULT_SNAP_PATH,
	host: String = DEFAULT_HOST,
	port: int = DEFAULT_PORT
) -> void:
	_server_binary = server_binary
	_graph_path = graph_path
	_snap_path = snap_path
	_host = host
	_port = port

func start() -> bool:
	if _server_pid > 0:
		if _peer == null:
			_peer = StreamPeerTCP.new()
		_try_connect()
		return true
	if not FileAccess.file_exists(_server_binary):
		transport_status.emit("GPS native server missing. Run: bash tools/build_native_gps.sh")
		return false
	if not FileAccess.file_exists(_graph_path) or not FileAccess.file_exists(_snap_path):
		transport_status.emit("GPS data missing: routing.brg / routing_snap.brs")
		return false
	var geometry_path := _graph_path.get_base_dir().path_join("routing_geometry.brh")
	if not FileAccess.file_exists(geometry_path):
		transport_status.emit("GPS data missing: routing_geometry.brh — rebuild routing data")
		return false
	var args := PackedStringArray([
		ProjectSettings.globalize_path(_graph_path),
		ProjectSettings.globalize_path(_snap_path),
		str(_port),
	])
	_server_pid = OS.create_process(ProjectSettings.globalize_path(_server_binary), args, false)
	if _server_pid <= 0:
		transport_status.emit("Could not start native GPS server")
		return false
	transport_status.emit("GPS native server starting…")
	_peer = StreamPeerTCP.new()
	_connect_retry_left = 0.0
	_try_connect()
	return true

func stop() -> void:
	_set_ready(false)
	_set_busy(false)
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1
	_receive_buffer = ""

func _exit_tree() -> void:
	stop()

func poll(delta: float) -> void:
	if _peer == null:
		if _busy:
			_set_busy(false)
			transport_status.emit("GPS connection lost during route calculation — try again")
		return
	_peer.poll()
	var status: StreamPeerTCP.Status = _peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_set_ready(true)
		_read_responses()
		return
	_set_ready(false)
	if _busy:
		_set_busy(false)
		transport_status.emit("GPS connection lost during route calculation — try again")
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	_connect_retry_left -= delta
	if _connect_retry_left <= 0.0:
		_connect_retry_left = CONNECT_RETRY_SECONDS
		_try_connect()

func send_request(request: String) -> bool:
	if request.is_empty() or not is_ready() or _busy:
		return false
	var error: Error = _peer.put_data(request.to_utf8_buffer())
	if error != OK:
		transport_status.emit("Could not send GPS route plan")
		return false
	_set_busy(true)
	return true

func is_ready() -> bool:
	return _ready and _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

func is_busy() -> bool:
	return _busy

func consume_perf_metrics() -> Dictionary:
	var result := {"gps_parse_ms": _parse_ms}
	_parse_ms = 0.0
	return result

func _try_connect() -> void:
	if _peer == null:
		_peer = StreamPeerTCP.new()
	var status: StreamPeerTCP.Status = _peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return
	_peer.disconnect_from_host()
	var error: Error = _peer.connect_to_host(_host, _port)
	if error != OK:
		_connect_retry_left = CONNECT_RETRY_SECONDS

func _read_responses() -> void:
	var available: int = _peer.get_available_bytes()
	if available <= 0:
		return
	_receive_buffer += _peer.get_utf8_string(available)
	while true:
		var newline: int = _receive_buffer.find("\n")
		if newline < 0:
			break
		var line: String = _receive_buffer.substr(0, newline).strip_edges()
		_receive_buffer = _receive_buffer.substr(newline + 1)
		if line.is_empty():
			continue
		var parse_started: int = Time.get_ticks_usec()
		var decoded: Dictionary = GpsProtocolScript.decode_response(line)
		_parse_ms += float(Time.get_ticks_usec() - parse_started) / 1000.0
		_set_busy(false)
		if bool(decoded.get("valid", false)):
			var payload: Dictionary = decoded.get("payload", {}) as Dictionary
			response_received.emit(payload)
		else:
			protocol_error.emit(str(decoded.get("error", "invalid_response")))

func _set_ready(value: bool) -> void:
	if _ready == value:
		return
	_ready = value
	ready_changed.emit(_ready)

func _set_busy(value: bool) -> void:
	if _busy == value:
		return
	_busy = value
	busy_changed.emit(_busy)
