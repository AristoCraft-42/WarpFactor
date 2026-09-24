class_name NewRunScreen
extends PanelContainer
## Новый забег: сид (случайный, можно ввести свой), превью первой планеты, творческий режим.

signal back_requested

var _seed_edit: LineEdit
var _preview: TextureRect
var _info: Label
var _creative: CheckBox
var _cheats: CheckBox
var _preview_seed: int = -1


func _ready() -> void:
	custom_minimum_size = Vector2(900, 620)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Registry.ensure_loaded()

	var root := UiUtil.vbox(12)
	add_child(root)
	root.add_child(UiUtil.label("NEW_RUN_TITLE", &"HeaderLabel"))
	var intro := UiUtil.label("NEW_RUN_INTRO", &"DimLabel")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)

	var preview_panel := PanelContainer.new()
	preview_panel.theme_type_variation = &"CardPanel"
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(preview_panel)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.custom_minimum_size = Vector2(420, 300)
	preview_panel.add_child(_preview)

	_info = Label.new()
	_info.theme_type_variation = &"DimLabel"
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	root.add_child(_info)

	var seed_row := UiUtil.hbox(10)
	root.add_child(seed_row)
	seed_row.add_child(UiUtil.label("NEW_RUN_SEED"))
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(220, 0)
	_seed_edit.text = str(_random_seed())
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _update_preview())
	_seed_edit.focus_exited.connect(_update_preview)
	seed_row.add_child(_seed_edit)
	seed_row.add_child(UiUtil.button("NEW_RUN_REROLL", func() -> void:
		_seed_edit.text = str(_random_seed())
		_update_preview()))

	var creative_row := UiUtil.hbox(10)
	_creative = CheckBox.new()
	_creative.text = "LEVELS_CREATIVE"
	_creative.tooltip_text = "LEVELS_CREATIVE_HINT"
	creative_row.add_child(_creative)
	var creative_hint := UiUtil.label("LEVELS_CREATIVE_HINT", &"DimLabel")
	creative_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creative_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creative_row.add_child(creative_hint)
	root.add_child(creative_row)

	var cheats_row := UiUtil.hbox(10)
	_cheats = CheckBox.new()
	_cheats.text = "LEVELS_CHEATS"
	_cheats.tooltip_text = "LEVELS_CHEATS_HINT"
	cheats_row.add_child(_cheats)
	var cheats_hint := UiUtil.label("LEVELS_CHEATS_HINT", &"DimLabel")
	cheats_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cheats_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cheats_row.add_child(cheats_hint)
	root.add_child(cheats_row)

	var bottom := UiUtil.hbox(10)
	root.add_child(bottom)
	bottom.add_child(UiUtil.button("SETTINGS_BACK", func() -> void: back_requested.emit()))
	bottom.add_child(UiUtil.spacer())
	var start := UiUtil.button("NEW_RUN_START", _start, &"AccentButton")
	start.custom_minimum_size = Vector2(200, 0)
	bottom.add_child(start)

	visibility_changed.connect(func() -> void:
		if visible:
			_update_preview())


func get_seed() -> int:
	var text := _seed_edit.text.strip_edges()
	if text.is_valid_int():
		return absi(text.to_int()) & 0x7fffffff
	return hash(text) & 0x7fffffff


func _update_preview() -> void:
	var run_seed := get_seed()
	if run_seed == _preview_seed:
		return
	_preview_seed = run_seed
	var star_map := StarMap.new(run_seed, Registry.run_def, Registry.planet_types)
	var node := star_map.get_current()
	var map := PlanetGenerator.generate(node, Registry.run_def.pad_start_size, Run.max_pad_size())
	var img := MapPreview.build_terrain_image(map.width, map.height, map.floors, map.ores)
	_preview.texture = ImageTexture.create_from_image(img)
	_info.text = "%s %s  ·  %s" % [tr(node.type.name_key), node.code, tr("LEVELS_SIZE") % [map.width, map.height]]


func _start() -> void:
	Session.start_run(get_seed(), _creative.button_pressed, _cheats.button_pressed)


static func _random_seed() -> int:
	return randi() & 0x7fffffff
