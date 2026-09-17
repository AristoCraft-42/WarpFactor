class_name Accumulator
extends Building
## Аккумулятор в зоне опоры: сеть заряжает его излишком выработки и разряжает при нехватке
## (PowerGraph.balance), не быстрее max_rate. Запас сохраняется и переезжает вместе с площадкой.

var stored_kj: float = 0.0
## Поток на прошлом тике, кВт: + заряд, − разряд.
var last_flow_kw: float = 0.0


func get_accumulator_def() -> AccumulatorDef:
	return def as AccumulatorDef


func is_power_storage() -> bool:
	return true


## Сколько можно отдать за dt секунд, кДж.
func get_discharge_limit_kj(dt: float) -> float:
	return minf(stored_kj, get_accumulator_def().max_rate * dt)


## Сколько можно принять за dt секунд, кДж.
func get_charge_limit_kj(dt: float) -> float:
	var d := get_accumulator_def()
	return minf(maxf(d.capacity_kj - stored_kj, 0.0), d.max_rate * dt)


## Изменить запас на kj (+ заряд, − разряд).
func apply_flow_kj(kj: float, dt: float) -> void:
	stored_kj = clampf(stored_kj + kj, 0.0, get_accumulator_def().capacity_kj)
	last_flow_kw = kj / dt


func save_state() -> Dictionary:
	return {"stored": stored_kj}


func load_state(state: Dictionary) -> void:
	stored_kj = clampf(float(state.get("stored", 0.0)), 0.0, get_accumulator_def().capacity_kj)


func get_status() -> Status:
	if power_net == null:
		return Status.NO_POWER
	return Status.WORKING if absf(last_flow_kw) > 0.01 else Status.IDLE


func get_info_lines() -> PackedStringArray:
	var d := get_accumulator_def()
	var lines := PackedStringArray([tr("INFO_ACCUMULATOR_CHARGE") % [stored_kj / 1000.0, d.capacity_kj / 1000.0]])
	if power_net == null:
		lines.append(tr("INFO_NO_POLE"))
	elif last_flow_kw > 0.01:
		lines.append(tr("INFO_ACCUMULATOR_CHARGING") % roundi(last_flow_kw))
	elif last_flow_kw < -0.01:
		lines.append(tr("INFO_ACCUMULATOR_DISCHARGING") % roundi(-last_flow_kw))
	return lines


func get_window_sections() -> Array[WindowSection]:
	var d := get_accumulator_def()
	var share := stored_kj / maxf(d.capacity_kj, 1.0)
	var flow_text := tr("WINDOW_KW_OF") % [roundi(absf(last_flow_kw)), roundi(d.max_rate)]
	var flow_title := tr("WINDOW_DISCHARGE") if last_flow_kw < 0.0 else tr("WINDOW_CHARGE_RATE")
	return [
		WindowSection.bar(tr("WINDOW_STORED"), share, tr("WINDOW_MJ_OF") % [stored_kj / 1000.0, d.capacity_kj / 1000.0], WindowSection.COLOR_POWER),
		WindowSection.bar(flow_title, absf(last_flow_kw) / maxf(d.max_rate, 0.001), flow_text,
			WindowSection.COLOR_FUEL if last_flow_kw < 0.0 else WindowSection.COLOR_PROGRESS),
	]
