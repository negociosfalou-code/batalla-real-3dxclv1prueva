extends Node3D
## Partida: mapa 3D, zona de tormenta que se cierra, HUD y controles tactiles.
## Modos: vs CPU (offline) o multijugador LAN por hotspot (hasta 4 jugadores).

var vs_cpu := true
var cpu_difficulty := 1

var fighters: Array[Fighter] = []
var local_fighter: Fighter = null
var storm_center := Vector3.ZERO
var storm_radius := 90.0
var storm_target_radius := 90.0
var storm_timer := 0.0
var storm_mesh: MeshInstance3D
var game_over := false
var hud: CanvasLayer
var hp_bar: ProgressBar
var alive_label: Label
var zone_label: Label
var msg_label: Label
var winner_shown := false

# Controles tactiles
var joy_center := Vector2.ZERO
var joy_knob: Control
var joy_touch_index := -1
var look_touch_index := -1
var look_last := Vector2.ZERO
var fire_btn: Button
var jump_btn: Button

const MAP_HALF := 95.0
const STORM_WAIT := 20.0
const STORM_SHRINK := 25.0
const STORM_DPS := 8.0

func _ready() -> void:
	add_to_group("game")
	_build_world()
	_spawn_fighters()
	_build_hud()

# ---------------- Mundo ----------------
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_HALF * 2, MAP_HALF * 2)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.25, 0.45, 0.25)
	ground.material_override = gmat
	add_child(ground)

	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(MAP_HALF * 2, 1, MAP_HALF * 2)
	gshape.shape = gbox
	gshape.position = Vector3(0, -0.5, 0)
	var gbody := StaticBody3D.new()
	gbody.add_child(gshape)
	add_child(gbody)

	# Edificios/cajas al azar (determinista por semilla)
	seed(12345)
	for i in 60:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := randf_range(2, 8)
		var h := randf_range(2, 12)
		bm.size = Vector3(w, h, randf_range(2, 8))
		b.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.3, 0.7), randf_range(0.3, 0.7), randf_range(0.3, 0.7))
		b.material_override = mat
		var body := StaticBody3D.new()
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		sh.shape = bs
		body.add_child(sh)
		body.add_child(b)
		var x := randf_range(-MAP_HALF + 10, MAP_HALF - 10)
		var z := randf_range(-MAP_HALF + 10, MAP_HALF - 10)
		body.position = Vector3(x, h / 2.0, z)
		add_child(body)

	# Tormenta: cilindro semitransparente que se encoge
	storm_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 60.0
	storm_mesh.mesh = cyl
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.6, 0.1, 0.8, 0.25)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	storm_mesh.material_override = smat
	add_child(storm_mesh)
	_update_storm_mesh()

# ---------------- Luchadores ----------------
func _spawn_fighters() -> void:
	var colors := [Color(0.2, 0.6, 1.0), Color(1.0, 0.4, 0.3), Color(0.3, 0.9, 0.4), Color(1.0, 0.9, 0.2)]
	var fighter_script := preload("res://scripts/fighter.gd")

	if vs_cpu:
		Net.offline()
		_spawn_one(fighter_script, 1, "Tu", colors[0], true, false, 1)
		for i in 3:
			var bot := _spawn_one(fighter_script, 2 + i, "CPU-%d" % (i + 1), colors[i + 1], false, true, 1)
			bot.difficulty = cpu_difficulty
			bot.max_hp = bot.get_ai_stat("hp")
			bot.hp = bot.max_hp
			bot.speed = bot.get_ai_stat("speed")
	else:
		Net.connected_peers.sort()
		var idx := 0
		for pid in Net.connected_peers:
			var is_me := pid == multiplayer.get_unique_id()
			_spawn_one(fighter_script, pid, "Jugador-%d" % idx, colors[idx % 4], is_me, false, pid)
			idx += 1
		# Rellenar con bots hasta 4 (solo el host los simula)
		if multiplayer.is_server():
			while idx < 4:
				var bot := _spawn_one(fighter_script, 100 + idx, "CPU-%d" % (idx + 1), colors[idx % 4], false, true, 1)
				bot.difficulty = 1
				idx += 1

	# Posiciones iniciales en circulo
	var n := fighters.size()
	for i in n:
		var ang := TAU * i / n
		fighters[i].global_position = Vector3(cos(ang) * 40, 1, sin(ang) * 40)
		fighters[i].yaw = atan2(-(-fighters[i].global_position.x), -(-fighters[i].global_position.z))

func _spawn_one(script: GDScript, id: int, fname: String, color: Color, is_local: bool, is_bot: bool, peer: int) -> Fighter:
	var f := CharacterBody3D.new()
	f.set_script(script)
	f.name = "F%d" % id
	f.fighter_name = fname
	f.body_color = color
	f.is_local = is_local
	f.is_bot = is_bot
	f.peer_id = peer
	add_child(f)
	f.died.connect(_on_fighter_died)
	fighters.append(f)
	if is_local:
		local_fighter = f
	return f

func on_peer_left(id: int) -> void:
	for f in fighters:
		if f.peer_id == id and f.alive:
			f._die()

func on_server_lost() -> void:
	_show_message("Conexion perdida con el host.")

