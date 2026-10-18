class_name Cultivator
extends CharacterBody3D

## The player's cultivator: third-person movement, sword strikes, meditation and breakthroughs.

signal stats_changed
signal realm_changed(realm_name: String)
signal message(text: String)
signal prompt_changed(text: String)

@export var height := 1.8
@export var move_speed := 5.5
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.003
@export var max_hp := 100.0
@export var attack_damage := 25.0
@export var attack_range := 2.6
@export var attack_cooldown := 0.45
@export var meditation_qi_per_second := 12.0
@export var interact_range := 3.0

## Tripo model for the cultivator. Assigned before the node enters the tree.
var model_scene: PackedScene
var hp := 100.0
var cultivation := Cultivation.new()
var is_meditating := false
var camera: Camera3D

var _spawn_position: Vector3
var _heading := 0.0
var _cooldown := 0.0
var _prompt := ""
var _visual: Node3D
var _yaw_pivot: Node3D
var _spring_arm: SpringArm3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	_spawn_position = position
	_build_body()
	_build_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw_pivot.rotate_y(-motion.relative.x * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x - motion.relative.y * mouse_sensitivity, -1.2, 0.35
		)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("meditate") and is_on_floor():
		_toggle_meditation()
	if Input.is_action_just_pressed("breakthrough"):
		_try_breakthrough()
	if Input.is_action_just_pressed("interact"):
		_interact()
	if Input.is_action_just_pressed("attack"):
		attack()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _yaw_pivot.global_transform.basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	direction = direction.normalized()
	if direction != Vector3.ZERO:
		is_meditating = false

	if is_meditating:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		if direction != Vector3.ZERO:
			_heading = atan2(direction.x, direction.z)

	_visual.rotation.y = lerp_angle(
		_visual.rotation.y, _heading + ModelUtils.FORWARD_OFFSET, clampf(12.0 * delta, 0.0, 1.0)
	)
	move_and_slide()

	if is_meditating:
		cultivation.gain_qi(meditation_qi_per_second * delta)
		hp = minf(hp + 2.0 * delta, max_hp)
		stats_changed.emit()
	_update_prompt()


## Sword strike: damages every spirit beast in a cone in front of the cultivator.
func attack() -> void:
	if _cooldown > 0.0 or is_meditating:
		return
	_cooldown = attack_cooldown
	_play_swing()
	var facing := Vector3(sin(_heading), 0.0, cos(_heading))
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as SpiritBeast
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length() <= attack_range and facing.dot(to_enemy.normalized()) > 0.3:
			enemy.take_damage(attack_damage)


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		hp = max_hp
		global_position = _spawn_position
		velocity = Vector3.ZERO
		is_meditating = false
		message.emit("You collapse and awaken at the sect gate.")
	stats_changed.emit()


func _toggle_meditation() -> void:
	is_meditating = not is_meditating
	if is_meditating:
		message.emit("You sit and circulate qi through your meridians.")
	else:
		message.emit("You rise from meditation.")


func _try_breakthrough() -> void:
	if cultivation.is_max_realm():
		message.emit("You already stand at the peak of this path.")
	elif cultivation.try_breakthrough():
		hp = max_hp
		realm_changed.emit(cultivation.realm_name())
	else:
		message.emit(
			(
				"The heavens refuse. Qi %d / %d."
				% [int(cultivation.qi), int(cultivation.qi_required())]
			)
		)
	stats_changed.emit()


func _interact() -> void:
	var npc := _nearest_npc()
	if npc != null:
		npc.interact(self)


func _nearest_npc() -> Npc:
	var best: Npc = null
	var best_distance := interact_range
	for node in get_tree().get_nodes_in_group("npcs"):
		var npc := node as Npc
		if npc == null:
			continue
		var distance := global_position.distance_to(npc.global_position)
		if distance <= best_distance:
			best = npc
			best_distance = distance
	return best


func _update_prompt() -> void:
	var npc := _nearest_npc()
	var text := npc.prompt_text() if npc != null else ""
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _play_swing() -> void:
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.04, 0.08)
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.14)


func _build_body() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var model := model_scene.instantiate() as Node3D
	_visual.add_child(model)
	ModelUtils.fit_to_height(model, height)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	add_child(shape)


func _build_camera() -> void:
	_yaw_pivot = Node3D.new()
	_yaw_pivot.position.y = height * 0.8
	add_child(_yaw_pivot)

	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 5.0
	_spring_arm.rotation.x = -0.35
	_spring_arm.add_excluded_object(get_rid())
	_yaw_pivot.add_child(_spring_arm)

	camera = Camera3D.new()
	_spring_arm.add_child(camera)
	camera.make_current()
