class_name LevelSelect
extends PanelContainer
## Выбор уровня кампании: список, превью карты, описание, флажок песочницы.

signal back_requested

var _list: ItemList
var _preview: TextureRect
var _title: Label
var _description: Label
var _info: Label
var _sandbox: CheckBox
var _start_button: Button
var _previews: Dictionary[StringName, Texture2D] = {}
var _sizes: Dictionary[StringName, Vector2i] = {}


func _ready() -> void:
	custom_minimum_size = Vector2(900, 640)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Registry.ensure_loaded()

	var root := UiUtil.vbox(12)
	add_child(root)
	root.add_child(UiUtil.label("LEVELS_TITLE", &"HeaderLabel"))

	var body := UiUtil.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(270, 0)
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.item_selected.connect(_on_level_selected)
	_list.item_activated.connect(func(_i: int) -> void: _start())
	body.add_child(_list)

	var details := UiUtil.vbox(10)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(details)

	var preview_panel := PanelContainer.new()
	preview_panel.theme_type_variation = &"CardPanel"
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(preview_panel)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.custom_minimum_size = Vector2(420, 260)
	preview_panel.add_child(_preview)

	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	details.add_child(_title)
	_description = Label.new()
	_description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(0, 48)
	details.add_child(_description)
	_info = Label.new()
	_info.theme_type_variation = &"DimLabel"
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	details.add_child(_info)

	var sandbox_row := UiUtil.hbox(10)
	_sandbox = CheckBox.new()
	_sandbox.text = "LEVELS_SANDBOX"
	_sandbox.tooltip_text = "LEVELS_SANDBOX_HINT"
	sandbox_row.add_child(_sandbox)
	var sandbox_hint := UiUtil.label("LEVELS_SANDBOX_HINT", &"DimLabel")
	sandbox_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sandbox_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sandbox_row.add_child(sandbox_hint)
	details.add_child(sandbox_row)

	var bottom := UiUtil.hbox(10)
	root.add_child(bottom)
	bottom.add_child(UiUtil.button("SETTINGS_BACK", func() -> void: back_requested.emit()))
	bottom.add_child(UiUtil.spacer())
	_start_button = UiUtil.button("LEVELS_START", _start, &"AccentButton")
	_start_button.custom_minimum_size = Vector2(180, 0)
	bottom.add_child(_start_button)

	_fill_list()


func _fill_list() -> void:
	var selected := _list.get_selected_items()
	var keep := selected[0] if not selected.is_empty() else 0
	_list.clear()
	for i in Registry.levels.size():
		var level := Registry.levels[i]
		_list.add_item("%02d.  %s" % [i + 1, tr(level.title_key)])
	if Registry.levels.is_empty():
		_title.text = tr("LEVELS_EMPTY")
		_start_button.disabled = true
		return
	_list.select(clampi(keep, 0, Registry.levels.size() - 1))
	_on_level_selected(clampi(keep, 0, Registry.levels.size() - 1))


func _on_level_selected(index: int) -> void:
	var level := Registry.levels[index]
	_title.text = tr(level.title_key)
	_description.text = tr(level.description_key)
	if not _previews.has(level.id):
		var map := LevelIO.load_map(level.map_path)
		if map != null:
			var img := MapPreview.build_terrain_image(map.width, map.height, map.floors, map.ores)
			MapPreview.draw_placements(img, map.placements)
			_previews[level.id] = ImageTexture.create_from_image(img)
			_sizes[level.id] = Vector2i(map.width, map.height)
	_preview.texture = _previews.get(level.id)
	var size: Vector2i = _sizes.get(level.id, Vector2i.ZERO)
	_info.text = tr("LEVELS_SIZE") % [size.x, size.y]
	_start_button.disabled = not _previews.has(level.id)


func _start() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or _start_button.disabled:
		return
	Session.start_level(Registry.levels[selected[0]], _sandbox.button_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _list != null:
		_fill_list()
