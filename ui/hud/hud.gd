class_name Hud
extends CanvasLayer
## Игровой интерфейс: заголовок уровня, кнопка меню, панель строительства, инфо-строка,
## подсказки режима, легенда оверлея руд, отладка, уведомления, подтверждение массового сноса.

var _game: Game
var _root: Control
var _info_label: Label
var _hint_label: Label
var _hint_panel: PanelContainer
var _fps_label: Label
var _ore_legend: PanelContainer
var _debug: DebugOverlay
var _confirm: ConfirmationDialog
var _pending_delete: Array[Building] = []
var _fps_timer: float = 0.0


func setup(game: Game) -> void:
	_game = game
	layer = 10
	_root = UiUtil.full_rect(Control.new())
	_root.name = "HudRoot"
	_root.theme = UiTheme.get_theme()
	add_child(_root)

	_build_top_left()
	_build_top_right()
	_build_bottom_left()
	_build_top_center()
	_build_build_menu()
	_build_toasts()
	_build_confirm()

	game.tools.hover_changed.connect(_update_info)
	game.tools.mode_changed.connect(_update_hint)
	game.tools.delete_confirmation_requested.connect(_on_delete_confirmation)
	Settings.changed.connect(_on_setting_changed)
	Settings.bindings_changed.connect(_update_hint)
	_update_info()
	_update_hint()
	_on_setting_changed(&"graphics/show_fps")


func set_ore_legend_visible(value: bool) -> void:
	_ore_legend.visible = value


func toggle_debug() -> bool:
	_debug.visible = not _debug.visible
	return _debug.visible


func is_modal_open() -> bool:
	return _confirm.visible


# --- Построение ---

func _build_top_left() -> void:
	var column := UiUtil.vbox(8)
	column.position = Vector2(16, 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	var title_panel := PanelContainer.new()
	title_panel.theme_type_variation = &"HudPanel"
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_row := UiUtil.hbox(10)
	title_panel.add_child(title_row)
	var title := UiUtil.label(_game.world.level.title_key, &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 20)
	title_row.add_child(title)
	if _game.world.sandbox:
		var badge := UiUtil.label("HUD_SANDBOX", &"BadgeLabel")
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(badge)
	column.add_child(title_panel)

	_ore_legend = PanelContainer.new()
	_ore_legend.theme_type_variation = &"HudPanel"
	_ore_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ore_legend.visible = false
	var legend := UiUtil.vbox(4)
	_ore_legend.add_child(legend)
	legend.add_child(UiUtil.label("HUD_ORE_LEGEND", &"DimLabel"))
	for ore in Registry.ores:
		var row := UiUtil.hbox(8)
		var swatch := TextureRect.new()
		swatch.texture = ArtRegistry.get_item_icon(ore.item)
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(swatch)
		var name_label := UiUtil.label(ore.get_name_key())
		name_label.add_theme_color_override("font_color", ArtRegistry.ore_overlay_color(ore.index))
		row.add_child(name_label)
		legend.add_child(row)
	column.add_child(_ore_legend)

	_debug = DebugOverlay.new()
	_debug.setup(_game)
	column.add_child(_debug)


func _build_top_right() -> void:
	var column := UiUtil.vbox(6)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.offset_left = -16
	column.offset_right = -16
	column.offset_top = 16
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	var menu_button := UiUtil.button("HUD_MENU", func() -> void: _game.open_pause_menu())
	menu_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	menu_button.focus_mode = Control.FOCUS_NONE
	column.add_child(menu_button)

	_fps_label = Label.new()
	_fps_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fps_label.theme_type_variation = &"DimLabel"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_fps_label)


func _build_bottom_left() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 16
	panel.offset_bottom = -16
	_root.add_child(panel)
	_info_label = Label.new()
	_info_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info_label.custom_minimum_size = Vector2(300, 0)
	panel.add_child(_info_label)


func _build_top_center() -> void:
	var holder := HBoxContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.offset_top = 16
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_hint_panel = PanelContainer.new()
	_hint_panel.theme_type_variation = &"HudPanel"
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_hint_panel)
	_hint_label = Label.new()
	_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_panel.add_child(_hint_label)


func _build_build_menu() -> void:
	var menu := BuildMenu.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu.offset_right = -16
	menu.offset_bottom = -16
	_root.add_child(menu)
	menu.setup(_game.tools)


func _build_toasts() -> void:
	var toasts := ToastStack.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 64
	_root.add_child(toasts)


func _build_confirm() -> void:
	_confirm = ConfirmationDialog.new()
	_confirm.theme = UiTheme.get_theme()
	_confirm.title = "CONFIRM_TITLE"
	_confirm.ok_button_text = "CONFIRM_DELETE_OK"
	_confirm.cancel_button_text = "CONFIRM_CANCEL"
	_confirm.confirmed.connect(_on_delete_confirmed)
	_confirm.canceled.connect(func() -> void: _pending_delete = [])
	add_child(_confirm)


# --- Обновление ---

func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.25
			_fps_label.text = "FPS %d" % Engine.get_frames_per_second()


func _update_info() -> void:
	var tools := _game.tools
	var grid := _game.world.grid
	if not tools.hover_in_bounds:
		_info_label.text = tr("HUD_INFO_OUT_OF_MAP")
		return
	var t := tools.hover_tile
	var lines := PackedStringArray()
	lines.append(tr("HUD_INFO_TILE") % [t.x, t.y])
	var floor_def := grid.get_floor_def(t.x, t.y)
	var floor_text := tr("HUD_INFO_FLOOR") % tr(floor_def.name_key)
	if not floor_def.buildable:
		floor_text += "  " + tr("HUD_INFO_UNBUILDABLE")
	lines.append(floor_text)
	var ore := grid.get_ore_def(t.x, t.y)
	if ore != null:
		lines.append(tr("HUD_INFO_ORE") % [tr(ore.get_name_key()), ore.hardness])
	else:
		lines.append(tr("HUD_INFO_NO_ORE"))
	if tools.hover_building != null:
		lines.append(tr("HUD_INFO_BUILDING") % tr(tools.hover_building.def.name_key))
	_info_label.text = "\n".join(lines)


func _update_hint() -> void:
	var tools := _game.tools
	var primary := InputActions.primary_label(&"build_primary")
	match tools.mode:
		ToolController.Mode.PLACE:
			_hint_label.text = tr("HINT_PLACE") % [
				tr(tools.place_def.name_key), primary,
				InputActions.primary_label(&"rotate"), InputActions.primary_label(&"cancel")]
		ToolController.Mode.DELETE:
			_hint_label.text = tr("HINT_DELETE") % [primary, InputActions.primary_label(&"delete_mode")]
		_:
			_hint_label.text = tr("HINT_IDLE") % [
				InputActions.primary_label(&"area_modifier"), primary,
				InputActions.primary_label(&"delete_mode"), InputActions.primary_label(&"pipette"),
				InputActions.primary_label(&"overlay_ores")]


func _on_delete_confirmation(targets: Array[Building]) -> void:
	_pending_delete = targets
	_confirm.dialog_text = tr("CONFIRM_MASS_DELETE") % targets.size()
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	_game.tools.remove_buildings(_pending_delete)
	_pending_delete = []


func _on_setting_changed(key: StringName) -> void:
	if key == &"graphics/show_fps":
		_fps_label.visible = Settings.get_bool(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _info_label != null:
		_update_info()
		_update_hint()
