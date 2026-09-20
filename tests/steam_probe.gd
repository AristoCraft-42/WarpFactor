extends Node
## Проверка, виден ли Steam и завёлся ли он.
## Запуск: godot --headless --path D:\Mind res://tests/steam_probe.tscn

func _ready() -> void:
	var has := Engine.has_singleton("Steam")
	print("Аддон GodotSteam загружен: ", "да" if has else "нет")
	if has:
		var steam := Engine.get_singleton("Steam")
		if steam.has_method("get_godotsteam_version"):
			print("Версия GodotSteam: ", steam.call("get_godotsteam_version"))
		print("App ID: ", SteamService.app_id())
		var ready := SteamService.start()
		print("Steam запущен: ", "да" if ready else "нет (%s)" % SteamService.status())
		if ready:
			print("Steam ID: ", SteamService.self_id(), ", имя: ", SteamService.self_name())
	else:
		print("Игра работает без Steam: остаются локальная сеть и прямой адрес (docs/STEAM.md).")
	get_tree().quit(0)
