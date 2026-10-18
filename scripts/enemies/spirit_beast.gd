class_name SpiritBeast
extends CharacterBody3D

## A hostile demonic beast that chases the cultivator and attacks in melee.

signal died(qi_reward: float)

@export var height := 1.2
@export var max_hp := 60.0
@export var move_speed := 3.2
@export var detect_range := 11.0
@export var attack_range := 2.0
@export var attack_damage := 8.0
@export var attack_cooldown := 1.4
@export var qi_reward := 40.0

## Tripo model for the beast. Assigned before the node enters the tree.
var model_scene: PackedScene
var hp := 60.0

var _visual: Node3D
var _cooldown := 0.0
var _dead := false
var _player: Cultivator
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_visual = Node3D.new()
	add_child(_visual)
	var model := model_scene.instantiate() as Node3D
	_visual.add_child(model)
	ModelUtils.fit_to_height(model, height)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	add_child(shape)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Cultivator

	var horizontal := Vector3.ZERO
	if _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance <= detect_range:
			_visual.rotation.y = ModelUtils.yaw_towards(to_player)
			if distance > attack_range:
				horizontal = to_player.normalized() * move_speed
			elif _cooldown <= 0.0:
				_cooldown = attack_cooldown
				_player.take_damage(attack_damage)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	remove_from_group("enemies")
	collision_layer = 0
	died.emit(qi_reward)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.6)
	tween.tween_callback(queue_free)
