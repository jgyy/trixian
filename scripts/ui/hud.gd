class_name Hud
extends CanvasLayer

## On-screen HUD: vitals, cultivation progress, quest log, interaction prompt and messages.

var _realm_label: Label
var _hp_bar: ProgressBar
var _qi_bar: ProgressBar
var _qi_label: Label
var _quest_label: Label
var _prompt_label: Label
var _message_label: Label
var _message_tween: Tween


func _ready() -> void:
	var vitals := _make_panel(Control.PRESET_TOP_LEFT)
	var vitals_box := VBoxContainer.new()
	vitals.add_child(vitals_box)
	_realm_label = _make_label(vitals_box)
	_hp_bar = _make_bar(vitals_box, Color(0.8, 0.24, 0.24))
	_qi_bar = _make_bar(vitals_box, Color(0.45, 0.85, 0.75))
	_qi_label = _make_label(vitals_box)

	_quest_label = _make_label(_make_panel(Control.PRESET_TOP_RIGHT))
	_prompt_label = _make_label(_make_panel(Control.PRESET_CENTER_BOTTOM))
	_message_label = _make_label(_make_panel(Control.PRESET_CENTER_TOP))
	_message_label.modulate.a = 0.0


func update_stats(hp: float, max_hp: float, realm: String, qi: float, qi_required: float) -> void:
	_realm_label.text = "Realm: %s" % realm
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_qi_bar.max_value = qi_required
	_qi_bar.value = qi
	_qi_label.text = "Qi %d / %d" % [int(qi), int(qi_required)]


func set_quest(text: String) -> void:
	_quest_label.text = text


func set_prompt(text: String) -> void:
	_prompt_label.text = text


func show_message(text: String, duration := 3.0) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.6)


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
	add_child(panel)
	return panel


func _make_label(parent: Node) -> Label:
	var label := Label.new()
	parent.add_child(label)
	return label


func _make_bar(parent: Node, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar
