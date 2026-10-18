class_name InputSetup
extends RefCounted

## Registers the game's input actions at runtime, so the bindings are readable in code
## and project.godot does not have to be hand-edited.


static func register_actions() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE])
	_bind("attack", [KEY_J], MOUSE_BUTTON_LEFT)
	_bind("meditate", [KEY_F])
	_bind("breakthrough", [KEY_B])
	_bind("interact", [KEY_E])
	_bind("release_mouse", [KEY_ESCAPE])


static func _bind(action: StringName, keys: Array, mouse_button: int = 0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	if mouse_button != 0:
		var click := InputEventMouseButton.new()
		click.button_index = mouse_button
		InputMap.action_add_event(action, click)
