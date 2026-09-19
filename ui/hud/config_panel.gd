class_name ConfigPanel
extends PanelContainer
## Панель настройки выбранного здания: фильтр по предмету (сортировщик, разгрузчик),
## переключатель инверсии (сортировщик), связь моста (подсказка и разрыв)
## или приоритетные стороны маршрутизатора (вход и выход).
## Изменения идут через GameWorld.configure.

const ITEM_COLUMNS := 10
const ITEM_BUTTON := 40

var _tools: ToolController
var _world: GameWorld
var _building: Building
var _content: VBoxContainer
var _title: Label


func setup(tools: ToolController, world: GameWorld) -> void:
	_tools = tools
	_world = world
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := UiUtil.vbox(8)
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 18)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_title)
	_content = UiUtil.vbox(6)
	column.add_child(_content)
	tools.selection_changed.connect(_rebuild)
	set_world(world)


func set_world(world: GameWorld) -> void:
	if world == _world and world.buildings.building_changed.is_connected(_on_building_changed):
		return
	if _world != null and _world.buildings != null and _world.buildings.building_changed.is_connected(_on_building_changed):
		_world.buildings.building_changed.disconnect(_on_building_changed)
	_world = world
	_world.buildings.building_changed.connect(_on_building_changed)
	_rebuild()


func _on_building_changed(building: Building) -> void:
	# Отложенно: изменение приходит из обработчика кнопки этой же панели.
	if building == _building:
		_rebuild.call_deferred()


func _rebuild() -> void:
	_building = _tools.selected
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if _building == null or _building.world == null or _building.get_config_kind() == Building.ConfigKind.NONE:
		visible = false
		return
	visible = true
	_title.text = tr(_building.def.name_key)
	match _building.get_config_kind():
		Building.ConfigKind.ITEM:
			_build_item_picker()
		Building.ConfigKind.BRIDGE:
			_build_bridge_info()
		Building.ConfigKind.ROUTER:
			_build_router_sides()
		Building.ConfigKind.RECIPE:
			_build_recipe_picker()
		Building.ConfigKind.MODE:
			if _building is Lift:
				_build_lift_direction()
		Building.ConfigKind.SOURCE:
			_build_creative_source()
	if _building.supports_inversion():
		_build_inversion_toggle()


