extends SceneTree
## Проверка, виден ли Steam: запускается без игры.
## godot --headless --path D:\Mind --script res://tests/steam_probe.gd

func _init() -> void:
	var has := Engine.has_singleton("Steam")
	print("Аддон GodotSteam загружен: ", "да" if has else "нет")
	if has:
		var steam := Engine.get_singleton("Steam")
		if steam.has_method("get_godotsteam_version"):
			print("Версия GodotSteam: ", steam.call("get_godotsteam_version"))
		print("Steam запущен: ", "да" if SteamService.start() else "нет (%s)" % SteamService.status())
		if SteamService.is_ready():
			print("Steam ID: ", SteamService.self_id(), ", имя: ", SteamService.self_name())
	else:
		print("Игра работает без Steam: остаются локальная сеть и прямой адрес (docs/STEAM.md).")
	quit()
