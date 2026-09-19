# Проверки: тесты, автопрогон, бенчмарки

Три уровня проверки. Перед сдачей этапа прогоняются все три.
Кратко команды — в корневом `CLAUDE.md`, здесь подробности.

Путь к движку: `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`.

---

## 0. Переимпорт

```
godot --headless --path D:\Mind --import
```

Обязателен после добавления новых `class_name` и новых ресурсов, иначе сцены не найдут скрипты
и тесты упадут с загадочными ошибками загрузки. После правки только чисел в `.tres` не нужен.

---

## 0б. Проверка строк интерфейса

```
python tools/data/check_strings.py
```

Сверяет каждое `tr("KEY")` в коде со строкой в `i18n/strings.csv`: нет ли пропавшего ключа
и совпадает ли число подстановок (`%s`, `%d`, `%.1f`) с тем, что подставляет код —
в русской и английской строке. Такие ошибки не видят ни тесты, ни автопрогон: Godot печатает
«String formatting error» в консоль, а текст остаётся несобранным.

## 1. Логические тесты

```
godot --headless --path D:\Mind res://tests/test_runner.tscn
```

`tests/test_runner.gd` — плоский список функций `_test_*`, каждая печатает свои проверки.
В конце — счётчик (сейчас **1336 проверок**) и ненулевой код возврата при провале.

Что покрыто, по группам:

| Группа | Функции |
|---|---|
| Данные и загрузка | `_test_registry`, `_test_recipes_data`, `_test_enemy_data`, `_test_defense_data`, `_test_levels_load`, `_test_level_io_roundtrip` |
| Конвейеры и логистика | `_test_conveyor_*`, `_test_junction`, `_test_router*`, `_test_sorters`, `_test_bridge`, `_test_unloader*`, `_test_pass_through_chains`, `_test_logistics_throughput` |
| Производство | `_test_furnace`, `_test_assembler_power`, `_test_crafter_contents`, `_test_output_blocked`, `_test_drill_*`, `_test_coal_drill`, `_test_creative_blocks` |
| Дрон и инвентарь | `_test_drone_mining`, `_test_drone_upgrades`, `_test_inventory`, `_test_hand_crafting`, `_test_player_transfer`, `_test_build_from_inventory` |
| Энергия и жидкости | `_test_power_network`, `_test_fluids`, `_test_accumulator`, `_test_underground_pipes`, `_test_power_and_fluids_between_floors`, `_test_pipe_dragging`, `_test_pipe_layer` |
| Исследования и этажи | `_test_research`, `_test_research_tree`, `_test_research_queue`, `_test_research_effects_and_floors`, `_test_gateway_ports`, `_test_lift`, `_test_creative_research` |
| Мир и забег | `_test_star_map`, `_test_planet_generator`, `_test_teleport`, `_test_run_gateway`, `_test_breach_teleport`, `_test_gateway_growth` |
| Сохранения | `_test_save_roundtrip_and_determinism`, `_test_save_remap`, `_test_save_files`, `_test_building_state_roundtrip`, `_test_determinism`, `_test_enemy_save_determinism` |
| Игроки и команды | `_test_players`, `_test_commands`, `_test_command_order`, `_test_command_determinism` |
| Бой и оборона | `_test_enemy_attack`, `_test_flow_field`, `_test_threat_schedule`, `_test_spawn_points`, `_test_turret_*`, `_test_walls_route`, `_test_drone_gun_and_repair`, `_test_artillery` |
| Интерфейс (логика) | `_test_building_windows`, `_test_pole_drag_and_camera`, `_test_belt_drag_obstacles`, `_test_line_planner`, `_test_quick_transfer`, `_test_settings_entries`, `_test_input_codes` |

Вспомогательное — в `tests/support/`: `test_worlds.gd` (готовые миры), `test_generator.gd`,
`item_source.gd` / `item_sink.gd` (источник и приёмник предметов с известной скоростью).

### Как писать тест сохранений

