extends SceneTree

## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main.tscn"
const SCENE_FRAMES := 5
const HALL_ORIGIN := Vector3(0.0, 0.0, -26.0)

const BIPED_MODELS := {
	"female_cultivator": preload("res://assets/models/female_cultivator.glb"),
	"hero": preload("res://assets/models/hero.glb"),
	"elder": preload("res://assets/models/elder.glb"),
}
const WOLF_MODEL := preload("res://assets/models/demon_wolf.glb")
const BIPED_CLIPS: Array[String] = ["idle", "walk", "run", "slash", "hurt", "greet"]
const WOLF_CLIPS: Array[String] = ["idle", "walk", "run", "slash", "hurt"]
## Longest each clip may run, in seconds. Tripo's presets were 15 s idles and 14 s hurts.
const MAX_CLIP_SECONDS := {
	"idle": 4.0, "walk": 1.5, "run": 1.0, "slash": 1.0, "hurt": 1.0, "greet": 2.5
}
## A triangle edge may grow to this many times its bind length in any pose. Tripo's own skin
## weights tear edges past 200x, which shows as spikes and smeared textures. Edges shorter
## than STRETCH_FLOOR count as that long, so zero-area slivers do not read as infinite.
const MAX_STRETCH := 6.0
const STRETCH_FLOOR := 0.004
## The albedo is baked from Tripo's 4096 px model; the export at 2048 px blurred every face.
const MIN_ALBEDO_SIZE := 4096
## The head gets its own share of the atlas. Texels per unit of surface on the head must be at
## least this many times those on the body, or faces go soft again.
const MIN_HEAD_DENSITY_RATIO := 4.0
## Most edges whose end normals may turn past MAX_NORMAL_TURN degrees.
const MAX_NORMAL_TURN := 32.0
const MAX_SHARP_EDGE_SHARE := 0.25

## Action, then the world direction the cultivator should end up facing while it is held.
const WALK_DIRECTIONS := [
	["move_right", Vector3.RIGHT],
	["move_back", Vector3.BACK],
	["move_left", Vector3.LEFT],
	["move_forward", Vector3.FORWARD],
]
const SECONDS_PER_DIRECTION := 0.8

var _passed := 0
var _failed := 0
var _frames := 0
var _elapsed := 0.0
var _walk_step := -1
var _main: Node3D


func _initialize() -> void:
	_test_cultivation_rules()
	_test_count_quest()
	_test_model_fitting()
	_test_clip_resolution()
	_main = load(MAIN_SCENE).instantiate() as Node3D
	root.add_child(_main)


func _process(delta: float) -> bool:
	_frames += 1
	if _frames < SCENE_FRAMES:
		return false
	if _frames == SCENE_FRAMES:
		_test_character_rigs()
		_test_scene_boots()
		print("Walking")
	_elapsed += delta
	if _elapsed >= SECONDS_PER_DIRECTION or _walk_step < 0:
		if _walk_step >= 0:
			_check_walk_direction(WALK_DIRECTIONS[_walk_step])
		_walk_step += 1
		_elapsed = 0.0
		if _walk_step < WALK_DIRECTIONS.size():
			Input.action_press(WALK_DIRECTIONS[_walk_step][0])
	if _walk_step < WALK_DIRECTIONS.size():
		return false
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


