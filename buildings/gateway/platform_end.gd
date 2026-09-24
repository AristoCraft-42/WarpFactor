class_name PlatformEnd
extends Building
## Общий конец связи платформы добычи: пульт в комнате и якорь на платформе.
## Пока платформа развёрнута, предметы ходят между ними очередями (PlatformLink): якорь собирает
## добытое и отдаёт его пульту, пульт отправляет обратно топливо, патроны и всё, что ему приносят.
## Пока платформа стоит в комнате, связь не работает — якорь и пульт стоят рядом, ленты идут напрямую.

## Номер комнаты добычи (0..3): по нему пульт и якорь находят друг друга после загрузки.
var room: int = 0
var link: PlatformLink

var _next_out: int = 0


func get_platform_def() -> PlatformDef:
	return def as PlatformDef


## Якорь кладёт предметы в очередь «к базе», пульт — в очередь «на платформу».
func pushes_to_base() -> bool:
	return get_platform_def().is_core


## Связь работает, только когда концы в разных мирах (платформа развёрнута).
func is_linked() -> bool:
	if link == null or link.console == null or link.core == null:
		return false
	return link.console.world != null and link.core.world != null and link.console.world != link.core.world


func other_end() -> PlatformEnd:
	if link == null:
		return null
	return link.console if pushes_to_base() else link.core


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


func accept_item(_source: Building, _item: int) -> bool:
	return is_linked() and link.has_space(pushes_to_base())


func handle_item(_source: Building, item: int) -> void:
	link.push(pushes_to_base(), item)
	var other := other_end()
	if other != null and other.world != null:
		other.wake()


func update_tick(tick: int) -> bool:
	if not is_linked():
		return false
	# Пульт забирает из очереди «к базе», якорь — из очереди «на платформу».
	var incoming := not pushes_to_base()
	if link.size_of(incoming) == 0:
		return false
	if tick < _next_out:
		sleep_until(_next_out)
		return false
	var item := link.peek(incoming)
	if not dump(item):
		wait_for_proximity()
		return false
	link.pop(incoming)
	_next_out = tick + get_platform_def().get_ticks_per_item()
	var other := other_end()
	if other != null and other.world != null:
		# В очереди освободилось место — тот конец может отдавать дальше.
		other.notify_space()
	if link.size_of(incoming) > 0:
		sleep_until(_next_out)
	return false


func collect_contents(out: PackedInt32Array) -> void:
	# Предметы в пути считаются один раз — за них отвечает пульт.
	if link != null and not pushes_to_base():
		link.collect(out)


func get_info_lines() -> PackedStringArray:
	if link == null:
		return PackedStringArray()
	return PackedStringArray([tr("INFO_PLATFORM_QUEUE") % [link.size_of(true), link.size_of(false)]])
