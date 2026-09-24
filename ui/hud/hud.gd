class_name Hud
extends CanvasLayer
## Игровой интерфейс: название текущего мира (планета или база), угроза планеты, пауза и скорость, кнопка меню,
## панель строительства, окно инвентаря и крафта, очередь крафта, инфо-строка, подсказки режима
## и перехода через шлюз, легенды оверлеев, отладка, уведомления, подтверждение массового сноса.

const INFO_REFRESH := 0.25
const HINT_WIDTH := 720

var _game: Game
var _root: Control
var _info_label: Label
var _hint_label: Label
var _problem_label: Label
var _paused_badge: Label
var _fps_label: Label
var _ore_legend: PanelContainer
var _belt_legend: PanelContainer
var _debug: DebugOverlay
var _confirm: ConfirmationDialog
var inventory_window: InventoryWindow
var _title_label: Label
var _safe_badge: Label
## Кто в забеге (видно только когда игроков больше одного).
var _players_label: Label
var _gateway_label: Label
var _charge_label: Label
var _respawn_label: Label
var threat_panel: ThreatPanel
var research_window: ResearchWindow
var _drone_was_dead: bool = false
var teleport_window: TeleportWindow
var platform_window: PlatformWindow
var chat_panel: ChatPanel
var summary_window: SummaryWindow
var _config_panel: ConfigPanel
var _build_menu: BuildMenu
var _pending_delete: Array[Building] = []
var _fps_timer: float = 0.0
var _info_timer: float = 0.0


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
	_build_craft_queue()
	_build_inventory_window()
	var alarm := AttackIndicator.new()
	alarm.name = "AttackIndicator"
	_root.add_child(alarm)
	alarm.setup(game)
	_build_toasts()
	_build_chat()
	_build_confirm()
	var tooltip := BuildingTooltip.new()
	_root.add_child(tooltip)
	tooltip.setup(game)

	game.tools.hover_changed.connect(_update_info)
	game.tools.mode_changed.connect(_update_hint)
	game.tools.plan_changed.connect(_update_problem)
	game.tools.area_changed.connect(_update_hint)
	game.tools.delete_confirmation_requested.connect(_on_delete_confirmation)
	game.clock.state_changed.connect(_update_paused_badge)
	game.run.players_changed.connect(_update_players)
	_connect_world_signals()
	_drone_was_dead = game.run.drone.dead
	game.run.research.completed.connect(func(research: ResearchDef) -> void:
		Events.toast(tr("TOAST_RESEARCH_DONE") % tr(research.name_key), Events.ToastKind.SUCCESS))
	game.run.research.next_taken.connect(func(research: ResearchDef) -> void:
		Events.toast(tr("TOAST_RESEARCH_NEXT") % tr(research.name_key), Events.ToastKind.INFO))
	Settings.changed.connect(_on_setting_changed)
	Settings.bindings_changed.connect(_update_hint)
	_update_info()
	_update_hint()
	_update_problem()
	_update_paused_badge()
	_on_setting_changed(&"graphics/show_fps")


func set_ore_legend_visible(value: bool) -> void:
	_ore_legend.visible = value


func set_belt_legend_visible(value: bool) -> void:
	_belt_legend.visible = value


func _make_belt_legend() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var column := UiUtil.vbox(4)
	panel.add_child(column)
	column.add_child(UiUtil.label("HUD_BELT_LEGEND", &"DimLabel"))
	var entries := [
		[BeltLoadOverlay.COLOR_EMPTY, "HUD_BELT_EMPTY"],
		[BeltLoadOverlay.COLOR_LOW, "HUD_BELT_FLOWING"],
		[BeltLoadOverlay.COLOR_HIGH, "HUD_BELT_DENSE"],
		[BeltLoadOverlay.COLOR_BLOCKED, "HUD_BELT_BLOCKED"],
	]
	for entry in entries:
		var row := UiUtil.hbox(8)
		var swatch := ColorRect.new()
		swatch.color = Color(entry[0], 1.0)
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		row.add_child(UiUtil.label(entry[1]))
		column.add_child(row)
	return panel


