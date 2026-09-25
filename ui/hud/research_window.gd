class_name ResearchWindow
extends PanelContainer
## Окно исследований (J или кнопка в HUD): на весь экран поверх игры, фон полупрозрачный — мир
## видно сквозь него. Слева дерево карточек с прогрессом, стоимостью и тем, что они открывают;
## справа — что изучается сейчас и очередь по порядку, у каждого пункта свой прогресс и крестик.
##
## ЛКМ по доступному исследованию делает его текущим, ПКМ ставит в очередь (ResearchState.QUEUE_MAX
## штук; ПКМ по стоящему в очереди убирает его). Наведение на карточку подсвечивает её цепочку.
## Колесо мыши над деревом приближает и отдаляет его, средняя кнопка тащит. Кнопка «Сдать наборы»
## кладёт научные наборы первого уровня из инвентаря дрона в ручную очередь — она обрабатывается
## медленно (ResearchState.MANUAL_SECONDS на набор); научный цех работает быстрее.

const REFRESH := 0.25
## Отступ окна от краёв экрана и ширина панели очереди.
const MARGIN := 24
const SIDE_WIDTH := 330.0
## Пределы и шаг приближения дерева колесом.
const ZOOM_MIN := 0.4
const ZOOM_MAX := 1.6
const ZOOM_STEP := 1.1
## Насколько гаснут карточки вне подсвеченной цепочки.
const DIM := 0.35

var _game: Game
var _queue_label: Label
var _deposit_button: Button
var _creative_row: HBoxContainer
var _manual_bar: ProgressBar
var _cards: Dictionary[StringName, Dictionary] = {}
var _tree: ResearchTreeView
## Обёртка дерева: её минимальный размер задаёт прокрутку при приближении.
var _tree_wrap: Control
## Прокрутка дерева: её двигает перетаскивание средней кнопкой.
var _scroll: ScrollContainer
var _tree_size: Vector2 = Vector2.ZERO
var _tree_zoom: float = 1.0
## Дерево тащат средней кнопкой мыши.
var _tree_panning: bool = false
var _timer: float = 0.0
## Панель справа: текущее исследование и очередь.
var _now_name: Label
var _now_status: Label
var _now_bar: ProgressBar
var _queue_title: Label
var _queue_rows: VBoxContainer
## Подпись очереди при прошлой сборке строк: строки пересобираются, только когда очередь сменилась.
var _queue_signature: String = "-"


func setup(game: Game) -> void:
	_game = game
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = MARGIN
	offset_top = MARGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	# Полупрозрачный фон: мир видно сквозь окно, но подсказки игры под ним уже не спорят с деревом.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTheme.BG_HARD, 0.93)
	box.border_color = Color(UiTheme.BG2, 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(16)
	add_theme_stylebox_override("panel", box)

	var column := UiUtil.vbox(10)
	add_child(column)
	var header := UiUtil.hbox(10)
	column.add_child(header)
	var title := UiUtil.label("RESEARCH_TITLE", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 22)
	header.add_child(title)
	var hint := Label.new()
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hint.theme_type_variation = &"DimLabel"
	hint.text = tr("RESEARCH_HINT") % ResearchState.QUEUE_MAX
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)
	var close := UiUtil.button("✕", close_window)
	close.focus_mode = Control.FOCUS_NONE
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(close)

	var body := UiUtil.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_tree = ResearchTreeView.new()
	var cards: Dictionary[StringName, Control] = {}
	for research in Registry.researches:
		cards[research.id] = _make_card(research)
	_tree.setup(cards)
	_tree_size = _tree.custom_minimum_size
	_tree_wrap = Control.new()
	_tree_wrap.custom_minimum_size = _tree_size
	_tree_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_wrap.add_child(_tree)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tree_wrap)
	scroll.gui_input.connect(_on_tree_scroll.bind(scroll))
	body.add_child(scroll)

	body.add_child(_build_side())