## The cultivator has held [param entry]'s action for a while. Its model must face where it walks.
func _check_walk_direction(entry: Array) -> void:
	Input.action_release(entry[0])
	var player := get_first_node_in_group("player") as Cultivator
	_check(
		player.facing().dot(entry[1]) > 0.95,
		"holding %s turns the cultivator to face %s" % [entry[0], entry[1]]
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s" % label)


func _test_cultivation_rules() -> void:
	print("Cultivation")
	var cultivation := Cultivation.new()
	_check(cultivation.realm_name() == "Qi Condensation", "starts at Qi Condensation")
	_check(is_equal_approx(cultivation.qi_required(), 100.0), "first breakthrough costs 100 qi")
	cultivation.gain_qi(60.0)
	_check(not cultivation.try_breakthrough(), "breakthrough fails below the requirement")
	cultivation.gain_qi(40.0)
	_check(cultivation.try_breakthrough(), "breakthrough succeeds at the requirement")
	_check(
		cultivation.realm_name() == "Foundation Establishment", "breakthrough advances the realm"
	)
	_check(is_equal_approx(cultivation.qi, 0.0), "breakthrough consumes the qi cost")
	_check(is_equal_approx(cultivation.qi_required(), 200.0), "next realm costs double")
	cultivation.gain_qi(-50.0)
	_check(is_equal_approx(cultivation.qi, 0.0), "negative qi gain is ignored")

	cultivation.gain_qi(100000.0)
	while cultivation.try_breakthrough():
		pass
	_check(cultivation.is_max_realm(), "cultivator reaches the final realm")
	_check(not cultivation.try_breakthrough(), "no breakthrough beyond the final realm")
	_check(cultivation.progress() <= 1.0, "progress is clamped to 1.0")


func _test_count_quest() -> void:
	print("CountQuest")
	var quest := CountQuest.new(2, 150.0)
	_check(quest.objective_text() == "Speak with Elder Wen", "quest starts unaccepted")
	quest.record()
	quest.record()
	_check(quest.progress() == 2, "wolves slain before accepting still count")
	_check(
		is_equal_approx(quest.talk(), 150.0),
		"accepting with the wolves already slain turns the quest in on the same talk"
	)
	_check(quest.step == CountQuest.Step.COMPLETE, "quest is complete after the turn-in")
	_check(is_equal_approx(quest.talk(), 0.0), "a completed quest pays no reward again")

	var later := CountQuest.new(2, 150.0)
	_check(is_equal_approx(later.talk(), 0.0), "accepting with no kills pays nothing")
	later.record()
	_check(later.objective_text() == "Slay demon wolves 1 / 2", "objective shows progress")
	_check(not later.is_ready_to_turn_in(), "one kill is not enough to turn in")
	later.record()
	_check(later.objective_text() == "Return to Elder Wen", "objective asks for the turn-in")
	_check(is_equal_approx(later.talk(), 150.0), "talking after the kills pays the reward")

	var herbs := CountQuest.new(4, 120.0, "Disciple Lin", "Gather moon lotus")
	_check(herbs.objective_text() == "Speak with Disciple Lin", "the giver is named")
	herbs.talk()
	herbs.record()
	_check(herbs.objective_text() == "Gather moon lotus 1 / 4", "the task is named with its count")
	_check(herbs.objective_text() != "", "an objective is always shown")


func _test_model_fitting() -> void:
	print("ModelUtils")
	var holder := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 4.0, 1.0)
	mesh_node.mesh = box
	mesh_node.position = Vector3(3.0, 2.0, 0.0)
	holder.add_child(mesh_node)

	var bounds := ModelUtils.fit_to_height(holder, 2.0)
	_check(is_equal_approx(bounds.size.y, 2.0), "fit_to_height scales to the target height")
	_check(is_equal_approx(bounds.position.y, 0.0), "fit_to_height rests the model on the ground")
	_check(is_equal_approx(bounds.get_center().x, 0.0), "fit_to_height centres the model on X")
	_check(
		is_equal_approx(ModelUtils.yaw_towards(Vector3(0.0, 0.0, 1.0)), ModelUtils.FORWARD_OFFSET),
		"yaw_towards turns the model front towards the heading"
	)
	for heading in [Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3(1.0, 0.0, 1.0)]:
		var front := Basis(Vector3.UP, ModelUtils.yaw_towards(heading)) * Vector3(0.0, 0.0, 1.0)
		_check(
			front.is_equal_approx(heading.normalized()),
			"a +Z facing model ends up facing %s" % [heading]
		)
	holder.free()


