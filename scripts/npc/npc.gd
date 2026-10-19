class_name Npc
extends StaticBody3D

## A non-player character the cultivator can talk to with the interact key.

signal talked(npc: Npc)

@export var display_name := "Villager"
@export var height := 1.8
## Lines spoken in turn each time the cultivator talks to this NPC, when the NPC has no quest.
@export var lines: PackedStringArray = []
## Tripo model for the character. Assigned before the node enters the tree.
var model_scene: PackedScene

var animator: CharacterAnimator
var _line_index := 0


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("interactables")
	var model := model_scene.instantiate() as Node3D
	add_child(model)
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


func prompt_text() -> String:
	return "Press E to talk to %s" % display_name


func interact(_player: Cultivator) -> void:
	animator.play_action(&"greet")
	talked.emit(self)


## The next line of small talk, cycling through [member lines].
func next_line() -> String:
	if lines.is_empty():
		return "..."
	var line := lines[_line_index % lines.size()]
	_line_index += 1
	return line