## Правая панель: что изучается, очередь по порядку и сдача наборов вручную.
func _build_side() -> Control:
	var side := UiUtil.vbox(8)
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_child(UiUtil.label("RESEARCH_NOW", &"DimLabel"))
	_now_name = Label.new()
	_now_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_now_name.add_theme_font_size_override("font_size", 18)
	_now_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_now_name)
	_now_status = Label.new()
	_now_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_now_status.theme_type_variation = &"DimLabel"
	_now_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_now_status)
	_now_bar = ProgressBar.new()
	_now_bar.custom_minimum_size = Vector2(0, 10)
	_now_bar.show_percentage = false
	side.add_child(_now_bar)

	side.add_child(HSeparator.new())
	_queue_title = Label.new()
	_queue_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_queue_title.theme_type_variation = &"DimLabel"
	side.add_child(_queue_title)
	_queue_rows = UiUtil.vbox(6)
	side.add_child(_queue_rows)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	side.add_child(HSeparator.new())
	_deposit_button = UiUtil.button("RESEARCH_DEPOSIT", _deposit, &"AccentButton")
	_deposit_button.focus_mode = Control.FOCUS_NONE
	_deposit_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	side.add_child(_deposit_button)
	_queue_label = Label.new()
	_queue_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_queue_label.theme_type_variation = &"DimLabel"
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_queue_label)
	_manual_bar = ProgressBar.new()
	_manual_bar.custom_minimum_size = Vector2(0, 8)
	_manual_bar.show_percentage = false
	_manual_bar.max_value = 1.0
	side.add_child(_manual_bar)
	_creative_row = UiUtil.hbox(6)
	side.add_child(_creative_row)
	var reset := UiUtil.button("RESEARCH_RESET", func() -> void:
		_game.run.submit(Command.Kind.RESEARCH_RESET)
		refresh())
	reset.focus_mode = Control.FOCUS_NONE
	_creative_row.add_child(reset)
	var unlock := UiUtil.button("RESEARCH_UNLOCK_ALL", func() -> void:
		_game.run.submit(Command.Kind.RESEARCH_UNLOCK)
		refresh())
	unlock.focus_mode = Control.FOCUS_NONE
	_creative_row.add_child(unlock)
	return side


## Колесо над деревом меняет масштаб, а не прокручивает список.
## Перетаскивание дерева средней кнопкой — как камера в мире.
##
## Ловится здесь, а не в gui_input прокрутки: карточки исследований перехватывают движение мыши
## раньше неё, и до прокрутки события просто не доходили — перетаскивание не работало.
func _input(event: InputEvent) -> void:
	if not visible or _scroll == null:
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_MIDDLE:
		if click.pressed and _scroll.get_global_rect().has_point(click.global_position):
			_tree_panning = true
			get_viewport().set_input_as_handled()
		elif not click.pressed and _tree_panning:
			_tree_panning = false
			get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion == null or not _tree_panning:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_tree_panning = false
		return
	_scroll.scroll_horizontal = maxi(_scroll.scroll_horizontal - roundi(motion.relative.x), 0)
	_scroll.scroll_vertical = maxi(_scroll.scroll_vertical - roundi(motion.relative.y), 0)
	get_viewport().set_input_as_handled()


