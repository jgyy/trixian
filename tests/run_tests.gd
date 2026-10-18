extends SceneTree

## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main.tscn"
const SCENE_FRAMES := 5
const HALL_ORIGIN := Vector3(0.0, 0.0, -26.0)

var _passed := 0
var _failed := 0
var _frames := 0
var _main: Node3D


func _initialize() -> void:
	_test_cultivation_rules()
	_test_wolf_quest()
	_test_model_fitting()
	_test_clip_resolution()
	_main = load(MAIN_SCENE).instantiate() as Node3D
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SCENE_FRAMES:
		return false
	_test_scene_boots()
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


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


func _test_wolf_quest() -> void:
	print("WolfQuest")
	var quest := WolfQuest.new(2, 150.0)
	_check(quest.objective_text() == "Speak with Elder Wen", "quest starts unaccepted")
	quest.record_kill()
	quest.record_kill()
	_check(quest.progress() == 2, "wolves slain before accepting still count")
	_check(
		is_equal_approx(quest.talk(), 150.0),
		"accepting with the wolves already slain turns the quest in on the same talk"
	)
	_check(quest.step == WolfQuest.Step.COMPLETE, "quest is complete after the turn-in")
	_check(is_equal_approx(quest.talk(), 0.0), "a completed quest pays no reward again")

	var later := WolfQuest.new(2, 150.0)
	_check(is_equal_approx(later.talk(), 0.0), "accepting with no kills pays nothing")
	later.record_kill()
	_check(later.objective_text() == "Slay demon wolves 1 / 2", "objective shows progress")
	_check(not later.is_ready_to_turn_in(), "one kill is not enough to turn in")
	later.record_kill()
	_check(later.objective_text() == "Return to Elder Wen", "objective asks for the turn-in")
	_check(is_equal_approx(later.talk(), 150.0), "talking after the kills pays the reward")


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


func _test_scene_boots() -> void:
	print("Scene")
	var player := get_first_node_in_group("player") as Cultivator
	_check(player != null, "one player is spawned")
	if player != null:
		_check(player.hp == player.max_hp, "player starts at full health")
		_check(
			player.cultivation.realm_name() == "Qi Condensation", "player starts at the first realm"
		)
		_check(player.animator.has_clip(&"idle"), "player model has an idle clip")
		_check(player.animator.has_clip(&"run"), "player model has a run clip")
		_check(player.animator.has_clip(&"slash"), "player model has a slash clip")
	_check(get_nodes_in_group("enemies").size() == 3, "three spirit beasts are spawned")
	_check(get_nodes_in_group("npcs").size() == 2, "two NPCs are spawned")
	for beast in get_nodes_in_group("enemies"):
		_check((beast as SpiritBeast).animator.has_clip(&"walk"), "spirit beast has a walk clip")
		break
	_test_hall_walk_in()


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
