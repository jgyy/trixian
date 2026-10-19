extends Node3D

## Builds the Azure Cloud Sect valley: scenery, spirit beasts, NPCs with a quest, and the player.

const WOLVES_REQUIRED := 2
const REWARD_QI := 150.0
const SPAWN_POINT := Vector3(0.0, 0.0, 8.0)
const HALL_HEIGHT := 18.0
const HALL_POSITION := Vector3(0.0, 0.0, -26.0)
## Measured on the Tripo hall at 18 m, in the hall's own space (centre of the footprint, y = 0 on
## the ground). The front and back stairs are 4.2 m wide and meet their terrace 10.25 m from the
## centre at 1.75 m. The side stairs are 5.4 m wide and meet the side terrace 8.6 m from the centre
## at 1.58 m. The east entry gallery is 3.6 m wide, and a ramp drops from it into the cella.
const FRONT_STAIR_WIDTH := 4.2
const FRONT_TERRACE_Z := 10.25
const FRONT_TERRACE_Y := 1.75
const SIDE_STAIR_WIDTH := 5.4
const SIDE_TERRACE_X := 8.6
const SIDE_TERRACE_Y := 1.58
const ENTRY_WIDTH := 3.6
const ENTRY_Z := -0.5
const ENTRY_TOP_X := 3.0
const ENTRY_TOP_Y := 1.75
const CELLA_X := 0.5
const RAMP_THICKNESS := 0.3
const BEAST_SPAWNS: Array[Vector3] = [
	Vector3(-16.0, 0.0, -18.0),
	Vector3(12.0, 0.0, 4.0),
	Vector3(-12.0, 0.0, 12.0),
]
## Seconds before a slain wolf of the pack returns to its den, and how far away the cultivator
## must be for it to come back, so a wolf never appears beside her.
const RESPAWN_SECONDS := 30.0
const RESPAWN_CLEARANCE := 14.0
## The alpha waits behind the hall once Elder Wen asks for it. Bigger, tougher and worth more.
const ALPHA_SPAWN := Vector3(-14.0, 0.0, -38.0)
const ALPHA_REWARD_QI := 300.0
const HERBS_REQUIRED := 4
const HERB_REWARD_QI := 120.0
## Moon lotuses: by the pond, in the bamboo grove, under the spirit trees and behind the hall.
const HERB_SPOTS: Array[Vector3] = [
	Vector3(9.6, 0.0, 6.8),
	Vector3(-17.2, 0.0, 0.6),
	Vector3(-13.0, 0.0, -10.4),
	Vector3(16.8, 0.0, -17.6),
	Vector3(-21.0, 0.0, 6.4),
	Vector3(6.0, 0.0, -40.0),
]
const DISCIPLE_LINES: PackedStringArray = [
	"Disciple Lin: The sect gate stands open to every cultivator who walks this path.",
	"Disciple Lin: Keep your qi calm. A troubled mind draws the demon wolves.",
	"Disciple Lin: Elder Wen waits by the hall. Speak with him once you are ready.",
]

## Scenery is seen from further away than the characters, so its ink outline is wider.
const PROP_OUTLINE_WIDTH := 0.02

const PLAYER_MODEL := preload("res://assets/models/female_cultivator.glb")
const DISCIPLE_MODEL := preload("res://assets/models/hero.glb")
const ELDER_MODEL := preload("res://assets/models/elder.glb")
const WOLF_MODEL := preload("res://assets/models/demon_wolf.glb")
const HALL_MODEL := preload("res://assets/models/sect_hall.glb")
const TREE_MODEL := preload("res://assets/models/spirit_tree.glb")
const ROCK_MODEL := preload("res://assets/models/jade_rock.glb")

var _player: Cultivator
var _hud: Hud
var _elder: Npc
var _quest := CountQuest.new(WOLVES_REQUIRED, REWARD_QI, "Elder Wen", "Slay demon wolves")
var _alpha_quest := CountQuest.new(1, ALPHA_REWARD_QI, "Elder Wen", "Slay the Demon Wolf Alpha")
var _herb_quest := CountQuest.new(
	HERBS_REQUIRED, HERB_REWARD_QI, "Disciple Lin", "Gather moon lotus"
)
var _disciple: Npc


