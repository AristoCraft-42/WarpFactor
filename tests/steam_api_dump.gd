extends Node
## Служебный дамп: какие функции и сигналы на самом деле есть в установленном GodotSteam.

const WANTED := ["steamInitEx", "steamInit", "run_callbacks", "steamShutdown", "getSteamID", "getPersonaName",
	"sendP2PPacket", "readP2PPacket", "getAvailableP2PPacketSize", "acceptP2PSessionWithUser",
	"closeP2PSessionWithUser", "createLobby", "joinLobby", "leaveLobby", "setLobbyData", "getLobbyData",
	"getLobbyOwner", "requestLobbyList", "addRequestLobbyListStringFilter", "activateGameOverlayInviteDialog"]

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		print("нет Steam")
		get_tree().quit(1)
		return
	var steam := Engine.get_singleton("Steam")
	var found := {}
	for m in steam.get_method_list():
		found[String(m["name"])] = m
	for name in WANTED:
		if not found.has(name):
			print("— нет: ", name)
			continue
		var args := PackedStringArray()
		for a in (found[name]["args"] as Array):
			args.append("%s: %s" % [a["name"], type_string(int(a["type"]))])
		print("%s(%s)" % [name, ", ".join(args)])
	var signals := PackedStringArray()
	for s in steam.get_signal_list():
		var n := String(s["name"])
		if n.begins_with("p2p") or n.begins_with("lobby") or n.begins_with("join"):
			signals.append(n)
	print("сигналы: ", ", ".join(signals))
	for sig in steam.get_signal_list():
		if String(sig["name"]) in ["lobby_match_list", "lobby_created", "lobby_joined"]:
			var args := PackedStringArray()
			for a in (sig["args"] as Array):
				args.append("%s: %s" % [a["name"], type_string(int(a["type"]))])
			print("сигнал %s(%s)" % [sig["name"], ", ".join(args)])
	for name in ClassDB.class_get_integer_constant_list("Steam"):
		var text := String(name)
		if text.begins_with("LOBBY_COMPARISON") or text.begins_with("LOBBY_DISTANCE") or text.begins_with("LOBBY_TYPE"):
			print("%s = %d" % [text, ClassDB.class_get_integer_constant("Steam", name)])
	get_tree().quit(0)