func toggle_debug() -> bool:
	_debug.visible = not _debug.visible
	return _debug.visible


## Пока открыто модальное окно, дрон стоит и мир не строится: у пульта платформы WASD
## двигают рамку наводки, а не дрона.
func is_modal_open() -> bool:
	return _confirm.visible or (platform_window != null and platform_window.is_open()) 		or (chat_panel != null and chat_panel.is_typing())


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
	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeaderLabel"
	_title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title_label.add_theme_font_size_override("font_size", 20)
	title_row.add_child(_title_label)
	_players_label = Label.new()
	_players_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_players_label.theme_type_variation = &"DimLabel"
	_players_label.visible = false
	title_row.add_child(_players_label)
	_safe_badge = UiUtil.label("HUD_SAFE_PLANET", &"BadgeLabel")
	_safe_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_safe_badge)
	_update_title()
	if _game.world.creative:
		var badge := UiUtil.label("HUD_CREATIVE", &"BadgeLabel")
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(badge)
	column.add_child(title_panel)

	threat_panel = ThreatPanel.new()
	column.add_child(threat_panel)
	threat_panel.setup(_game)

	_belt_legend = _make_belt_legend()
	column.add_child(_belt_legend)

	_ore_legend = PanelContainer.new()
	_ore_legend.theme_type_variation = &"HudPanel"
	_ore_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ore_legend.visible = false
	var legend := UiUtil.vbox(4)
	_ore_legend.add_child(legend)
	legend.add_child(UiUtil.label("HUD_ORE_LEGEND", &"DimLabel"))
	for ore in Registry.ores:
		var row := UiUtil.hbox(8)
		if ore.item != null:
			var swatch := TextureRect.new()
			swatch.texture = ArtRegistry.get_item_icon(ore.item)
			swatch.custom_minimum_size = Vector2(20, 20)
			swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(swatch)
		else:
			# Месторождение жидкости (вода): у него нет предмета — квадрат цвета жидкости.
			var fluid_swatch := ColorRect.new()
			fluid_swatch.color = ore.fluid.color
			fluid_swatch.custom_minimum_size = Vector2(20, 20)
			row.add_child(fluid_swatch)
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
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	var row := UiUtil.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(row)
	var speed := SpeedPanel.new()
	row.add_child(speed)
	speed.setup(_game.clock, _game.run.cheats_allowed())
	var research_button := UiUtil.button("HUD_RESEARCH", func() -> void: research_window.toggle())
	research_button.focus_mode = Control.FOCUS_NONE
	research_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(research_button)
	var menu_button := UiUtil.button("HUD_MENU", func() -> void: _game.open_pause_menu())
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(menu_button)

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
	var column := UiUtil.vbox(6)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = 16
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	var hint_panel := PanelContainer.new()
	hint_panel.theme_type_variation = &"HudPanel"
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hint_panel)
	var hint_column := UiUtil.vbox(2)
	hint_panel.add_child(hint_column)
	_hint_label = Label.new()
	_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Ограниченная ширина: длинная подсказка переносится и не наезжает на панель скорости.
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(HINT_WIDTH, 0)
	hint_column.add_child(_hint_label)
	_problem_label = Label.new()
	_problem_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_problem_label.add_theme_font_size_override("font_size", 15)
	_problem_label.add_theme_color_override("font_color", UiTheme.RED)
	_problem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_column.add_child(_problem_label)

	_gateway_label = Label.new()
	_gateway_label.theme_type_variation = &"BadgeLabel"
	_gateway_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_gateway_label.add_theme_font_size_override("font_size", 18)
	_gateway_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_gateway_label.visible = false
	column.add_child(_gateway_label)

	_charge_label = Label.new()
	_charge_label.theme_type_variation = &"BadgeLabel"
	_charge_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_charge_label.add_theme_font_size_override("font_size", 18)
	_charge_label.add_theme_color_override("font_color", UiTheme.AQUA)
	_charge_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_charge_label.visible = false
	column.add_child(_charge_label)

	_respawn_label = Label.new()
	_respawn_label.theme_type_variation = &"BadgeLabel"
	_respawn_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_respawn_label.add_theme_font_size_override("font_size", 18)
	_respawn_label.add_theme_color_override("font_color", UiTheme.RED)
	_respawn_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_respawn_label.visible = false
	column.add_child(_respawn_label)

	_paused_badge = UiUtil.label("HUD_PAUSED", &"BadgeLabel")
	_paused_badge.add_theme_font_size_override("font_size", 18)
	_paused_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_paused_badge)


