class_name BuildingTooltip
extends PanelContainer
## Подсказка у курсора для здания под мышью (пустой рукой): название, рецепт (вход → выход),
## статус (работает / нет сырья / выход забит / нет руды), прогресс цикла и буферы.
## Появляется после короткой задержки, обновляется несколько раз в секунду.

const DELAY := 0.35
const REFRESH := 0.2
const OFFSET := Vector2(22, 22)
const ICON := 22

var _game: Game
var _building: Building
var _delay: float = 0.0
var _refresh: float = 0.0

var _title: Label
var _recipe_row: HBoxContainer
var _status: Label
var _progress: ProgressBar
var _lines: Label


func setup(game: Game) -> void:
	_game = game
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var column := UiUtil.vbox(4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = _make_label(&"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 17)
	column.add_child(_title)
	_recipe_row = UiUtil.hbox(4)
	_recipe_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_recipe_row)
	_status = _make_label(&"")
	column.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(180, 8)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_progress)
	_lines = _make_label(&"DimLabel")
	column.add_child(_lines)


func _process(delta: float) -> void:
	var tools := _game.tools
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var candidate: Building = null
	if tools.input_enabled and tools.mode == ToolController.Mode.NONE and not tools.is_dragging() and not over_ui:
		candidate = tools.hover_building
	if candidate != _building:
		_building = candidate
		_delay = DELAY
		visible = false
	if _building == null or _building.world == null:
		visible = false
		return
	if not visible:
		_delay -= delta
		if _delay > 0.0:
			return
		_rebuild()
		visible = true
	else:
		_refresh -= delta
		if _refresh <= 0.0:
			_refresh = REFRESH
			_update_dynamic()
	_place_near_mouse()


func _rebuild() -> void:
	_title.text = tr(_building.def.name_key)
	# Удаляем сразу (а не в конце кадра), чтобы панель ужалась под новое содержимое.
	for child in _recipe_row.get_children():
		_recipe_row.remove_child(child)
		child.queue_free()
	var recipe: Recipe = _building.get_recipe() if _building is Crafter else null
	_recipe_row.visible = recipe != null
	if recipe != null:
		for c in recipe.consumes:
			for s in c.display_stacks():
				_add_stack(s, -1.0)
		var arrow := _make_label(&"DimLabel")
		arrow.text = " → "
		_recipe_row.add_child(arrow)
		for p in recipe.produces:
			var stacks := p.display_stacks()
			var chances := p.display_chances()
			for i in stacks.size():
				_add_stack(stacks[i], chances[i] if i < chances.size() else -1.0)
		var time := _make_label(&"DimLabel")
		time.text = "  " + tr("TOOLTIP_CRAFT_TIME") % recipe.craft_time
		_recipe_row.add_child(time)
	_refresh = REFRESH
	_update_dynamic()


func _update_dynamic() -> void:
	var status := _building.get_status()
	var color := UiTheme.FG4
	var text := ""
	match status:
		Building.Status.WORKING:
			text = tr("STATUS_WORKING")
			color = UiTheme.GREEN
		Building.Status.IDLE:
			text = tr("STATUS_IDLE")
		Building.Status.NO_INPUT:
			text = tr("STATUS_NO_INPUT")
			if _building is Crafter:
				var missing := (_building as Crafter).get_missing_inputs()
				if not missing.is_empty():
					text = tr("STATUS_NO_INPUT_ITEMS") % ", ".join(missing)
			color = UiTheme.ORANGE
		Building.Status.OUTPUT_BLOCKED:
			text = tr("STATUS_OUTPUT_BLOCKED")
			color = UiTheme.RED
		Building.Status.NO_ORE:
			text = tr("STATUS_NO_ORE")
			color = UiTheme.RED
		Building.Status.NO_AMMO:
			text = tr("STATUS_NO_AMMO")
			color = UiTheme.RED
		Building.Status.NO_POWER:
			text = tr("STATUS_NO_POWER")
			color = UiTheme.RED
		Building.Status.NO_FUEL:
			text = tr("STATUS_NO_FUEL")
			color = UiTheme.ORANGE
		Building.Status.NO_RECIPE:
			text = tr("STATUS_NO_RECIPE")
			color = UiTheme.ORANGE
		Building.Status.NO_RESEARCH:
			text = tr("STATUS_NO_RESEARCH")
			color = UiTheme.ORANGE
	_status.visible = not text.is_empty()
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	var crafter := _building as Crafter
	_progress.visible = crafter != null and crafter.crafting
	if _progress.visible:
		_progress.value = crafter.get_progress(_building.world.simulation.tick)
	var lines := _building.get_info_lines()
	_lines.visible = not lines.is_empty()
	_lines.text = "\n".join(lines)
	reset_size()


func _add_stack(stack: ItemStack, chance: float) -> void:
	var icon := TextureRect.new()
	icon.texture = ArtRegistry.get_item_icon(stack.item)
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recipe_row.add_child(icon)
	var label := _make_label(&"")
	label.text = ("%d%%" % roundi(chance * 100.0)) if chance >= 0.0 else ("×%d" % stack.amount)
	_recipe_row.add_child(label)


func _place_near_mouse() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var pos := _game.camera.get_mouse_screen() + OFFSET
	pos.x = minf(pos.x, viewport_size.x - size.x - 8.0)
	pos.y = minf(pos.y, viewport_size.y - size.y - 8.0)
	position = pos


func _make_label(variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not variation.is_empty():
		l.theme_type_variation = variation
	return l
