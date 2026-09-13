class_name ResourcePanel
extends PanelContainer
## Запасы ядра: иконка, количество и дельта в секунду (поступление минус расход).
## Показываются предметы, которые есть в ядре или двигались за последние секунды.
## Обновляется по изменению запасов/статистики, не чаще 4 раз в секунду.

const REFRESH_INTERVAL := 0.25

var _world: GameWorld
var _grid: GridContainer
var _rows: Dictionary[int, Array] = {}
var _timer: float = 0.0
var _storage_revision: int = -1
var _stats_revision: int = -1
var _empty_label: Label


func setup(world: GameWorld) -> void:
	_world = world
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UiUtil.vbox(4)
	add_child(column)
	column.add_child(UiUtil.label("HUD_CORE_RESOURCES", &"DimLabel"))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 2)
	column.add_child(_grid)
	_empty_label = UiUtil.label("HUD_CORE_EMPTY", &"DimLabel")
	column.add_child(_empty_label)
	for item in Registry.items:
		var icon := TextureRect.new()
		icon.texture = ArtRegistry.get_item_icon(item)
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		icon.tooltip_text = item.name_key
		var amount := Label.new()
		amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		amount.custom_minimum_size = Vector2(48, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var rate := Label.new()
		rate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		rate.theme_type_variation = &"DimLabel"
		rate.custom_minimum_size = Vector2(56, 0)
		_grid.add_child(icon)
		_grid.add_child(amount)
		_grid.add_child(rate)
		_rows[item.index] = [icon, amount, rate]
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	if _world.core_storage.revision != _storage_revision or _world.stats.revision != _stats_revision:
		_refresh()


func _refresh() -> void:
	var storage := _world.core_storage
	var stats := _world.stats
	_storage_revision = storage.revision
	_stats_revision = stats.revision
	var any := false
	for item in Registry.items:
		var row: Array = _rows[item.index]
		var count := storage.get_count(item.index)
		var net := stats.income_per_second(item.index) - stats.outcome_per_second(item.index)
		var row_visible := count > 0 or absf(net) > 0.001
		for control in row:
			(control as Control).visible = row_visible
		if not row_visible:
			continue
		any = true
		var amount: Label = row[1]
		amount.text = _format_amount(count)
		amount.add_theme_color_override("font_color", UiTheme.ORANGE if count >= storage.capacity else UiTheme.FG)
		amount.tooltip_text = tr("HUD_CORE_CAPACITY") % [count, storage.capacity]
		var rate: Label = row[2]
		if absf(net) < 0.05:
			rate.text = ""
		else:
			rate.text = ("+%.1f/s" if net > 0.0 else "%.1f/s") % net
			rate.add_theme_color_override("font_color", UiTheme.GREEN if net > 0.0 else UiTheme.RED)
	_empty_label.visible = not any


static func _format_amount(value: int) -> String:
	if value >= 10000:
		return "%.1fk" % (value / 1000.0)
	return str(value)