func _build_build_menu() -> void:
	# Правая колонка: панель настройки над меню строительства. Высота меню постоянная,
	# поэтому панель настройки не прыгает, пока курсор движется к ней.
	var column := UiUtil.vbox(8)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_right = -16
	column.offset_bottom = -16
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)
	_config_panel = ConfigPanel.new()
	_config_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_config_panel)
	_config_panel.setup(_game.tools, _game.world)
	_build_menu = BuildMenu.new()
	column.add_child(_build_menu)
	_build_menu.setup(_game.tools, _game.world)


var _craft_queue: CraftQueuePanel


func _build_craft_queue() -> void:
	var queue := CraftQueuePanel.new()
	queue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	queue.grow_horizontal = Control.GROW_DIRECTION_BOTH
	queue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	queue.offset_bottom = -16
	_root.add_child(queue)
	_craft_queue = queue
	queue.setup(_game.world.drone, _game.world)


func _build_inventory_window() -> void:
	inventory_window = InventoryWindow.new()
	_root.add_child(inventory_window)
	inventory_window.setup(_game.tools, _game.world)
	teleport_window = TeleportWindow.new()
	_root.add_child(teleport_window)
	teleport_window.setup(_game)
	platform_window = PlatformWindow.new()
	_root.add_child(platform_window)
	platform_window.setup(_game)
	summary_window = SummaryWindow.new()
	_root.add_child(summary_window)
	summary_window.setup()
	research_window = ResearchWindow.new()
	_root.add_child(research_window)
	research_window.setup(_game)


## Чат: слева внизу, над подсказками. Открывается по Enter.
func _build_chat() -> void:
	chat_panel = ChatPanel.new()
	chat_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_panel.offset_left = 16
	chat_panel.offset_bottom = -120
	_root.add_child(chat_panel)
	chat_panel.setup(_game)


func _build_toasts() -> void:
	var toasts := ToastStack.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 110
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

## Дрон перешёл в другой мир: панели переключаются на него.
func on_world_changed() -> void:
	var world := _game.world
	_config_panel.set_world(world)
	_build_menu.set_world(world)
	inventory_window.set_world(world)
	if _craft_queue != null and world.drone != null:
		_craft_queue.set_drone(world.drone, world)
	_update_title()
	_update_info()
	_update_hint()
	_update_gateway_label()


func _update_title() -> void:
	var world := _game.world
	_title_label.text = _game.run.get_world_title(world)
	_update_players()
	_safe_badge.visible = not world.is_base and _game.run.is_planet_safe()


## Телепорт завершён: новая планета, показываем итог.
func on_planet_changed() -> void:
	on_world_changed()
	_connect_world_signals()
	threat_panel.refresh()
	summary_window.show_summary(_game.run.last_summary)


## Уведомления мира планеты (после телепорта мир новый — подписываемся заново).
func _connect_world_signals() -> void:
	for world in [_game.run.planet, _game.run.base, _game.run.mining]:
		if not world.crate_picked.is_connected(_on_crate_picked):
			world.crate_picked.connect(_on_crate_picked)


