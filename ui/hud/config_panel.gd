class_name ConfigPanel
extends PanelContainer
## Панель настройки выбранного здания: фильтр по предмету (сортировщики, разгрузчик)
## или связь моста (подсказка и разрыв связи). Изменения идут через GameWorld.configure.

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
	world.buildings.building_changed.connect(_on_building_changed)


func _on_building_changed(building: Building) -> void:
	if building == _building:
		_rebuild()


func _rebuild() -> void:
	_building = _tools.selected
	for child in _content.get_children():
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
	var current: Variant = _building.get_config()
	var none := _make_button(current == null)
	none.text = "✕"
	none.tooltip_text = "CONFIG_ANY_ITEM" if _building is Unloader else "CONFIG_NO_ITEM"
	none.pressed.connect(func() -> void: _world.configure(_building, null))
	grid.add_child(none)
	for item in Registry.items:
		var b := _make_button(current is int and int(current) == item.index)
		b.icon = ArtRegistry.get_item_icon(item)
		b.expand_icon = true
		b.tooltip_text = item.name_key
		b.pressed.connect(_world.configure.bind(_building, item.index))
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
