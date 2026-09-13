extends Node
## Шина событий для интерфейса (автозагрузка Events).
## Симуляция через сигналы не работает — только UI и уведомления.

enum ToastKind { INFO, SUCCESS, WARNING }

## Показать всплывающее уведомление.
signal toast_requested(text: String, kind: ToastKind)


func toast(text: String, kind: ToastKind = ToastKind.INFO) -> void:
	toast_requested.emit(text, kind)