func _ready() -> void:
	InputSetup.register_actions()
	_build_environment()
	_build_ground()
	_build_scenery()
	_build_npcs()
	_build_enemies()
	_build_herbs()
	_hud = Hud.new()
	add_child(_hud)
	_build_player()
	_refresh_quest()
	_refresh_hud()
	_hud.show_message("Welcome to the Azure Cloud Sect valley. Press F to meditate.", 5.0)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.5, 0.76)
	sky_material.sky_horizon_color = Color(0.82, 0.86, 0.88)
	sky_material.ground_horizon_color = Color(0.7, 0.74, 0.72)
	sky_material.ground_bottom_color = Color(0.25, 0.3, 0.26)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.8, 0.84, 0.86)
	environment.fog_density = 0.005
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

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
	_add_hall(HALL_MODEL, HALL_POSITION, HALL_HEIGHT)
	_add_prop(TREE_MODEL, Vector3(9.0, 0.0, -7.0), 7.0, 0.3, false)
	_add_prop(TREE_MODEL, Vector3(-14.0, 0.0, -8.0), 5.0, 1.0, false)
	_add_prop(TREE_MODEL, Vector3(15.0, 0.0, -20.0), 8.0, 2.2, false)
	_add_prop(TREE_MODEL, Vector3(-22.0, 0.0, 4.0), 6.0, 0.6, false)
	_add_prop(ROCK_MODEL, Vector3(-6.0, 0.0, -3.0), 2.6, 0.0, true)
	_add_prop(ROCK_MODEL, Vector3(-10.0, 0.0, 5.0), 1.6, 1.2, true)
	_add_prop(ROCK_MODEL, Vector3(10.0, 0.0, 12.0), 1.2, 0.5, true)
	ValleyDecor.build(self)


## Places a fitted Tripo prop. Solid props get a box collider matching their footprint.
func _add_prop(scene: PackedScene, at: Vector3, height: float, yaw: float, solid: bool) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	add_child(root)

	var model := scene.instantiate() as Node3D
	root.add_child(model)
	var bounds := ModelUtils.fit_to_height(model, height)
	ModelUtils.apply_anime_style(model, PROP_OUTLINE_WIDTH)
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


## Places the sect hall as a walk-in building. Its collision is built from the model's own
## triangles, so the walls, pillars and terraces block the player where they are drawn. The stairs
## are left out of that collision and replaced by ramps, because a capsule cannot climb their
## risers. A stone ramp also drops from the east entry gallery into the cella.
func _add_hall(scene: PackedScene, at: Vector3, height: float) -> void:
	var root := _add_prop(scene, at, height, 0.0, false)
	var model := root.get_child(0) as Node3D
	var body := StaticBody3D.new()
	root.add_child(body)

	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(_hall_faces(_find_mesh(model), root))
	var shape := CollisionShape3D.new()
	shape.shape = concave
	body.add_child(shape)

	var bounds := model.transform * ModelUtils.local_bounds(model)
	for side in [1.0, -1.0]:
		_add_ramp(
			body,
			Vector3(0.0, 0.0, side * bounds.end.z),
			Vector3(0.0, FRONT_TERRACE_Y, side * FRONT_TERRACE_Z),
			FRONT_STAIR_WIDTH,
			false
		)
		_add_ramp(
			body,
			Vector3(side * bounds.end.x, 0.0, 0.0),
			Vector3(side * SIDE_TERRACE_X, SIDE_TERRACE_Y, 0.0),
			SIDE_STAIR_WIDTH,
			false
		)
	_add_ramp(
		body,
		Vector3(CELLA_X, 0.0, ENTRY_Z),
		Vector3(ENTRY_TOP_X, ENTRY_TOP_Y, ENTRY_Z),
		ENTRY_WIDTH,
		true
	)


## Triangles of the hall mesh in the hall's own space, leaving out the stairs.
func _hall_faces(mesh_node: MeshInstance3D, root: Node3D) -> PackedVector3Array:
	var to_root := root.global_transform.affine_inverse() * mesh_node.global_transform
	var corners := mesh_node.mesh.get_faces()
	var faces := PackedVector3Array()
	for index in range(0, corners.size(), 3):
		var a := to_root * corners[index]
		var b := to_root * corners[index + 1]
		var c := to_root * corners[index + 2]
		if not _on_stairs((a + b + c) / 3.0):
			faces.append_array([a, b, c])
	return faces


func _on_stairs(point: Vector3) -> bool:
	var front := (
		absf(point.x) <= FRONT_STAIR_WIDTH * 0.5 + 0.1
		and absf(point.z) >= FRONT_TERRACE_Z - 0.05
		and point.y <= FRONT_TERRACE_Y + 0.1
	)
	var side := (
		absf(point.x) >= SIDE_TERRACE_X
		and absf(point.x) <= SIDE_STAIR_WIDTH * 0.5 + 0.1 + SIDE_TERRACE_X
		and absf(point.z) <= SIDE_STAIR_WIDTH * 0.5 + 0.15
		and point.y <= SIDE_TERRACE_Y + 0.1
	)
	return front or side


