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
	get_tree().quit(0)
