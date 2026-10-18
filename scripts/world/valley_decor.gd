class_name ValleyDecor
extends RefCounted

## Procedural dressing for the valley: mountains, ground patches, grass and flowers, a lotus pond,
## a bamboo grove, stone lanterns along the path, a sect gate, braziers and drifting particles.
## Everything is built from primitives with a fixed seed, so the valley looks the same each run.
## None of these props block movement; the solid scenery is placed by main.gd.

const SEED := 20260418
const PATH_HALF_WIDTH := 1.5
const PATH_Z_RANGE := Vector2(-23.0, 11.0)

const GRASS_COLOR := Color(0.36, 0.5, 0.28)
const STONE_COLOR := Color(0.58, 0.57, 0.53)
const LACQUER_COLOR := Color(0.62, 0.11, 0.1)
const GOLD_COLOR := Color(0.85, 0.66, 0.26)
const BAMBOO_COLOR := Color(0.38, 0.55, 0.26)
const FLOWER_COLORS: Array[Color] = [
	Color(0.97, 0.7, 0.8),
	Color(0.98, 0.95, 0.9),
	Color(0.85, 0.5, 0.7),
	Color(0.95, 0.85, 0.45),
]


static func build(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_add_mountain_ring(root, rng)
	_add_ground_patches(root, rng)
	_add_grass(root, rng)
	_add_flowers(root, rng)
	_add_bamboo_grove(root, rng, Vector3(-19.0, 0.0, -2.0))
	_add_lotus_pond(root, Vector3(7.0, 0.0, 4.5))
	_add_path_lanterns(root)
	_add_sect_gate(root)
	_add_braziers(root, Vector3(-3.6, 0.0, -10.0), Vector3(3.6, 0.0, -10.0))
	_add_banner_poles(root, Vector3(-6.0, 0.0, -12.0), Vector3(6.0, 0.0, -12.0))
	_add_petals(root, Vector3(9.0, 0.0, -7.0))
	_add_qi_motes(root, Vector3(-6.0, 0.0, -3.0))


static func _add_mountain_ring(root: Node3D, rng: RandomNumberGenerator) -> void:
	var material := _material(Color(0.36, 0.45, 0.42), 0.95)
	for index in range(18):
		var angle := TAU * index / 18.0 + rng.randf_range(-0.08, 0.08)
		var radius := 115.0 + rng.randf_range(-6.0, 8.0)
		var height := rng.randf_range(28.0, 52.0)
		var peak := CylinderMesh.new()
		peak.top_radius = 0.0
		peak.bottom_radius = rng.randf_range(18.0, 30.0)
		peak.height = height
		peak.radial_segments = 8
		peak.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = peak
		mesh.position = Vector3(cos(angle) * radius, height * 0.5 - 4.0, sin(angle) * radius)
		root.add_child(mesh)


static func _add_ground_patches(root: Node3D, rng: RandomNumberGenerator) -> void:
	for index in range(14):
		var disc := CylinderMesh.new()
		disc.top_radius = rng.randf_range(4.0, 10.0)
		disc.bottom_radius = disc.top_radius
		disc.height = 0.01
		disc.radial_segments = 24
		var tint := rng.randf_range(-0.06, 0.04)
		disc.material = _material(GRASS_COLOR + Color(tint, tint * 0.6, tint * 0.4), 0.97)
		var mesh := MeshInstance3D.new()
		mesh.mesh = disc
		mesh.position = Vector3(rng.randf_range(-70.0, 70.0), 0.006, rng.randf_range(-60.0, 50.0))
		root.add_child(mesh)


static func _add_grass(root: Node3D, rng: RandomNumberGenerator) -> void:
	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 0.45, 0.02)
	blade.material = _material(GRASS_COLOR * 1.05, 0.9)
	var transforms: Array[Transform3D] = []
	while transforms.size() < 2400:
		var at := Vector3(rng.randf_range(-45.0, 45.0), 0.0, rng.randf_range(-40.0, 30.0))
		if _on_path(at, 1.2) or at.length() < 3.0:
			continue
		var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		transforms.append(Transform3D(basis, at + Vector3(0.0, 0.22, 0.0)))
	_add_multimesh(root, blade, transforms)