func _on_crate_picked(moved: int) -> void:
	Events.toast(tr("TOAST_CRATE_PICKED") % moved, Events.ToastKind.SUCCESS)

func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.25
			_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	# Зарядка телепорта видна в любом мире.
	var charging := _game.run != null and _game.run.is_charging()
	_charge_label.visible = charging
	if charging:
		_charge_label.text = tr("HUD_TELEPORT_CHARGING") % ceili(_game.run.get_charge_seconds_left())
	# Сбитый дрон: отсчёт до появления у шлюза.
	var drone := _game.run.drone if _game.run != null else null
	var dead := drone != null and drone.dead
	_respawn_label.visible = dead
	if dead:
		var world_tick := drone.world.simulation.tick if drone.world != null else 0
		_respawn_label.text = tr("HUD_DRONE_RESPAWN") % ceili(maxi(drone.respawn_tick - world_tick, 0) / float(GameConst.TICK_RATE))
		if not _drone_was_dead:
			Events.toast(tr("TOAST_DRONE_DESTROYED"), Events.ToastKind.WARNING)
	_drone_was_dead = dead
	# Подсказка перехода: дрон над центральным шлюзом (закрытый этаж — подсказка об исследовании).
	var can_pass := _game.run != null and _game.run.is_over_gateway()
	if can_pass != _gateway_label.visible:
		_gateway_label.visible = can_pass
		if can_pass:
			_update_gateway_label()
	# Состояние здания под курсором меняется со временем (буфер бура, предметы на ленте).
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = INFO_REFRESH
		if _game.tools.hover_building != null:
			_update_info()


## Список игроков: своё имя выделено, остальные — где они сейчас.
func _update_players() -> void:
	var run := _game.run
	_players_label.visible = run.players.size() > 1 or Session.net.is_networked()
	if not _players_label.visible:
		return
	var online := Session.net.online_players() if Session.net.is_networked() else PackedInt32Array()
	var parts := PackedStringArray()
	for p in run.players:
		var mark := "▸" if p.id == run.local_player else "·"
		var suffix := ""
		if Session.net.is_networked() and not online.has(p.id):
			suffix = " (%s)" % tr("HUD_NET_OFFLINE")
		parts.append("%s %s%s" % [mark, p.name, suffix])
	_players_label.text = tr("HUD_PLAYERS") % ", ".join(parts)


func _update_info() -> void:
	var tools := _game.tools
	var grid := _game.world.grid
	var t := tools.hover_tile
	if not tools.hover_in_bounds or not grid.in_bounds_v(t):
		_info_label.text = tr("HUD_INFO_OUT_OF_MAP")
		return
	var lines := PackedStringArray()
	lines.append(tr("HUD_INFO_TILE") % [t.x, t.y])
	var floor_def := grid.get_floor_def(t.x, t.y)
	var floor_text := tr("HUD_INFO_FLOOR") % tr(floor_def.name_key)
	if not floor_def.buildable:
		floor_text += "  " + tr("HUD_INFO_UNBUILDABLE")
	lines.append(floor_text)
	if _game.world.pad_rect.has_point(t):
		lines.append(tr("HUD_INFO_PAD"))
	var ore := grid.get_ore_def(t.x, t.y)
	if ore != null:
		if ore.fluid != null:
			lines.append(tr("HUD_INFO_FLUID") % tr(ore.get_name_key()))
		else:
			lines.append(tr("HUD_INFO_ORE") % [tr(ore.get_name_key()), ore.hardness])
	else:
		lines.append(tr("HUD_INFO_NO_ORE"))
	var b := tools.hover_building
	if b != null and b.world != null:
		lines.append(tr("HUD_INFO_BUILDING") % tr(b.def.name_key))
		lines.append(tr("HUD_INFO_HEALTH") % [ceili(b.health), roundi(b.get_max_health())])
		lines.append_array(b.get_info_lines())
	_info_label.text = "\n".join(lines)


