extends SceneTree

## Renders a contact sheet of animation poses. Needs a display (not --headless):
##   godot --path . --script res://tools/capture_clip_sheet.gd -- OUT.png VIEW ROW [ROW...]
## VIEW is "front" (camera on +Z, for a character facing the camera) or "side" (camera on +X).
## ROW is MODEL|CLIP|T1,T2,...[|HEIGHT] with times in seconds and the model's height in metres
## (1.8 unless given). MODEL is a res:// scene or the path of a .glb file, which is loaded at
## run time, so an old version of a model can sit beside the new one. Every row becomes a line of
## the sheet and must list the same number of times. CLIP "rest" shows the bind pose.

const CELL := 400
const DEFAULT_HEIGHT := 1.8
const CAMERA_DISTANCE := 3.4
const SETTLE_FRAMES := 4

var _out_path := ""
var _view := "front"
var _rows: Array[PackedStringArray] = []
var _model: Node3D
var _camera: Camera3D
var _sheet: Image
var _row := 0
var _column := 0
var _frames_left := 0
var _loaded_row := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out_path = args[0]
	_view = args[1]
	for spec in args.slice(2):
		_rows.append(PackedStringArray(spec.split("|")))
	_build_stage()
	var columns := _rows[0][2].split(",").size()
	_sheet = Image.create(CELL * columns, CELL * _rows.size(), false, Image.FORMAT_RGB8)
	_frames_left = SETTLE_FRAMES


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	if _loaded_row >= 0:
		_capture_cell()
		_column += 1
		if _column == _rows[_row][2].split(",").size():
			_column = 0
			_row += 1
	if _row == _rows.size():
		_sheet.save_png(_out_path)
		print("saved %s" % _out_path)
		quit(0)
		return true
	if _loaded_row != _row:
		_load_row()
	_pose(float(_rows[_row][2].split(",")[_column]))
	_frames_left = SETTLE_FRAMES
	return false


func _build_stage() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	root.add_child(light)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.7, 0.75, 0.8)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)


func _load_row() -> void:
	if _model != null:
		_model.queue_free()
	var path := _rows[_row][0]
	if path.begins_with("res://"):
		_model = (load(path) as PackedScene).instantiate() as Node3D
	else:
		var state := GLTFState.new()
		var document := GLTFDocument.new()
		document.append_from_file(path, state)
		_model = document.generate_scene(state) as Node3D
	root.add_child(_model)
	var height := float(_rows[_row][3]) if _rows[_row].size() > 3 else DEFAULT_HEIGHT
	var bounds := ModelUtils.fit_to_height(_model, height)
	ModelUtils.apply_anime_style(_model)
	var middle := Vector3(0.0, bounds.get_center().y, 0.0)
	var offset := Vector3(0.0, 0.1, CAMERA_DISTANCE)
	if _view == "side":
		offset = Vector3(CAMERA_DISTANCE, 0.1, 0.0)
	_camera.look_at_from_position(middle + offset, middle)
	_loaded_row = _row


func _pose(seconds: float) -> void:
	var player := _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var wanted := _rows[_row][1]
	for clip in player.get_animation_list():
		if String(clip).ends_with(wanted):
			player.play(clip)
			player.seek(seconds, true)
			player.pause()
			return
	if wanted != "rest":
		push_error("no clip %s in %s" % [wanted, _rows[_row][0]])


func _capture_cell() -> void:
	var image := root.get_texture().get_image()
	var side := mini(image.get_width(), image.get_height())
	var crop := image.get_region(
		Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side)
	)
	crop.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
	# The viewport is RGBA on some renderers, and blit_rect needs matching formats.
	crop.convert(Image.FORMAT_RGB8)
	_sheet.blit_rect(crop, Rect2i(0, 0, CELL, CELL), Vector2i(CELL * _column, CELL * _row))
