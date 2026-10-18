class_name CharacterAnimator
extends RefCounted

## Drives the preset clips baked into a rigged Tripo model.
##
## Looping states (idle, walk, run) keep playing until another state is requested. One-shot
## actions (slash, hurt, greet) play once and then resume the looping state that was active.
## Clip lookup is forgiving: a state matches a clip whose name ends with it, so "Armature|walk"
## and "walk" both count. Models without a clip for a state fall back to the closest one.

const BLEND_TIME := 0.2
const LOOPING_STATES := ["idle", "walk", "run"]

var _player: AnimationPlayer
var _loop_state := &"idle"
var _action_playing := false


func _init(model: Node) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_player = players[0] as AnimationPlayer
	_player.animation_finished.connect(_on_animation_finished)
	for clip_name in _player.get_animation_list():
		var animation := _player.get_animation(clip_name)
		if _leaf_name(clip_name) in LOOPING_STATES:
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			animation.loop_mode = Animation.LOOP_NONE


func has_clip(state: StringName) -> bool:
	return _resolve(state) != &""


## Switches the looping state. Ignored in name only while a one-shot action is playing.
func play(state: StringName) -> void:
	_loop_state = state
	if _action_playing or _player == null:
		return
	_play_loop(state)


## Plays a one-shot action. Returns false when the model has no matching clip, so callers
## can fall back to a procedural effect.
func play_action(state: StringName) -> bool:
	var clip := _resolve(state)
	if _player == null or clip == &"":
		return false
	_action_playing = true
	_player.speed_scale = 1.0
	_player.play(clip, BLEND_TIME)
	return true


func is_action_playing() -> bool:
	return _action_playing


func _play_loop(state: StringName) -> void:
	var clip := _resolve(state)
	var freeze := false
	if clip == &"" and state == &"run":
		clip = _resolve(&"walk")
	if clip == &"" and state == &"idle":
		# Models without an idle clip hold the first frame of their walk cycle instead.
		clip = _resolve(&"walk")
		freeze = clip != &""
	if clip == &"":
		return
	_player.speed_scale = 0.0 if freeze else 1.0
	# Only restart the clip when it changes, otherwise it would rewind every physics frame.
	if _player.current_animation == String(clip) and _player.is_playing():
		return
	_player.play(clip, BLEND_TIME)
	if freeze:
		_player.seek(0.0, true)


func _on_animation_finished(_clip_name: StringName) -> void:
	if not _action_playing:
		return
	_action_playing = false
	_play_loop(_loop_state)


func _resolve(state: StringName) -> StringName:
	if _player == null:
		return &""
	var wanted := String(state)
	var partial := &""
	for clip_name in _player.get_animation_list():
		var leaf := _leaf_name(clip_name)
		if leaf == wanted:
			return clip_name
		if partial == &"" and leaf.contains(wanted):
			partial = clip_name
	return partial


static func _leaf_name(clip_name: StringName) -> String:
	var text := String(clip_name).to_lower()
	for separator in ["|", "/", ":", "."]:
		text = text.get_slice(separator, text.get_slice_count(separator) - 1)
	return text
