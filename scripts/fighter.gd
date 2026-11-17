extends CharacterBody3D
class_name Fighter
## Personaje: jugador local, jugador remoto o bot (CPU). Se construye por codigo.

signal died(fighter)
signal health_changed(hp: float)

const GRAVITY := 28.0

var hp := 100.0
var max_hp := 100.0
var speed := 6.5
var alive := true
var is_local := false
var is_bot := false
var peer_id := 1
var fighter_name := "Jugador"
var body_color := Color(0.2, 0.5, 1.0)

# Entrada (local) o IA (bot)
var input_move := Vector2.ZERO
var input_look := Vector2.ZERO   # yaw, pitch deltas
var input_fire := false
var input_jump := false

# IA
var difficulty := 1
var ai_target: Fighter = null
var ai_think_timer := 0.0
var ai_shoot_timer := 0.0

var fire_cooldown := 0.0
var yaw := 0.0
var pitch := -0.15
var bullet_script := preload("res://scripts/bullet.gd")

var cam_pivot: Node3D
var cam: Camera3D
var mesh: MeshInstance3D

func _ready() -> void:
	_build_body()
	if is_local:
		cam.current = true

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	mesh = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	mesh.mesh = cap
	mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mesh.material_override = mat
	add_child(mesh)

	# "Arma": caja delante
	var gun := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.7)
	gun.mesh = box
	gun.position = Vector3(0.35, 1.2, -0.5)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.15, 0.15)
	gun.material_override = gmat
	add_child(gun)

	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, 1.6, 0)
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.fov = 75
	cam.position = Vector3(0, 0.6, 4.5)  # tercera persona
	cam_pivot.add_child(cam)

	set_multiplayer_authority(peer_id)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	fire_cooldown = maxf(0.0, fire_cooldown - delta)

	if is_bot and (multiplayer.multiplayer_peer == null or multiplayer.is_server()):
		_think(delta)

	if not is_local and not is_bot:
		# Los luchadores remotos se mueven por rpc_state: no simular fisica local.
		return

	if is_local:
		_apply_camera()

	var dir := Vector3(input_move.x, 0, input_move.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Mover relativo al yaw del personaje
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var vel := (right * dir.x + forward * -dir.y) * speed
	velocity.x = vel.x
	velocity.z = vel.z
	if input_jump and is_on_floor():
		velocity.y = 9.0
		input_jump = false
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()

	if input_fire and fire_cooldown <= 0.0:
		_shoot()

func _apply_camera() -> void:
	cam_pivot.rotation.y = yaw
	cam.rotation.x = pitch

func aim_origin() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)

func aim_direction() -> Vector3:
	var d := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	return d.normalized()

func _shoot() -> void:
	fire_cooldown = 0.22
	var b := Area3D.new()
	b.set_script(bullet_script)
	b.shooter = self
	b.damage = 12.0
	get_parent().add_child(b)
	b.global_position = aim_origin() + aim_direction() * 0.8
	b.direction = aim_direction()
	if multiplayer.multiplayer_peer != null and not is_bot:
		rpc("rpc_shoot", [global_position, yaw, pitch])

@rpc("any_peer", "call_remote", "unreliable")
func rpc_state(pos: Vector3, p_yaw: float, p_hp: float, p_alive: bool) -> void:
	global_position = pos
	yaw = p_yaw
	cam_pivot.rotation.y = yaw
	hp = p_hp
	if alive and not p_alive:
		_die()
	alive = p_alive

@rpc("any_peer", "call_remote", "reliable")
func rpc_shoot(pos: Vector3, p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch
	var b := Area3D.new()
	b.set_script(bullet_script)
	b.shooter = self
	b.damage = 12.0
	get_parent().add_child(b)
	b.global_position = aim_origin() + aim_direction() * 0.8
	b.direction = aim_direction()

func take_damage(amount: float, from: Node) -> void:
	if not alive:
		return
	hp -= amount
	health_changed.emit(hp)
	if hp <= 0.0:
		_die()
		if from is Fighter:
			pass  # contable de bajas en game.gd

func _die() -> void:
	alive = false
	hp = 0
	health_changed.emit(0)
	visible = false
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	died.emit(self)

func respawn() -> void:
	alive = true
	hp = max_hp
	visible = true
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1

# ---------------- IA del bot ----------------
func _think(delta: float) -> void:
	ai_think_timer -= delta
	ai_shoot_timer -= delta
	# Buscar objetivo mas cercano vivo que no sea bot
	if ai_think_timer <= 0.0 or ai_target == null or not is_instance_valid(ai_target) or not ai_target.alive:
		ai_think_timer = 1.0
		var best: Fighter = null
		var best_d := INF
		for f in get_parent().get_children():
			if f is Fighter and f != self and f.alive and not f.is_bot:
				var d: float = global_position.distance_to(f.global_position)
				if d < best_d:
					best_d = d
					best = f
		ai_target = best

	if ai_target == null:
		input_move = Vector2.ZERO
		input_fire = false
		return

	var to_target := ai_target.global_position - global_position
	var dist := to_target.length()
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	yaw = lerp_angle(yaw, desired_yaw, get_ai_stat("turn") * delta)
	pitch = -0.05

	# Mantener distancia media y acercarse a la zona segura
	var game := get_parent()
	var storm_center: Vector3 = game.storm_center
	var storm_radius: float = game.storm_radius
	var to_storm := storm_center - global_position
	var want_move := Vector3.ZERO
	if global_position.distance_to(storm_center) > storm_radius * 0.8:
		want_move = to_storm.normalized()
	elif dist > 18.0:
		want_move = to_target.normalized()
	elif dist < 8.0:
		want_move = -to_target.normalized()
	else:
		want_move = to_target.cross(Vector3.UP).normalized() * (1.0 if int(ai_think_timer * 10.0) % 2 == 0 else -1.0)

	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	input_move = Vector2(want_move.dot(right), -want_move.dot(forward))
	if input_move.length() > 1.0:
		input_move = input_move.normalized()

	# Disparo con dispersion segun dificultad
	input_fire = dist < 45.0 and ai_shoot_timer <= 0.0
	if input_fire:
		ai_shoot_timer = get_ai_stat("fire_delay")
		var spread := get_ai_stat("spread")
		var aim := to_target.normalized()
		aim = (aim + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
		var ang := atan2(-aim.x, -aim.z)
		yaw = ang
		pitch = asin(clampf(aim.y, -1, 1))

func get_ai_stat(key: String) -> float:
	# 0 Facil, 1 Normal, 2 Dificil, 3 Extremo
	var stats := [
		{"turn": 2.0, "fire_delay": 1.6, "spread": 0.14, "speed": 4.5, "hp": 70.0},
		{"turn": 4.0, "fire_delay": 1.0, "spread": 0.09, "speed": 5.5, "hp": 100.0},
		{"turn": 6.0, "fire_delay": 0.6, "spread": 0.05, "speed": 6.5, "hp": 130.0},
		{"turn": 9.0, "fire_delay": 0.35, "spread": 0.02, "speed": 7.5, "hp": 160.0},
	][difficulty]
	return stats[key]
