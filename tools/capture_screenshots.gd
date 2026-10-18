extends SceneTree

## Captures README screenshots of the running valley. Needs a display (not --headless):
##   godot --path . --script res://tools/capture_screenshots.gd
## PNG files are written to docs/screenshots/.

const MAIN_SCENE := "res://scenes/main.tscn"
const OUTPUT_DIR := "res://docs/screenshots"
const SHOT_FRAMES := 30

const SHOTS: Array[String] = [
	"valley_overview",
	"third_person_spawn",
	"sect_hall",
	"sect_hall_entrance",
	"meditation_breakthrough",
]
const SETUPS: Array[String] = [
	"_setup_overview",
	"_setup_spawn",
	"_setup_hall",
	"_setup_hall_entrance",
	"_setup_meditation",
]

var _main: Node3D
var _free_camera: Camera3D
var _frame := 0
var _step := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_main = load(MAIN_SCENE).instantiate() as Node3D
	root.add_child(_main)
	_free_camera = Camera3D.new()
	root.add_child(_free_camera)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % SHOT_FRAMES != 0:
		return false
	if _step > 0:
		_save_png(SHOTS[_step - 1])
	if _step == SHOTS.size():
		quit(0)
		return true
	call(SETUPS[_step])
	_step += 1
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


## The player is built during the main scene's _ready, so it is looked up on demand.
func _find_player() -> Cultivator:
	return get_first_node_in_group("player") as Cultivator


func _save_png(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUTPUT_DIR, shot_name])
	var error := image.save_png(path)
	print("saved %s (error %d)" % [path, error])
