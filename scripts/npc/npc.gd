class_name Npc
extends StaticBody3D

## A non-player character the cultivator can talk to with the interact key.

signal talked(npc: Npc)

@export var display_name := "Villager"
@export var height := 1.8
## Tripo model for the character. Assigned before the node enters the tree.
var model_scene: PackedScene


func _ready() -> void:
	add_to_group("npcs")
	var model := model_scene.instantiate() as Node3D
	add_child(model)
	ModelUtils.fit_to_height(model, height)

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
	talked.emit(self)