static func _add_flowers(root: Node3D, rng: RandomNumberGenerator) -> void:
	var bloom := SphereMesh.new()
	bloom.radius = 0.09
	bloom.height = 0.12
	bloom.radial_segments = 6
	bloom.rings = 3
	var material := _material(Color.WHITE, 0.6)
	material.vertex_color_use_as_albedo = true
	bloom.material = material
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	while transforms.size() < 500:
		var at := Vector3(rng.randf_range(-40.0, 40.0), 0.0, rng.randf_range(-35.0, 25.0))
		if _on_path(at, 1.2) or at.length() < 4.0:
			continue
		transforms.append(Transform3D(Basis(), at + Vector3(0.0, 0.1, 0.0)))
		colors.append(FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()])
	_add_multimesh(root, bloom, transforms, colors)


static func _add_bamboo_grove(root: Node3D, rng: RandomNumberGenerator, centre: Vector3) -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.07
	stem.bottom_radius = 0.09
	stem.height = 7.0
	stem.radial_segments = 6
	stem.material = _material(BAMBOO_COLOR, 0.6)
	var transforms: Array[Transform3D] = []
	for index in range(36):
		var offset := Vector3(rng.randf_range(-3.5, 3.5), 0.0, rng.randf_range(-3.5, 3.5))
		var height_scale := rng.randf_range(0.75, 1.2)
		var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.05, 0.05), 0.0, 0.0))
		var basis := tilt.scaled(Vector3(1.0, height_scale, 1.0))
		transforms.append(
			Transform3D(basis, centre + offset + Vector3(0.0, 3.5 * height_scale, 0.0))
		)
	_add_multimesh(root, stem, transforms)


static func _add_lotus_pond(root: Node3D, centre: Vector3) -> void:
	var water := CylinderMesh.new()
	water.top_radius = 2.6
	water.bottom_radius = 2.6
	water.height = 0.05
	water.radial_segments = 32
	var water_material := _material(Color(0.2, 0.42, 0.45), 0.08)
	water_material.metallic = 0.3
	water.material = water_material
	var surface := MeshInstance3D.new()
	surface.mesh = water
	surface.position = centre + Vector3(0.0, 0.03, 0.0)
	root.add_child(surface)

	var pad := CylinderMesh.new()
	pad.top_radius = 0.32
	pad.bottom_radius = 0.32
	pad.height = 0.02
	pad.radial_segments = 12
	pad.material = _material(Color(0.25, 0.5, 0.25), 0.7)
	var bloom := SphereMesh.new()
	bloom.radius = 0.14
	bloom.height = 0.22
	bloom.material = _material(Color(0.95, 0.6, 0.72), 0.5)
	var offsets := [Vector2(-0.9, 0.6), Vector2(0.7, -0.5), Vector2(0.2, 1.1), Vector2(-0.4, -1.2)]
	for index in range(offsets.size()):
		var offset: Vector2 = offsets[index]
		var at := centre + Vector3(offset.x, 0.06, offset.y)
		_add_mesh(root, pad, at)
		if index % 2 == 0:
			_add_mesh(root, bloom, at + Vector3(0.0, 0.1, 0.0))


static func _add_path_lanterns(root: Node3D) -> void:
	for z in [-18.0, -8.0, 2.0, 8.0]:
		for side in [-1.0, 1.0]:
			_add_stone_lantern(root, Vector3(side * 2.4, 0.0, z))


static func _add_stone_lantern(root: Node3D, at: Vector3) -> void:
	var base := BoxMesh.new()
	base.size = Vector3(0.6, 0.35, 0.6)
	base.material = _material(STONE_COLOR, 0.9)
	_add_mesh(root, base, at + Vector3(0.0, 0.18, 0.0))
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.14
	pillar.bottom_radius = 0.18
	pillar.height = 1.1
	pillar.material = base.material
	_add_mesh(root, pillar, at + Vector3(0.0, 0.9, 0.0))
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.5, 0.42, 0.5)
	var lamp_material := _material(Color(1.0, 0.82, 0.5), 0.4)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.72, 0.35)
	lamp_material.emission_energy_multiplier = 1.6
	lamp.material = lamp_material
	_add_mesh(root, lamp, at + Vector3(0.0, 1.6, 0.0))
	_add_light(root, at + Vector3(0.0, 1.8, 0.0), Color(1.0, 0.78, 0.45), 1.1, 6.0)


