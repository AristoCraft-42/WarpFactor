class_name InventoryWindow
extends PanelContainer
## Окно инвентаря дрона. Слева — ячейки инвентаря, справа — ручной крафт (открывается по E)
## или содержимое выбранного здания: склада, завода, бура (открывается кликом по зданию).
##
## Ячейки здания: ЛКМ — забрать стопку, ПКМ — половину, Shift+ЛКМ — всё этого предмета.
## Ячейки инвентаря при открытом здании: ЛКМ — положить стопку, ПКМ — половину, Shift+ЛКМ — всё.
## Без здания ЛКМ по постройке в инвентаре берёт её в руку.
## Рецепты: ЛКМ — скрафтить 1, ПКМ — 5, Shift+ЛКМ — сколько хватает сырья.

enum Mode { CRAFT, BUILDING }

const CATEGORY_KEYS := ["CATEGORY_EXTRACTION", "CATEGORY_TRANSPORT", "CATEGORY_PRODUCTION", "CATEGORY_STORAGE", "CATEGORY_DEFENSE"]
const INVENTORY_COLUMNS := 10
const RIGHT_COLUMNS := 8
const RIGHT_MIN_SIZE := Vector2(8 * (ItemSlot.SIZE + 4), 330)
const REFRESH := 0.2
const CRAFT_LIMIT := 99
## Сдвиг окна влево от центра экрана, чтобы не перекрывать меню строительства справа.
const SHIFT_LEFT := 260.0

var mode: Mode = Mode.CRAFT

var _tools: ToolController
var _world: GameWorld
var _drone: Drone
var _inventory_slots: Array[ItemSlot] = []
## Подсказка окна здания: у турели своя (патроны только кладутся).
var _take_hint: Label
var _slots_label: Label
var _right_title: Label
var _craft_box: VBoxContainer
var _category_buttons: Array[Button] = []
var _recipe_grid: GridContainer
var _recipe_slots: Dictionary[int, ItemSlot] = {}
var _category: int = BuildingDef.Category.TRANSPORT
var _building_box: VBoxContainer
var _building_grid: GridContainer
var _building_slots: Array[ItemSlot] = []
var _building_info: Label
var _building: Building
var _inventory_revision: int = -1
var _timer: float = 0.0


func setup(tools: ToolController, world: GameWorld) -> void:
	_tools = tools
	_world = world
	_drone = world.drone
	theme_type_variation = &"CardPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left -= SHIFT_LEFT
	offset_right -= SHIFT_LEFT

	var root := UiUtil.hbox(18)
	add_child(root)

	# Инвентарь дрона.
	var left := UiUtil.vbox(8)
	root.add_child(left)
	var left_header := UiUtil.hbox(10)
	left.add_child(left_header)
	var title := UiUtil.label("INVENTORY_TITLE", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 18)
	left_header.add_child(title)
	left_header.add_child(UiUtil.spacer())
	_slots_label = Label.new()
	_slots_label.theme_type_variation = &"DimLabel"
	_slots_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	left_header.add_child(_slots_label)
	var grid := GridContainer.new()
	grid.columns = INVENTORY_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	for i in _drone.inventory.size():
		var slot := ItemSlot.new()
		slot.slot_clicked.connect(_on_inventory_slot_clicked.bind(i))
		grid.add_child(slot)
		_inventory_slots.append(slot)
	var hint := UiUtil.label("INVENTORY_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(INVENTORY_COLUMNS * (ItemSlot.SIZE + 4), 0)
	left.add_child(hint)

	# Правая часть: крафт или содержимое здания.
	var right := UiUtil.vbox(8)
	right.custom_minimum_size = RIGHT_MIN_SIZE
	root.add_child(right)
	var right_header := UiUtil.hbox(10)
	right.add_child(right_header)
	_right_title = Label.new()
	_right_title.theme_type_variation = &"HeaderLabel"
	_right_title.add_theme_font_size_override("font_size", 18)
	_right_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_right_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_header.add_child(_right_title)
	var close := UiUtil.button("✕", close_window)
	close.focus_mode = Control.FOCUS_NONE
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	right_header.add_child(close)

	_craft_box = UiUtil.vbox(8)
	right.add_child(_craft_box)
	var tabs := UiUtil.hbox(4)
	_craft_box.add_child(tabs)
	var group := ButtonGroup.new()
	for i in CATEGORY_KEYS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = CATEGORY_KEYS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_select_category.bind(i))
		tabs.add_child(b)
		_category_buttons.append(b)
	_recipe_grid = GridContainer.new()
	_recipe_grid.columns = RIGHT_COLUMNS
	_recipe_grid.add_theme_constant_override("h_separation", 4)
	_recipe_grid.add_theme_constant_override("v_separation", 4)
	_craft_box.add_child(_recipe_grid)
	var craft_hint := UiUtil.label("CRAFT_HINT", &"DimLabel")
	craft_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	craft_hint.custom_minimum_size = Vector2(RIGHT_MIN_SIZE.x, 0)
	_craft_box.add_child(craft_hint)

	_building_box = UiUtil.vbox(8)
	right.add_child(_building_box)
	_building_grid = GridContainer.new()
	_building_grid.columns = RIGHT_COLUMNS
	_building_grid.add_theme_constant_override("h_separation", 4)
	_building_grid.add_theme_constant_override("v_separation", 4)
	_building_box.add_child(_building_grid)
	_building_info = Label.new()
	_building_info.theme_type_variation = &"DimLabel"
	_building_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_building_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_building_info.custom_minimum_size = Vector2(RIGHT_MIN_SIZE.x, 0)
	_building_box.add_child(_building_info)
	_take_hint = UiUtil.label("BUILDING_WINDOW_HINT", &"DimLabel")
	_take_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_take_hint.custom_minimum_size = Vector2(RIGHT_MIN_SIZE.x, 0)
	_building_box.add_child(_take_hint)

	tools.selection_changed.connect(_on_selection_changed)
	_select_category(_category)
	_apply_mode()


