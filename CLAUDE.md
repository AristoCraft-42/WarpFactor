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
| `world/` | Генерация и карты: `world_gen.gd`, `level_map.gd`, руды (`ores/`), полы (`floors/`), типы планет (`planet_types/`), `run.tres` (забег и площадка), `base.tres` (подземный этаж), `mining.tres` (этаж добычи) |
| `power/` | `power_graph.gd`: сети, баланс спроса и выработки, аккумуляторы, история для графиков |
| `fluids/` | `fluid_graph.gd`: трубы, порты построек, сети жидкостей |
| `research/` | `research_state.gd`, `research_def.gd`, дерево и эффекты — `research/defs/*.tres` |
| `enemies/`, `combat/` | Враги, волны (`threat_director.gd`), поле потоков, снаряды |
| `player/` | Игрок (`player.gd`), дрон, очередь крафта, выпавший груз; параметры — `player/drone.tres` |
| `render/` | Отрисовка мира, предметов, врагов, оверлеи (ленты, сети, радиусы). Тяжёлые слои (`building_layer.gd`, `pipe_layer.gd`) кэшируют отрисовку по чанкам — не рисовать мир каждый кадр обходом всех зданий |
| `ui/` | `hud/` (окна, панели, дерево исследований, график сети), `menu/`, `tools/` (инструменты мыши, протягивание линий) |
| `save/` | `save_io.gd` (формат и слоты), `save_context.gd` (ремап ссылок при загрузке) |
| `net/` | Сетевая игра: `net_transport.gd` (интерфейс доставки), `enet_transport.gd`, `net_protocol.gd` (пакеты), `net_session.gd` (lockstep), `lan_discovery.gd`; Steam — `steam_service.gd`, `steam_transport.gd`, `steam_lobbies.gd` |
| `i18n/` | `strings.csv` — все тексты RU/EN (переводы пересобираются при импорте) |
| `levels/` | Тестовые карты и их содержимое |
| `audio/` | Звук: `audio_director.gd` (автозагрузка `Audio`: звуки мира из `GameWorld.sounds`, интерфейс, музыка по обстановке), `sound_log.gd`, синтез заглушек (`synth.gd`, `placeholder_sounds.gd`, `placeholder_music.gd`). Свои файлы — `audio/sfx/`, `audio/music/`, формат в `audio/README.md` |
| `art/buildings/` | Нарисованные спрайты зданий: `<id>.png` — полоса из трёх кадров (работа, простой, выключено). Формат и экспорт из Aseprite — `art/buildings/README.md` |
| `tools/data/` | Python-генераторы данных: `make_content.py` (постройки, предметы, рецепты, исследования), `make_csv.py` (`i18n/strings.csv`), `make_content_doc.py` (`docs/CONTENT.md`), `make_enemies.py`. Правки контента делаются в них, а не в `.tres` руками |
| `tests/` | `test_runner.tscn` (логические тесты), `autoshot.gd` (автопрогон со скриншотами), `bench_*.tscn` |
| `docs/` | Уровень 2 — подробности по запросу (ссылки внизу) |

## Команды

Godot: `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (далее `$g`).

```powershell
$g = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

# Переимпорт (обязателен после новых class_name и новых .tres)
& $g --headless --path D:\Mind --import

# Проверка строк интерфейса (подстановки %s/%d и пропавшие ключи)
python tools/data/check_strings.py

# Сетевой прогон через настоящий ENet на 127.0.0.1
& $g --headless --path D:\Mind res://tests/net_check.tscn

# Настоящая игровая сцена в роли клиента: снимок, починка, сверка состояний
& $g --headless --path D:\Mind res://tests/net_scene_check.tscn

# Логические тесты (сейчас 2002 проверки)
& $g --headless --path D:\Mind res://tests/test_runner.tscn

# Автопрогон со скриншотами (НЕ headless, нужно видимое неперекрытое окно; 237 проверок, ~8 мин)
& $g --path D:\Mind res://core/game.tscn -- --autoshot --autoshot-dir=D:/shots
& $g --path D:\Mind res://ui/menu/main_menu.tscn -- --autoshot --autoshot-dir=D:/shots

# Бенчмарки
& $g --headless --path D:\Mind res://tests/bench_conveyors.tscn   # ленты
& $g --headless --path D:\Mind res://tests/bench_saves.tscn       # сохранения
& $g --headless --path D:\Mind res://tests/bench_enemies.tscn     # бой
& $g --headless --path D:\Mind res://tests/bench_turrets.tscn     # турели (тик и перерисовки)

# Послушать звуки и музыку без игры (WAV в D:/shots/audio)
& $g --headless --path D:\Mind --script res://tools/preview_audio.gd

