extends SceneTree

## Renders close-ups of a character's face, one column per model. Needs a display (not --headless):
##   godot --path . --script res://tools/capture_face_closeup.gd -- OUT.png MODEL [MODEL...]
## MODEL is a res:// scene or the path of a .glb file, which is loaded at run time, so an old
## version of a model can sit beside the new one. Every model gets two rows: a bust, then the face
## from as close as the game's camera zoom allows.

const CELL := 640
const HEIGHT := 1.8
## How far above the head joint the middle of the face is, as a fraction of the model's height.
const FACE_LIFT := 0.035
## Camera distance in metres, and vertical field of view in degrees, for each row.
const ROWS: Array = [[1.1, 30.0], [0.45, 24.0]]
const SETTLE_FRAMES := 5

var _out_path := ""
var _models: PackedStringArray = []
var _model: Node3D
var _face := Vector3.ZERO
var _camera: Camera3D
var _sheet: Image
var _column := 0
var _row := 0
var _frames_left := 0
var _loaded := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out_path = args[0]
	_models = args.slice(1)
	_build_stage()
	_sheet = Image.create(CELL * _models.size(), CELL * ROWS.size(), false, Image.FORMAT_RGB8)
	_frames_left = SETTLE_FRAMES


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	if _loaded:
		_capture_cell()
		_row += 1
		if _row == ROWS.size():
			_row = 0
			_column += 1
			_loaded = false
	if _column == _models.size():
		_sheet.save_png(_out_path)
		print("saved %s" % _out_path)
		quit(0)
		return true
	if not _loaded:
		_load_model()
	_aim_camera()
	_frames_left = SETTLE_FRAMES
	return false


func _build_stage() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
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
	root.add_child(_camera)


func _load_model() -> void:
	if _model != null:
		_model.queue_free()
	var path := _models[_column]
	if path.begins_with("res://"):
		_model = (load(path) as PackedScene).instantiate() as Node3D
	else:
		var state := GLTFState.new()
		var document := GLTFDocument.new()
		document.append_from_file(path, state)
		_model = document.generate_scene(state) as Node3D
	root.add_child(_model)
	ModelUtils.fit_to_height(_model, HEIGHT)
	ModelUtils.fix_skinned_normal_maps(_model)
	var player := _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in player.get_animation_list():
		if String(clip).ends_with("idle"):
			player.play(clip)
			player.seek(0.0, true)
			player.pause()
	_face = _head_position() + Vector3(0.0, HEIGHT * FACE_LIFT, 0.0)
	_loaded = true


## Where the head joint is after the idle pose, in world space.
func _head_position() -> Vector3:
	var skeleton := _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).to_lower().contains("head"):
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return Vector3(0.0, HEIGHT * 0.9, 0.0)


func _aim_camera() -> void:
	_camera.fov = ROWS[_row][1]
	_camera.look_at_from_position(_face + Vector3(0.0, 0.0, ROWS[_row][0]), _face)


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