func _test_clip_resolution() -> void:
	print("CharacterAnimator")
	var holder := Node3D.new()
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in ["Armature|idle", "Armature|walk", "slash"]:
		library.add_animation(clip, Animation.new())
	player.add_animation_library("", library)
	holder.add_child(player)

	var animator := CharacterAnimator.new(holder)
	_check(animator.has_clip(&"idle"), "a prefixed clip name matches its state")
	_check(animator.has_clip(&"walk"), "walk resolves inside a prefixed name")
	_check(animator.has_clip(&"slash"), "a bare clip name matches its state")
	_check(not animator.has_clip(&"hurt"), "a missing clip is reported as missing")
	_check(not animator.play_action(&"hurt"), "a missing action returns false for fallbacks")
	_check(animator.play_action(&"slash"), "a present action plays")
	_check(animator.is_action_playing(), "the action is marked as playing")
	holder.free()
	_test_action_restarts()


## A strike inside the previous strike's clip must swing again from the top, because the cut
## lands strike_delay after the key press whatever the clip is doing.
func _test_action_restarts() -> void:
	var holder := Node3D.new()
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 0.6
	library.add_animation("slash", clip)
	player.add_animation_library("", library)
	holder.add_child(player)
	root.add_child(holder)
	var animator := CharacterAnimator.new(holder)
	animator.play_action(&"slash")
	player.advance(0.4)
	animator.play_action(&"slash")
	player.advance(0.0)
	_check(
		player.current_animation_position < 0.05,
		"a second strike restarts the slash clip instead of carrying on from 0.4 s"
	)
	holder.free()


func _test_character_rigs() -> void:
	print("Character rigs")
	for model_name in BIPED_MODELS:
		_check_rig(model_name, BIPED_MODELS[model_name], BIPED_CLIPS)
	_check_rig("demon_wolf", WOLF_MODEL, WOLF_CLIPS)


func _check_rig(label: String, scene: PackedScene, clips: Array[String]) -> void:
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mesh_instance := (
		model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	)
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer

	var names := Array(player.get_animation_list())
	names.sort()
	var wanted := clips.duplicate()
	wanted.sort()
	_check(names == wanted, "%s carries exactly the clips %s" % [label, clips])
	for clip in clips:
		var length := player.get_animation(clip).length
		_check(
			length > 0.2 and length <= MAX_CLIP_SECONDS[clip],
			"%s %s clip is %.2f s, at most %.1f s" % [label, clip, length, MAX_CLIP_SECONDS[clip]]
		)

	_check(_faces_forward(skeleton), "%s faces +Z, the way the game turns it" % label)
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	_check_normals(label, arrays)
	_check_textures(label, mesh_instance, arrays)
	_check(
		_dummy_bone_weight(mesh_instance.skin, arrays) == 0,
		"%s has no vertices pinned to the dummy neutral_bone" % label
	)
	var worst := 0.0
	for clip in clips:
		var length := player.get_animation(clip).length
		for fraction in [0.25, 0.5, 0.75]:
			player.play(clip)
			player.seek(length * fraction, true)
			worst = maxf(worst, _worst_stretch(skeleton, mesh_instance.skin, arrays))
	_check(
		worst <= MAX_STRETCH,
		"%s never stretches a triangle past %.0fx (worst %.1fx)" % [label, MAX_STRETCH, worst]
	)
	root.remove_child(model)
	model.free()


## The albedo is sharp, there is a normal map, the head has its own dense share of the atlas, and
## the cel shader carries the albedo over.
func _check_textures(label: String, mesh_instance: MeshInstance3D, arrays: Array) -> void:
	var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	var albedo := material.albedo_texture
	_check(
		albedo.get_width() >= MIN_ALBEDO_SIZE and albedo.get_height() >= MIN_ALBEDO_SIZE,
		(
			"%s albedo is %dx%d, at least %d px"
			% [label, albedo.get_width(), albedo.get_height(), MIN_ALBEDO_SIZE]
		)
	)
	_check(material.normal_texture != null, "%s has a normal map" % label)
	var head := _head_vertices(mesh_instance.skin, arrays)
	var ratio := _head_density_ratio(head, arrays)
	_check(
		ratio >= MIN_HEAD_DENSITY_RATIO,
		(
			"%s head has %.1fx the body's texel density, at least %.0fx"
			% [label, ratio, MIN_HEAD_DENSITY_RATIO]
		)
	)
	var styled := ModelUtils.apply_anime_style(mesh_instance.get_parent())
	var override := mesh_instance.get_surface_override_material(0) as ShaderMaterial
	_check(
		styled == 1 and override != null and override.shader == ModelUtils.ANIME_TOON_SHADER,
		"%s is cel shaded instead of glossy PBR" % label
	)
	_check(
		override != null and override.get_shader_parameter("albedo_texture") == albedo,
		"%s keeps its sharp albedo under the cel shader" % label
	)
	var outline := override.next_pass as ShaderMaterial if override != null else null
	_check(
		outline != null and outline.shader == ModelUtils.ANIME_OUTLINE_SHADER,
		"%s has an ink outline pass" % label
	)
	_check(
		mesh_instance.mesh.surface_get_material(0) == material,
		"%s leaves the shared material untouched" % label
	)
	mesh_instance.set_surface_override_material(0, null)


