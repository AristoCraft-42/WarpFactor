extends Node
## Параметры текущего запуска и переходы между сценами (автозагрузка Session).

const MENU_SCENE := "res://ui/menu/main_menu.tscn"
const GAME_SCENE := "res://core/game.tscn"

## Уровень, который нужно запустить в игровой сцене (разработка и тесты).
var level: LevelDef
## Сид нового забега (-1 — забег не выбран, запускается уровень).
var run_seed: int = -1
## Творческий режим: постройки не расходуются, радиус дрона не ограничен.
var creative: bool = false


## Новый забег: первая планета генерируется по сиду.
func start_run(p_seed: int, p_creative: bool) -> void:
	run_seed = p_seed
	level = null
	creative = p_creative
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func start_level(level_def: LevelDef, p_creative: bool) -> void:
	level = level_def
	run_seed = -1
	creative = p_creative
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func exit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func quit_game() -> void:
	Settings.save_now()
	get_tree().quit()
