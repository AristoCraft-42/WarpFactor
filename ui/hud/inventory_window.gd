class_name InventoryWindow
extends PanelContainer
## Окно инвентаря дрона. Слева — ячейки инвентаря, справа — ручной крафт (открывается по E)
## или содержимое выбранного здания (открывается кликом по зданию): у склада — сетка ячеек,
## у остальных — разделы здания (Building.get_window_sections): отдельные ячейки сырья, топлива
## и продукта, полоски прогресса, питания, жидкостей и мощности.
##
## Ячейки здания: ЛКМ — забрать стопку, ПКМ — половину, Shift+ЛКМ — всё этого предмета.
## Ячейки инвентаря при открытом здании: ЛКМ — положить стопку, ПКМ — половину, Shift+ЛКМ — всё.
## Без здания ЛКМ по постройке в инвентаре берёт её в руку.
## Рецепты: ЛКМ — скрафтить 1, ПКМ — 5, Shift+ЛКМ — сколько хватает сырья.
## Первая вкладка — компоненты (шестерни, кабель, наборы, патроны), остальные — постройки по разделам.
## Закрытые исследованием рецепты затемнены.

enum Mode { CRAFT, BUILDING }

const CATEGORY_KEYS := ["CRAFT_COMPONENTS", "CATEGORY_TRANSPORT", "CATEGORY_PRODUCTION", "CATEGORY_POWER", "CATEGORY_DEFENSE"]
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
## Вкладка крафта: 0 — компоненты, дальше — раздел построек + 1.
var _category: int = 0
var _building_box: VBoxContainer
var _building_grid: GridContainer
var _building_slots: Array[ItemSlot] = []
var _building_info: Label
## Разделы здания: контейнер, подпись набора разделов (перестраиваются при её смене) и элементы по разделам.
var _sections_box: VBoxContainer
var _sections_signature: String = ""
var _section_views: Array[Dictionary] = []
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
	_sections_box = UiUtil.vbox(8)
	_building_box.add_child(_sections_box)
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
	# Локальный игрок мог смениться — окно показывает инвентарь его дрона.
	if world.drone != null and world.drone != _drone:
		_drone = world.drone
		_inventory_revision = -1


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
	if b != null and b.world != null and (b.get_inventory() != null or not b.get_window_sections().is_empty()):
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
		_take_hint.visible = _building.accepts_player_items() or _building.get_inventory() != null


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
		_world.submit(Command.Kind.PUT, {"id": _building.id, "item": item, "amount": amount})
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
		if category == 0:
			if def != null:
				continue
		elif def == null or def.category != category - 1:
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
		var unlocked := queue.is_available(recipe)
		var craftable := (CRAFT_LIMIT if _world.creative else queue.max_craftable(recipe, CRAFT_LIMIT)) if unlocked else 0
		slot.set_stack(item, craftable, true)
		if not unlocked:
			slot.modulate = Color(0.55, 0.45, 0.45, 0.6)
		else:
			slot.modulate = Color.WHITE if craftable > 0 else Color(1, 1, 1, 0.45)
		slot.tooltip_text = _recipe_tooltip(recipe, craftable)


func _on_recipe_clicked(button: MouseButton, shift: bool, recipe: HandRecipe) -> void:
	var count := 1
	if button == MOUSE_BUTTON_RIGHT:
		count = 5
	elif shift:
		count = CRAFT_LIMIT
	if not _drone.crafting.is_available(recipe):
		Events.toast(tr("TOAST_LOCKED") % _research_name(recipe), Events.ToastKind.WARNING)
		return
	if _world.creative:
		_world.submit(Command.Kind.CREATIVE_GIVE, {"item": recipe.output.index, "count": recipe.amount * count})
		return
	if _drone.crafting.max_craftable(recipe, count) == 0:
		Events.toast(tr("TOAST_CANNOT_CRAFT") % tr(recipe.output.name_key), Events.ToastKind.WARNING)
	else:
		_world.submit(Command.Kind.CRAFT, {"item": recipe.output.index, "count": count})
	_refresh_recipes()


