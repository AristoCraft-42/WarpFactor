extends Node
## Параметры текущего запуска и переходы между сценами (автозагрузка Session).

const MENU_SCENE := "res://ui/menu/main_menu.tscn"
const GAME_SCENE := "res://core/game.tscn"

## Уровень, который нужно запустить в игровой сцене.
var level: LevelDef
var sandbox: bool = false


func start_level(level_def: LevelDef, p_sandbox: bool) -> void:
	level = level_def
	sandbox = p_sandbox
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func exit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func quit_game() -> void:
	Settings.save_now()
	get_tree().quit()
