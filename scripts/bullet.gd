extends Area3D

@export var speed: float = 28.0
@export var damage: int = 25
@export var lifetime: float = 1.8

var direction := Vector3.FORWARD
var life_left := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE   # v0.1.1: stops with the tree
	life_left = lifetime
	body_entered.connect(_on_body_entered)

func setup(dir: Vector3) -> void:
	direction = dir.normalized()

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	life_left -= delta
	if life_left <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
