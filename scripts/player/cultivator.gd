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
## Seconds from the key press to the sword landing, which is when the slash clip's cut connects.
@export var strike_delay := 0.27
@export var meditation_qi_per_second := 12.0
@export var interact_range := 3.0
@export var min_zoom := 1.8
@export var max_zoom := 9.0
@export var zoom_step := 0.6

## Tripo model for the cultivator. Assigned before the node enters the tree.
var model_scene: PackedScene
var hp := 100.0
var cultivation := Cultivation.new()
var is_meditating := false
var camera: Camera3D
var animator: CharacterAnimator

var _spawn_position: Vector3
var _heading := PI
var _cooldown := 0.0
var _prompt := ""
## Set by the click that recaptures the mouse, so that click does not also swing the sword.
var _swallow_attack := false
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
	elif event is InputEventMouseButton and event.pressed and _is_wheel(event):
		_zoom(event as InputEventMouseButton)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_swallow_attack = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw_pivot.rotate_y(-motion.relative.x * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x - motion.relative.y * mouse_sensitivity, -1.2, 0.35
		)


static func _is_wheel(event: InputEventMouseButton) -> bool:
	return event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]


## Each wheel notch moves the camera boom in or out, clamped to the zoom range.
func _zoom(event: InputEventMouseButton) -> void:
	var step := -zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else zoom_step
	_spring_arm.spring_length = clampf(_spring_arm.spring_length + step, min_zoom, max_zoom)


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
	if Input.is_action_just_pressed("attack") and not _swallow_attack:
		attack()
	_swallow_attack = false

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
	_update_animation()
	_update_prompt()


## Sword strike: swings now and damages every spirit beast in a cone in front of the cultivator
## when the blade lands, [member strike_delay] seconds later.
func attack() -> void:
	if _cooldown > 0.0 or is_meditating:
		return
	_cooldown = attack_cooldown
	if not animator.play_action(&"slash"):
		_play_swing()
	get_tree().create_timer(strike_delay).timeout.connect(_land_strike)


func _land_strike() -> void:
	var facing := Vector3(sin(_heading), 0.0, cos(_heading))
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as SpiritBeast
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length() <= attack_range and facing.dot(to_enemy.normalized()) > 0.3:
			enemy.take_damage(attack_damage)


## The direction the model's front points in, on the world axes.
func facing() -> Vector3:
	return _visual.global_transform.basis * Vector3.BACK


func take_damage(amount: float) -> void:
	hp -= amount
	if is_meditating:
		is_meditating = false
		message.emit("A blow breaks your meditation.")
	if hp <= 0.0:
		hp = max_hp
		global_position = _spawn_position
		velocity = Vector3.ZERO
		is_meditating = false
		message.emit("You collapse and awaken at the sect gate.")
	else:
		animator.play_action(&"hurt")
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
	var target := _nearest_interactable()
	if target != null:
		target.interact(self)


## The nearest NPC or spirit herb within [member interact_range]. Everything in the
## "interactables" group has prompt_text() and interact(cultivator).
func _nearest_interactable() -> Node3D:
	var best: Node3D = null
	var best_distance := interact_range
	for node in get_tree().get_nodes_in_group("interactables"):
		var target := node as Node3D
		if target == null:
			continue
		var distance := global_position.distance_to(target.global_position)
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best


func _update_prompt() -> void:
	var target := _nearest_interactable()
	var text: String = target.prompt_text() if target != null else ""
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _update_animation() -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	animator.play(&"run" if moving and not is_meditating else &"idle")


## Fallback swing for models without a slash clip: the body pulses in scale.
func _play_swing() -> void:
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.04, 0.08)
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.14)


func _build_body() -> void:
	_visual = Node3D.new()
	_visual.rotation.y = _heading + ModelUtils.FORWARD_OFFSET
	add_child(_visual)
	var model := model_scene.instantiate() as Node3D
	_visual.add_child(model)
	ModelUtils.fit_to_height(model, height)
	ModelUtils.apply_anime_style(model)
	animator = CharacterAnimator.new(model)
	animator.play(&"idle")

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
