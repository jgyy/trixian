class_name Hud
extends CanvasLayer

## On-screen HUD: vitals with labelled bars, a quest tracker, the interaction prompt, message
## toasts, a low-health vignette and a controls hint. One theme is built in code and shared by
## every panel, so the look lives in one place.

const GOLD := Color(0.92, 0.78, 0.45)
const PARCHMENT := Color(0.96, 0.93, 0.85)
const INK := Color(0.07, 0.1, 0.11, 0.8)
const HP_COLOR := Color(0.82, 0.26, 0.24)
const QI_COLOR := Color(0.42, 0.86, 0.74)
const PEAK_COLOR := Color(1.0, 0.84, 0.45)
const DONE_COLOR := Color(0.6, 0.9, 0.55)
const LOW_HP_RATIO := 0.3
const CONTROLS_TEXT := (
	"WASD move   Space jump   J / LMB strike   F meditate   B break through   E talk   "
	+ "Wheel zoom   Esc cursor"
)

var _root: Control
var _realm_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _qi_bar: ProgressBar
var _qi_label: Label
var _quest_box: VBoxContainer
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _message_panel: PanelContainer
var _message_label: Label
var _vignette: TextureRect
var _message_tween: Tween


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _build_theme()
	add_child(_root)

	_vignette = _make_vignette()
	_build_vitals(_make_panel(Control.PRESET_TOP_LEFT))
	_build_quest(_make_panel(Control.PRESET_TOP_RIGHT))
	_prompt_panel = _make_panel(Control.PRESET_CENTER_BOTTOM)
	_prompt_label = _make_label(_prompt_panel, 18)
	_prompt_panel.visible = false
	_message_panel = _make_panel(Control.PRESET_CENTER_TOP)
	_message_label = _make_label(_message_panel, 18)
	_message_panel.modulate.a = 0.0
	_make_controls_hint()


func update_stats(
	hp: float, max_hp: float, realm: String, qi: float, qi_required: float, at_peak := false
) -> void:
	_realm_label.text = realm
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_label.text = "HP %d / %d" % [ceili(hp), int(max_hp)]
	if at_peak:
		_qi_bar.max_value = 1.0
		_qi_bar.value = 1.0
		_qi_label.text = "Qi %d   Peak realm" % int(qi)
		_qi_label.add_theme_color_override("font_color", PEAK_COLOR)
	else:
		_qi_bar.max_value = qi_required
		_qi_bar.value = qi
		_qi_label.text = "Qi %d / %d" % [int(qi), int(qi_required)]
		_qi_label.remove_theme_color_override("font_color")
	# The red vignette fades in as health drops below LOW_HP_RATIO.
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	_vignette.modulate.a = clampf((LOW_HP_RATIO - ratio) / LOW_HP_RATIO, 0.0, 1.0)


## Lists the quests in the tracker. Each entry is [title, objective, complete]; a finished
## quest stays on the list in green until it is replaced.
func set_quests(entries: Array) -> void:
	for child in _quest_box.get_children():
		_quest_box.remove_child(child)
		child.queue_free()
	for entry in entries:
		var title := _make_label(_quest_box, 13)
		title.text = String(entry[0]).to_upper()
		title.add_theme_color_override("font_color", GOLD)
		var objective := _make_label(_quest_box, 17)
		objective.text = entry[1]
		objective.add_theme_color_override("font_color", DONE_COLOR if entry[2] else PARCHMENT)


## The objective lines in the tracker, top to bottom.
func quest_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for index in range(1, _quest_box.get_child_count(), 2):
		lines.append((_quest_box.get_child(index) as Label).text)
	return lines


func set_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_panel.visible = not text.is_empty()


func show_message(text: String, duration := 3.0) -> void:
	_message_label.text = text
	_message_panel.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(_message_panel, "modulate:a", 0.0, 0.6)


func _build_vitals(panel: PanelContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_realm_label = _make_label(box, 17)
	_realm_label.add_theme_color_override("font_color", GOLD)
	_hp_label = Label.new()
	_hp_bar = _make_bar(box, HP_COLOR, _hp_label)
	_qi_label = Label.new()
	_qi_bar = _make_bar(box, QI_COLOR, _qi_label)


func _build_quest(panel: PanelContainer) -> void:
	_quest_box = VBoxContainer.new()
	_quest_box.add_theme_constant_override("separation", 2)
	panel.add_child(_quest_box)


func _make_controls_hint() -> void:
	var hint := Label.new()
	hint.text = CONTROLS_TEXT
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate.a = 0.7
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 16.0
	hint.offset_bottom = -12.0
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(hint)


func _make_vignette() -> TextureRect:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.7, 0.0, 0.0, 0.0), Color(0.6, 0.0, 0.0, 0.85)])
	gradient.offsets = PackedFloat32Array([0.55, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	_root.add_child(rect)
	return rect


func _build_theme() -> Theme:
	var theme := Theme.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = INK
	panel_style.set_corner_radius_all(10)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(GOLD, 0.55)
	panel_style.set_content_margin_all(12)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.7))
	theme.set_constant("outline_size", "Label", 3)
	return theme


func _make_panel(preset: Control.LayoutPreset) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	# Grow towards the middle of the screen so the panel stays visible as its text changes.
	match preset:
		Control.PRESET_TOP_RIGHT:
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_BOTTOM:
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	return panel


func _make_label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


## A progress bar with its value text laid over the fill.
func _make_bar(parent: Node, fill_color: Color, overlay: Label) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(280, 22)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(5)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	background.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	parent.add_child(bar)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 14)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(overlay)
	return bar