# ---------------- Tormenta ----------------
func _physics_process(delta: float) -> void:
	if game_over:
		return
	storm_timer += delta
	if storm_radius > 8.0:
		if storm_timer > STORM_WAIT:
			storm_radius = maxf(8.0, storm_radius - (90.0 - 8.0) / STORM_SHRINK * delta)
			_update_storm_mesh()
		zone_label.text = "Zona: %.0fm (se cierra en %ds)" % [storm_radius, maxi(0, int(STORM_WAIT - storm_timer))]
		if storm_timer > STORM_WAIT + STORM_SHRINK:
			storm_timer = 0.0  # ciclo: espera y vuelve a encoger
	else:
		zone_label.text = "Zona final"

	# Dano fuera de la zona
	for f in fighters:
		if f.alive and Vector2(f.global_position.x, f.global_position.z).distance_to(Vector2(storm_center.x, storm_center.z)) > storm_radius:
			f.take_damage(STORM_DPS * delta, null)

	# Sincronizar estado en red
	if multiplayer.multiplayer_peer != null:
		for f in fighters:
			if f.is_local:
				f.rpc_state.rpc(f.global_position, f.yaw, f.hp, f.alive)
			elif f.is_bot and multiplayer.is_server():
				f.rpc_state.rpc(f.global_position, f.yaw, f.hp, f.alive)

	if local_fighter != null:
		hp_bar.value = clampf(local_fighter.hp, 0, local_fighter.max_hp)

func _update_storm_mesh() -> void:
	storm_mesh.scale = Vector3(storm_radius, 1, storm_radius)
	storm_mesh.global_position = Vector3(storm_center.x, 29, storm_center.z)

# ---------------- Fin de partida ----------------
func _on_fighter_died(_f: Fighter) -> void:
	var alive_count := 0
	var winner: Fighter = null
	for f in fighters:
		if f.alive:
			alive_count += 1
			winner = f
	alive_label.text = "Vivos: %d" % alive_count
	if alive_count <= 1 and not winner_shown:
		winner_shown = true
		game_over = true
		if winner != null and winner.is_local:
			_show_message("¡VICTORIA! Eres el ultimo en pie.")
		elif winner != null:
			_show_message("Gano " + winner.fighter_name)
		else:
			_show_message("Empate.")
		var back := Button.new()
		back.text = "Volver al menu"
		back.custom_minimum_size = Vector2(240, 60)
		back.position = Vector2(340, 400)
		hud.add_child(back)
		back.pressed.connect(func():
			Net.leave()
			get_tree().reload_current_scene())

# ---------------- HUD y controles tactiles ----------------
func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(400, 26)
	hp_bar.position = Vector2(20, 20)
	hp_bar.max_value = 100
	hud.add_child(hp_bar)

	alive_label = Label.new()
	alive_label.position = Vector2(20, 55)
	alive_label.text = "Vivos: 4"
	hud.add_child(alive_label)

	zone_label = Label.new()
	zone_label.position = Vector2(20, 85)
	hud.add_child(zone_label)

	msg_label = Label.new()
	msg_label.position = Vector2(200, 200)
	msg_label.add_theme_font_size_override("font_size", 36)
	hud.add_child(msg_label)

	# Joystick virtual (mitad izquierda inferior)
	var joy_base := Control.new()
	joy_base.position = Vector2(60, 380)
	joy_base.custom_minimum_size = Vector2(220, 220)
	joy_base.gui_input.connect(_on_joy_input)
	var joy_bg := ColorRect.new()
	joy_bg.color = Color(1, 1, 1, 0.15)
	joy_bg.size = Vector2(220, 220)
	joy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_child(joy_bg)
	joy_knob = ColorRect.new()
	joy_knob.color = Color(1, 1, 1, 0.4)
	joy_knob.size = Vector2(70, 70)
	joy_knob.position = Vector2(75, 75)
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_child(joy_knob)
	hud.add_child(joy_base)

	# Mirar: arrastrar en mitad derecha
	var look_area := Control.new()
	look_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_area.gui_input.connect(_on_look_input)
	look_area.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(look_area)
	hud.move_child(look_area, 0)  # detras del joystick y botones

	fire_btn = Button.new()
	fire_btn.text = "DISPARAR"
	fire_btn.position = Vector2(880, 440)
	fire_btn.custom_minimum_size = Vector2(160, 100)
	fire_btn.button_down.connect(func(): if local_fighter: local_fighter.input_fire = true)
	fire_btn.button_up.connect(func(): if local_fighter: local_fighter.input_fire = false)
	hud.add_child(fire_btn)

	jump_btn = Button.new()
	jump_btn.text = "SALTAR"
	jump_btn.position = Vector2(880, 320)
	jump_btn.custom_minimum_size = Vector2(160, 90)
	jump_btn.pressed.connect(func(): if local_fighter: local_fighter.input_jump = true)
	hud.add_child(jump_btn)

func _on_joy_input(event: InputEvent) -> void:
	if local_fighter == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			joy_touch_index = event.index
			joy_center = event.position
		elif event.index == joy_touch_index:
			joy_touch_index = -1
			local_fighter.input_move = Vector2.ZERO
			joy_knob.position = Vector2(75, 75)
	elif event is InputEventScreenDrag and event.index == joy_touch_index:
		var v := (event.position - joy_center) / 60.0
		if v.length() > 1.0:
			v = v.normalized()
		local_fighter.input_move = v
		joy_knob.position = Vector2(75, 75) + v * 60.0

func _on_look_input(event: InputEvent) -> void:
	if local_fighter == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			look_touch_index = event.index
			look_last = event.position
		elif event.index == look_touch_index:
			look_touch_index = -1
	elif event is InputEventScreenDrag and event.index == look_touch_index:
		var d := event.position - look_last
		look_last = event.position
		local_fighter.yaw -= d.x * 0.005
		local_fighter.pitch = clampf(local_fighter.pitch - d.y * 0.005, -1.2, 0.8)

func _show_message(text: String) -> void:
	msg_label.text = text