func is_open() -> bool:
	return visible


## Смена активного мира: окно здания закрывается (здание осталось в другом мире).
func set_world(world: GameWorld) -> void:
	if mode == Mode.BUILDING:
		visible = false
		_building = null
	_world = world


func open_craft() -> void:
	if mode == Mode.BUILDING and _tools.selected != null:
		_tools.select(null)
	mode = Mode.CRAFT
	_building = null
	visible = true
	_apply_mode()
	_refresh_all()


func toggle_craft() -> void:
	if visible and mode == Mode.CRAFT:
		close_window()
	else:
		open_craft()


func close_window() -> void:
	if not visible:
		return
	visible = false
	if mode == Mode.BUILDING and _tools.selected != null:
		_tools.select(null)
	_building = null


func _unhandled_input(event: InputEvent) -> void:
	if _tools == null or not _tools.input_enabled:
		return
	if event.is_action_pressed("inventory"):
		toggle_craft()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("cancel"):
		close_window()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if _drone.inventory.revision != _inventory_revision:
		_inventory_revision = _drone.inventory.revision
		_refresh_inventory()
		if mode == Mode.CRAFT:
			_refresh_recipes()
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		if mode == Mode.BUILDING:
			_refresh_building()


# --- Режимы ---

func _on_selection_changed() -> void:
	var b := _tools.selected
	if b != null and b.world != null and (b.get_inventory() != null or b.accepts_player_items() or b is Drill):
		mode = Mode.BUILDING
		_building = b
		visible = true
		_apply_mode()
		_rebuild_building_slots()
		_refresh_all()
	elif mode == Mode.BUILDING and visible:
		visible = false
		_building = null


func _apply_mode() -> void:
	_craft_box.visible = mode == Mode.CRAFT
	_building_box.visible = mode == Mode.BUILDING
	if mode == Mode.CRAFT:
		_right_title.text = tr("CRAFT_TITLE")
	elif _building != null:
		_right_title.text = tr(_building.def.name_key)
		_take_hint.text = "TURRET_WINDOW_HINT" if _building is Turret else "BUILDING_WINDOW_HINT"


func _refresh_all() -> void:
	_inventory_revision = _drone.inventory.revision
	_refresh_inventory()
	if mode == Mode.CRAFT:
		_refresh_recipes()
	else:
		_refresh_building()


# --- Инвентарь дрона ---

func _refresh_inventory() -> void:
	var inventory := _drone.inventory
	for i in _inventory_slots.size():
		_inventory_slots[i].set_stack(inventory.slot_items[i], inventory.slot_counts[i])
	_slots_label.text = tr("INVENTORY_SLOTS") % [inventory.used_slots(), inventory.size()]


func _on_inventory_slot_clicked(button: MouseButton, shift: bool, slot: int) -> void:
	var inventory := _drone.inventory
	var item := inventory.slot_items[slot]
	if item < 0:
		return
	if mode == Mode.BUILDING and _building != null and _building.accepts_player_items():
		var amount := inventory.count(item) if shift else inventory.slot_counts[slot]
		if button == MOUSE_BUTTON_RIGHT:
			amount = maxi(1, inventory.slot_counts[slot] / 2)
		_world.player_put(_building, item, amount)
		_refresh_all()
		return
	# Постройку из инвентаря — сразу в руку.
	var def := Registry.items[item].building
	if def != null and button == MOUSE_BUTTON_LEFT:
		close_window()
		_tools.select_building(def)