static func _add_sect_gate(root: Node3D) -> void:
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.22
	pillar.bottom_radius = 0.26
	pillar.height = 4.2
	pillar.material = _material(LACQUER_COLOR, 0.5)
	var beam := BoxMesh.new()
	beam.size = Vector3(6.4, 0.42, 0.7)
	beam.material = _material(LACQUER_COLOR, 0.5)
	var roof := BoxMesh.new()
	roof.size = Vector3(7.6, 0.18, 1.5)
	roof.material = _material(Color(0.12, 0.2, 0.22), 0.6)
	for side in [-1.0, 1.0]:
		_add_mesh(root, pillar, Vector3(side * 2.9, 2.1, 1.0))
	_add_mesh(root, beam, Vector3(0.0, 3.85, 1.0))
	_add_mesh(root, roof, Vector3(0.0, 4.25, 1.0))
	var sign := BoxMesh.new()
	sign.size = Vector3(2.0, 0.42, 0.08)
	sign.material = _material(GOLD_COLOR, 0.4)
	_add_mesh(root, sign, Vector3(0.0, 3.5, 1.4))


static func _add_braziers(root: Node3D, left: Vector3, right: Vector3) -> void:
	for at in [left, right]:
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.6
		bowl.bottom_radius = 0.3
		bowl.height = 0.7
		bowl.material = _material(GOLD_COLOR * 0.7, 0.35)
		_add_mesh(root, bowl, at + Vector3(0.0, 1.05, 0.0))
		var flame := CPUParticles3D.new()
		flame.position = at + Vector3(0.0, 1.45, 0.0)
		flame.amount = 24
		flame.lifetime = 0.9
		flame.direction = Vector3.UP
		flame.spread = 18.0
		flame.initial_velocity_min = 0.4
		flame.initial_velocity_max = 1.0
		flame.scale_amount_min = 0.5
		flame.scale_amount_max = 1.0
		flame.mesh = _particle_quad(Color(1.0, 0.6, 0.2), 0.14)
		root.add_child(flame)
		_add_light(root, at + Vector3(0.0, 1.9, 0.0), Color(1.0, 0.6, 0.25), 1.4, 7.0)


static func _add_banner_poles(root: Node3D, left: Vector3, right: Vector3) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.07
	pole.height = 5.0
	pole.material = _material(LACQUER_COLOR, 0.5)
	var cloth_material := _material(Color(0.86, 0.72, 0.42), 0.8)
	cloth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cloth := QuadMesh.new()
	cloth.size = Vector2(0.9, 2.4)
	cloth.material = cloth_material
	for at in [left, right]:
		_add_mesh(root, pole, at + Vector3(0.0, 2.5, 0.0))
		var banner := MeshInstance3D.new()
		banner.mesh = cloth
		banner.position = at + Vector3(0.0, 2.9, 0.08)
		root.add_child(banner)


static func _add_petals(root: Node3D, at: Vector3) -> void:
	var petals := CPUParticles3D.new()
	petals.position = at + Vector3(0.0, 6.0, 0.0)
	petals.amount = 60
	petals.lifetime = 9.0
	petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	petals.emission_box_extents = Vector3(6.0, 0.5, 6.0)
	petals.direction = Vector3(0.0, -1.0, 0.0)
	petals.spread = 25.0
	petals.gravity = Vector3(0.4, -0.6, 0.2)
	petals.initial_velocity_min = 0.2
	petals.initial_velocity_max = 0.6
	petals.scale_amount_min = 0.7
	petals.scale_amount_max = 1.1
	petals.mesh = _particle_quad(Color(1.0, 0.72, 0.84), 0.12)
	root.add_child(petals)


static func _add_qi_motes(root: Node3D, at: Vector3) -> void:
	var motes := CPUParticles3D.new()
	motes.position = at + Vector3(0.0, 1.2, 0.0)
	motes.amount = 30
	motes.lifetime = 4.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 1.4
	motes.direction = Vector3.UP
	motes.spread = 30.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.35
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.0
	motes.mesh = _particle_quad(Color(0.55, 1.0, 0.75), 0.08)
	root.add_child(motes)


static func _particle_quad(color: Color, size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = material
	quad.size = Vector2(size, size)
	return quad


static func _add_light(
	root: Node3D, at: Vector3, color: Color, energy: float, range_m: float
) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	root.add_child(light)


static func _add_multimesh(
	root: Node3D, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color] = []
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		if not colors.is_empty():
			multimesh.set_instance_color(index, colors[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	root.add_child(instance)


static func _add_mesh(root: Node3D, mesh: Mesh, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	root.add_child(instance)


static func _on_path(at: Vector3, margin: float) -> bool:
	return (
		absf(at.x) < PATH_HALF_WIDTH + margin
		and at.z > PATH_Z_RANGE.x - margin
		and at.z < PATH_Z_RANGE.y + margin
	)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