Схема, которой держимся: сохранить → загрузить → сохранить снова, сравнить дампы побайтно;
затем прогнать одинаковое число тиков в обеих копиях и сравнить ещё раз. Любое действие
на загрузке (пересборка сетей, применение эффектов исследований) не должно будить постройки —
для этого у таких функций есть флаг `notify = false`.

---

## 2. Автопрогон со скриншотами

```
godot --path D:\Mind res://core/game.tscn -- --autoshot --autoshot-dir=D:/shots
godot --path D:\Mind res://ui/menu/main_menu.tscn -- --autoshot --autoshot-dir=D:/shots
```

`tests/autoshot.gd` подключается из `core/game.gd`, если в аргументах есть `--autoshot`.
Он играет в игру настоящим вводом (движение дрона, клики, горячие клавиши), проверяет состояние
и делает скриншот на каждом шаге. Сейчас **199 проверок**, около 150 секунд.

Сценарии: `_run_menu`, `_run_game`, `_run_drone`, `_run_interaction`, `_run_build_helpers`,
`_run_coal_drill`, `_run_production_chain`, `_run_factory`, `_run_logistics`, `_run_power`,
`_run_pipe_dragging`, `_run_research`,
`_run_gateway`, `_run_lift`, `_run_pad_expansion`, `_run_enemies`, `_run_defense`, `_run_breach`,
`_run_teleport`, `_run_saves`.

### Грабли

- **Автопрогон не headless.** Ему нужно видимое неперекрытое окно: Godot не отдаёт кадры
  свёрнутому или полностью закрытому окну, и прогон зависает в ожидании тиков (`_wait_ticks`)
  или завершается раньше времени. Один и тот же код может дать 171/171 и «зависнуть» —
  причина в занятом экране, а не в коде. Запускать, когда за компьютером не работают.
- Автопрогон ждёт тик после действия (`_settle`): команды применяются не мгновенно.
- Числа бенчмарков заметно пляшут, если за компьютером работают (и особенно если открыт редактор Godot): сравнивать стоит порядок величины, а не десятые доли.
- Скриншоты копятся в `--autoshot-dir`; имя файла печатается в консоль (`autoshot: <файл>`).
- Сценарий пишет в слот сохранения с именем `autoshot slot` — он перезаписывается каждым прогоном.

---

## 2б. Совместная игра

```
godot --path D:\Mind res://core/game.tscn -- --seed=99 --creative --players-check
```

`tests/players_check.gd` — отдельный прогон пути совместной игры настоящими клавишами:
Ctrl+U добавляет игроков, U переключает между ними, в том числе когда напарник на другом этаже,
а также переключение при открытом инвентаре, с постройкой в руке, с выделением и со сбитым дроном.
Нужен потому, что обычный автопрогон идёт в нетворческом забеге, где игрока не добавить.

**Грабли:** F5-F8 нельзя занимать под действия игры — их перехватывает редактор Godot
(запуск, пауза, остановка). Нажатие F8 во встроенном окне игры останавливает её, и это выглядит
как мгновенный краш без единого сообщения в логе.

## 3. Бенчмарки

```
godot --headless --path D:\Mind res://tests/bench_conveyors.tscn
godot --headless --path D:\Mind res://tests/bench_saves.tscn
godot --headless --path D:\Mind res://tests/bench_enemies.tscn
```

Ориентиры, снятые на этапе 11 (падение ниже — повод разбираться):

| Бенчмарк | Результат |
|---|---|
| Ленты (движущиеся) | ~4–5 мс на тик |
| Сохранение / загрузка | ~45–60 мс запись, ~330–440 мс чтение |
| Враги | тик забега ~9–13 мс, из них враги ~3–4 мс |
| Отрисовка (автопрогон) | ~8.5 мс на кадр, в том числе с 560 трубами на экране |
| Генерация планеты 345×324 | ~350 мс |

`tests/stress_render.gd` — отдельная проверка отрисовки, запускается вручную при подозрении
на просадку кадров.
