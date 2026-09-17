class_name ResearchWindow
extends PanelContainer
## Окно исследований (J или кнопка в HUD): дерево карточек с прогрессом, стоимостью и тем,
## что они открывают; линии ведут от предшественника к следующему. Клик по доступному исследованию делает его текущим. Кнопка «Сдать наборы»
## кладёт научные наборы первого уровня из инвентаря дрона в ручную очередь — она обрабатывается
## медленно (ResearchState.MANUAL_SECONDS на набор); научный цех работает быстрее.

const REFRESH := 0.25
## Дерево больше этого прокручивается.
const MAX_TREE_SIZE := Vector2(1330, 560)

var _game: Game
var _list: VBoxContainer
var _queue_label: Label
var _deposit_button: Button
var _manual_bar: ProgressBar
var _cards: Dictionary[StringName, Dictionary] = {}
var _tree: ResearchTreeView
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
	var hint := UiUtil.label("RESEARCH_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_tree = ResearchTreeView.new()
	var cards: Dictionary[StringName, Control] = {}
	for research in Registry.researches:
		cards[research.id] = _make_card(research)
	_tree.setup(cards)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(_tree.custom_minimum_size.x, MAX_TREE_SIZE.x) + 12.0,
		minf(_tree.custom_minimum_size.y, MAX_TREE_SIZE.y) + 12.0)
	scroll.add_child(_tree)
	column.add_child(scroll)
	hint.custom_minimum_size = Vector2(scroll.custom_minimum_size.x, 0)
	var footer := UiUtil.hbox(10)
	column.add_child(footer)
	_deposit_button = UiUtil.button("RESEARCH_DEPOSIT", _deposit, &"AccentButton")
	_deposit_button.focus_mode = Control.FOCUS_NONE
	_deposit_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	footer.add_child(_deposit_button)
	var queue_column := UiUtil.vbox(4)
	queue_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(queue_column)
	_queue_label = Label.new()
	_queue_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_queue_label.theme_type_variation = &"DimLabel"
	queue_column.add_child(_queue_label)
	_manual_bar = ProgressBar.new()
	_manual_bar.custom_minimum_size = Vector2(200, 8)
	_manual_bar.show_percentage = false
	_manual_bar.max_value = 1.0
	queue_column.add_child(_manual_bar)


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
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = ResearchTreeView.CARD_SIZE
	button.theme_type_variation = &"SlotButton"
	button.pressed.connect(func() -> void:
		var state := _game.run.research
		if state.is_available(research):
			state.set_active(research.id if state.active != research.id else &"")
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
	for research in Registry.researches:
		var card: Dictionary = _cards.get(research.id, {})
		if card.is_empty():
			continue
		var button: Button = card["button"]
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
	var active := state.get_active()
	var kits := _game.run.drone.inventory.count(active.cost_item.index) if active != null and active.cost_item != null else 0
	var room := state.get_needed(active) - state.manual_queue if active != null else 0
	_deposit_button.disabled = active == null or kits == 0 or room <= 0 or active.cost_item.science_tier != 1
	_deposit_button.text = tr("RESEARCH_DEPOSIT") % kits
	_queue_label.text = tr("RESEARCH_QUEUE") % [state.manual_queue, ResearchState.MANUAL_SECONDS]
	_tree.state = state
	_tree.queue_redraw()
	_manual_bar.value = state.get_manual_fraction() if state.manual_queue > 0 else 0.0


func _deposit() -> void:
	var moved := _game.run.research.deposit_manual(_game.run.drone.inventory)
	if moved > 0:
		Events.toast(tr("TOAST_RESEARCH_DEPOSITED") % moved, Events.ToastKind.SUCCESS)
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
