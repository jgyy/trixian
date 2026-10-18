class_name ModelUtils
extends RefCounted

## Helpers for Tripo generated models, whose native scale and origin differ per asset.

## Yaw correction applied to visuals so that a model's front faces its heading.
const FORWARD_OFFSET := PI


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
