extends Node
## Параметры текущего запуска и переходы между сценами (автозагрузка Session).

const MENU_SCENE := "res://ui/menu/main_menu.tscn"
const GAME_SCENE := "res://core/game.tscn"

## Уровень, который нужно запустить в игровой сцене (разработка и тесты).
var level: LevelDef
## Сид нового забега (-1 — забег не выбран, запускается уровень).
var run_seed: int = -1
## Файл сохранения, который нужно загрузить при старте игровой сцены (пусто — не загружать).
var load_path: String = ""
## Творческий режим: постройки не расходуются, радиус дрона не ограничен.
var creative: bool = false
## Совместная игра: одна на всё приложение, переживает смену сцен.
var net := NetSession.new()
## Имя игрока в сети.
var player_name: String = ""
## Поиск игр в локальной сети (создаётся по требованию).
var discovery: LanDiscovery


func _process(_delta: float) -> void:
	# Транспорт опрашивается и в меню: так работает подключение до загрузки игровой сцены.
	if net.is_networked():
		net.poll()
	if discovery != null:
		discovery.poll()


## Имя игрока: из настроек (там оно и правится), иначе имя пользователя системы.
func get_player_name() -> String:
	if not player_name.is_empty():
		return player_name
	var saved := Settings.get_string(&"game/player_name").strip_edges()
	return saved if not saved.is_empty() else "Player"


## Загрузить сохранение: игровая сцена перезапускается и берёт забег из файла.
func load_game(path: String) -> void:
	load_path = path
	run_seed = -1
	level = null
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## Новый забег: первая планета генерируется по сиду.
func start_run(p_seed: int, p_creative: bool) -> void:
	load_path = ""
	run_seed = p_seed
	level = null
	creative = p_creative
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func start_level(level_def: LevelDef, p_creative: bool) -> void:
	load_path = ""
	level = level_def
	run_seed = -1
	creative = p_creative
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func exit_to_menu() -> void:
	net.close()
	if discovery != null:
		discovery.stop()
		discovery = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func quit_game() -> void:
	Settings.save_now()
	get_tree().quit()
