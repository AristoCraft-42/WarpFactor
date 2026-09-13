class_name SettingEntry
extends RefCounted
## Описание одной настройки. По этим описаниям строится меню настроек
## и выполняется сохранение/загрузка.

enum Kind { BOOL, CHOICE, RANGE }

## Ключ вида "раздел/имя", например "graphics/vsync".
var key: StringName
## Вкладка меню: graphics, game, audio.
var tab: StringName
var kind: Kind = Kind.BOOL
var default_value: Variant
var label_key: String
var hint_key: String = ""
## Для CHOICE: массив пар [значение, ключ перевода или готовый текст].
var choices: Array = []
var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.05
## Показывать значение RANGE в процентах.
var percent: bool = false
## Суффикс значения RANGE (например, «×»).
var suffix: String = ""
## Применять RANGE только по отпусканию ползунка (масштаб интерфейса).
var apply_on_release: bool = false
## Неактивная настройка (функция появится позже).
var enabled: bool = true


static func make_bool(p_key: StringName, p_tab: StringName, p_default: bool, p_label: String, p_hint: String = "") -> SettingEntry:
	var e := SettingEntry.new()
	e.key = p_key
	e.tab = p_tab
	e.kind = Kind.BOOL
	e.default_value = p_default
	e.label_key = p_label
	e.hint_key = p_hint
	return e


static func make_choice(p_key: StringName, p_tab: StringName, p_default: Variant, p_label: String, p_choices: Array, p_hint: String = "") -> SettingEntry:
	var e := SettingEntry.new()
	e.key = p_key
	e.tab = p_tab
	e.kind = Kind.CHOICE
	e.default_value = p_default
	e.label_key = p_label
	e.choices = p_choices
	e.hint_key = p_hint
	return e


static func make_range(p_key: StringName, p_tab: StringName, p_default: float, p_label: String, p_min: float, p_max: float, p_step: float, p_percent: bool = false, p_hint: String = "") -> SettingEntry:
	var e := SettingEntry.new()
	e.key = p_key
	e.tab = p_tab
	e.kind = Kind.RANGE
	e.default_value = p_default
	e.label_key = p_label
	e.min_value = p_min
	e.max_value = p_max
	e.step = p_step
	e.percent = p_percent
	e.hint_key = p_hint
	return e


## Приводит значение к допустимому для этой настройки.
func sanitize(value: Variant) -> Variant:
	match kind:
		Kind.BOOL:
			return bool(value) if (value is bool or value is int) else default_value
		Kind.RANGE:
			if not (value is float or value is int):
				return default_value
			return clampf(float(value), min_value, max_value)
		Kind.CHOICE:
			for pair in choices:
				if same_value(pair[0], value):
					return pair[0]
			return default_value
	return default_value


## Сравнение без ошибок при разных типах (в GDScript 4 "a" == 1 — ошибка выполнения).
static func same_value(a: Variant, b: Variant) -> bool:
	var a_num := a is int or a is float
	var b_num := b is int or b is float
	if a_num and b_num:
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	return a == b
