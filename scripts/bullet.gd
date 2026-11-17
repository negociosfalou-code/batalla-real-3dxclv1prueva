extends Area3D
## Bala: viaja recto, daña al primer luchador que toca.

var direction := Vector3.FORWARD
var shooter: Node = null
var damage := 12.0
var life := 2.0
var speed := 60.0

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.15
	shape.shape = s
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.1
	m.height = 0.2
	mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.1)
	mesh.material_override = mat
	add_child(mesh)

	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	if body is Fighter and body.alive:
		body.take_damage(damage, shooter)
		queue_free()
	elif not (body is Fighter):
		queue_free()
