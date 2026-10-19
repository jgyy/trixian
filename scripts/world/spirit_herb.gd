class_name SpiritHerb
extends Node3D

## A moon lotus, a spirit herb the cultivator gathers with the interact key for Disciple Lin.
## It is built from primitives: a stem, two rings of petals, a glowing core, a soft light and a
## faint beam of qi above it, so it can be found from across the valley. It bobs and turns slowly
## so it can be told apart from the valley's ordinary flowers.

signal gathered(herb: SpiritHerb)

const PETAL_COLOR := Color(0.78, 0.88, 1.0)
const CORE_COLOR := Color(0.55, 1.0, 0.85)
const STEM_COLOR := Color(0.3, 0.5, 0.3)
const BOB_HEIGHT := 0.06
const BOB_SPEED := 2.2
const TURN_SPEED := 0.5
## How much larger than the primitives below the bloom is drawn.
const BLOOM_SCALE := 2.2
const BEAM_HEIGHT := 3.0

@export var display_name := "Moon Lotus"
@export var qi_reward := 10.0

var _bloom: Node3D
var _time := 0.0
var _picked := false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("herbs")
	_time = position.x + position.z
	_build()


func _process(delta: float) -> void:
	_time += delta
	_bloom.position.y = 0.5 + sin(_time * BOB_SPEED) * BOB_HEIGHT
	_bloom.rotation.y += TURN_SPEED * delta


func prompt_text() -> String:
	return "Press E to gather the %s" % display_name


func is_picked() -> bool:
	return _picked


func interact(_player: Cultivator) -> void:
	if _picked:
		return
	_picked = true
	remove_from_group("interactables")
	remove_from_group("herbs")
	gathered.emit(self)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tween.tween_callback(queue_free)


func _build() -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.015
	stem.bottom_radius = 0.025
	stem.height = 0.5
	stem.radial_segments = 6
	stem.material = _material(STEM_COLOR, 0.0)
	var stem_mesh := MeshInstance3D.new()
	stem_mesh.mesh = stem
	stem_mesh.position.y = 0.25
	add_child(stem_mesh)

	var beam := CylinderMesh.new()
	beam.top_radius = 0.01
	beam.bottom_radius = 0.08
	beam.height = BEAM_HEIGHT
	beam.radial_segments = 8
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_material.albedo_color = Color(CORE_COLOR, 0.35)
	beam.material = beam_material
	var beam_mesh := MeshInstance3D.new()
	beam_mesh.mesh = beam
	beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_mesh.position.y = 0.5 + BEAM_HEIGHT * 0.5
	add_child(beam_mesh)

	_bloom = Node3D.new()
	_bloom.scale = Vector3.ONE * BLOOM_SCALE
	add_child(_bloom)
	var petal := SphereMesh.new()
	petal.radius = 0.06
	petal.height = 0.05
	petal.radial_segments = 8
	petal.rings = 4
	petal.material = _material(PETAL_COLOR, 0.6)
	for ring in range(2):
		var count := 6 + ring * 2
		for index in range(count):
			var angle := TAU * (index + ring * 0.5) / count
			var mesh := MeshInstance3D.new()
			mesh.mesh = petal
			var reach := 0.08 + ring * 0.05
			mesh.position = Vector3(cos(angle) * reach, -ring * 0.02, sin(angle) * reach)
			mesh.rotation = Vector3(0.0, -angle, 0.5 + ring * 0.3)
			mesh.scale = Vector3(1.6, 1.0, 0.8)
			_bloom.add_child(mesh)

	var core := SphereMesh.new()
	core.radius = 0.05
	core.height = 0.1
	core.material = _material(CORE_COLOR, 2.5)
	var core_mesh := MeshInstance3D.new()
	core_mesh.mesh = core
	core_mesh.position.y = 0.02
	_bloom.add_child(core_mesh)

	var light := OmniLight3D.new()
	light.light_color = CORE_COLOR
	light.light_energy = 1.2
	light.omni_range = 1.5
	light.position.y = 0.1
	_bloom.add_child(light)


static func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