## Колесо приближает дерево, точка под курсором остаётся на месте.
func _on_tree_scroll(event: InputEvent, scroll: ScrollContainer) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var factor := 0.0
	if click.button_index == MOUSE_BUTTON_WHEEL_UP:
		factor = ZOOM_STEP
	elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		factor = 1.0 / ZOOM_STEP
	else:
		return
	var before := _tree_zoom
	_tree_zoom = clampf(_tree_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	scroll.accept_event()
	if is_equal_approx(before, _tree_zoom):
		return
	_tree.scale = Vector2(_tree_zoom, _tree_zoom)
	_tree_wrap.custom_minimum_size = _tree_size * _tree_zoom
	# Точка под курсором остаётся на месте.
	var offset := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
	var at := click.position + offset
	var moved := at * (_tree_zoom / before) - at
	scroll.scroll_horizontal = maxi(roundi(offset.x + moved.x), 0)
	scroll.scroll_vertical = maxi(roundi(offset.y + moved.y), 0)


func get_tree_zoom() -> float:
	return _tree_zoom


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close_window()
	else:
		visible = true
		refresh()


func close_window() -> void:
	visible = false
	_tree.set_hovered(&"")


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		close_window()
		get_viewport().set_input_as_handled()


func _make_card(research: ResearchDef) -> Control:
	var button := Button.new()
	button.toggle_mode = true
	button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = ResearchTreeView.CARD_SIZE
	button.theme_type_variation = &"SlotButton"
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
			return
		_toggle_queue(research)
		button.accept_event())
	button.pressed.connect(func() -> void:
		var state := _game.run.research
		if state.is_available(research):
			_game.run.submit(Command.Kind.RESEARCH_SELECT, {"research": String(research.id) if state.active != research.id else ""})
		refresh())
	# Наведение подсвечивает цепочку: что нужно до этой карточки и что она открывает.
	button.mouse_entered.connect(func() -> void:
		_tree.set_hovered(research.id)
		_apply_focus())
	button.mouse_exited.connect(func() -> void:
		if _tree.hovered == research.id:
			_tree.set_hovered(&"")
			_apply_focus())
	var column := UiUtil.vbox(4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_top = 8
	column.offset_right = -10
	column.offset_bottom = -8
	button.add_child(column)
	var name_label := _label(research.name_key)
	name_label.add_theme_font_size_override("font_size", 16)
	column.add_child(name_label)
	var status := _label("")
	status.theme_type_variation = &"DimLabel"
	column.add_child(status)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = research.total_cost()
	column.add_child(bar)
	var icons := UiUtil.hbox(4)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icons)
	for def in research.unlock_buildings:
		icons.add_child(_icon(ArtRegistry.get_building_texture(def), tr(def.name_key)))
	for recipe in research.unlock_recipes:
		var main := recipe.get_main_output()
		if main != null:
			icons.add_child(_icon(ArtRegistry.get_item_icon(main.item), tr(main.item.name_key)))
	var tips := PackedStringArray([tr(research.description_key)])
	var names := PackedStringArray()
	for def in research.unlock_buildings:
		names.append(tr(def.name_key))
	for recipe in research.unlock_recipes:
		var main := recipe.get_main_output()
		if main != null:
			names.append(tr(main.item.name_key))
	if not names.is_empty():
		tips.append(tr("RESEARCH_UNLOCKS") % ", ".join(names))
	button.tooltip_text = "\n".join(tips)
	_cards[research.id] = {"button": button, "status": status, "bar": bar, "tint": Color.WHITE}
	return button


func refresh() -> void:
	var run := _game.run
	if run == null or run.research == null:
		return
	var state := run.research
	_creative_row.visible = state.sandbox
	for research in Registry.researches:
		var card: Dictionary = _cards.get(research.id, {})
		if card.is_empty():
			continue
		var button: Button = card["button"]
		if research.creative_only:
			button.visible = state.sandbox
			if not state.sandbox:
				continue
		var status: Label = card["status"]
		var bar: ProgressBar = card["bar"]
		var progress := state.get_progress(research)
		bar.value = progress
		button.set_pressed_no_signal(state.active == research.id)
		var tint := Color.WHITE
		if state.is_done(research.id):
			status.text = tr("RESEARCH_DONE")
			tint = Color(0.75, 1.0, 0.75)
		elif not state.is_available(research):
			var missing := PackedStringArray()
			for id in research.prerequisites:
				if not state.is_done(id):
					missing.append(tr(Registry.get_research(id).name_key))
			status.text = tr("RESEARCH_REQUIRES") % ", ".join(missing)
			tint = Color(1, 1, 1, 0.5)
		else:
			status.text = _cost_text(state, research)
			if state.active == research.id:
				status.text = tr("RESEARCH_ACTIVE") + " · " + status.text
		var place := state.queue_position(research.id)
		if place > 0:
			status.text = tr("RESEARCH_QUEUED") % place + " · " + status.text
			tint = Color(0.85, 0.95, 1.0)
		card["tint"] = tint
	_apply_focus()
	_refresh_side(state)
	_tree.state = state
	_tree.queue_redraw()


## Стоимость по видам наборов: у мидгейма их два, показываем каждый отдельно.
func _cost_text(state: ResearchState, research: ResearchDef) -> String:
	var parts := PackedStringArray()
	var costs := research.costs()
	for k in costs.size():
		parts.append(tr("RESEARCH_COST") % [state.get_progress_of(research, k), costs[k].amount,
			tr(costs[k].item.name_key)])
	return "  ·  ".join(parts)


## Цвет карточки по состоянию и гашение всего, что вне подсвеченной цепочки.
func _apply_focus() -> void:
	for id in _cards:
		var card: Dictionary = _cards[id]
		var tint: Color = card["tint"]
		if not _tree.in_focus(id):
			tint = Color(tint, tint.a * DIM)
		(card["button"] as Button).modulate = tint


