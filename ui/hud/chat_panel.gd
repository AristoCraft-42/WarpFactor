class_name ChatPanel
extends VBoxContainer
## Чат совместной игры: последние сообщения слева внизу и строка ввода по Enter.
##
## Сообщения идут мимо тиков (NetSession.send_chat) — на мир они не влияют, поэтому и в отпечаток
## состояния не попадают. Имя отправителя пишется его цветом, старые сообщения тускнеют и уходят.

const HISTORY := 8
## Сколько секунд сообщение видно, когда строка ввода закрыта.
const FADE_SECONDS := 12.0

var _game: Game
var _list: VBoxContainer
var _input: LineEdit
## Время появления каждой строки (для угасания).
var _shown: Array[float] = []


func setup(game: Game) -> void:
	_game = game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_list = UiUtil.vbox(2)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	_input = LineEdit.new()
	_input.placeholder_text = "CHAT_PLACEHOLDER"
	_input.custom_minimum_size = Vector2(420, 0)
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	add_child(_input)
	Session.net.chat_received.connect(_on_received)


func is_typing() -> bool:
	return _input.visible


## Открыть строку ввода (Enter). В одиночной игре чат тоже работает — пишет сам себе.
func open_input() -> void:
	_input.visible = true
	_input.grab_focus()


func close_input() -> void:
	_input.visible = false
	_input.text = ""
	_input.release_focus()


func _on_submitted(text: String) -> void:
	Session.net.send_chat(text, _game.run.local_player if _game != null and _game.run != null else 0)
	close_input()


func _on_received(player_id: int, text: String) -> void:
	var player := _game.run.get_player(player_id)
	var line := Label.new()
	line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	line.theme_type_variation = &"ChatLabel"
	line.text = "%s: %s" % [player.name if player != null else "?", text]
	# Имя и текст пишутся цветом игрока, но на тёмной подложке — цвет чуть высветляем.
	line.add_theme_color_override("font_color", player.color.lightened(0.25) if player != null else UiTheme.FG)
	_list.add_child(line)
	_shown.append(Time.get_ticks_msec() / 1000.0)
	while _list.get_child_count() > HISTORY:
		var old := _list.get_child(0)
		_list.remove_child(old)
		old.queue_free()
		_shown.remove_at(0)


func _process(_delta: float) -> void:
	# Пока пишешь, история видна целиком; в остальное время старые строки тускнеют и уходят.
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_list.get_child_count() - 1, -1, -1):
		var line := _list.get_child(i) as Control
		if i >= _shown.size():
			continue
		var age := now - _shown[i]
		if _input.visible:
			line.modulate.a = 1.0
			continue
		if age > FADE_SECONDS:
			_list.remove_child(line)
			line.queue_free()
			_shown.remove_at(i)
			continue
		line.modulate.a = clampf((FADE_SECONDS - age) / 2.0, 0.0, 1.0)