# Игра с готовой картой или сгенерированным забегом
& $g --path D:\Mind res://core/game.tscn -- --level=rift
& $g --path D:\Mind res://core/game.tscn -- --seed=123
```

## Грабли и правила

- **Язык.** Ответы пользователю и комментарии в коде — на русском, id сущностей и имена классов — на английском.
- **Этапы.** Один этап за ответ = играбельная сборка = один коммит. В отчёте: файлы, ручные проверки, ограничения.
- **Перед сдачей этапа** гоняются логические тесты, автопрогон и бенчмарки — все три.
- **Автопрогон зависает или начинает врать**, если окно Godot перекрыто, свёрнуто или машина занята (открыт редактор, идёт другая игра). Это не баг кода: запускать, когда экран свободен.
- **Отладочные прогоны запускаются из `Game._start`** (`--autoshot`, `--players-check`, `--stress=`). Однажды этот блок уехал в `_on_teleport_starting` при разборе `_start` на части — автопрогон просто не стартовал, а выглядело это как «зависает». Если прогон молчит и не делает снимков, первым делом смотреть, вызывается ли этот блок.
- **F5-F8 не занимать под действия игры**: их перехватывает редактор Godot (запуск, пауза, остановка). Нажатие F8 во встроенном окне игры просто останавливает её — выглядит как мгновенный краш.
- **Сохранения.** Любая новая система обязана сохраняться и загружаться байт в байт; действия на загрузке не должны будить постройки (флаг `notify = false`).
- **Мир меняется только командами.** Интерфейс вызывает `world.submit(Command.Kind...)`, а не `build/demolish/configure` напрямую: команды применяются в начале тика в порядке (игрок, номер) — на этом держится будущая сетевая игра. Действие применяется в ближайшем тике, а не мгновенно.
- **Дрон не один.** Локальный — `run.drone`, действующий — `world.acting_drone()`, все в мире — `world.drones`.
- **Аддон GodotSteam необязателен.** Обращаться к нему только через `Engine.get_singleton("Steam")` и `has_method`/`call`, иначе проект перестанет собираться без аддона.
- **В сетевой игре команда не применяется сразу:** она уходит хосту и возвращается в составе тика. Всё, что влияет на симуляцию, обязано идти командой; пауза и скорость — наоборот, мимо тиков (пакет TIME).
- **Числа не в коде.** Баланс — только в `.tres`. Новый шаг расширения, порт шлюза или ступень дрона = новый файл исследования с нужным `effects`, а не правка логики.
- **Контент генерируется.** Таблицы построек, рецептов, исследований и строк живут в `tools/data/*.py`; после правки таблицы прогнать `make_content.py`, `make_csv.py`, `make_content_doc.py` и переимпорт.
- **Не трогать в `.tres`:** `id`, `name_key`, `description_key`, `logic_script`, `script`, `ExtResource`, файлы `.uid`. Удаление предмета ломает старые сохранения.
- **Тексты** добавляются в `i18n/strings.csv` (ключ, EN, RU), иначе в интерфейсе появится сырой ключ.
- **Парсер GDScript:** метод не может называться как поле класса; типизированные массивы не складываются через `+`; целочисленное деление обрезает.
- **Ссылки на сети** (`PowerNetwork`, сети жидкостей) пересоздаются при пересборке — перечитывать после тиков.
- **Звук только читает мир.** Новые звуки мира — `world.sounds.push(SoundLog.Kind…)` в симуляции плюс строка в `AudioDirector.KIND_SOUNDS` и рецепт в `PlaceholderSounds`; из звука в симуляцию ничего не возвращается.
- **Размер здания** берётся из `Building.get_size()`, а не из `def.size`: шлюз растёт по исследованиям.
- `.godot/` и `/builds/` в `.gitignore`; коммиты — по одному на этап.

## Уровень 2 — подробности

- Архитектура и подсистемы: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Steam: установка аддона, App ID, известные проблемы: [docs/STEAM.md](docs/STEAM.md)
- Тесты, автопрогон, бенчмарки: [docs/TESTING.md](docs/TESTING.md)
- Дизайн-документ: [docs/GDD.md](docs/GDD.md)
- План этапов: [docs/ROADMAP.md](docs/ROADMAP.md)
- Таблицы контента (генерируются по данным, весь файл — таблицы; у построек есть id и размер полосы спрайта): [docs/CONTENT.md](docs/CONTENT.md)
- Управление и запуск для игрока: [README.md](README.md)
- Заметки и гайд по правке данных для автора: `D:\obsidian\obsi\WarpFactor\`
- Общая база знаний: `D:\obsidian\obsi\LoreBase\` (страница проекта — `wiki/projects/warpfactor.md`)

Держите эту карту в актуальном состоянии, если меняется структура проекта или порядок работы.