## Правая панель: текущее исследование, очередь по порядку, ручная сдача.
func _refresh_side(state: ResearchState) -> void:
	var active := state.get_active()
	if active != null:
		_now_name.text = tr(active.name_key)
		_now_status.text = _cost_text(state, active)
		_now_bar.max_value = active.total_cost()
		_now_bar.value = state.get_progress(active)
		_now_bar.visible = true
	else:
		_now_name.text = tr("RESEARCH_NOTHING")
		_now_status.text = ""
		_now_bar.visible = false
	_queue_title.text = tr("RESEARCH_QUEUE_TITLE") % [state.queue.size(), ResearchState.QUEUE_MAX]
	var signature := ",".join(state.queue)
	if signature != _queue_signature:
		_queue_signature = signature
		_rebuild_queue_rows(state)
	# Прогресс в строках очереди обновляется без пересборки.
	for k in _queue_rows.get_child_count():
		var row := _queue_rows.get_child(k)
		if k < state.queue.size() and row.has_meta("bar"):
			var research := Registry.get_research(state.queue[k])
			(row.get_meta("bar") as ProgressBar).value = state.get_progress(research) if research != null else 0
	var kits := _game.run.drone.inventory.count(active.cost_item.index) if active != null and active.cost_item != null else 0
	# Руками сдают только наборы первого уровня.
	var room := state.get_needed_of(active, 0) - state.manual_queue if active != null else 0
	_deposit_button.disabled = active == null or kits == 0 or room <= 0 or active.cost_item.science_tier != 1
	_deposit_button.text = tr("RESEARCH_DEPOSIT") % kits
	_queue_label.text = tr("RESEARCH_QUEUE") % [state.manual_queue, ResearchState.MANUAL_SECONDS]
	_manual_bar.value = state.get_manual_fraction() if state.manual_queue > 0 else 0.0


func _rebuild_queue_rows(state: ResearchState) -> void:
	for child in _queue_rows.get_children():
		_queue_rows.remove_child(child)
		child.queue_free()
	if state.queue.is_empty():
		var empty := UiUtil.label("RESEARCH_QUEUE_EMPTY", &"DimLabel")
		_queue_rows.add_child(empty)
		return
	for k in state.queue.size():
		var research := Registry.get_research(state.queue[k])
		if research == null:
			continue
		var row := UiUtil.vbox(2)
		var line := UiUtil.hbox(6)
		row.add_child(line)
		var title_label := Label.new()
		title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title_label.text = "%d. %s" % [k + 1, tr(research.name_key)]
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.clip_text = true
		line.add_child(title_label)
		var remove := UiUtil.button("✕", _toggle_queue.bind(research))
		remove.focus_mode = Control.FOCUS_NONE
		remove.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		remove.tooltip_text = tr("RESEARCH_QUEUE_REMOVE")
		line.add_child(remove)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.show_percentage = false
		bar.max_value = research.total_cost()
		bar.value = state.get_progress(research)
		row.add_child(bar)
		row.set_meta("bar", bar)
		# Строка очереди подсвечивает карточку в дереве, как и наведение на саму карточку.
		row.mouse_entered.connect(func() -> void:
			_tree.set_hovered(research.id)
			_apply_focus())
		row.mouse_exited.connect(func() -> void:
			if _tree.hovered == research.id:
				_tree.set_hovered(&"")
				_apply_focus())
		_queue_rows.add_child(row)


## ПКМ по карточке: поставить в очередь или убрать из неё.
func _toggle_queue(research: ResearchDef) -> void:
	var state := _game.run.research
	if state.queue_position(research.id) == 0 and state.queue.size() >= ResearchState.QUEUE_MAX:
		Events.toast(tr("RESEARCH_QUEUE_FULL") % ResearchState.QUEUE_MAX, Events.ToastKind.WARNING)
		return
	_game.run.submit(Command.Kind.RESEARCH_QUEUE, {"research": String(research.id)})
	refresh()


func _deposit() -> void:
	_game.run.submit(Command.Kind.RESEARCH_DEPOSIT)
	refresh()


func _label(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _icon(texture: Texture2D, tip: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = tip
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	return icon
