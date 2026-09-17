class_name GatewayDef
extends BuildingDef
## Центральный шлюз (на планете) и его пара на подземном этаже.
## Порты — тайлы сторон inbound_side (в базу) и outbound_side (наружу): сначала открыт средний, исследования
## «Порты шлюза» открывают крайние (до трёх на сторону). Пара зеркальна: предмет, вошедший в шлюз с западной
## стороны, выходит из западной стороны пары; вошедший в пару с восточной — выходит из шлюза на восток.

## Здание стоит в базе (пара), а не на планете.
@export var in_base: bool = false
@export var inbound_side: int = GameConst.Dir.LEFT
@export var outbound_side: int = GameConst.Dir.RIGHT
## Сколько предметов ждёт перехода в каждую сторону.
@export var buffer_capacity: int = 10
## Скорость портов — как у этой ленты.
@export var throughput_of: ConveyorDef


func get_ticks_per_item() -> int:
	return throughput_of.get_ticks_per_item() if throughput_of != null else 1


## Тайл снаружи середины стороны side для здания с левым верхним тайлом origin.
func get_port_tile(origin: Vector2i, side: int) -> Vector2i:
	var half := size / 2
	return origin + Vector2i(half, half) + GameConst.dir_vector(side) * (half + 1)


## Тайлы портов стороны side: первые count из порядка «середина, затем по краям».
func get_port_tiles(origin: Vector2i, side: int, count: int) -> Array[Vector2i]:
	var middle := get_port_tile(origin, side)
	var dir := GameConst.dir_vector(side)
	var along := Vector2i(-dir.y, dir.x)
	var result: Array[Vector2i] = [middle]
	var half := size / 2
	for k in range(1, half + 1):
		result.append(middle - along * k)
		result.append(middle + along * k)
	return result.slice(0, clampi(count, 0, result.size()))


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_THROUGHPUT") % (float(GameConst.TICK_RATE) / get_ticks_per_item())])
