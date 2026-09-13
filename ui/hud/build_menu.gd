class_name BuildMenu
extends PanelContainer
## Панель строительства: вкладки категорий, сетка кнопок зданий, описание и стоимость.
## Вкладки переключаются свободно, даже когда здание уже в руке. Автоматически раздел меняется
## только если сменилось само выбранное здание (например, пипеткой).
## Недоступные по ресурсам здания приглушены; стоимость показывается иконками.

const CATEGORY_KEYS := ["CATEGORY_EXTRACTION", "CATEGORY_TRANSPORT", "CATEGORY_PRODUCTION", "CATEGORY_STORAGE"]
const COLUMNS := 6
const BUTTON_SIZE := 54
const REFRESH_INTERVAL := 0.3
const INFO_HEIGHT := 170

var _tools: ToolController
var _world: GameWorld
var _category: int = BuildingDef.Category.TRANSPORT
var _category_buttons: Array[Button] = []
var _grid: GridContainer
var _title: Label
var _description: Label
var _stats: Label
var _cost_row: HBoxContainer
var _building_buttons: Dictionary[StringName, Button] = {}
var _building_group := ButtonGroup.new()
var _synced_def: BuildingDef
var _shown_def: BuildingDef
var _storage_revision: int = -1
var _timer: float = 0.0


func setup(tools: ToolController, world: GameWorld) -> void:
	_tools = tools
	_world = world
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
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		var sample := Registry.buildings_in_category(i as BuildingDef.Category)
		if not sample.is_empty():
			b.icon = ArtRegistry.get_building_texture(sample[0])
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
	# Информация фиксированной высоты: иначе при наведении панель меняет размер
	# и кнопки уезжают из-под курсора.
	var info := UiUtil.vbox(6)
	info.custom_minimum_size = Vector2(0, INFO_HEIGHT)
	root.add_child(info)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 18)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.add_child(_title)
	_description = Label.new()
	_description.theme_type_variation = &"DimLabel"
	_description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(COLUMNS * (BUTTON_SIZE + 4), 0)
	info.add_child(_description)
	_stats = Label.new()
	_stats.theme_type_variation = &"DimLabel"
	_stats.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stats.add_theme_color_override("font_color", UiTheme.AQUA)
	info.add_child(_stats)
	_cost_row = UiUtil.hbox(10)
	info.add_child(_cost_row)

	tools.mode_changed.connect(_sync_with_tool)
	_select_category(_category)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	if _world.core_storage.revision != _storage_revision:
		_storage_revision = _world.core_storage.revision
		_update_affordability()
		if _shown_def != null:
			_show_cost(_shown_def)


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
		b.focus_mode = Control.FOCUS_NONE
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
	_refresh_pressed()
	_update_affordability()
	_show_selected_info()


func _on_building_pressed(def: BuildingDef, button: Button) -> void:
	if button.button_pressed:
		_tools.select_building(def)
	else:
		_tools.clear_tool()


func _sync_with_tool() -> void:
	var def: BuildingDef = _tools.place_def if _tools.mode == ToolController.Mode.PLACE else null
	if def != _synced_def:
		_synced_def = def
		if def != null and def.player_buildable and def.category != _category:
			_select_category(def.category)
			return
	_refresh_pressed()
	_show_selected_info()


func _refresh_pressed() -> void:
	var selected_id: StringName = _tools.place_def.id if (_tools.mode == ToolController.Mode.PLACE and _tools.place_def != null) else &""
	for id in _building_buttons:
		_building_buttons[id].set_pressed_no_signal(id == selected_id)


func _update_affordability() -> void:
	for id in _building_buttons:
		var def := Registry.get_building(id)
		var affordable := _world.sandbox or _world.core_storage.can_afford(def.cost)
		_building_buttons[id].modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.45)


func _show_info(def: BuildingDef) -> void:
	_shown_def = def
	_title.text = "%s  (%d×%d)" % [tr(def.name_key), def.size, def.size]
	_description.text = tr(def.description_key)
	_stats.text = "\n".join(def.get_stat_lines())
	_stats.visible = not _stats.text.is_empty()
	_show_cost(def)


func _show_cost(def: BuildingDef) -> void:
	for child in _cost_row.get_children():
		child.queue_free()
	if _world.sandbox or def.cost.is_empty():
		var free_label := UiUtil.label("BUILD_COST_FREE", &"DimLabel")
		_cost_row.add_child(free_label)
		return
	for stack in def.cost:
		var cell := UiUtil.hbox(3)
		var icon := TextureRect.new()
		icon.texture = ArtRegistry.get_item_icon(stack.item)
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(icon)
		var amount := Label.new()
		amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		amount.text = str(stack.amount)
		var enough := _world.core_storage.get_count(stack.item.index) >= stack.amount
		amount.add_theme_color_override("font_color", UiTheme.FG if enough else UiTheme.RED)
		cell.add_child(amount)
		_cost_row.add_child(cell)


func _show_selected_info() -> void:
	if _tools.mode == ToolController.Mode.PLACE and _tools.place_def != null:
		_show_info(_tools.place_def)
	else:
		_shown_def = null
		_title.text = tr(CATEGORY_KEYS[_category])
		_description.text = tr("BUILD_MENU_HINT")
		_stats.visible = false
		for child in _cost_row.get_children():
			child.queue_free()


func _tooltip_for(def: BuildingDef) -> String:
	var lines := PackedStringArray(["%s  (%d×%d)" % [tr(def.name_key), def.size, def.size], tr(def.description_key)])
	lines.append_array(def.get_stat_lines())
	if not def.cost.is_empty():
		var parts := PackedStringArray()
		for stack in def.cost:
			parts.append("%d %s" % [stack.amount, tr(stack.item.name_key)])
		lines.append(tr("BUILD_COST") % ", ".join(parts))
	return "\n".join(lines)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _grid != null:
		_select_category(_category)
