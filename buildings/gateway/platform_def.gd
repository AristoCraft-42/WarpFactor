class_name PlatformDef
extends BuildingDef
## Пульт платформы добычи (в комнате) и её якорь (на самой платформе): у обоих одни и те же числа,
## потому что это два конца одной связи.

## Сколько предметов ждёт перехода в одну сторону.
@export var buffer_capacity: int = 20
## Скорость выдачи — как у этой ленты.
@export var throughput_of: ConveyorDef
## Сколько секунд платформа разворачивается на планете и столько же сворачивается обратно.
@export var deploy_seconds: float = 6.0
## Якорь (иначе — пульт в комнате).
@export var is_core: bool = false


func get_ticks_per_item() -> int:
	return throughput_of.get_ticks_per_item() if throughput_of != null else 1


func get_deploy_ticks() -> int:
	return maxi(roundi(deploy_seconds * GameConst.TICK_RATE), 1)


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_THROUGHPUT") % (float(GameConst.TICK_RATE) / get_ticks_per_item()),
		tr("STAT_DEPLOY_TIME") % deploy_seconds])