## The normals are smooth enough for the two-tone cel shade to draw clean shapes
## (tools/anime_normals.py). Tripo's own turned more than MAX_NORMAL_TURN on 43% of edges.
func _check_normals(label: String, arrays: Array) -> void:
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sharp := 0
	var limit := cos(deg_to_rad(MAX_NORMAL_TURN))
	for corner in indices.size():
		var other := indices[corner - corner % 3 + (corner + 1) % 3]
		if normals[indices[corner]].dot(normals[other]) < limit:
			sharp += 1
	var share := float(sharp) / indices.size()
	_check(
		share <= MAX_SHARP_EDGE_SHARE,
		(
			"%s normals turn past %.0f degrees on %.0f%% of edges, at most %.0f%%"
			% [label, MAX_NORMAL_TURN, share * 100.0, MAX_SHARP_EDGE_SHARE * 100.0]
		)
	)


## Whether each vertex follows a head joint more than any other joint.
func _head_vertices(skin: Skin, arrays: Array) -> Array[bool]:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var is_head_bind: Array[bool] = []
	for bind in skin.get_bind_count():
		is_head_bind.append(skin.get_bind_name(bind).to_lower().contains("head"))
	var is_head_vertex: Array[bool] = []
	for vertex in vertices.size():
		var strongest := 0
		for slot in 4:
			if weights[vertex * 4 + slot] > weights[vertex * 4 + strongest]:
				strongest = slot
		is_head_vertex.append(is_head_bind[bones[vertex * 4 + strongest]])
	return is_head_vertex


## Texels per unit of surface on the triangles that follow a head joint, divided by the same
## figure for every other triangle.
func _head_density_ratio(is_head_vertex: Array[bool], arrays: Array) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var surface := [0.0, 0.0]
	var texture_area := [0.0, 0.0]
	for corner in range(0, indices.size(), 3):
		var a := indices[corner]
		var b := indices[corner + 1]
		var c := indices[corner + 2]
		var group := (
			0
			if int(is_head_vertex[a]) + int(is_head_vertex[b]) + int(is_head_vertex[c]) >= 2
			else 1
		)
		surface[group] += (
			0.5 * (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length()
		)
		texture_area[group] += 0.5 * absf((uvs[b] - uvs[a]).cross(uvs[c] - uvs[a]))
	if surface[0] <= 0.0 or surface[1] <= 0.0:
		return 0.0
	return (texture_area[0] / surface[0]) / (texture_area[1] / surface[1])


## True when the toes (or, for the beast, the head) lie ahead of the ankles (or the hips) on +Z.
func _faces_forward(skeleton: Skeleton3D) -> bool:
	var pairs := [["L_ToeBase", "L_Foot"], ["R_ToeBase", "R_Foot"]]
	if skeleton.find_bone("tripo__Head_0") >= 0:
		pairs = [["tripo__Head_0", "tripo__Spine_0"]]
	for pair in pairs:
		var front := (
			skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(pair[0]))
		)
		var back := (
			skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(pair[1]))
		)
		if front.origin.z - back.origin.z <= 0.0:
			return false
	return true


## Number of vertices that give weight to the dummy joint Tripo adds to every rig.
func _dummy_bone_weight(skin: Skin, arrays: Array) -> int:
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var dummy := -1
	for bind in skin.get_bind_count():
		if skin.get_bind_name(bind) == "neutral_bone":
			dummy = bind
	var pinned := 0
	for index in bones.size():
		if bones[index] == dummy and weights[index] > 0.001:
			pinned += 1
	return pinned


