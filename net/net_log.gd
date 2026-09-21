class_name NetLog
extends RefCounted
## Подробный журнал сетевой игры: подключение, лобби Steam, пакеты, команды, сверка — с временем.
##
## Пишется в user://logs/net_<дата>.log (на Windows — %APPDATA%\Godot\app_userdata\WarpFactor\logs)
## и дублируется в консоль. Файл нужен, чтобы игрок мог прислать его: сетевые поломки
## воспроизводятся только на настоящей связи между двумя компьютерами, и без записи
## остаётся гадать по симптомам.
##
## Каждая строка сбрасывается на диск сразу: журнал должен пережить и вылет игры.

const DIR := "user://logs/"
## Сколько последних журналов хранить.
const KEEP := 10

## Выключается в логических тестах: там тысячи подключений, и журнал только мешает.
static var enabled: bool = true
## Дублировать ли строки в консоль.
static var echo: bool = true

static var _file: FileAccess
static var _path: String = ""
static var _started_msec: int = 0
static var _failed: bool = false


static func write(area: String, text: String) -> void:
	if not enabled:
		return
	_open()
	var line := "%9.3f [%s] %s" % [float(Time.get_ticks_msec() - _started_msec) / 1000.0, area, text]
	if echo:
		print("[net] ", line)
	if _file != null:
		_file.store_line(line)
		_file.flush()


## Полный путь к текущему журналу (или к папке журналов, пока он не открыт).
static func path() -> String:
	return ProjectSettings.globalize_path(_path if not _path.is_empty() else DIR)


static func folder() -> String:
	return ProjectSettings.globalize_path(DIR)


static func _open() -> void:
	if _file != null or _failed:
		return
	_started_msec = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(DIR)
	_prune()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	_path = DIR + "net_%s.log" % stamp
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		_failed = true
		return
	_file.store_line("WarpFactor %s, протокол %d, %s, %s" % [
		String(ProjectSettings.get_setting("application/config/version", "?")), NetProtocol.VERSION,
		OS.get_name(), Time.get_datetime_string_from_system(false, true)])
	_file.store_line("Аргументы запуска: %s" % " ".join(OS.get_cmdline_args()))
	_file.flush()


## Удалить старые журналы, оставив KEEP - 1 последних (плюс тот, что сейчас откроется).
static func _prune() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var files := PackedStringArray()
	for name in dir.get_files():
		if name.begins_with("net_") and name.ends_with(".log"):
			files.append(name)
	files.sort()
	while files.size() >= KEEP:
		dir.remove(files[0])
		files.remove_at(0)


## Имя вида команды для журнала.
static func kind_name(kind: int) -> String:
	var keys := Command.Kind.keys()
	return String(keys[kind]) if kind >= 0 and kind < keys.size() else "?%d" % kind