func _recipe_tooltip(recipe: HandRecipe, craftable: int) -> String:
	var lines := PackedStringArray()
	var header := tr(recipe.output.name_key)
	if recipe.amount > 1:
		header += " ×%d" % recipe.amount
	lines.append(header)
	if not _drone.crafting.is_available(recipe):
		lines.append(tr("CRAFT_LOCKED") % _research_name(recipe))
	var parts := PackedStringArray()
	for stack in recipe.ingredients:
		parts.append("%s %d/%d" % [tr(stack.item.name_key), _drone.inventory.count(stack.item.index), stack.amount])
	lines.append(tr("CRAFT_INGREDIENTS") % ", ".join(parts))
	lines.append(tr("CRAFT_TIME") % recipe.get_seconds())
	lines.append(tr("CRAFT_IN_INVENTORY") % _drone.inventory.count(recipe.output.index))
	lines.append(tr("CRAFT_AVAILABLE") % craftable)
	return "\n".join(lines)


func _research_name(recipe: HandRecipe) -> String:
	var research := Registry.get_building_research(recipe.building) if recipe.building != null else Registry.get_recipe_research(recipe.recipe)
	return tr(research.name_key) if research != null else "—"


# --- Здание ---

func _rebuild_building_slots() -> void:
	for child in _building_grid.get_children():
		_building_grid.remove_child(child)
		child.queue_free()
	_building_slots.clear()
	_clear_sections()
	if _building == null:
		return
	var inventory := _building.get_inventory()
	_building_grid.visible = inventory != null
	if inventory == null:
		return
	for i in inventory.size():
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
		_refresh_sections(_building.get_window_sections())
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
	_world.submit(Command.Kind.TAKE, {"id": _building.id, "item": view.item, "amount": amount})
	if _world.last_error == GameWorld.ActionError.INVENTORY_FULL:
		Events.toast(tr("TOAST_INVENTORY_FULL"), Events.ToastKind.WARNING)
	_refresh_all()


# --- Разделы здания ---

func _clear_sections() -> void:
	for child in _sections_box.get_children():
		_sections_box.remove_child(child)
		child.queue_free()
	_section_views.clear()
	_sections_signature = ""


## Подпись набора разделов: виды, заголовки и число ячеек. Совпала — обновляются только значения.
static func _signature(sections: Array[WindowSection]) -> String:
	var parts := PackedStringArray()
	for section in sections:
		var title := section.title if section.kind != WindowSection.Kind.GRAPH else ""
		parts.append("%d:%s:%d:%d" % [section.kind, title, section.stacks.size(), section.series_names.size()])
	return "|".join(parts)


func _refresh_sections(sections: Array[WindowSection]) -> void:
	var signature := _signature(sections)
	if signature != _sections_signature:
		_clear_sections()
		_sections_signature = signature
		for section in sections:
			_section_views.append(_make_section_view(section))
	for i in sections.size():
		_update_section_view(_section_views[i], sections[i])


