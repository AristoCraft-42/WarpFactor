# WarpFactor — карта проекта

2D-игра: фабрика + выживание + оборона мобильной базы. Godot 4.7.2, GDScript со статической
типизацией, весь баланс — в ресурсах `.tres`. Главная сцена — `ui/menu/main_menu.tscn`.
Симуляция: фиксированный тик 30/с (`Constants.TICK_RATE`), сохранения байт в байт.

## Карта каталогов

| Путь | Назначение |
|---|---|
| `core/` | Каркас: `game.gd` (сцена и аргументы), `run.gd` (забег: планета + подземный этаж + дрон), `game_world.gd` (мир, тайлы, границы), `simulation.gd` + `scheduler.gd` (тик, сон и пробуждение), `building_manager.gd` (проверки постройки), `registry.gd` (загрузка всех данных), `star_map.gd`, `gateway_link.gd`, `session.gd`, `settings.gd`, `camera_controller.gd` |
| `buildings/` | `building.gd` / `building_def.gd` + логика по группам: `transport/`, `production/`, `storage/`, `power/`, `fluid/`, `gateway/`, `defense/`. Данные построек — `buildings/defs/*.tres`. `window_section.gd` описывает панель окна здания |
| `items/` | Предметы, стаки, инвентарь, рецепты (`items/recipes/`), типы (`items/types/`) |
| `world/` | Генерация и карты: `world_gen.gd`, `level_map.gd`, руды (`ores/`), полы (`floors/`), типы планет (`planet_types/`), `run.tres` (забег и площадка), `base.tres` (подземный этаж) |
| `power/` | `power_graph.gd`: сети, баланс спроса и выработки, аккумуляторы, история для графиков |
| `fluids/` | `fluid_graph.gd`: трубы, порты построек, сети жидкостей |
| `research/` | `research_state.gd`, `research_def.gd`, дерево и эффекты — `research/defs/*.tres` |
| `enemies/`, `combat/` | Враги, волны (`threat_director.gd`), поле потоков, снаряды |
| `player/` | Дрон, очередь крафта, выпавший груз; параметры — `player/drone.tres` |
| `render/` | Отрисовка мира, предметов, врагов, оверлеи (ленты, сети, радиусы) |
| `ui/` | `hud/` (окна, панели, дерево исследований, график сети), `menu/`, `tools/` (инструменты мыши, протягивание линий) |
| `save/` | `save_io.gd` (формат и слоты), `save_context.gd` (ремап ссылок при загрузке) |
| `i18n/` | `strings.csv` — все тексты RU/EN (переводы пересобираются при импорте) |
| `levels/`, `tools/` | Тестовые карты и скрипт их сборки |
| `tests/` | `test_runner.tscn` (логические тесты), `autoshot.gd` (автопрогон со скриншотами), `bench_*.tscn` |
| `docs/` | Уровень 2 — подробности по запросу (ссылки внизу) |

## Команды

Godot: `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (далее `$g`).

```powershell
$g = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

# Переимпорт (обязателен после новых class_name и новых .tres)
& $g --headless --path D:\Mind --import

# Логические тесты (сейчас 1183 проверки)
& $g --headless --path D:\Mind res://tests/test_runner.tscn

# Автопрогон со скриншотами (НЕ headless, нужно видимое окно; 171 проверка, ~130 с)
& $g --path D:\Mind res://core/game.tscn -- --autoshot --autoshot-dir=D:/shots
& $g --path D:\Mind res://ui/menu/main_menu.tscn -- --autoshot --autoshot-dir=D:/shots

# Бенчмарки
& $g --headless --path D:\Mind res://tests/bench_conveyors.tscn   # ленты
& $g --headless --path D:\Mind res://tests/bench_saves.tscn       # сохранения
& $g --headless --path D:\Mind res://tests/bench_enemies.tscn     # бой

# Игра с готовой картой или сгенерированным забегом
& $g --path D:\Mind res://core/game.tscn -- --level=rift
& $g --path D:\Mind res://core/game.tscn -- --seed=123
```

## Грабли и правила

- **Язык.** Ответы пользователю и комментарии в коде — на русском, id сущностей и имена классов — на английском.
- **Этапы.** Один этап за ответ = играбельная сборка = один коммит. В отчёте: файлы, ручные проверки, ограничения.
- **Перед сдачей этапа** гоняются логические тесты, автопрогон и бенчмарки — все три.
- **Автопрогон зависает**, если окно Godot перекрыто или свёрнуто. Это не баг кода: запускать, когда экран свободен.
- **Сохранения.** Любая новая система обязана сохраняться и загружаться байт в байт; действия на загрузке не должны будить постройки (флаг `notify = false`).
- **Числа не в коде.** Баланс — только в `.tres`. Новый шаг расширения или порт шлюза = новый файл исследования с нужным `effects`, а не правка логики.
- **Не трогать в `.tres`:** `id`, `name_key`, `description_key`, `logic_script`, `script`, `ExtResource`, файлы `.uid`. Удаление предмета ломает старые сохранения.
- **Тексты** добавляются в `i18n/strings.csv` (ключ, EN, RU), иначе в интерфейсе появится сырой ключ.
- **Парсер GDScript:** метод не может называться как поле класса; типизированные массивы не складываются через `+`; целочисленное деление обрезает.
- **Ссылки на сети** (`PowerNetwork`, сети жидкостей) пересоздаются при пересборке — перечитывать после тиков.
- `.godot/` и `/builds/` в `.gitignore`; коммиты — по одному на этап.

## Уровень 2 — подробности

- Архитектура и подсистемы: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Тесты, автопрогон, бенчмарки: [docs/TESTING.md](docs/TESTING.md)
- Дизайн-документ: [docs/GDD.md](docs/GDD.md)
- План этапов: [docs/ROADMAP.md](docs/ROADMAP.md)
- Таблицы контента (генерируются по данным): [docs/CONTENT.md](docs/CONTENT.md)
- Управление и запуск для игрока: [README.md](README.md)
- Заметки и гайд по правке данных для автора: `D:\obsidian\obsi\WarpFactor\`
- Общая база знаний: `D:\obsidian\obsi\LoreBase\` (страница проекта — `wiki/projects/warpfactor.md`)

Держите эту карту в актуальном состоянии, если меняется структура проекта или порядок работы.