func _build_item_picker() -> void:
	var hint_key := "CONFIG_UNLOADER_HINT" if _building is Unloader else "CONFIG_SORTER_HINT"
	var hint := UiUtil.label(hint_key, &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	_content.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = ITEM_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	var current := _building.get_display_item()
	var none := _make_button(current < 0)
	none.text = "✕"
	none.tooltip_text = "CONFIG_ANY_ITEM" if _building is Unloader else "CONFIG_NO_ITEM"
	none.pressed.connect(func() -> void: _world.configure(_building, null))
	grid.add_child(none)
	for item in Registry.items:
		var b := _make_button(current == item.index)
		b.icon = ArtRegistry.get_item_icon(item)
		b.expand_icon = true
		b.tooltip_text = item.name_key
		b.pressed.connect(_world.configure.bind(_building, item.index))
		grid.add_child(b)


## Творческий блок: что выдавать (предмет или жидкость) и ступень скорости.
func _build_creative_source() -> void:
	var block := _building as CreativeBlock
	if block == null:
		return
	var def := block.get_creative_def()
	var hint := UiUtil.label("CONFIG_CREATIVE_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	_content.add_child(hint)
	if def.kind == CreativeBlockDef.Kind.ITEM or def.kind == CreativeBlockDef.Kind.FLUID:
		var grid := GridContainer.new()
		grid.columns = ITEM_COLUMNS
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		_content.add_child(grid)
		if def.kind == CreativeBlockDef.Kind.ITEM:
			for item in Registry.items:
				var b := _make_button(block.pick == item.index)
				b.icon = ArtRegistry.get_item_icon(item)
				b.expand_icon = true
				b.tooltip_text = item.name_key
				b.pressed.connect(func() -> void: _world.configure(block, Vector2i(item.index, block.rate_index)))
				grid.add_child(b)
		else:
			for fluid in Registry.fluids:
				var b := _make_button(block.pick == fluid.index)
				b.tooltip_text = fluid.name_key
				b.text = tr(fluid.name_key).substr(0, 1)
				b.add_theme_color_override("font_color", fluid.color)
				b.pressed.connect(func() -> void: _world.configure(block, Vector2i(fluid.index, block.rate_index)))
				grid.add_child(b)
	# Ступени скорости.
	var row := UiUtil.hbox(4)
	_content.add_child(row)
	var minus := UiUtil.button("−", func() -> void: _world.configure(block, Vector2i(block.pick, block.rate_index - 1)))
	minus.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	minus.focus_mode = Control.FOCUS_NONE
	minus.disabled = block.rate_index <= 0
	row.add_child(minus)
	var value := Label.new()
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.text = tr(_rate_key(def.kind)) % block.get_rate()
	row.add_child(value)
	var plus := UiUtil.button("+", func() -> void: _world.configure(block, Vector2i(block.pick, block.rate_index + 1)))
	plus.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	plus.focus_mode = Control.FOCUS_NONE
	plus.disabled = block.rate_index >= def.rates.size() - 1
	row.add_child(plus)


static func _rate_key(kind: CreativeBlockDef.Kind) -> String:
	match kind:
		CreativeBlockDef.Kind.POWER:
			return "CONFIG_RATE_POWER"
		CreativeBlockDef.Kind.FLUID:
			return "CONFIG_RATE_FLUID"
		CreativeBlockDef.Kind.VOID:
			return "CONFIG_RATE_VOID"
	return "CONFIG_RATE_ITEM"


## Переключатель инверсии сортировщика: «выбранное в стороны».
func _build_inversion_toggle() -> void:
	var toggle := CheckButton.new()
	toggle.text = "CONFIG_INVERT_SORTER"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.button_pressed = _building.is_inverted()
	var building := _building
	toggle.toggled.connect(func(pressed: bool) -> void: _world.configure(building, pressed))
	_content.add_child(toggle)
	var hint := UiUtil.label("CONFIG_INVERT_SORTER_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	_content.add_child(hint)


## Приоритетные стороны маршрутизатора: для входа и выхода — «нет» или одна из четырёх сторон.
## Стрелки показывают стороны в мире; хранится сторона относительно поворота здания.
func _build_router_sides() -> void:
	var router := _building as Router
	var hint := UiUtil.label("CONFIG_ROUTER_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	_content.add_child(hint)
	for is_input in [true, false]:
		var row := UiUtil.hbox(6)
		_content.add_child(row)
		var caption := UiUtil.label("CONFIG_ROUTER_IN" if is_input else "CONFIG_ROUTER_OUT")
		caption.custom_minimum_size = Vector2(170, 0)
		row.add_child(caption)
		var current: int = router.priority_in if is_input else router.priority_out
		for relative in [Router.NO_SIDE, 0, 1, 2, 3]:
			var b := _make_button(current == relative)
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = "✕" if relative == Router.NO_SIDE else ["→", "↓", "←", "↑"][router.world_side(relative)]
			b.tooltip_text = tr("CONFIG_ROUTER_NONE") if relative == Router.NO_SIDE else ""
			var in_side: int = relative if is_input else router.priority_in
			var out_side: int = router.priority_out if is_input else relative
			b.pressed.connect(func() -> void:
				var value: Variant = null
				if in_side != Router.NO_SIDE or out_side != Router.NO_SIDE:
					value = {"in": in_side, "out": out_side}
				_world.configure(router, value))
			row.add_child(b)


## Направление лифта: вниз (площадка → этаж) или вверх (этаж → площадка).
func _build_lift_direction() -> void:
	var lift := _building as Lift
	var hint := UiUtil.label("CONFIG_LIFT_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	_content.add_child(hint)
	var row := UiUtil.hbox(6)
	_content.add_child(row)
	for value in [Lift.Direction.DOWN, Lift.Direction.UP]:
		var b := UiUtil.button("CONFIG_LIFT_DOWN" if value == Lift.Direction.DOWN else "CONFIG_LIFT_UP",
			func() -> void: _world.configure(lift, value))
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = lift.direction == value
		row.add_child(b)


## Выбор рецепта сборщика: иконки результатов; закрытые исследованием недоступны.
func _build_recipe_picker() -> void:
	var crafter := _building as Crafter
	var hint := UiUtil.label("CONFIG_RECIPE_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	_content.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = ITEM_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	var current := crafter.get_recipe()
	for recipe in crafter.get_crafter_def().recipes:
		var main := recipe.get_main_output()
		if main == null:
			continue
		var b := _make_button(recipe == current)
		b.icon = ArtRegistry.get_item_icon(main.item)
		b.expand_icon = true
		var unlocked := _world.research == null or _world.research.is_recipe_unlocked(recipe)
		var tip := PackedStringArray(["%s ×%d" % [tr(main.item.name_key), main.amount]])
		var parts := PackedStringArray()
		for c in recipe.consumes:
			for s in c.display_stacks():
				parts.append("%s ×%d" % [tr(s.item.name_key), s.amount])
		tip.append(tr("CRAFT_INGREDIENTS") % ", ".join(parts))
		tip.append(tr("CRAFT_TIME") % recipe.craft_time)
		if not unlocked:
			tip.append(tr("CRAFT_LOCKED") % tr(Registry.get_recipe_research(recipe).name_key))
			b.disabled = true
		b.tooltip_text = "\n".join(tip)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.pressed.connect(_world.configure.bind(crafter, recipe.id))
		grid.add_child(b)


func _build_bridge_info() -> void:
	var bridge := _building as BridgeConveyor
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ITEM_COLUMNS * (ITEM_BUTTON + 4), 0)
	hint.text = tr("CONFIG_BRIDGE_HINT") % bridge.get_range()
	_content.add_child(hint)
	var unlink := UiUtil.button("CONFIG_BRIDGE_UNLINK", func() -> void: _world.configure(bridge, null))
	unlink.focus_mode = Control.FOCUS_NONE
	unlink.disabled = bridge.get_link_target() == null
	_content.add_child(unlink)


func _make_button(pressed: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"SlotButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(ITEM_BUTTON, ITEM_BUTTON)
	b.toggle_mode = true
	b.button_pressed = pressed
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _content != null and visible:
		_rebuild()
