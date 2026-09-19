class_name ResearchWindow
extends PanelContainer
## Окно исследований (J или кнопка в HUD): дерево карточек с прогрессом, стоимостью и тем,
## что они открывают; линии ведут от предшественника к следующему. ЛКМ по доступному исследованию
## делает его текущим, ПКМ ставит в очередь (ResearchState.QUEUE_MAX штук; ПКМ по стоящему
## в очереди убирает его). Колесо мыши над деревом приближает и отдаляет его. Кнопка «Сдать наборы»
## кладёт научные наборы первого уровня из инвентаря дрона в ручную очередь — она обрабатывается
## медленно (ResearchState.MANUAL_SECONDS на набор); научный цех работает быстрее.

const REFRESH := 0.25
## Дерево больше этого прокручивается.
const MAX_TREE_SIZE := Vector2(1330, 560)
## Пределы и шаг приближения дерева колесом.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 1.6
const ZOOM_STEP := 1.1

var _game: Game
var _list: VBoxContainer
var _queue_label: Label
var _queue_list: Label
var _deposit_button: Button
var _creative_row: HBoxContainer
var _manual_bar: ProgressBar
var _cards: Dictionary[StringName, Dictionary] = {}
var _tree: ResearchTreeView
## Обёртка дерева: её минимальный размер задаёт прокрутку при приближении.
var _tree_wrap: Control
var _tree_size: Vector2 = Vector2.ZERO
var _tree_zoom: float = 1.0
var _timer: float = 0.0


func setup(game: Game) -> void:
	_game = game
	theme_type_variation = &"CardPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := UiUtil.vbox(10)
	add_child(column)
	var header := UiUtil.hbox(10)
	column.add_child(header)
	var title := UiUtil.label("RESEARCH_TITLE", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UiUtil.button("✕", close_window)
	close.focus_mode = Control.FOCUS_NONE
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(close)
	var hint := Label.new()
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hint.theme_type_variation = &"DimLabel"
	hint.text = tr("RESEARCH_HINT") % ResearchState.QUEUE_MAX
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
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
	scroll.custom_minimum_size = Vector2(minf(_tree_size.x, MAX_TREE_SIZE.x) + 12.0,
		minf(_tree_size.y, MAX_TREE_SIZE.y) + 12.0)
	scroll.add_child(_tree_wrap)
	scroll.gui_input.connect(_on_tree_scroll.bind(scroll))
	column.add_child(scroll)
	hint.custom_minimum_size = Vector2(scroll.custom_minimum_size.x, 0)
	var footer := UiUtil.hbox(10)
	column.add_child(footer)
	_creative_row = UiUtil.hbox(6)
	column.add_child(_creative_row)
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
	_deposit_button = UiUtil.button("RESEARCH_DEPOSIT", _deposit, &"AccentButton")
	_deposit_button.focus_mode = Control.FOCUS_NONE
	_deposit_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	footer.add_child(_deposit_button)
	var queue_column := UiUtil.vbox(4)
	queue_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(queue_column)
	_queue_list = Label.new()
	_queue_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_queue_list.clip_text = true
	queue_column.add_child(_queue_list)
	_queue_label = Label.new()
	_queue_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_queue_label.theme_type_variation = &"DimLabel"
	queue_column.add_child(_queue_label)
	_manual_bar = ProgressBar.new()
	_manual_bar.custom_minimum_size = Vector2(200, 8)
	_manual_bar.show_percentage = false
	_manual_bar.max_value = 1.0
	queue_column.add_child(_manual_bar)


## Колесо над деревом меняет масштаб, а не прокручивает список.
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
	bar.max_value = research.cost_amount
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
	_cards[research.id] = {"button": button, "status": status, "bar": bar}
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
		if state.is_done(research.id):
			status.text = tr("RESEARCH_DONE")
			button.modulate = Color(0.75, 1.0, 0.75)
		elif not state.is_available(research):
			var missing := PackedStringArray()
			for id in research.prerequisites:
				if not state.is_done(id):
					missing.append(tr(Registry.get_research(id).name_key))
			status.text = tr("RESEARCH_REQUIRES") % ", ".join(missing)
			button.modulate = Color(1, 1, 1, 0.5)
		else:
			status.text = tr("RESEARCH_COST") % [progress, research.cost_amount, tr(research.cost_item.name_key)]
			if state.active == research.id:
				status.text = tr("RESEARCH_ACTIVE") + " · " + status.text
			button.modulate = Color.WHITE
		var place := state.queue_position(research.id)
		if place > 0:
			status.text = tr("RESEARCH_QUEUED") % place + " · " + status.text
			button.modulate = Color(0.85, 0.95, 1.0)
	var active := state.get_active()
	var kits := _game.run.drone.inventory.count(active.cost_item.index) if active != null and active.cost_item != null else 0
	var room := state.get_needed(active) - state.manual_queue if active != null else 0
	_deposit_button.disabled = active == null or kits == 0 or room <= 0 or active.cost_item.science_tier != 1
	_deposit_button.text = tr("RESEARCH_DEPOSIT") % kits
	_queue_label.text = tr("RESEARCH_QUEUE") % [state.manual_queue, ResearchState.MANUAL_SECONDS]
	if state.queue.is_empty():
		_queue_list.text = tr("RESEARCH_QUEUE_EMPTY")
	else:
		var names := PackedStringArray()
		for id in state.queue:
			names.append(tr(Registry.get_research(id).name_key))
		_queue_list.text = tr("RESEARCH_QUEUE_LIST") % " → ".join(names)
	_tree.state = state
	_tree.queue_redraw()
	_manual_bar.value = state.get_manual_fraction() if state.manual_queue > 0 else 0.0


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
