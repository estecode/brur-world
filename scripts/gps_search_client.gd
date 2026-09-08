extends Node

## Thin Godot transport adapter for resident native offline GPS search.
##
## Dependencies:
## - bin/brur-gps-search-server owns BSI2 mmap/search and JSON result serialization.
## - gps_search_index.gd is used only for the shared text-normalization contract.
## - Emits plain response dictionaries; owns no search UI, routing or rendering.

signal ready_changed(ready: bool)
signal response_received(response: Dictionary)
signal status_changed(text: String)

const SearchIndexScript = preload("res://scripts/gps_search_index.gd")
const SERVER_BINARY: String = "res://bin/brur-gps-search-server"
const INDEX_PATH: String = "res://world_data/search_index.bsi"
const SERVER_HOST: String = "127.0.0.1"
const SERVER_PORT: int = 47742
const CONNECT_RETRY_SECONDS: float = 0.15

var server_pid: int = -1
var server_peer: StreamPeerTCP
var receive_buffer: String = ""
var connect_retry_left: float = 0.0
var in_flight: bool = false
var queued_query: String = ""
var queued_limit: int = 8
var _ready_state: bool = false

func _ready() -> void:
	set_process(true)
	call_deferred("_start")

func _exit_tree() -> void:
	if server_peer != null:
		server_peer.disconnect_from_host()
		server_peer = null
	if server_pid > 0:
		OS.kill(server_pid)
		server_pid = -1

func is_ready() -> bool:
	return _ready_state

func request(query: String, limit: int = 8) -> void:
	var normalized: String = SearchIndexScript.normalize_search_text(query)
	queued_query = normalized
	queued_limit = clampi(limit, 1, 32)
	if normalized.is_empty():
		queued_query = ""
		response_received.emit({"success": true, "query_ms": 0.0, "count": 0, "results": []})
		return
	_try_send_queued()

func _start() -> void:
	if not FileAccess.file_exists(SERVER_BINARY):
		status_changed.emit("Native search server missing — run bash tools/build_native_gps.sh")
		return
	if not FileAccess.file_exists(INDEX_PATH):
		status_changed.emit("Search index missing — build world_data/search_index.bsi")
		return
	var server_path: String = ProjectSettings.globalize_path(SERVER_BINARY)
	var index_path: String = ProjectSettings.globalize_path(INDEX_PATH)
	server_pid = OS.create_process(server_path, PackedStringArray([index_path, str(SERVER_PORT)]), false)
	if server_pid <= 0:
		status_changed.emit("Could not start native search server")
		return
	status_changed.emit("Native search starting…")
	server_peer = StreamPeerTCP.new()
	_try_connect()

func _process(delta: float) -> void:
	if server_peer == null:
		return
	server_peer.poll()
	var status: StreamPeerTCP.Status = server_peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_set_ready(true)
		_read_responses()
		_try_send_queued()
		return
	_set_ready(false)
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	connect_retry_left -= delta
	if connect_retry_left <= 0.0:
		connect_retry_left = CONNECT_RETRY_SECONDS
		_try_connect()

func _try_connect() -> void:
	if server_peer == null:
		server_peer = StreamPeerTCP.new()
	var status: StreamPeerTCP.Status = server_peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return
	server_peer.disconnect_from_host()
	var error: Error = server_peer.connect_to_host(SERVER_HOST, SERVER_PORT)
	if error != OK:
		connect_retry_left = CONNECT_RETRY_SECONDS

func _try_send_queued() -> void:
	if in_flight or queued_query.is_empty() or server_peer == null:
		return
	if server_peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var query: String = queued_query
	var limit: int = queued_limit
	queued_query = ""
	var payload: String = "search %d %s\n" % [limit, query]
	var error: Error = server_peer.put_data(payload.to_utf8_buffer())
	if error != OK:
		status_changed.emit("Native search send failed")
		queued_query = query
		return
	in_flight = true

func _read_responses() -> void:
	var available: int = server_peer.get_available_bytes()
	if available <= 0:
		return
	receive_buffer += server_peer.get_utf8_string(available)
	while true:
		var newline: int = receive_buffer.find("\n")
		if newline < 0:
			break
		var line: String = receive_buffer.substr(0, newline)
		receive_buffer = receive_buffer.substr(newline + 1)
		if line.is_empty():
			continue
		in_flight = false
		var value: Variant = JSON.parse_string(line)
		if typeof(value) == TYPE_DICTIONARY:
			response_received.emit(value as Dictionary)
		else:
			response_received.emit({"success": false, "adapter_error": "invalid_json"})
		_try_send_queued()

func _set_ready(value: bool) -> void:
	if _ready_state == value:
		return
	_ready_state = value
	ready_changed.emit(value)
	if value:
		status_changed.emit("Search ready")