func _update_hint() -> void:
	var tools := _game.tools
	var primary := InputActions.primary_label(&"build_primary")
	match tools.mode:
		ToolController.Mode.PLACE:
			_hint_label.text = tr("HINT_PLACE") % [
				tr(tools.place_def.name_key), primary,
				InputActions.primary_label(&"rotate"), InputActions.primary_label(&"cancel")]
		ToolController.Mode.PASTE:
			_hint_label.text = tr("HINT_PASTE") % [
				tools.plan.size(), primary, InputActions.primary_label(&"rotate"),
				InputActions.primary_label(&"select_area"), InputActions.primary_label(&"cancel")]
		ToolController.Mode.MOVE:
			_hint_label.text = tr("HINT_MOVE") % [
				tools.plan.size(), primary, InputActions.primary_label(&"select_area"),
				InputActions.primary_label(&"cancel")]
		_:
			if tools.has_area():
				_hint_label.text = tr("HINT_AREA") % [
					tools.area_buildings.size(), InputActions.primary_label(&"delete_selection"),
					InputActions.primary_label(&"copy_selection"), InputActions.primary_label(&"move_selection"),
					InputActions.primary_label(&"select_area"), InputActions.primary_label(&"cancel")]
			else:
				var move := "%s%s%s%s" % [InputActions.primary_label(&"move_up"), InputActions.primary_label(&"move_left"),
					InputActions.primary_label(&"move_down"), InputActions.primary_label(&"move_right")]
				_hint_label.text = tr("HINT_IDLE") % [
					move, primary, InputActions.primary_label(&"inventory"), InputActions.primary_label(&"select_area"),
					InputActions.primary_label(&"delete_selection"), InputActions.primary_label(&"rotate"),
					InputActions.primary_label(&"pipette")]
	_update_problem()


func _update_gateway_label() -> void:
	if not _game.run.is_underground_open():
		_gateway_label.text = tr("HINT_GATEWAY_LOCKED") % tr(Registry.get_research(&"underground").name_key)
		return
	# Этажей три, поэтому подсказка называет, куда именно ведёт проход под дроном.
	var passage := _game.run.get_passage()
	var target := _game.run.passage_target(passage) if passage != null else null
	if target == null or target.world == null:
		_gateway_label.text = ""
		return
	_gateway_label.text = tr("HINT_GATEWAY_TO") % [InputActions.primary_label(&"use_gateway"),
		_game.run.get_world_title(target.world)]


func _update_problem() -> void:
	var key := ""
	if _game.tools.mode == ToolController.Mode.PLACE:
		match _game.tools.plan_problem:
			BuildingManager.Check.NO_ITEM:
				key = "PROBLEM_NO_ITEM"
			BuildingManager.Check.OUT_OF_RANGE:
				key = "PROBLEM_OUT_OF_RANGE"
			BuildingManager.Check.NO_ORE:
				key = "PROBLEM_NO_ORE"
			BuildingManager.Check.BAD_TERRAIN:
				key = "PROBLEM_BAD_TERRAIN"
			BuildingManager.Check.ON_FLUID:
				key = "PROBLEM_ON_FLUID"
			BuildingManager.Check.LIFT_AREA:
				key = "PROBLEM_LIFT_AREA"
			BuildingManager.Check.LIFT_PAIR:
				key = "PROBLEM_LIFT_PAIR"
			BuildingManager.Check.LOCKED:
				key = "PROBLEM_LOCKED"
			BuildingManager.Check.OCCUPIED:
				key = "PROBLEM_OCCUPIED"
			BuildingManager.Check.OUT_OF_BOUNDS:
				key = "PROBLEM_OUT_OF_BOUNDS"
	_problem_label.text = tr(key) if not key.is_empty() else ""
	_problem_label.visible = not key.is_empty()


func _update_paused_badge() -> void:
	_paused_badge.visible = _game.clock.paused


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
		_update_title()
		_update_info()
		_update_hint()
		_update_gateway_label()