## Skins the mesh on the CPU in the skeleton's current pose and returns the largest ratio of a
## posed edge to its bind length.
func _worst_stretch(skeleton: Skeleton3D, skin: Skin, arrays: Array) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Bone global poses are composed by hand: the skeleton caches them until its next frame.
	var globals: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var local := skeleton.get_bone_pose(bone)
		globals.append(local if parent < 0 else globals[parent] * local)
	var matrices: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := skeleton.find_bone(skin.get_bind_name(bind))
		matrices.append(globals[bone] * skin.get_bind_pose(bind))
	var posed := PackedVector3Array()
	posed.resize(vertices.size())
	for vertex in vertices.size():
		var point := Vector3.ZERO
		for slot in 4:
			var weight := weights[vertex * 4 + slot]
			if weight > 0.0:
				point += weight * (matrices[bones[vertex * 4 + slot]] * vertices[vertex])
		posed[vertex] = point
	var worst := 0.0
	for corner in indices.size():
		var a := indices[corner]
		var b := indices[corner - corner % 3 + (corner + 1) % 3]
		var bind_length := maxf(vertices[a].distance_to(vertices[b]), STRETCH_FLOOR)
		worst = maxf(worst, posed[a].distance_to(posed[b]) / bind_length)
	return worst


func _test_scene_boots() -> void:
	print("Scene")
	var player := get_first_node_in_group("player") as Cultivator
	_check(player != null, "one player is spawned")
	if player != null:
		_check(player.hp == player.max_hp, "player starts at full health")
		_check(
			player.cultivation.realm_name() == "Qi Condensation", "player starts at the first realm"
		)
		_check(
			player.facing().dot(Vector3.FORWARD) > 0.99,
			"the cultivator starts facing the hall, away from the camera"
		)
		_check(player.animator.has_clip(&"idle"), "player model has an idle clip")
		_check(player.animator.has_clip(&"run"), "player model has a run clip")
		_check(player.animator.has_clip(&"slash"), "player model has a slash clip")
	_check(get_nodes_in_group("enemies").size() == 3, "three spirit beasts are spawned")
	_check(get_nodes_in_group("npcs").size() == 2, "two NPCs are spawned")
	_check(get_nodes_in_group("herbs").size() == 6, "six moon lotuses are spawned")
	for beast in get_nodes_in_group("enemies"):
		_check((beast as SpiritBeast).animator.has_clip(&"run"), "spirit beast has a run clip")
		break
	_check_cel_shaded()
	_check_sun_shade(player)
	_test_hall_walk_in()
	if player != null:
		_test_quest_line(player)


## Every character in the valley wears the cel shader, not Tripo's glossy PBR material.
func _check_cel_shaded() -> void:
	var characters: Array[Node] = []
	for group in ["player", "enemies", "npcs"]:
		characters.append_array(get_nodes_in_group(group))
	var glossy := 0
	for character in characters:
		for node in character.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface) as ShaderMaterial
				if material == null or material.shader != ModelUtils.ANIME_TOON_SHADER:
					glossy += 1
	_check(
		glossy == 0,
		"all %d characters are cel shaded (%d glossy surfaces)" % [characters.size(), glossy]
	)


## Characters skip the shadow map; a probe darkens them as a whole under the scenery instead.
func _check_sun_shade(player: Cultivator) -> void:
	var probes := player.find_children("*", "SunShadeProbe", true, false)
	_check(probes.size() == 1, "the cultivator carries a sun shade probe")
	if probes.size() == 1:
		_check(
			not (probes[0] as SunShadeProbe).is_sun_blocked(),
			"the cultivator stands in the sun at the gate"
		)
	var inside := SunShadeProbe.new()
	inside.position = HALL_ORIGIN + Vector3(0.0, 3.0, 0.0)
	_main.add_child(inside)
	_check(inside.is_sun_blocked(), "inside the sect hall the roof shades a character")
	inside.free()


