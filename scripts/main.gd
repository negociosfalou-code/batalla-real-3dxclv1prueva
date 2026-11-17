extends Node3D
## Menu principal: elegir modo (vs CPU con dificultad, o multijugador LAN 4 jugadores).

var difficulty := 1  # 0 Facil, 1 Normal, 2 Dificil, 3 Extremo
var game_scene := preload("res://scripts/game.gd")

var menu_layer: CanvasLayer
var status_label: Label
var ip_input: LineEdit

func _ready() -> void:
	_build_menu()

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = Vector2(-260, -280)
	box.add_theme_constant_override("separation", 14)
	menu_layer.add_child(box)

	var title := Label.new()
	title.text = "BATALLA REAL 3D"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Battle royale offline vs CPU o 4 jugadores por hotspot"
	sub.add_theme_font_size_override("font_size", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(HSeparator.new())

	# --- Dificultad CPU ---
	var diff_label := Label.new()
	diff_label.text = "Dificultad del CPU:"
	box.add_child(diff_label)
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	box.add_child(diff_row)
	var names := ["Facil", "Normal", "Dificil", "Extremo"]
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_pressed = (i == difficulty)
		b.pressed.connect(func():
			difficulty = i
			for other in diff_row.get_children():
				other.button_pressed = (other == b))
		b.custom_minimum_size = Vector2(120, 50)
		diff_row.add_child(b)

	box.add_child(HSeparator.new())

	var btn_cpu := Button.new()
	btn_cpu.text = "Jugar solo contra el CPU"
	btn_cpu.custom_minimum_size = Vector2(0, 60)
	btn_cpu.pressed.connect(_start_vs_cpu)
	box.add_child(btn_cpu)

	var btn_host := Button.new()
	btn_host.text = "Crear partida (host, hasta 4 jugadores)"
	btn_host.custom_minimum_size = Vector2(0, 60)
	btn_host.pressed.connect(_start_host)
	box.add_child(btn_host)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "IP del host (ej. 192.168.43.1)"
	ip_input.custom_minimum_size = Vector2(340, 55)
	join_row.add_child(ip_input)
	var btn_join := Button.new()
	btn_join.text = "Unirse"
	btn_join.custom_minimum_size = Vector2(160, 55)
	btn_join.pressed.connect(_start_join)
	join_row.add_child(btn_join)

	status_label = Label.new()
	status_label.text = "Para jugar por hotspot: uno crea la partida y los demas se unen con su IP."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(520, 60)
	box.add_child(status_label)

func _start_vs_cpu() -> void:
	Net.offline()
	_start_game(true)

func _start_host() -> void:
	if not Net.host_game():
		status_label.text = "Error: no se pudo abrir el puerto %d" % Net.PORT
		return
	_start_game(false)

func _start_join() -> void:
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Escribe la IP del host."
		return
	if not Net.join_game(ip):
		status_label.text = "Error: IP invalida."
		return
	status_label.text = "Conectando a " + ip + " ..."
	# Esperamos confirmacion de conexion antes de entrar.
	await get_tree().create_timer(2.0).timeout
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_start_game(false)
	else:
		status_label.text = "No se pudo conectar. Revisa la IP y que ambos esten en el mismo hotspot."

func _start_game(vs_cpu: bool) -> void:
	menu_layer.queue_free()
	var game := game_scene.new()
	game.name = "Game"
	game.vs_cpu = vs_cpu
	game.cpu_difficulty = difficulty
	add_child(game)
