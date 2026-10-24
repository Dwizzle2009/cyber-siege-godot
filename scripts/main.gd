extends Node3D

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

@onready var player: CharacterBody3D = $Player
@onready var spawn_timer: Timer = $SpawnTimer
@onready var wave_label: Label = $HUD/Margin/VBox/Wave
@onready var score_label: Label = $HUD/Margin/VBox/Score
@onready var health_label: Label = $HUD/Margin/VBox/Health
@onready var status_label: Label = $HUD/Center/Status

var wave := 1
var score := 0
var enemies_to_spawn := 6
var enemies_spawned := 0
var enemies_alive := 0
var advancing_wave := false
var game_over := false

func _ready() -> void:
	# Main keeps processing while the tree is paused so it can see the resume
	# press and keep the HUD honest. Player, timer, enemies and bullets pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	spawn_timer.process_mode = Node.PROCESS_MODE_PAUSABLE

	randomize()
	spawn_timer.timeout.connect(_spawn_enemy)
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	_on_health_changed(100, 100)
	_update_hud()
	status_label.text = "WAVE 1"
	await get_tree().create_timer(1.0).timeout
	status_label.text = ""
	spawn_timer.start()

func _notification(what: int) -> void:
	# v0.1.1: the Aeon guide overlay takes keyboard focus from the game while the
	# player is in the menu. Pause when that happens; do not auto-resume on return --
	# a wave landing on you the instant you close the menu is not a fair fight.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not game_over:
		_pause_game()

func _process(_delta: float) -> void:
	if get_tree().paused:
		if Input.is_action_just_pressed("resume"):
			_resume_game()
		return
	if game_over and Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()

func _pause_game() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	status_label.text = "PAUSED\n\nA  TO RESUME"

func _resume_game() -> void:
	get_tree().paused = false
	status_label.text = ""

func _spawn_enemy() -> void:
	if game_over or enemies_spawned >= enemies_to_spawn:
		spawn_timer.stop()
		return

	var enemy := ENEMY_SCENE.instantiate()
	add_child(enemy)
	enemy.target = player
	enemy.global_position = _random_spawn_position()
	enemy.died.connect(_on_enemy_died)
	enemies_spawned += 1
	enemies_alive += 1

func _random_spawn_position() -> Vector3:
	var side := randi_range(0, 3)
	var edge := 12.5
	var spread := randf_range(-11.0, 11.0)
	match side:
		0:
			return Vector3(spread, 0.65, -edge)
		1:
			return Vector3(spread, 0.65, edge)
		2:
			return Vector3(-edge, 0.65, spread)
		_:
			return Vector3(edge, 0.65, spread)

func _on_enemy_died(points: int) -> void:
	score += points
	enemies_alive = maxi(0, enemies_alive - 1)
	_update_hud()
	if enemies_spawned >= enemies_to_spawn and enemies_alive == 0 and not advancing_wave:
		advance_wave()

func advance_wave() -> void:
	advancing_wave = true
	await get_tree().create_timer(1.2).timeout
	if game_over:
		return
	wave += 1
	if wave == 2: Aeon.unlock("first_wave")   # survived the first wave
	Aeon.progress("wave_10", wave, 10)
	Aeon.set_presence("Wave %d" % wave)
	enemies_to_spawn = 4 + wave * 2
	enemies_spawned = 0
	enemies_alive = 0
	spawn_timer.wait_time = maxf(0.28, 0.95 - wave * 0.045)
	status_label.text = "WAVE %d" % wave
	_update_hud()
	await get_tree().create_timer(0.9).timeout
	status_label.text = ""
	advancing_wave = false
	spawn_timer.start()

func _on_health_changed(current: int, maximum: int) -> void:
	health_label.text = "INTEGRITY  %03d / %03d" % [current, maximum]

func _on_player_died() -> void:
	game_over = true
	Aeon.submit_score("waves", wave)
	spawn_timer.stop()
	status_label.text = "SYSTEM BREACH\n\nSCORE  %06d\n\nR / A  TO REBOOT" % score

func _update_hud() -> void:
	wave_label.text = "WAVE  %02d" % wave
	score_label.text = "SCORE  %06d" % score
