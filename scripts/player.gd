extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died

const BULLET_SCENE := preload("res://scenes/bullet.tscn")

@export var move_speed: float = 6.5
@export var max_health: int = 100
@export var fire_rate: float = 0.16

var health: int
var fire_cooldown := 0.0
var aim_direction := Vector3(0.0, 0.0, -1.0)
var invulnerable_time := 0.0

@onready var muzzle: Marker3D = $Muzzle
@onready var camera: Camera3D = get_viewport().get_camera_3d()

func _ready() -> void:
	# Stops when the tree pauses (guide overlay / focus loss). Main stays ALWAYS
	# so it can catch the resume press; everything that moves is PAUSABLE.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	health = max_health
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	invulnerable_time = maxf(0.0, invulnerable_time - delta)

	# v0.1.1: everything goes through the InputMap. Keyboard and left stick both
	# feed the same four actions, so remapping later touches project.godot, not code.
	var move_2d := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	velocity = Vector3(move_2d.x, 0.0, move_2d.y) * move_speed
	move_and_slide()
	global_position.x = clampf(global_position.x, -13.2, 13.2)
	global_position.z = clampf(global_position.z, -13.2, 13.2)

	_update_aim()
	if aim_direction.length_squared() > 0.01:
		look_at(global_position + aim_direction, Vector3.UP)

	if Input.is_action_pressed("fire") and fire_cooldown <= 0.0:
		_fire()
		fire_cooldown = fire_rate

func _update_aim() -> void:
	# Right stick wins when it is deflected past its deadzone; otherwise mouse.
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length_squared() > 0.0:
		aim_direction = Vector3(stick.x, 0.0, stick.y).normalized()
		return

	if camera == null:
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_direction := camera.project_ray_normal(mouse)
	var aim_plane := Plane(Vector3.UP, global_position.y)
	var hit = aim_plane.intersects_ray(ray_origin, ray_direction)
	if hit is Vector3:
		var toward_mouse: Vector3 = hit - global_position
		toward_mouse.y = 0.0
		if toward_mouse.length() > 0.1:
			aim_direction = toward_mouse.normalized()

func _fire() -> void:
	var bullet := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.setup(aim_direction)

func take_damage(amount: int) -> void:
	if invulnerable_time > 0.0 or health <= 0:
		return
	health = maxi(0, health - amount)
	invulnerable_time = 0.18
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()
		set_physics_process(false)
