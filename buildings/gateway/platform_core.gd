class_name PlatformCore
extends PlatformEnd
## Якорь платформы добычи: центр платформы, который уезжает на планету вместе со всем, что на ней
## стоит. Через него добытое уходит в комнату, а с базы приходят топливо и патроны; по нему же
## дрон переходит между комнатой и платформой (F).
## Не сносится: без якоря платформу было бы не отозвать.


func save_state() -> Dictionary:
	return {"room": room, "next_out": _next_out}


func load_state(data: Dictionary) -> void:
	room = int(data.get("room", room))
	_next_out = int(data.get("next_out", 0))
	wake()
