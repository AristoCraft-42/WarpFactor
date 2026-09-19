class_name BuildMenu
extends PanelContainer
## Панель строительства: вкладки категорий и сетка кнопок зданий. Описание, характеристики и рецепт —
## в подсказке при наведении на кнопку, отдельной панели описания нет (экономит место).
## Вкладки переключаются свободно, даже когда здание уже в руке. Автоматически раздел меняется
## только если сменилось само выбранное здание (например, пипеткой).
## На кнопке — сколько таких построек в инвентаре дрона; без построек кнопка приглушена.
## ЛКМ — взять в руку, ПКМ — скрафтить одну, Shift+ПКМ — пять.
## Постройки, ещё не открытые исследованием, затемнены; в подсказке — нужное исследование.

const CATEGORY_KEYS := ["CATEGORY_TRANSPORT", "CATEGORY_PRODUCTION", "CATEGORY_POWER", "CATEGORY_DEFENSE"]
const COLUMNS := 8
const ROWS := 2
const BUTTON_SIZE := 54
const REFRESH_INTERVAL := 0.2

var _tools: ToolController
var _world: GameWorld
var _category: int = BuildingDef.Category.TRANSPORT
var _category_buttons: Array[Button] = []
var _grid: GridContainer
var _building_buttons: Dictionary[StringName, Button] = {}
var _count_labels: Dictionary[StringName, Label] = {}
var _building_group := ButtonGroup.new()
var _synced_def: BuildingDef
var _inventory_revision: int = -1
## Число завершённых исследований при последнем обновлении (открытые постройки перестают быть тусклыми).
var _research_done: int = -1
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
		b.add_theme_font_size_override("font_size", 13)
		var sample := Registry.buildings_in_category(i as BuildingDef.Category, _world.creative)
		if not sample.is_empty():
			b.icon = ArtRegistry.get_building_texture(sample[0])
			b.add_theme_constant_override("icon_max_width", 18)
		b.pressed.connect(_select_category.bind(i))
		tabs.add_child(b)
		_category_buttons.append(b)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	# Постоянная высота: панель не прыгает при смене вкладки.
	_grid.custom_minimum_size = Vector2(COLUMNS * (BUTTON_SIZE + 4), ROWS * (BUTTON_SIZE + 4))
	root.add_child(_grid)

	tools.mode_changed.connect(_sync_with_tool)
	_select_category(_category)


func set_world(world: GameWorld) -> void:
	_world = world
	_update_counts()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	var inventory := _world.drone.inventory
	var research_done := _world.research.done.size() if _world.research != null else 0
	if inventory.revision != _inventory_revision or research_done != _research_done:
		_inventory_revision = inventory.revision
		_research_done = research_done
		_update_counts()


func _select_category(category: int) -> void:
	_category = category
	# set_pressed_no_signal не отжимает остальные кнопки группы — синхронизируем все.
	for i in _category_buttons.size():
		_category_buttons[i].set_pressed_no_signal(i == category)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_building_buttons.clear()
	_count_labels.clear()
	for def in Registry.buildings_in_category(category as BuildingDef.Category, _world.creative):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _building_group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		b.icon = ArtRegistry.get_building_texture(def)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.theme_type_variation = &"SlotButton"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.pressed.connect(_on_building_pressed.bind(def, b))
		b.gui_input.connect(_on_building_input.bind(def, b))
		var count := Label.new()
		count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.offset_right = -3
		count.offset_bottom = 1
		count.add_theme_font_size_override("font_size", 13)
		count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		count.add_theme_constant_override("outline_size", 4)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(count)
		_grid.add_child(b)
		_building_buttons[def.id] = b
		_count_labels[def.id] = count
	_refresh_pressed()
	_update_counts()


func _on_building_pressed(def: BuildingDef, button: Button) -> void:
	if button.button_pressed:
		_tools.select_building(def)
	else:
		_tools.clear_tool()


## ПКМ по кнопке — скрафтить (Shift — пять штук).
func _on_building_input(event: InputEvent, def: BuildingDef, button: Button) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	button.accept_event()
	if def.item == null:
		return
	var recipe := Registry.get_hand_recipe(def.item.index)
	if recipe == null:
		return
	if not _is_unlocked(def):
		Events.toast(tr("TOAST_LOCKED") % tr(Registry.get_building_research(def).name_key), Events.ToastKind.WARNING)
		return
	var count := 5 if mb.shift_pressed else 1
	if _world.creative:
		_world.drone.inventory.add(def.item.index, recipe.amount * count)
	elif _world.drone.crafting.enqueue(recipe, count) == 0:
		Events.toast(tr("TOAST_CANNOT_CRAFT") % tr(def.name_key), Events.ToastKind.WARNING)


func _sync_with_tool() -> void:
	var def: BuildingDef = _tools.place_def if _tools.mode == ToolController.Mode.PLACE else null
	if def != _synced_def:
		_synced_def = def
		if def != null and def.player_buildable and def.category != _category:
			_select_category(def.category)
			return
	_refresh_pressed()


func _refresh_pressed() -> void:
	var selected_id: StringName = _tools.place_def.id if (_tools.mode == ToolController.Mode.PLACE and _tools.place_def != null) else &""
	for id in _building_buttons:
		_building_buttons[id].set_pressed_no_signal(id == selected_id)


func _update_counts() -> void:
	var inventory := _world.drone.inventory
	for id in _building_buttons:
		var def := Registry.get_building(id)
		var owned := inventory.count(def.item.index) if def.item != null else 0
		_count_labels[id].text = str(owned) if owned > 0 and not _world.creative else ""
		var available := _world.creative or owned > 0
		if not _is_unlocked(def):
			_building_buttons[id].modulate = Color(0.55, 0.45, 0.45, 0.6)
		else:
			_building_buttons[id].modulate = Color.WHITE if available else Color(1, 1, 1, 0.45)
		_building_buttons[id].tooltip_text = _tooltip_for(def, owned)


func _tooltip_for(def: BuildingDef, owned: int) -> String:
	var lines := PackedStringArray(["%s  (%d×%d)" % [tr(def.name_key), def.size, def.size], tr(def.description_key)])
	if not _is_unlocked(def):
		lines.append(tr("CRAFT_LOCKED") % tr(Registry.get_building_research(def).name_key))
	lines.append_array(def.get_stat_lines())
	lines.append(tr("STAT_HEALTH") % roundi(def.get_max_health()))
	if not def.solid:
		lines.append(tr("STAT_WALKABLE"))
	if not def.cost.is_empty():
		var inventory := _world.drone.inventory
		var parts := PackedStringArray()
		for stack in def.cost:
			parts.append("%s %d/%d" % [tr(stack.item.name_key), inventory.count(stack.item.index), stack.amount])
		lines.append(tr("CRAFT_INGREDIENTS") % ", ".join(parts))
	if not _world.creative:
		lines.append(tr("CRAFT_IN_INVENTORY") % owned)
	lines.append(tr("BUILD_BUTTON_HINT"))
	return "\n".join(lines)


func _is_unlocked(def: BuildingDef) -> bool:
	return _world.research == null or _world.research.is_building_unlocked(def)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _grid != null:
		_select_category(_category)