## Plays both quest lines through the real scene: Lin's herbs, Elder Wen's wolves, then the alpha.
func _test_quest_line(player: Cultivator) -> void:
	print("Quests")
	var hud: Hud = null
	for child in _main.get_children():
		if child is Hud:
			hud = child
	var elder: Npc = null
	var lin: Npc = null
	for npc in get_nodes_in_group("npcs"):
		if (npc as Npc).display_name == "Elder Wen":
			elder = npc
		else:
			lin = npc
	_check(
		hud.quest_lines() == PackedStringArray(["Speak with Elder Wen", "Speak with Disciple Lin"]),
		"the tracker lists both quests before they are accepted"
	)

	var qi_before := player.cultivation.qi
	lin.interact(player)
	var herbs := get_nodes_in_group("herbs")
	for index in range(4):
		(herbs[index] as SpiritHerb).interact(player)
	_check(get_nodes_in_group("herbs").size() == 2, "a gathered lotus leaves the valley")
	_check(hud.quest_lines()[1] == "Return to Disciple Lin", "four lotuses fill Lin's quest")
	lin.interact(player)
	_check(
		is_equal_approx(player.cultivation.qi - qi_before, 4 * 10.0 + 120.0),
		"each lotus gives 10 qi and Lin pays 120 for four"
	)
	_check(hud.quest_lines()[1] == "Quest complete", "Lin's quest completes")

	var wolves := get_nodes_in_group("enemies")
	for index in range(2):
		(wolves[index] as SpiritBeast).take_damage(1000.0)
	elder.interact(player)
	_check(hud.quest_lines()[0] == "Quest complete", "two wolves complete the elder's first quest")
	_check(get_nodes_in_group("alpha").is_empty(), "the alpha waits until the elder asks for it")
	elder.interact(player)
	var alphas := get_nodes_in_group("alpha")
	_check(alphas.size() == 1, "talking again sends the cultivator after the alpha")
	_check(
		hud.quest_lines()[0] == "Slay the Demon Wolf Alpha 0 / 1",
		"the tracker moves on to the alpha"
	)
	var alpha := alphas[0] as SpiritBeast
	_check(alpha.max_hp > 3.0 * 60.0, "the alpha is far tougher than a wolf")
	alpha.take_damage(alpha.max_hp - 1.0)
	_check(not alpha.is_dead(), "the alpha survives a blow that would kill three wolves")
	alpha.take_damage(1.0)
	qi_before = player.cultivation.qi
	elder.interact(player)
	_check(
		is_equal_approx(player.cultivation.qi - qi_before, 300.0), "the elder pays 300 qi for it"
	)
	_check(hud.quest_lines()[0] == "Quest complete", "the alpha quest completes")


func _test_hall_walk_in() -> void:
	print("Sect hall")
	var space := _main.get_world_3d().direct_space_state
	var through_doorway := PhysicsRayQueryParameters3D.create(
		HALL_ORIGIN + Vector3(4.0, 3.0, -0.5), HALL_ORIGIN + Vector3(-1.0, 3.0, -0.5)
	)
	_check(space.intersect_ray(through_doorway).is_empty(), "the east doorway is open")
	var into_west_wall := PhysicsRayQueryParameters3D.create(
		HALL_ORIGIN + Vector3(-1.0, 3.0, -0.5), HALL_ORIGIN + Vector3(-9.0, 3.0, -0.5)
	)
	_check(not space.intersect_ray(into_west_wall).is_empty(), "the cella's west wall blocks")
	_check(
		absf(_floor_height(space, 1.7, -0.5) - 0.84) < 0.03,
		"the entry ramp is at 0.84 m, partway down from the gallery to the cella"
	)
	_check(
		absf(_floor_height(space, 0.0, 9.6) - 1.75) < 0.06,
		"the front terrace stands about 1.75 m above the ground"
	)


## Height of the first collision surface below a point over the hall, or -1 when there is none.
func _floor_height(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var from := HALL_ORIGIN + Vector3(x, 6.0, z)
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0)
	)
	return snappedf(hit.position.y, 0.01) if not hit.is_empty() else -1.0
