extends SceneTree

## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main.tscn"
const SCENE_FRAMES := 5

var _passed := 0
var _failed := 0
var _frames := 0
var _main: Node3D


func _initialize() -> void:
	_test_cultivation_rules()
	_test_model_fitting()
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


func _test_scene_boots() -> void:
	print("Scene")
	var player := get_first_node_in_group("player") as Cultivator
	_check(player != null, "one player is spawned")
	if player != null:
		_check(player.hp == player.max_hp, "player starts at full health")
		_check(
			player.cultivation.realm_name() == "Qi Condensation", "player starts at the first realm"
		)
	_check(get_nodes_in_group("enemies").size() == 3, "three spirit beasts are spawned")
	_check(get_nodes_in_group("npcs").size() == 1, "one NPC is spawned")