## A slab that runs from [param low] up to [param high]. Its width is measured across the slope.
## A visible ramp also gets a stone mesh, because it has no Tripo geometry to stand in for it.
func _add_ramp(
	body: StaticBody3D, low: Vector3, high: Vector3, width: float, visible_surface: bool
) -> void:
	var slope := high - low
	var box := BoxShape3D.new()
	box.size = Vector3(width, RAMP_THICKNESS, slope.length())
	var basis := Basis.looking_at(slope.normalized(), Vector3.UP)
	var slab := Transform3D(basis, (low + high) * 0.5 - basis.y * RAMP_THICKNESS * 0.5)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = slab
	body.add_child(shape)
	if visible_surface:
		var stone := BoxMesh.new()
		stone.size = box.size
		var mesh := MeshInstance3D.new()
		mesh.mesh = stone
		mesh.material_override = _stone_material()
		mesh.transform = slab
		body.add_child(mesh)


func _stone_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.58, 0.52)
	material.roughness = 0.95
	return material


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _build_npcs() -> void:
	_elder = _add_npc(ELDER_MODEL, "Elder Wen", Vector3(2.5, 0.0, -4.0), 1.9)
	_elder.rotation.y = ModelUtils.yaw_towards(SPAWN_POINT - _elder.position)
	_elder.talked.connect(_on_npc_talked)

	_disciple = _add_npc(DISCIPLE_MODEL, "Disciple Lin", Vector3(-4.5, 0.0, 4.0), 1.8)
	_disciple.lines = DISCIPLE_LINES
	_disciple.rotation.y = ModelUtils.yaw_towards(SPAWN_POINT - _disciple.position)
	_disciple.talked.connect(_on_npc_talked)


func _add_npc(model: PackedScene, npc_name: String, at: Vector3, height: float) -> Npc:
	var npc := Npc.new()
	npc.model_scene = model
	npc.display_name = npc_name
	npc.height = height
	npc.position = at
	add_child(npc)
	return npc


func _build_enemies() -> void:
	for spawn in BEAST_SPAWNS:
		_spawn_wolf(spawn)


func _spawn_wolf(spawn: Vector3) -> SpiritBeast:
	var beast := SpiritBeast.new()
	beast.model_scene = WOLF_MODEL
	beast.position = spawn
	beast.died.connect(_on_beast_died.bind(spawn))
	add_child(beast)
	return beast


## The alpha of the pack: half as tall again as a wolf, nearly four times its health and a
## harder bite. It only appears once Elder Wen asks for it, and it does not come back.
func _spawn_alpha() -> SpiritBeast:
	var alpha := SpiritBeast.new()
	alpha.model_scene = WOLF_MODEL
	alpha.display_name = "Demon Wolf Alpha"
	alpha.position = ALPHA_SPAWN
	alpha.height = 1.9
	alpha.max_hp = 220.0
	alpha.attack_damage = 16.0
	alpha.attack_range = 2.8
	alpha.move_speed = 3.8
	alpha.detect_range = 15.0
	alpha.qi_reward = 0.0
	alpha.aura = Color(1.0, 0.12, 0.05, 0.9)
	alpha.add_to_group("alpha")
	alpha.died.connect(_on_alpha_died)
	add_child(alpha)
	return alpha


func _build_herbs() -> void:
	for spot in HERB_SPOTS:
		var herb := SpiritHerb.new()
		herb.position = spot
		herb.gathered.connect(_on_herb_gathered)
		add_child(herb)


func _build_player() -> void:
	_player = Cultivator.new()
	_player.model_scene = PLAYER_MODEL
	_player.position = SPAWN_POINT
	_player.stats_changed.connect(_refresh_hud)
	_player.realm_changed.connect(_on_realm_changed)
	_player.message.connect(_hud.show_message)
	_player.prompt_changed.connect(_hud.set_prompt)
	add_child(_player)


func _on_npc_talked(npc: Npc) -> void:
	if npc == _elder:
		if _quest.step == CountQuest.Step.COMPLETE:
			_talk_alpha_quest()
		else:
			_talk_wolf_quest()
	elif npc == _disciple:
		_talk_herb_quest()
	else:
		_hud.show_message(npc.next_line(), 5.0)
	_refresh_quest()
	_refresh_hud()


