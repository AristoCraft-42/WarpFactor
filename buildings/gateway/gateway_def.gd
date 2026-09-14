class_name GatewayDef
extends BuildingDef
## Центральный шлюз (на планете) и его пара в базе.
## Порта два и они фиксированы: вход в базу — середина стороны inbound_side, выход наружу — середина
## outbound_side. Пара в базе зеркальна: предмет, вошедший в шлюз с западной стороны, выходит из
## западной стороны пары; предмет, вошедший в пару с восточной стороны, выходит из шлюза на восток.

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


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_THROUGHPUT") % (float(GameConst.TICK_RATE) / get_ticks_per_item())])
