class_name BuildMenu
extends PanelContainer
## Панель строительства: вкладки категорий и сетка кнопок зданий.
## Выбор здания включает инструмент строительства; внешняя смена инструмента
## (пипетка, отмена) синхронизирует нажатую кнопку.

const CATEGORY_KEYS := ["CATEGORY_EXTRACTION", "CATEGORY_TRANSPORT", "CATEGORY_PRODUCTION", "CATEGORY_STORAGE"]
const COLUMNS := 6
const BUTTON_SIZE := 54

var _tools: ToolController
var _category: int = BuildingDef.Category.TRANSPORT
var _category_buttons: Array[Button] = []
var _grid: GridContainer
var _title: Label
var _description: Label
var _building_buttons: Dictionary[StringName, Button] = {}
var _building_group := ButtonGroup.new()


func setup(tools: ToolController) -> void:
	_tools = tools
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_building_group.allow_unpress = true

	var root := UiUtil.vbox(8)
	add_child(root)

	var tabs := UiUtil.hbox(4)
	root.add_child(tabs)
	var category_group := ButtonGroup.new()
	for i in CATEGORY_KEYS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = category_group
		b.text = CATEGORY_KEYS[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		var sample := Registry.buildings_in_category(i as BuildingDef.Category)
		if not sample.is_empty():
			b.icon = ArtRegistry.get_building_texture(sample[0])
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 20)
		b.pressed.connect(_select_category.bind(i))
		tabs.add_child(b)
		_category_buttons.append(b)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.custom_minimum_size = Vector2(COLUMNS * (BUTTON_SIZE + 4), BUTTON_SIZE * 2 + 4)
	root.add_child(_grid)

	root.add_child(HSeparator.new())
	_title = UiUtil.label("", &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 18)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	root.add_child(_title)
	_description = UiUtil.label("", &"DimLabel")
	_description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(COLUMNS * (BUTTON_SIZE + 4), 40)
	root.add_child(_description)

	tools.mode_changed.connect(_sync_with_tool)
	_select_category(_category)


func _select_category(category: int) -> void:
	_category = category
	# set_pressed_no_signal не отжимает остальные кнопки группы — синхронизируем все.
	for i in _category_buttons.size():
		_category_buttons[i].set_pressed_no_signal(i == category)
	for child in _grid.get_children():
		child.queue_free()
	_building_buttons.clear()
	for def in Registry.buildings_in_category(category as BuildingDef.Category):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _building_group
		b.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		b.icon = ArtRegistry.get_building_texture(def)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.theme_type_variation = &"SlotButton"
		b.tooltip_text = _tooltip_for(def)
		b.pressed.connect(_on_building_pressed.bind(def, b))
		b.mouse_entered.connect(_show_info.bind(def))
		b.mouse_exited.connect(_show_selected_info)
		_grid.add_child(b)
		_building_buttons[def.id] = b
	_sync_with_tool()


func _on_building_pressed(def: BuildingDef, button: Button) -> void:
	if button.button_pressed:
		_tools.select_building(def)
	else:
		_tools.clear_tool()


func _sync_with_tool() -> void:
	var selected_id: StringName = _tools.place_def.id if (_tools.mode == ToolController.Mode.PLACE and _tools.place_def != null) else &""
	if not selected_id.is_empty() and _tools.place_def.category != _category and _tools.place_def.player_buildable:
		_select_category(_tools.place_def.category)
		return
	for id in _building_buttons:
		_building_buttons[id].set_pressed_no_signal(id == selected_id)
	_show_selected_info()


func _show_info(def: BuildingDef) -> void:
	_title.text = "%s  (%d×%d)" % [tr(def.name_key), def.size, def.size]
	_description.text = tr(def.description_key)


func _show_selected_info() -> void:
	if _tools.mode == ToolController.Mode.PLACE and _tools.place_def != null:
		_show_info(_tools.place_def)
	else:
		_title.text = tr(CATEGORY_KEYS[_category])
		_description.text = tr("BUILD_MENU_HINT")


func _tooltip_for(def: BuildingDef) -> String:
	return "%s  (%d×%d)\n%s" % [tr(def.name_key), def.size, def.size, tr(def.description_key)]


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _grid != null:
		_select_category(_category)
