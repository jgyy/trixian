extends Node3D

## Builds the Azure Cloud Sect valley: scenery, spirit beasts, an NPC quest, and the player.

enum QuestState { NOT_STARTED, ACTIVE, COMPLETE }

const WOLVES_REQUIRED := 2
const REWARD_QI := 150.0
const SPAWN_POINT := Vector3(0.0, 0.0, 8.0)
const BEAST_SPAWNS: Array[Vector3] = [
	Vector3(-8.0, 0.0, -20.0),
	Vector3(12.0, 0.0, 4.0),
	Vector3(-12.0, 0.0, 12.0),
]

const HERO_MODEL := preload("res://assets/models/hero.glb")
const ELDER_MODEL := preload("res://assets/models/elder.glb")
const WOLF_MODEL := preload("res://assets/models/demon_wolf.glb")
const HALL_MODEL := preload("res://assets/models/sect_hall.glb")
const TREE_MODEL := preload("res://assets/models/spirit_tree.glb")
const ROCK_MODEL := preload("res://assets/models/jade_rock.glb")

var _player: Cultivator
var _hud: Hud
var _elder: Npc
var _quest_state := QuestState.NOT_STARTED
var _wolves_slain := 0


func _ready() -> void:
	InputSetup.register_actions()
	_build_environment()
	_build_ground()
	_build_scenery()
	_build_npc()
	_build_enemies()
	_hud = Hud.new()
	add_child(_hud)
	_build_player()
	_refresh_quest()
	_refresh_hud()
	_hud.show_message("Welcome to the Azure Cloud Sect valley. Press F to meditate.", 5.0)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.5, 0.74)
	sky_material.sky_horizon_color = Color(0.8, 0.84, 0.88)
	sky_material.ground_horizon_color = Color(0.7, 0.74, 0.74)
	sky_material.ground_bottom_color = Color(0.25, 0.3, 0.26)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.8, 0.84, 0.88)
	environment.fog_density = 0.004

	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.42, 0.52, 0.36)
	ground_material.roughness = 0.95
	plane.material = ground_material
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.mesh = plane
	ground.add_child(ground_mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	add_child(ground)

	var path := MeshInstance3D.new()
	var path_mesh := BoxMesh.new()
	path_mesh.size = Vector3(3.0, 0.04, 34.0)
	var path_material := StandardMaterial3D.new()
	path_material.albedo_color = Color(0.6, 0.58, 0.52)
	path_mesh.material = path_material
	path.mesh = path_mesh
	path.position = Vector3(0.0, 0.02, -6.0)
	add_child(path)


func _build_scenery() -> void:
	_add_prop(HALL_MODEL, Vector3(0.0, 0.0, -16.0), 9.0, 0.0, true)
	_add_prop(TREE_MODEL, Vector3(9.0, 0.0, -7.0), 7.0, 0.3, false)
	_add_prop(TREE_MODEL, Vector3(-14.0, 0.0, -8.0), 5.0, 1.0, false)
	_add_prop(ROCK_MODEL, Vector3(-6.0, 0.0, -3.0), 2.6, 0.0, true)
	_add_prop(ROCK_MODEL, Vector3(-10.0, 0.0, 5.0), 1.6, 1.2, true)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.45, 1.0, 0.65)
	glow.light_energy = 2.0
	glow.omni_range = 7.0
	glow.position = Vector3(-6.0, 2.0, -3.0)
	add_child(glow)


## Places a fitted Tripo prop. Solid props get a box collider matching their footprint.
func _add_prop(scene: PackedScene, at: Vector3, height: float, yaw: float, solid: bool) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	add_child(root)

	var model := scene.instantiate() as Node3D
	root.add_child(model)
	var bounds := ModelUtils.fit_to_height(model, height)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(bounds.size.x, height, bounds.size.z)
		shape.shape = box
		shape.position.y = height * 0.5
		body.add_child(shape)
		root.add_child(body)
	return root


func _build_npc() -> void:
	_elder = Npc.new()
	_elder.model_scene = ELDER_MODEL
	_elder.display_name = "Elder Wen"
	_elder.height = 1.9
	_elder.position = Vector3(2.5, 0.0, -4.0)
	_elder.rotation.y = ModelUtils.yaw_towards(SPAWN_POINT - _elder.position)
	_elder.talked.connect(_on_npc_talked)
	add_child(_elder)


func _build_enemies() -> void:
	for spawn in BEAST_SPAWNS:
		var beast := SpiritBeast.new()
		beast.model_scene = WOLF_MODEL
		beast.position = spawn
		beast.died.connect(_on_beast_died)
		add_child(beast)


func _build_player() -> void:
	_player = Cultivator.new()
	_player.model_scene = HERO_MODEL
	_player.position = SPAWN_POINT
	_player.stats_changed.connect(_refresh_hud)
	_player.realm_changed.connect(_on_realm_changed)
	_player.message.connect(_hud.show_message)
	_player.prompt_changed.connect(_hud.set_prompt)
	add_child(_player)


func _on_npc_talked(_npc: Npc) -> void:
	match _quest_state:
		QuestState.NOT_STARTED:
			_quest_state = QuestState.ACTIVE
			_hud.show_message(
				(
					"Elder Wen: Demon wolves stalk the valley. Slay %d and return to me."
					% WOLVES_REQUIRED
				),
				6.0
			)
		QuestState.ACTIVE:
			if _wolves_slain >= WOLVES_REQUIRED:
				_quest_state = QuestState.COMPLETE
				_player.cultivation.gain_qi(REWARD_QI)
				_hud.show_message(
					"Elder Wen: Well done. Take this qi from the sect's reserves.", 6.0
				)
			else:
				_hud.show_message(
					"Elder Wen: %d more beasts remain." % (WOLVES_REQUIRED - _wolves_slain)
				)
		QuestState.COMPLETE:
			_hud.show_message("Elder Wen: Walk the path of immortality, cultivator.")
	_refresh_quest()
	_refresh_hud()


func _on_beast_died(qi_reward: float) -> void:
	_wolves_slain += 1
	_player.cultivation.gain_qi(qi_reward)
	_hud.show_message("Spirit beast slain. +%d qi." % int(qi_reward))
	_refresh_quest()
	_refresh_hud()


func _on_realm_changed(realm_name: String) -> void:
	_hud.show_message("Breakthrough! You now stand at %s." % realm_name, 4.0)


func _refresh_quest() -> void:
	match _quest_state:
		QuestState.NOT_STARTED:
			_hud.set_quest("Quest: Speak with Elder Wen")
		QuestState.ACTIVE:
			_hud.set_quest(
				(
					"Quest: Slay demon wolves %d / %d"
					% [mini(_wolves_slain, WOLVES_REQUIRED), WOLVES_REQUIRED]
				)
			)
		QuestState.COMPLETE:
			_hud.set_quest("Quest complete")


func _refresh_hud() -> void:
	if _player == null or _hud == null:
		return
	var cultivation := _player.cultivation
	_hud.update_stats(
		_player.hp,
		_player.max_hp,
		cultivation.realm_name(),
		cultivation.qi,
		cultivation.qi_required()
	)
