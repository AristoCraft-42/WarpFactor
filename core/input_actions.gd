class_name InputActions
extends RefCounted
## Действия ввода: список, раскладка по умолчанию, кодирование привязок для файла настроек.
## Клавиши привязываются по физическому коду, поэтому управление не зависит от раскладки (RU/EN).
##
## Формат привязки в настройках: "key:W", "key:Ctrl+S", "key:Shift", "mouse:1".

const GROUP_DRONE := "INPUT_GROUP_DRONE"
const GROUP_CAMERA := "INPUT_GROUP_CAMERA"
const GROUP_BUILD := "INPUT_GROUP_BUILD"
const GROUP_TIME := "INPUT_GROUP_TIME"
const GROUP_VIEW := "INPUT_GROUP_VIEW"
const GROUP_GAME := "INPUT_GROUP_GAME"

## Максимум привязок на действие в меню управления.
const SLOTS := 2
## Версия схемы управления. Сохранённые привязки старой версии сбрасываются к умолчаниям,
## если схема изменилась несовместимо (например, WASD стали двигать дрона, а не камеру).
const BINDINGS_VERSION := 3


## Описание всех действий: имя, ключ перевода, группа, привязки по умолчанию.
static func definitions() -> Array[Dictionary]:
	return [
		{"name": &"move_up", "label": "ACTION_MOVE_UP", "group": GROUP_DRONE, "events": ["key:W", "key:Up"]},
		{"name": &"move_down", "label": "ACTION_MOVE_DOWN", "group": GROUP_DRONE, "events": ["key:S", "key:Down"]},
		{"name": &"move_left", "label": "ACTION_MOVE_LEFT", "group": GROUP_DRONE, "events": ["key:A", "key:Left"]},
		{"name": &"move_right", "label": "ACTION_MOVE_RIGHT", "group": GROUP_DRONE, "events": ["key:D", "key:Right"]},
		{"name": &"inventory", "label": "ACTION_INVENTORY", "group": GROUP_DRONE, "events": ["key:E", "key:Tab"]},
		{"name": &"use_gateway", "label": "ACTION_USE_GATEWAY", "group": GROUP_DRONE, "events": ["key:F"]},
		{"name": &"cam_pan", "label": "ACTION_CAM_PAN", "group": GROUP_CAMERA, "events": ["mouse:3"]},
		{"name": &"zoom_in", "label": "ACTION_ZOOM_IN", "group": GROUP_CAMERA, "events": ["mouse:4", "key:Equal"]},
		{"name": &"zoom_out", "label": "ACTION_ZOOM_OUT", "group": GROUP_CAMERA, "events": ["mouse:5", "key:Minus"]},
		{"name": &"cam_home", "label": "ACTION_CAM_HOME", "group": GROUP_CAMERA, "events": ["key:H"]},

		{"name": &"build_primary", "label": "ACTION_BUILD_PRIMARY", "group": GROUP_BUILD, "events": ["mouse:1"]},
		{"name": &"rotate", "label": "ACTION_ROTATE", "group": GROUP_BUILD, "events": ["key:R"]},
		{"name": &"pipette", "label": "ACTION_PIPETTE", "group": GROUP_BUILD, "events": ["key:Q"]},
		{"name": &"select_area", "label": "ACTION_SELECT_AREA", "group": GROUP_BUILD, "events": ["mouse:2"]},
		{"name": &"delete_selection", "label": "ACTION_DELETE_SELECTION", "group": GROUP_BUILD, "events": ["key:X", "key:Delete"]},
		{"name": &"copy_selection", "label": "ACTION_COPY_SELECTION", "group": GROUP_BUILD, "events": ["key:C"]},
		{"name": &"cancel", "label": "ACTION_CANCEL", "group": GROUP_BUILD, "events": ["key:Escape"]},

		{"name": &"quick_save", "label": "ACTION_QUICK_SAVE", "group": GROUP_GAME, "events": ["key:F5"]},
		{"name": &"quick_load", "label": "ACTION_QUICK_LOAD", "group": GROUP_GAME, "events": ["key:F9"]},
		{"name": &"pause", "label": "ACTION_PAUSE", "group": GROUP_TIME, "events": ["key:Space"]},
		{"name": &"speed_1", "label": "ACTION_SPEED_1", "group": GROUP_TIME, "events": ["key:1"]},
		{"name": &"speed_2", "label": "ACTION_SPEED_2", "group": GROUP_TIME, "events": ["key:2"]},
		{"name": &"speed_3", "label": "ACTION_SPEED_3", "group": GROUP_TIME, "events": ["key:3"]},

		{"name": &"overlay_ores", "label": "ACTION_OVERLAY_ORES", "group": GROUP_VIEW, "events": ["key:O"]},
		{"name": &"overlay_belts", "label": "ACTION_OVERLAY_BELTS", "group": GROUP_VIEW, "events": ["key:L"]},
		{"name": &"toggle_grid", "label": "ACTION_TOGGLE_GRID", "group": GROUP_VIEW, "events": ["key:G"]},
		{"name": &"toggle_debug", "label": "ACTION_TOGGLE_DEBUG", "group": GROUP_VIEW, "events": ["key:F3"]},
	]


