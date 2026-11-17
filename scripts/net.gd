extends Node
## Gestor de red: partida offline (vs CPU) o multijugador LAN por punto de acceso movil.
## En modo hotspot, el host crea un servidor ENet en el puerto 7777 y los demas
## moviles se conectan poniendo la IP del host (se muestra en pantalla del host).

const PORT := 7777
const MAX_PLAYERS := 4

signal player_list_changed

var is_host := false
var connected_peers: Array[int] = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	connected_peers = [1]
	player_list_changed.emit()
	return true

func join_game(ip: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()

func offline() -> void:
	leave()

func _on_peer_connected(id: int) -> void:
	if is_host:
		connected_peers.append(id)
		player_list_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	player_list_changed.emit()
	get_tree().call_group("game", "on_peer_left", id)

func _on_connected_ok() -> void:
	connected_peers = [multiplayer.get_unique_id()]
	player_list_changed.emit()

func _on_connected_fail() -> void:
	leave()

func _on_server_disconnected() -> void:
	leave()
	get_tree().call_group("game", "on_server_lost")
