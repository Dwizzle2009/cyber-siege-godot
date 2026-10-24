extends CharacterBody3D

signal died(points: int)

@export var speed: float = 3.1
@export var max_health: int = 50
@export var contact_damage: int = 10
@export var score_value: int = 100

var target: Node3D
var health: int
var attack_cooldown := 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE   # v0.1.1: stops with the tree
	health = max_health
	var base_material := mesh.get_active_material(0)
	if base_material != null:
		mesh.material_override = base_material.duplicate()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = Vector3.ZERO
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()

	if distance > 1.15:
		velocity = offset.normalized() * speed
		move_and_slide()
	else:
		velocity = Vector3.ZERO
		if attack_cooldown <= 0.0 and target.has_method("take_damage"):
			target.take_damage(contact_damage)
			attack_cooldown = 0.75

	if offset.length_squared() > 0.01:
		look_at(global_position + offset, Vector3.UP)

func take_damage(amount: int) -> void:
	health -= amount
	_flash_hit()
	if health <= 0:
		died.emit(score_value)
		queue_free()

func _flash_hit() -> void:
	var material := mesh.material_override as StandardMaterial3D
	if material == null:
		return
	var original := material.albedo_color
	material.albedo_color = Color(1.0, 0.85, 0.85)
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(mesh):
		material.albedo_color = original
