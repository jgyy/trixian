class_name SunShadeProbe
extends Node3D

## Tells a cel-shaded character whether it stands in the shade of the scenery.
##
## Characters do not take the sun's shadow map (shaders/anime_toon.gdshader, self_shadows off),
## because their own hair and sleeves cast ragged blotches across their faces. Once per physics
## frame this probe casts one ray from the character's chest towards the sun. If the hall, a tree
## or a rock is in the way, the whole character fades into its shade tone, as anime draws it.
## Other characters do not count.

const RAY_LENGTH := 60.0
## How fast the shade fades in and out, in full tones per second.
const FADE_PER_SECOND := 4.0
const SKIPPED_GROUPS: Array[StringName] = [&"player", &"enemies", &"npcs"]
const MAX_SKIPS := 4

## 0 in the sun, 1 in the shade of the scenery.
var shade := 0.0
var _materials: Array[ShaderMaterial] = []
var _exclude: Array[RID] = []
var _sun: DirectionalLight3D
var _settled := false


## Adds a probe at [param chest_height] above [param body] for every cel-shaded surface under
## [param model], and turns those surfaces' own sun shadows off. Without a body, as on a capture
## stage, the probe goes under the model.
static func attach(model: Node, body: CollisionObject3D, chest_height: float) -> SunShadeProbe:
	var probe := SunShadeProbe.new()
	probe.position.y = chest_height
	if body != null:
		probe._exclude.append(body.get_rid())
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_surface_override_material(surface) as ShaderMaterial
			if material != null and material.shader == ModelUtils.ANIME_TOON_SHADER:
				material.set_shader_parameter("self_shadows", false)
				probe._materials.append(material)
	(body if body != null else model).add_child(probe)
	return probe


func _physics_process(delta: float) -> void:
	if _sun == null or not is_instance_valid(_sun):
		_sun = _find_sun()
		if _sun == null:
			return
	var target := 1.0 if is_sun_blocked() else 0.0
	shade = target if not _settled else move_toward(shade, target, FADE_PER_SECOND * delta)
	_settled = true
	for material in _materials:
		material.set_shader_parameter("sun_shade", shade)


## Whether the scenery stands between this probe and the sun.
func is_sun_blocked() -> bool:
	if _sun == null or not is_instance_valid(_sun):
		_sun = _find_sun()
		if _sun == null:
			return false
	# A directional light shines along its -Z axis, so the sun lies along +Z.
	var from := global_position
	var to := from + _sun.global_basis.z.normalized() * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, _exclude.duplicate())
	var space := get_world_3d().direct_space_state
	for _skip in MAX_SKIPS:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider := hit["collider"] as Node
		if not _is_character(collider):
			return true
		var exclude := query.exclude
		exclude.append(hit["rid"])
		query.exclude = exclude
	return false


func _is_character(node: Node) -> bool:
	for group in SKIPPED_GROUPS:
		if node != null and node.is_in_group(group):
			return true
	return false


func _find_sun() -> DirectionalLight3D:
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if (node as DirectionalLight3D).visible:
			return node as DirectionalLight3D
	return null
