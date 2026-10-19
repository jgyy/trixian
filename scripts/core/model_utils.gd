class_name ModelUtils
extends RefCounted

## Helpers for Tripo generated models, whose native scale and origin differ per asset.

## Yaw correction applied to visuals so that a model's front faces its heading. Every character
## model is repaired to face +Z, the glTF front (tools/fix_character_rig.py), so none is needed.
const FORWARD_OFFSET := 0.0
## Ink outline width in metres for a character-sized model.
const OUTLINE_WIDTH := 0.004
const ANIME_TOON_SHADER := preload("res://shaders/anime_toon.gdshader")
const ANIME_OUTLINE_SHADER := preload("res://shaders/anime_outline.gdshader")


## Scales [param root] uniformly so its visible height equals [param target_height],
## then moves it so the base sits on y = 0 and the centre sits on the origin in X/Z.
## Returns the resulting bounds in the parent's space.
static func fit_to_height(root: Node3D, target_height: float) -> AABB:
	var bounds := local_bounds(root)
	if bounds.size.y <= 0.0:
		return AABB()
	var scale_factor := target_height / bounds.size.y
	var centre := bounds.get_center()
	root.transform = Transform3D(
		Basis.from_scale(Vector3.ONE * scale_factor),
		Vector3(-centre.x, -bounds.position.y, -centre.z) * scale_factor
	)
	return root.transform * bounds


## Union of every MeshInstance3D bounding box, expressed in [param root]'s local space.
static func local_bounds(root: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_boxes(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var merged := boxes[0]
	for index in range(1, boxes.size()):
		merged = merged.merge(boxes[index])
	return merged


## Gives every mesh under [param root] the anime cel-shading material: two hard-edged tones of
## light, no specular, a sharpened and more saturated albedo, a rim of light and an ink outline in
## a second pass (shaders/anime_toon.gdshader, shaders/anime_outline.gdshader). Tripo's PBR
## materials make cloth and skin look glossy and smudged, like an oil painting.
## The albedo texture and colour are carried over; normal and roughness maps are dropped, which
## also sidesteps the Compatibility renderer's skinning pass, which never binds the TANGENT
## attribute (drivers/gles3/storage/mesh_storage.cpp, 4.7.2) and broke normal-mapped faces into
## patches. The shared materials are left untouched; each surface gets an override.
## Returns how many surfaces were restyled.
static func apply_anime_style(root: Node, outline_width := OUTLINE_WIDTH) -> int:
	var changed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			mesh_instance.set_surface_override_material(
				surface, anime_material(source, outline_width)
			)
			changed += 1
	return changed


## The cel-shading material for one Tripo [param source] material, with its outline as the next
## pass. An [param outline_width] of zero leaves the outline out.
static func anime_material(
	source: BaseMaterial3D, outline_width := OUTLINE_WIDTH
) -> ShaderMaterial:
	var toon := ShaderMaterial.new()
	toon.shader = ANIME_TOON_SHADER
	toon.set_shader_parameter("albedo_texture", source.albedo_texture)
	toon.set_shader_parameter("albedo_color", source.albedo_color)
	if outline_width > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = ANIME_OUTLINE_SHADER
		outline.set_shader_parameter("albedo_texture", source.albedo_texture)
		outline.set_shader_parameter("albedo_color", source.albedo_color)
		outline.set_shader_parameter("outline_width", outline_width)
		toon.next_pass = outline
	return toon


## Yaw (radians) that turns a model's front towards [param direction] on the XZ plane.
static func yaw_towards(direction: Vector3) -> float:
	return atan2(direction.x, direction.z) + FORWARD_OFFSET


static func _collect_boxes(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	for child in node.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * (child as Node3D).transform
		if child is MeshInstance3D:
			boxes.append(child_transform * (child as MeshInstance3D).get_aabb())
		_collect_boxes(child, child_transform, boxes)