# --- Крафт ---

func _select_category(category: int) -> void:
	_category = category
	for i in _category_buttons.size():
		_category_buttons[i].set_pressed_no_signal(i == category)
	for child in _recipe_grid.get_children():
		_recipe_grid.remove_child(child)
		child.queue_free()
	_recipe_slots.clear()
	for recipe in Registry.hand_recipes:
		var def := recipe.output.building
		if def == null or def.category != category:
			continue
		var slot := ItemSlot.new()
		slot.slot_clicked.connect(_on_recipe_clicked.bind(recipe))
		_recipe_grid.add_child(slot)
		_recipe_slots[recipe.output.index] = slot
	_refresh_recipes()


func _refresh_recipes() -> void:
	var queue := _drone.crafting
	for item in _recipe_slots:
		var recipe := Registry.get_hand_recipe(item)
		var slot := _recipe_slots[item]
		var craftable := CRAFT_LIMIT if _world.creative else queue.max_craftable(recipe, CRAFT_LIMIT)
		slot.set_stack(item, craftable, true)
		slot.modulate = Color.WHITE if craftable > 0 else Color(1, 1, 1, 0.45)
		slot.tooltip_text = _recipe_tooltip(recipe, craftable)


func _on_recipe_clicked(button: MouseButton, shift: bool, recipe: HandRecipe) -> void:
	var count := 1
	if button == MOUSE_BUTTON_RIGHT:
		count = 5
	elif shift:
		count = CRAFT_LIMIT
	if _world.creative:
		_drone.inventory.add(recipe.output.index, recipe.amount * count)
		return
	var queued := _drone.crafting.enqueue(recipe, count)
	if queued == 0:
		Events.toast(tr("TOAST_CANNOT_CRAFT") % tr(recipe.output.name_key), Events.ToastKind.WARNING)
	_refresh_recipes()


func _recipe_tooltip(recipe: HandRecipe, craftable: int) -> String:
	var lines := PackedStringArray()
	var header := tr(recipe.output.name_key)
	if recipe.amount > 1:
		header += " ×%d" % recipe.amount
	lines.append(header)
	var parts := PackedStringArray()
	for stack in recipe.ingredients:
		parts.append("%s %d/%d" % [tr(stack.item.name_key), _drone.inventory.count(stack.item.index), stack.amount])
	lines.append(tr("CRAFT_INGREDIENTS") % ", ".join(parts))
	lines.append(tr("CRAFT_TIME") % recipe.get_seconds())
	lines.append(tr("CRAFT_IN_INVENTORY") % _drone.inventory.count(recipe.output.index))
	lines.append(tr("CRAFT_AVAILABLE") % craftable)
	return "\n".join(lines)


# --- Здание ---

func _rebuild_building_slots() -> void:
	for child in _building_grid.get_children():
		_building_grid.remove_child(child)
		child.queue_free()
	_building_slots.clear()
	if _building == null:
		return
	var inventory := _building.get_inventory()
	var count := inventory.size() if inventory != null else RIGHT_COLUMNS
	for i in count:
		var slot := ItemSlot.new()
		slot.slot_clicked.connect(_on_building_slot_clicked.bind(i))
		_building_grid.add_child(slot)
		_building_slots.append(slot)


func _refresh_building() -> void:
	if _building == null or _building.world == null:
		return
	var inventory := _building.get_inventory()
	if inventory != null:
		for i in _building_slots.size():
			_building_slots[i].set_stack(inventory.slot_items[i], inventory.slot_counts[i])
	else:
		var stacks := _building.get_player_stacks()
		for i in _building_slots.size():
			if i < stacks.size():
				_building_slots[i].set_stack(stacks[i].x, stacks[i].y)
			else:
				_building_slots[i].set_stack(-1, 0)
	var lines := _building.get_info_lines()
	_building_info.text = "\n".join(lines)


func _on_building_slot_clicked(button: MouseButton, shift: bool, slot: int) -> void:
	if _building == null or _building.world == null:
		return
	var view := _building_slots[slot]
	if view.item < 0:
		return
	var amount := view.amount
	if shift:
		amount = 1 << 30
	elif button == MOUSE_BUTTON_RIGHT:
		amount = maxi(1, view.amount / 2)
	_world.player_take(_building, view.item, amount)
	if _world.last_error == GameWorld.ActionError.INVENTORY_FULL:
		Events.toast(tr("TOAST_INVENTORY_FULL"), Events.ToastKind.WARNING)
	_refresh_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _recipe_grid != null:
		_apply_mode()
		if visible:
			_refresh_all()