static func default_bindings() -> Dictionary[StringName, PackedStringArray]:
	var result: Dictionary[StringName, PackedStringArray] = {}
	for d in definitions():
		result[d["name"]] = PackedStringArray(d["events"])
	return result


## Создаёт действия в InputMap и назначает им привязки (отсутствующие берутся по умолчанию).
static func apply_bindings(bindings: Dictionary) -> void:
	for d in definitions():
		var action: StringName = d["name"]
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		InputMap.action_erase_events(action)
		var codes: PackedStringArray = bindings.get(action, PackedStringArray(d["events"]))
		for code in codes:
			var event := decode(code)
			if event != null:
				InputMap.action_add_event(action, event)


## Текущие привязки из InputMap в виде строк.
static func current_bindings() -> Dictionary[StringName, PackedStringArray]:
	var result: Dictionary[StringName, PackedStringArray] = {}
	for d in definitions():
		var action: StringName = d["name"]
		var codes := PackedStringArray()
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action):
				var code := encode(event)
				if not code.is_empty():
					codes.append(code)
		result[action] = codes
	return result


static func encode(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_NONE:
			return ""
		if _is_modifier_key(code):
			return "key:" + OS.get_keycode_string(code)
		var mods := 0
		if key.shift_pressed:
			mods |= KEY_MASK_SHIFT
		if key.ctrl_pressed:
			mods |= KEY_MASK_CTRL
		if key.alt_pressed:
			mods |= KEY_MASK_ALT
		if key.meta_pressed:
			mods |= KEY_MASK_META
		return "key:" + OS.get_keycode_string((code | mods) as Key)
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


static func decode(code: String) -> InputEvent:
	if code.begins_with("key:"):
		var full := OS.find_keycode_from_string(code.substr(4))
		var key_code := full & KEY_CODE_MASK
		if key_code == KEY_NONE:
			return null
		var event := InputEventKey.new()
		event.physical_keycode = key_code as Key
		if not _is_modifier_key(key_code):
			event.shift_pressed = (full & KEY_MASK_SHIFT) != 0
			event.ctrl_pressed = (full & KEY_MASK_CTRL) != 0
			event.alt_pressed = (full & KEY_MASK_ALT) != 0
			event.meta_pressed = (full & KEY_MASK_META) != 0
		return event
	if code.begins_with("mouse:"):
		var index := code.substr(6).to_int()
		if index <= 0:
			return null
		var event := InputEventMouseButton.new()
		event.button_index = index as MouseButton
		return event
	return null


## Подпись привязки для интерфейса.
static func label_for_code(code: String) -> String:
	if code.begins_with("key:"):
		return code.substr(4)
	if code.begins_with("mouse:"):
		match code.substr(6).to_int():
			MOUSE_BUTTON_LEFT:
				return TranslationServer.translate("MOUSE_LEFT")
			MOUSE_BUTTON_RIGHT:
				return TranslationServer.translate("MOUSE_RIGHT")
			MOUSE_BUTTON_MIDDLE:
				return TranslationServer.translate("MOUSE_MIDDLE")
			MOUSE_BUTTON_WHEEL_UP:
				return TranslationServer.translate("MOUSE_WHEEL_UP")
			MOUSE_BUTTON_WHEEL_DOWN:
				return TranslationServer.translate("MOUSE_WHEEL_DOWN")
			MOUSE_BUTTON_WHEEL_LEFT:
				return TranslationServer.translate("MOUSE_WHEEL_LEFT")
			MOUSE_BUTTON_WHEEL_RIGHT:
				return TranslationServer.translate("MOUSE_WHEEL_RIGHT")
			var other:
				return TranslationServer.translate("MOUSE_BUTTON_N") % other
	return code


## Первая привязка действия в виде подписи (для подсказок в HUD).
static func primary_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		var code := encode(event)
		if not code.is_empty():
			return label_for_code(code)
	return "—"


static func _is_modifier_key(code: int) -> bool:
	return code == KEY_SHIFT or code == KEY_CTRL or code == KEY_ALT or code == KEY_META