func _talk_wolf_quest() -> void:
	var accepting := _quest.step == CountQuest.Step.NOT_STARTED
	var reward := _quest.talk()
	if reward > 0.0:
		_player.cultivation.gain_qi(reward)
		_hud.show_message(
			"Elder Wen: Well done. Take this qi from the sect's reserves. Speak with me again.", 6.0
		)
	elif accepting:
		_hud.show_message(
			"Elder Wen: Demon wolves stalk the valley. Slay %d and return to me." % WOLVES_REQUIRED,
			6.0
		)
	else:
		_hud.show_message("Elder Wen: %s remain." % _count_text(_quest, "beast", "beasts"))


func _talk_alpha_quest() -> void:
	var accepting := _alpha_quest.step == CountQuest.Step.NOT_STARTED
	var reward := _alpha_quest.talk()
	if reward > 0.0:
		_player.cultivation.gain_qi(reward)
		_hud.show_message("Elder Wen: The pack is leaderless. The sect owes you a great debt.", 6.0)
	elif accepting:
		_spawn_alpha()
		_hud.show_message(
			"Elder Wen: Their alpha prowls behind the hall, wreathed in red qi. End it.", 6.0
		)
	elif _alpha_quest.step == CountQuest.Step.ACTIVE:
		_hud.show_message("Elder Wen: The alpha still lives, behind the hall.")
	else:
		_hud.show_message("Elder Wen: Walk the path of immortality, cultivator.")


func _talk_herb_quest() -> void:
	if _herb_quest.step == CountQuest.Step.COMPLETE:
		_hud.show_message(_disciple.next_line(), 5.0)
		return
	var accepting := _herb_quest.step == CountQuest.Step.NOT_STARTED
	var reward := _herb_quest.talk()
	if reward > 0.0:
		_player.cultivation.gain_qi(reward)
		_hud.show_message("Disciple Lin: Moon lotus! The elders will brew pills from these.", 6.0)
	elif accepting:
		(
			_hud
			. show_message(
				(
					"Disciple Lin: Moon lotuses glow by the pond, the bamboo and the trees. Bring me %d."
					% HERBS_REQUIRED
				),
				6.0
			)
		)
	else:
		_hud.show_message("Disciple Lin: %s to go." % _count_text(_herb_quest, "lotus", "lotuses"))


## "1 more beast" or "2 more beasts": what is left of [param quest].
static func _count_text(quest: CountQuest, one: String, many: String) -> String:
	var remaining := quest.required - quest.progress()
	return "%d more %s" % [remaining, one if remaining == 1 else many]


func _on_beast_died(qi_reward: float, spawn: Vector3) -> void:
	_quest.record()
	_player.cultivation.gain_qi(qi_reward)
	_hud.show_message("Spirit beast slain. +%d qi." % int(qi_reward))
	_refresh_quest()
	_refresh_hud()
	_respawn_later(spawn)


## Brings a slain wolf back to its den after [constant RESPAWN_SECONDS], once the cultivator is
## far enough away, so the valley never runs out of wolves to hunt.
func _respawn_later(spawn: Vector3) -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	while _player.global_position.distance_to(spawn) < RESPAWN_CLEARANCE:
		await get_tree().create_timer(2.0).timeout
	_spawn_wolf(spawn)


func _on_alpha_died(_qi_reward: float) -> void:
	_alpha_quest.record()
	_hud.show_message("The Demon Wolf Alpha falls. Return to Elder Wen.", 5.0)
	_refresh_quest()


func _on_herb_gathered(herb: SpiritHerb) -> void:
	_herb_quest.record()
	_player.cultivation.gain_qi(herb.qi_reward)
	_hud.show_message("You gather a %s. +%d qi." % [herb.display_name, int(herb.qi_reward)])
	_refresh_quest()
	_refresh_hud()


func _on_realm_changed(realm_name: String) -> void:
	_hud.show_message("Breakthrough! You now stand at %s." % realm_name, 4.0)


## Elder Wen's hunt shows the wolves until they are done, then the alpha. Lin's herbs sit below.
func _refresh_quest() -> void:
	var hunt := _quest
	var hunt_title := "Wolves of the valley"
	if _quest.step == CountQuest.Step.COMPLETE and _alpha_quest.step != CountQuest.Step.NOT_STARTED:
		hunt = _alpha_quest
		hunt_title = "The alpha"
	_hud.set_quests([_entry(hunt_title, hunt), _entry("Moon lotus", _herb_quest)])


static func _entry(title: String, quest: CountQuest) -> Array:
	return [title, quest.objective_text(), quest.step == CountQuest.Step.COMPLETE]


func _refresh_hud() -> void:
	if _player == null or _hud == null:
		return
	var cultivation := _player.cultivation
	_hud.update_stats(
		_player.hp,
		_player.max_hp,
		cultivation.realm_name(),
		cultivation.qi,
		cultivation.qi_required(),
		cultivation.is_max_realm()
	)
