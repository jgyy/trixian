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
## Seconds from the start of the bite to the jaws closing.
@export var bite_delay := 0.25
@export var qi_reward := 40.0
@export var turn_speed := 8.0

## Tripo model for the beast. Assigned before the node enters the tree.
var model_scene: PackedScene
var hp := 60.0
var animator: CharacterAnimator

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
	animator = CharacterAnimator.new(model)

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
			_turn_towards(delta, to_player)
			if distance > attack_range:
				horizontal = to_player.normalized() * move_speed
			elif _cooldown <= 0.0:
				_cooldown = attack_cooldown
				_lunge()
				get_tree().create_timer(bite_delay).timeout.connect(_land_bite)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	animator.play(&"run" if horizontal.length() > 0.1 else &"idle")


## The bite hurts only if the cultivator is still within a lunge's reach when the jaws close.
func _land_bite() -> void:
	if _dead or not is_instance_valid(_player):
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= attack_range * 1.4:
		_player.take_damage(attack_damage)


## The direction the model's front points in, on the world axes.
func facing() -> Vector3:
	return _visual.global_transform.basis * Vector3.BACK


func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_die()
	else:
		_flinch()


func _turn_towards(delta: float, direction: Vector3) -> void:
	var target := ModelUtils.yaw_towards(direction)
	_visual.rotation.y = lerp_angle(
		_visual.rotation.y, target, clampf(turn_speed * delta, 0.0, 1.0)
	)


## Procedural strike used when the model has no attack clip: the body snaps forward and back.
func _lunge() -> void:
	if animator.play_action(&"slash"):
		return
	var tween := create_tween()
	tween.tween_property(_visual, "position:y", 0.12, 0.08)
	tween.tween_property(_visual, "position:y", 0.0, 0.16)


## Procedural recoil used when the model has no hurt clip.
func _flinch() -> void:
	if animator.play_action(&"hurt"):
		return
	var tween := create_tween()
	tween.tween_property(_visual, "rotation:x", -0.18, 0.06)
	tween.tween_property(_visual, "rotation:x", 0.0, 0.18)


func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	remove_from_group("enemies")
	collision_layer = 0
	died.emit(qi_reward)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.6)
	tween.tween_callback(queue_free)