func _make_section_view(section: WindowSection) -> Dictionary:
	var view := {}
	if section.kind == WindowSection.Kind.SLOTS:
		var box := UiUtil.vbox(4)
		_sections_box.add_child(box)
		var title := Label.new()
		title.theme_type_variation = &"DimLabel"
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.text = section.title
		box.add_child(title)
		var row := GridContainer.new()
		row.columns = RIGHT_COLUMNS
		row.add_theme_constant_override("h_separation", 4)
		row.add_theme_constant_override("v_separation", 4)
		box.add_child(row)
		var slots: Array[ItemSlot] = []
		for i in section.stacks.size():
			var slot := ItemSlot.new()
			slot.slot_clicked.connect(_on_section_slot_clicked.bind(slot, section.can_take))
			row.add_child(slot)
			slots.append(slot)
		view["slots"] = slots
	elif section.kind == WindowSection.Kind.GRAPH:
		var box := UiUtil.vbox(4)
		_sections_box.add_child(box)
		var chart := PowerChart.new()
		chart.custom_minimum_size = Vector2(RIGHT_MIN_SIZE.x, 130)
		box.add_child(chart)
		var legend := UiUtil.hbox(8)
		box.add_child(legend)
		var legend_buttons: Array[Button] = []
		for i in section.series_names.size():
			var b := Button.new()
			b.toggle_mode = true
			b.button_pressed = true
			b.focus_mode = Control.FOCUS_NONE
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.add_theme_font_size_override("font_size", 13)
			var index := i
			b.toggled.connect(func(on: bool) -> void:
				if on:
					chart.hidden_series.erase(index)
				else:
					chart.hidden_series[index] = true
				chart.queue_redraw())
			legend.add_child(b)
			legend_buttons.append(b)
		view["chart"] = chart
		view["legend"] = legend_buttons
	elif section.kind == WindowSection.Kind.TEXT:
		var label := Label.new()
		label.theme_type_variation = &"DimLabel"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(RIGHT_MIN_SIZE.x, 0)
		_sections_box.add_child(label)
		view["text"] = label
	else:
		var row := UiUtil.hbox(10)
		_sections_box.add_child(row)
		var title := Label.new()
		title.theme_type_variation = &"DimLabel"
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.text = section.title
		title.custom_minimum_size = Vector2(130, 0)
		row.add_child(title)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		bar.custom_minimum_size = Vector2(0, 22)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.11, 0.13, 0.13, 0.9)
		background.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", background)
		row.add_child(bar)
		var value := Label.new()
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		value.add_theme_constant_override("outline_size", 4)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(value)
		view["bar"] = bar
		view["fill"] = fill
		view["value"] = value
	return view


func _update_section_view(view: Dictionary, section: WindowSection) -> void:
	if view.has("slots"):
		var slots: Array[ItemSlot] = view["slots"]
		for i in slots.size():
			var stack := section.stacks[i] if i < section.stacks.size() else Vector2i(-1, 0)
			var hint := section.hints[i] if i < section.hints.size() else -1
			if stack.x >= 0 and stack.y > 0:
				slots[i].set_stack(stack.x, stack.y)
				slots[i].modulate = Color.WHITE
			elif hint >= 0:
				# Пустая ячейка с бледной иконкой того, что сюда кладётся.
				slots[i].set_stack(hint, 0, true)
				slots[i].modulate = Color(1, 1, 1, 0.35)
			else:
				slots[i].set_stack(-1, 0)
				slots[i].modulate = Color.WHITE
	elif view.has("chart"):
		(view["chart"] as PowerChart).set_data(section.series, section.series_colors, section.max_value, section.title)
		var legend: Array[Button] = view["legend"]
		for i in legend.size():
			legend[i].text = "— " + section.series_names[i] if i < section.series_names.size() else ""
			var col: Color = section.series_colors[i] if i < section.series_colors.size() else Color.WHITE
			legend[i].add_theme_color_override("font_color", col)
			legend[i].add_theme_color_override("font_pressed_color", col)
			legend[i].add_theme_color_override("font_hover_color", col.lightened(0.2))
	elif view.has("text"):
		(view["text"] as Label).text = "\n".join(section.lines)
	else:
		(view["bar"] as ProgressBar).value = section.fraction
		(view["fill"] as StyleBoxFlat).bg_color = section.color
		(view["value"] as Label).text = section.text


func _on_section_slot_clicked(button: MouseButton, shift: bool, slot: ItemSlot, can_take: bool) -> void:
	if _building == null or _building.world == null or not can_take or slot.item < 0 or slot.amount <= 0:
		return
	var amount := slot.amount
	if shift:
		amount = 1 << 30
	elif button == MOUSE_BUTTON_RIGHT:
		amount = maxi(1, slot.amount / 2)
	_world.submit(Command.Kind.TAKE, {"id": _building.id, "item": slot.item, "amount": amount})
	if _world.last_error == GameWorld.ActionError.INVENTORY_FULL:
		Events.toast(tr("TOAST_INVENTORY_FULL"), Events.ToastKind.WARNING)
	_refresh_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _recipe_grid != null:
		_apply_mode()
		_sections_signature = ""
		if visible:
			_refresh_all()
