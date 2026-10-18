extends SceneTree

## Captures README screenshots of the running valley. Needs a display (not --headless):
##   godot --path . --script res://tools/capture_screenshots.gd
## PNG files are written to docs/screenshots/.

const MAIN_SCENE := "res://scenes/main.tscn"
const OUTPUT_DIR := "res://docs/screenshots"
## Name, setup method and the number of frames to wait after the setup before the shot.
const SHOTS: Array = [
	["valley_overview", "_setup_overview", 30],
	["third_person_spawn", "_setup_spawn", 30],
	["player_face_closeup", "_setup_face", 40],
	["sect_hall", "_setup_hall", 30],
	["sect_hall_entrance", "_setup_hall_entrance", 30],
	["meditation_breakthrough", "_setup_meditation", 30],
	["player_running", "_setup_running", 50],
	["player_slash", "_setup_slash", 16],
	["wolf_charge", "_setup_wolf", 70],
]
const WOLF_STAGE := Vector3(12.0, 0.0, 12.0)
## Where the side-on camera sits, relative to the middle of the cultivator and the wolf.
const FIGHT_CAMERA_OFFSET := Vector3(4.5, 1.2, 0.0)
## How far above the head joint the middle of the face is, and how far in front of it the
## close-up camera stands, in metres.
const FACE_LIFT := 0.06
const FACE_DISTANCE := 0.75

var _main: Node3D
var _free_camera: Camera3D
var _wait := 0
var _step := -1
var _following_fight := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_main = load(MAIN_SCENE).instantiate() as Node3D
	root.add_child(_main)
	_free_camera = Camera3D.new()
	root.add_child(_free_camera)
	_wait = 30


func _process(_delta: float) -> bool:
	if _following_fight:
		_frame_fight()
	_wait -= 1
	if _wait > 0:
		return false
	if _step >= 0:
		_save_png(SHOTS[_step][0])
	_step += 1
	if _step == SHOTS.size():
		quit(0)
		return true
	_release_inputs()
	_following_fight = false
	call(SHOTS[_step][1])
	_wait = SHOTS[_step][2]
	return false


func _setup_overview() -> void:
	_free_camera.make_current()
	_free_camera.look_at_from_position(Vector3(-4.0, 22.0, 36.0), Vector3(0.0, 1.0, -8.0))


func _setup_spawn() -> void:
	_find_player().camera.make_current()


func _setup_hall() -> void:
	_free_camera.make_current()
	_free_camera.look_at_from_position(Vector3(-9.0, 4.0, -2.0), Vector3(0.0, 7.0, -26.0))


## Looks at the hall from the east, where the side stairs lead up to the entry gallery.
func _setup_hall_entrance() -> void:
	_free_camera.make_current()
	_free_camera.look_at_from_position(Vector3(20.0, 5.5, -34.0), Vector3(2.5, 2.0, -26.0))


func _setup_meditation() -> void:
	var player := _find_player()
	player.camera.make_current()
	player.cultivation.gain_qi(70.0)
	player.is_meditating = true


## Holds forward from the sect gate, so the shot catches the run cycle mid-stride.
func _setup_running() -> void:
	var player := _find_player()
	player.is_meditating = false
	player.camera.make_current()
	Input.action_press("move_forward")


## Fires the sword and waits for the cut to land.
func _setup_slash() -> void:
	var player := _find_player()
	player.camera.make_current()
	player.attack()


## A free camera in front of the cultivator's face, closer than the game's zoom allows, to show
## how sharp the face texture is in the valley's light.
func _setup_face() -> void:
	var player := _find_player()
	player.is_meditating = false
	var skeleton := player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var model := skeleton.owner if skeleton.owner != null else skeleton.get_parent_node_3d()
	var head := Vector3.ZERO
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).to_lower().contains("head"):
			head = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	# The model faces +Z in its own space, so its front is its Z axis in the world.
	var front := (model as Node3D).global_transform.basis.z.normalized()
	var face := head + Vector3.UP * FACE_LIFT
	_free_camera.make_current()
	_free_camera.fov = 30.0
	_free_camera.look_at_from_position(face + front * FACE_DISTANCE + Vector3.UP * 0.03, face)


## Drops the cultivator in front of a wolf, which charges and bites. A side-on camera follows
## the pair so the wolf's stride and the bite read clearly.
func _setup_wolf() -> void:
	var player := _find_player()
	player.global_position = WOLF_STAGE
	_free_camera.make_current()
	_following_fight = true
	_frame_fight()


## Keeps the free camera beside the cultivator and the nearest wolf.
func _frame_fight() -> void:
	var player := _find_player()
	var nearest: Node3D = null
	for wolf in get_nodes_in_group("enemies"):
		var candidate := wolf as Node3D
		if (
			nearest == null
			or (
				candidate.global_position.distance_to(player.global_position)
				< nearest.global_position.distance_to(player.global_position)
			)
		):
			nearest = candidate
	var middle := (player.global_position + nearest.global_position) * 0.5 + Vector3.UP * 0.7
	_free_camera.look_at_from_position(middle + FIGHT_CAMERA_OFFSET, middle)


func _release_inputs() -> void:
	Input.action_release("move_forward")


## The player is built during the main scene's _ready, so it is looked up on demand.
func _find_player() -> Cultivator:
	return get_first_node_in_group("player") as Cultivator


func _save_png(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUTPUT_DIR, shot_name])
	var error := image.save_png(path)
	print("saved %s (error %d)" % [path, error])
