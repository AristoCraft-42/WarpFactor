class_name WindowSection
extends RefCounted
## Раздел окна здания: ряд ячеек (сырьё, топливо, продукт, запас) или полоска (прогресс крафта, питание,
## жидкость, мощность). Здание собирает разделы в get_window_sections(), окно рисует их по порядку.
## Клик по ячейке забирает предмет (take_player_items), клик по инвентарю кладёт (accept_item сам решает,
## куда: топливо — в топливо, сырьё — во вход).

enum Kind { SLOTS, BAR }

const COLOR_PROGRESS := Color(0.98, 0.74, 0.18)
const COLOR_POWER := Color(0.72, 0.73, 0.15)
const COLOR_FUEL := Color(0.99, 0.5, 0.1)
const COLOR_LOW := Color(0.98, 0.29, 0.2)

var kind: Kind = Kind.SLOTS
var title: String = ""
## Ячейки: (предмет, количество); предмет -1 — пустая ячейка.
var stacks: Array[Vector2i] = []
## Для пустой ячейки — бледная иконка того, что сюда кладётся (-1 — без подсказки).
var hints: PackedInt32Array = PackedInt32Array()
## Можно ли забирать из этих ячеек.
var can_take: bool = true
## Полоска: доля 0..1 и подпись.
var fraction: float = 0.0
var text: String = ""
var color: Color = COLOR_PROGRESS


static func slots(p_title: String, p_stacks: Array[Vector2i], p_hints: PackedInt32Array = PackedInt32Array(), p_can_take: bool = true) -> WindowSection:
	var s := WindowSection.new()
	s.kind = Kind.SLOTS
	s.title = p_title
	s.stacks = p_stacks
	s.hints = p_hints
	s.can_take = p_can_take
	return s


static func bar(p_title: String, p_fraction: float, p_text: String, p_color: Color = COLOR_PROGRESS) -> WindowSection:
	var s := WindowSection.new()
	s.kind = Kind.BAR
	s.title = p_title
	s.fraction = clampf(p_fraction, 0.0, 1.0)
	s.text = p_text
	s.color = p_color
	return s


## Полоска прогресса в процентах.
static func progress(p_fraction: float) -> WindowSection:
	return bar(TranslationServer.translate("WINDOW_PROGRESS"), p_fraction, "%d%%" % roundi(clampf(p_fraction, 0.0, 1.0) * 100.0))


## Одна ячейка с запасом предмета item (hint — что сюда кладётся, если пусто).
static func single(p_title: String, item: int, count: int, hint: int, p_can_take: bool = true) -> WindowSection:
	var stack := Vector2i(item, count) if item >= 0 and count > 0 else Vector2i(-1, 0)
	return slots(p_title, [stack], PackedInt32Array([hint]), p_can_take)


## Первый предмет-топливо реестра (подсказка для пустой ячейки топлива).
static func fuel_hint() -> int:
	for item in Registry.items:
		if item.is_fuel():
			return item.index
	return -1


## Ячейка топлива из массива количеств по предметам.
static func fuel_slot(counts: PackedInt32Array) -> WindowSection:
	var item := -1
	for i in counts.size():
		if counts[i] > 0:
			item = i
			break
	return single(TranslationServer.translate("WINDOW_FUEL"), item, counts[item] if item >= 0 else 0, fuel_hint())


## Полоска питания потребителя: доля удовлетворённости сети.
static func power(building: Building) -> WindowSection:
	if building.power_net == null:
		return bar(TranslationServer.translate("WINDOW_POWER"), 0.0, TranslationServer.translate("WINDOW_NO_POLE"), COLOR_LOW)
	var satisfaction := building.get_power_satisfaction()
	return bar(TranslationServer.translate("WINDOW_POWER"), satisfaction,
		TranslationServer.translate("WINDOW_POWER_VALUE") % [roundi(satisfaction * 100.0), roundi(building.def.power_use)],
		COLOR_POWER if satisfaction >= 0.999 else COLOR_PROGRESS)


## Полоска жидкости сети (null — не подключено).
static func fluid(p_title: String, net: FluidGraph.FluidNetwork) -> WindowSection:
	if net == null or net.capacity <= 0.0:
		return bar(p_title, 0.0, TranslationServer.translate("WINDOW_NOT_CONNECTED"), COLOR_LOW)
	var col := Registry.fluids[net.fluid].color if net.fluid >= 0 else Color(0.5, 0.5, 0.5)
	var prefix := TranslationServer.translate(Registry.fluids[net.fluid].name_key) + " · " if net.fluid >= 0 else ""
	return bar(p_title, net.amount / net.capacity, "%s%d / %d" % [prefix, roundi(net.amount), roundi(net.capacity)], col)


## Полоска горения: сколько осталось от текущей порции топлива (энергия одной единицы — как у подсказки).
static func burn(energy: float) -> WindowSection:
	var hint := fuel_hint()
	var full := Registry.items[hint].fuel_value if hint >= 0 else 1.0
	var share := clampf(energy / maxf(full, 1.0), 0.0, 1.0)
	return bar(TranslationServer.translate("WINDOW_BURN"), share, "%d%%" % roundi(share * 100.0), COLOR_FUEL)


## Полоска мощности генератора.
static func output(kw: float, max_kw: float) -> WindowSection:
	return bar(TranslationServer.translate("WINDOW_OUTPUT"), kw / maxf(max_kw, 0.001),
		TranslationServer.translate("WINDOW_KW_OF") % [roundi(kw), roundi(max_kw)], COLOR_POWER)
