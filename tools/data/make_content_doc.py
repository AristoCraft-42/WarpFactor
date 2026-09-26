"""Генерирует docs/CONTENT.md из таблиц make_content.py и строк i18n/strings.csv."""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
src = open(os.path.join(HERE, "make_content.py"), encoding="utf-8").read()
data_part = src[:src.index("def item_path(")]
ns = {"__file__": os.path.join(HERE, "make_content.py")}
exec(data_part, ns)

names = {}
with open(os.path.join(ROOT, "i18n", "strings.csv"), encoding="utf-8") as f:
    for row in csv.reader(f):
        if len(row) >= 3:
            names[row[0]] = row[2]


def item_name(i):
    for key in ("ITEM_" + i.upper(), "BUILDING_" + i.upper(), "FLUID_" + i.upper()):
        if key in names:
            return names[key]
    return i


def building_name(b):
    return names.get("BUILDING_" + b.upper(), b)


def fmt(v):
    if isinstance(v, float):
        return ("%.2f" % v).rstrip("0").rstrip(".")
    return str(v)


def stacks(lst):
    """Входы и выходы текстом. «any:<группа>» — любые разные предметы группы, «fluid:<id>» — жидкость."""
    if not lst:
        return "—"
    parts = []
    groups = {}
    for key, amount in lst:
        if key.startswith("any:"):
            groups.setdefault(key[4:], []).append(amount)
        elif key.startswith("fluid:"):
            parts.append("%s ×%s (по трубам)" % (item_name(key[6:]), fmt(amount)))
        else:
            parts.append("%s ×%s" % (item_name(key), fmt(amount)))
    for group, amounts in groups.items():
        members = ", ".join(item_name(i) for i in ns["ITEM_GROUPS"][group])
        parts.append("%d разных вида из «%s» по %s (%s)" % (len(amounts), names.get(ns["GROUP_KEYS"][group], group),
                                                          fmt(amounts[0]), members))
    return ", ".join(parts)


ITEMS = ns["ITEMS"]
ORES = ns["ORES"]
RECIPES = ns["RECIPES"]
BUILDINGS = ns["BUILDINGS"]
RESEARCH = ns["RESEARCH"]
MG_AMMO = ns["MG_AMMO"]
kit2_amount = ns["kit2_amount"]
research_costs = ns["research_costs"]
START_ITEMS = ns["START_ITEMS"]
CATEGORIES = ["Логистика", "Производство", "Энергия", "Оборона"]

research_of = {}
for rid, _, cost, pre, blds, recs, _effects in RESEARCH:
    for b in blds:
        research_of[b] = rid
    for r in recs:
        research_of[r] = rid


def research_name(rid):
    return names.get("RESEARCH_" + rid.upper(), rid)


def recipe_name(rid):
    """Рецепт в списке «что открывает»: по имени выхода, а не по id."""
    for r in RECIPES:
        if r[0] == rid:
            out = r[2][0][0] if r[2] else rid
            name = item_name(out)
            return name if name != rid else rid
    return item_name(rid)


def params_of(bid):
    """Параметры постройки из таблицы BUILDINGS."""
    for b in BUILDINGS:
        if b[0] == bid:
            return b[12]
    return {}


def size_of(bid):
    for b in BUILDINGS:
        if b[0] == bid:
            return b[4]
    return 0


def tres_values(path):
    """Числа из .tres: строки вида «ключ = значение» (значения — числа)."""
    values = {}
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return values
    for line in open(full, encoding="utf-8"):
        if " = " not in line:
            continue
        key, _, value = line.partition(" = ")
        value = value.strip()
        try:
            values[key.strip()] = float(value)
        except ValueError:
            continue
    return values


def table(header, rows):
    """Таблица: заголовок, разделитель и строки (каждая — список ячеек)."""
    w("| %s |" % " | ".join(header))
    w("|%s|" % "|".join(["---"] * len(header)))
    for row in rows:
        w("| %s |" % " | ".join(str(cell) for cell in row))
    w("")


out = []
w = out.append
w("# WarpFactor — контент ранней игры и начала мидгейма")
w("")
table(["Про файл", "Что здесь"], [
    ["Откуда числа", "из данных (`*.tres`); файл собирает `tools/data/make_content_doc.py`"],
    ["Единицы", "время — секунды, мощность — кВт, энергия — кДж, скорость — предметов в секунду"],
    ["Сколько сделано", "**Early game**, **Early midgame** и первая колонка **Midgame** из `WarpFactor/Заметки.md`"],
    ["Чего ещё нет", "боксит, киноварь, аутунит"],
])
w("## 1. Месторождения и сырьё")
w("")
w("| Месторождение | Даёт | Твёрдость | Кто добывает | Этап |")
w("|---|---|---|---|---|")
stage = {"hematite": "Early game", "stone": "Early game", "coal": "Early game", "malachite": "Early midgame",
         "water": "Early midgame", "sphalerite": "Midgame", "oil": "Midgame"}


def pump_of(fluid):
    """Чем качать жидкость: постройка-насос с этой жидкостью (или любой)."""
    for b in BUILDINGS:
        p = b[12]
        if b[1] == "fluid" and p.get("role") == 1 and p.get("pump_fluid", fluid) == fluid:
            power = ", %g кВт" % p["power_use"] if p.get("power_use") else ""
            return "%s (1 тайл = %g ед./с%s)" % (building_name(b[0]).lower(), p["pump_per_tile"], power)
    return "—"


for oid, (kind, target), hardness, _ in ORES:
    who = pump_of(target) if kind == "fluid" else ("дрон и бур" if hardness <= 1 else "только бур")
    w("| %s | %s | %d | %s | %s |" % (names.get("ORE_" + oid.upper(), oid), item_name(target), hardness, who, stage[oid]))
w("")
table(["Правило", "Как работает"], [
    ["Добыча дроном", "%g + %g × твёрдость секунд на предмет, делённые на множитель богатства клетки; твёрдость только до %d (малахит и сфалерит — буром)" % (
        tres_values("player/drone.tres").get("mine_base_seconds", 1.5), tres_values("player/drone.tres").get("mine_hardness_seconds", 0.6),
        tres_values("player/drone.tres").get("mine_tier", 1))],
    ["Добыча буром", "(6 + 1.5 × твёрдость) / сумма множителей богатства клеток руды под ним, 90 кВт"],
    ["Руды на планете", "на стартовой есть все руды её типа; дальше по шансам типа: %s" % "; ".join(
        "%s — %s" % ({"normal": "обычная", "rich": "рудный мир"}[t], ", ".join(
            "%s %d %%" % (names.get("ORE_" + o.upper(), o).lower(), round(c * 100)) for o, c in ores if c < 1))
        for t, ores in ns["PLANET_ORES"].items())],
    ["Из чего карта", "области разного пола, скальные гряды с проходами, озёра (если узлу выпала вода), рудные поля и нефтяные скважины"],
    ["Нефтяные скважины", "небольшие пятна (радиус 1.6–2.6) вдали от посадки, к каждой прорублен проход; на обычной планете около 3, на рудном мире больше"],
    ["Рудные поля", "у каждой руды своя сторона карты, первая залежь — у посадки; к каждому полю есть проход по земле"],
    ["Типы планет", "обычная, рудный мир (руды больше, волны раньше и злее), пустошь (ни руд, ни врагов) — `world/planet_types/*.tres`"],
    ["Строить на воде", "только трубы, подземные трубы, насосы и баки; на нефти — что угодно (она под землёй)"],
])
w("### Богатство клеток руды")
w("")
table(["Клетка", "Множитель добычи", "Где чаще", "Доля на обычной планете"], [
    ["бедная", "×0.5", "край мелкой залежи", "≈ 14 %"],
    ["средняя", "×1", "основная масса залежи", "≈ 64 %"],
    ["богатая", "×1.6", "середина залежи, крупные жилы", "≈ 20 %"],
    ["ультра-концентрированная", "×2.5", "сердце крупной жилы", "≈ 2 %"],
])
table(["Правило", "Как работает"], [
    ["Оценка клетки", "0.65 × близость к центру + 0.25 × крупность жилы (радиус 6 → 0, 12 → 1) + бонус планеты ± 0.15 разброс"],
    ["Пороги", "> 0.75 ультра, > 0.5 богатая, > 0.15 средняя, иначе бедная"],
    ["Бонус планеты", "`ore_richness` типа планеты: обычная 0, рудный мир 0.15 (в среднем ×1.5 против ×1.1)"],
    ["Наложение залежей", "клетке остаётся лучшее богатство из двух"],
    ["Как видно", "бедная тусклее и с парой самородков, богатая и ультра — светлее и гуще; подсказка над рудой пишет богатство и скорость"],
])
w("## 2. Предметы")
w("")
w("| Предмет | id | Стак | Особое |")
w("|---|---|---|---|")
for iid, _, _, _, stack, fuel, tier in ITEMS:
    extra = []
    if fuel > 0:
        extra.append("топливо %s кДж" % fmt(fuel))
    if tier > 0:
        extra.append("научный набор уровня %d" % tier)
    w("| %s | `%s` | %d | %s |" % (item_name(iid), iid, stack, ", ".join(extra) or "—"))
w("")
table(["Жидкость", "Откуда", "Где живёт"], [
    ["Вода", "насос на месторождении воды", "трубы и порты построек; в инвентарь и на ленты не попадает"],
    ["Пар", "бойлер (вода + топливо)", "трубы и порты построек"],
])
w("## 3. Рецепты")
w("")
w("| Рецепт | Входы | Выход | Время | Где делается | Исследование |")
w("|---|---|---|---|---|---|")
# Где делается рецепт: заводы, у которых он в списке (печь, сборщик, химзавод…).
makers_of = {}
for _b in BUILDINGS:
    for _r in _b[12].get("recipes", []):
        makers_of.setdefault(_r, []).append(building_name(_b[0]).lower())
for rid, ins, outs, t, hand, _ in RECIPES:
    if rid.startswith("build_"):
        continue
    makers = makers_of.get(rid, [])
    # Сборщик и фабрикатор делают одно и то же — хватает первого.
    if "сборщик" in makers:
        makers = [m for m in makers if m != "фабрикатор"]
    where = ("руками, " if hand else "") + (", ".join(makers) or "—")
    w("| `%s` | %s | %s | %s | %s | %s |" % (rid, stacks(ins), stacks(outs), fmt(t), where,
                                            research_name(research_of[rid]) if rid in research_of else "—"))
w("")
table(["Где делается", "Как выбирается рецепт", "Питание"], [
    ["Печь", "сама по пришедшему сырью (`RecipeMode.AUTO`)", "уголь: %g кВт, один уголь (4000 кДж) ≈ %d с работы" % (
        params_of("furnace").get("fuel_use", 0), round(4000 / max(params_of("furnace").get("fuel_use", 1), 1)))],
    ["Сборщик", "в панели настройки (`RecipeMode.SELECT`)", "электричество %g кВт" % params_of("assembler").get("power_use", 0)],
    ["Руками", "в окне крафта; промежуточные детали докрафчиваются сами", "не нужно, но переплавка — только в печи"],
])
w("## 4. Патроны")
w("")
table(["Из чего патрон", "Что задаёт"], [
    ["Гильза", "калибр; сейчас один — пулемётный (`casing_mg`, 2 гильзы из медного слитка)"],
    ["Наполнитель", "эффект патрона: урон, поджог, скорострельность, осколки"],
    ["Артиллерийский калибр", "появится вместе с артиллерией (механика в коде есть, в данных нет)"],
])
w("| Патрон | Наполнитель | Выстрелов на патрон | Урон | Эффект |")
w("|---|---|---|---|---|")
fillers = {out: filler for filler, out in ns["FILLERS"]}
for aid, shots, dmg, splash, speed, reload_mul, _, burn, burn_s in MG_AMMO:
    fx = []
    if splash > 0:
        fx.append("осколки: взрыв радиусом %s тайла при попадании" % fmt(splash))
    if burn > 0:
        fx.append("поджог: %s урона/с на %s с" % (fmt(burn), fmt(burn_s)))
    if reload_mul < 1.0:
        fx.append("скорострельность ×%s, пуля быстрее (%s тайл/с)" % (fmt(round(1 / reload_mul, 2)), fmt(speed)))
    if not fx:
        fx.append("повышенный урон" if dmg > 10 else "базовый")
    w("| %s | %s | %d | %s | %s |" % (item_name(aid), item_name(fillers[aid]), shots, fmt(dmg), "; ".join(fx)))
w("")
w("## 5. Постройки")
w("")
for cat in range(4):
    w("### %s" % CATEGORIES[cat])
    w("")
    # id и размер полосы нужны художнику: файл называется art/buildings/<id>.png,
    # а в полосе три квадратных кадра стороной size × 32.
    w("| Постройка | id | Размер | Полоса спрайта | Стоимость | Энергия | Параметры | Исследование |")
    w("|---|---|---|---|---|---|---|---|")
    for b in BUILDINGS:
        bid, kind, logic, category, size, _, _, buildable, _, _, _, cost, params, (hp, solid), craft = b
        if category != cat or not buildable:
            continue
        power = "—"
        if params.get("power_use"):
            power = "потребляет %s" % fmt(params["power_use"])
        elif kind == "generator":
            power = "даёт до %s" % fmt(params["max_output"])
        elif params.get("fuel_use"):
            power = "топливо %s" % fmt(params["fuel_use"])
        p = []
        if bid == "conveyor":
            p.append("%s тайла/с, 6 предм./с" % fmt(params["tiles_per_second"]))
        if kind == "logistic":
            p.append("пропускная способность как у ленты")
        if "link_range" in params:
            p.append("дальность %d" % params["link_range"])
        if "slots" in params:
            p.append("%d ячеек" % params["slots"])
        if kind == "crafter":
            p.append("рецептов: %d" % len(params["recipes"]))
        if kind == "drill":
            p.append("твёрдость до %d" % params["tier"])
            p.append("%s с на предмет с одного тайла" % fmt(params["base_seconds"] + params["hardness_seconds"]))
        if kind == "workshop":
            p.append("%s с на набор" % fmt(params["seconds_per_kit"]))
        if kind == "pole":
            p.append("провод %s тайла, зона %d×%d, до %d проводов" % (fmt(params["wire_range"]), params["supply_size"], params["supply_size"], params["max_links"]))
        if bid == "thermal_generator":
            p.append("КПД %d %%, уголь" % round(params["efficiency"] * 100))
        if bid == "steam_generator":
            p.append("пар %s кДж/ед. (30 ед./с на полной мощности)" % fmt(params["steam_energy"]))
        if bid == "pipe":
            p.append("вмещает %s" % fmt(params["fluid_capacity"]))
        if bid == "underground_pipe":
            p.append("под землёй до %d тайлов, выход сам разворачивается ко входу" % params["underground_range"])
        if params.get("allowed_on_fluid"):
            p.append("можно на воду")
        if bid == "drill":
            p.append("отдаёт только с лицевой стороны")
        if bid == "small_power_pole":
            p.append("протягивание — через 7 тайлов")
        if bid == "accumulator":
            p.append("ёмкость %s МДж, заряд и разряд до %s кВт" % (fmt(params["capacity_kj"] / 1000.0), fmt(params["max_rate"])))
        if bid == "lift":
            p.append("пара на другом этаже, буфер %d, 6 предм./с" % params["buffer_capacity"])
        if bid == "pump":
            p.append("%s ед./с с тайла воды, без электричества" % fmt(params["pump_per_tile"]))
        if bid == "boiler":
            p.append("уголь %s кВт → пар %s ед./с" % (fmt(params["fuel_power"]), fmt(params["steam_per_second"])))
        if kind == "turret":
            # 0 — патроны, 1 — молния, 2 — ремонт, 3 — полив (TurretDef.Kind).
            turret_kind = params.get("kind", 0)
            if turret_kind == 1:
                p.append("радиус %s, молния %s урона по цепи до %d целей" %
                         (fmt(params["shoot_range"]), fmt(params["chain_damage"]), params["chain_targets"]))
            elif turret_kind == 2:
                p.append("радиус %s, чинит по %s прочности раз в %s с" %
                         (fmt(params["shoot_range"]), fmt(params["repair_amount"]), fmt(params["reload_seconds"])))
            elif turret_kind == 3:
                p.append("радиус %s, лужа %s тайла: вода замедляет, пар жжёт; %s ед. жидкости за раз" %
                         (fmt(params["shoot_range"]), fmt(params["spray_radius"]), fmt(params["spray_use"])))
            else:
                p.append("радиус %s, запас %d выстрелов, без электричества" % (fmt(params["shoot_range"]), params["max_ammo"]))
        if bid == "stone_wall":
            p.append("ставится линией")
        p.append("прочность %d" % hp)
        if not solid:
            p.append("проходима")
        amount = craft[1] if craft else 1
        cost_text = stacks(cost) + ("" if amount == 1 else " → %d шт." % amount)
        w("| %s | `%s` | %d×%d | %d×%d | %s | %s | %s | %s |" % (building_name(bid), bid, size, size,
            size * 32 * 3, size * 32, cost_text, power, "; ".join(p),
            research_name(research_of[bid]) if bid in research_of else "—"))
    w("")
w("## 6. Энергия и жидкости")
w("")
_thermal = params_of("thermal_generator")
_boiler = params_of("boiler")
_steam = params_of("steam_generator")
_coal_kj = 4000.0
_steam_need = _steam.get("max_output", 0) / max(_steam.get("steam_energy", 1), 0.001)
table(["Что", "Как работает"], [
    ["Сеть", "опоры, соединённые проводами, и всё в их зонах 5×5; новая опора сама цепляется к ближайшим в радиусе 7.5 тайла (до 5 проводов)"],
    ["Тик сети", "спрос = запросы работающих потребителей, мощность = что могут дать генераторы, удовлетворённость = мощность / спрос (не больше 1)"],
    ["Нехватка тока", "все потребители сети работают медленнее, генераторы тратят топливо и пар пропорционально нагрузке"],
    ["Кто потребляет", ", ".join("%s %g" % (building_name(b[0]), b[12]["power_use"])
        for b in BUILDINGS if b[12].get("power_use", 0) > 0 and b[1] != "creative")],
    ["Кто без тока", "печь и плавильня (топливо), пулемётная и жидкостная турели, насос, разгрузчик, ленты и остальная логистика"],
    ["Термогенератор", "%g кВт, КПД %d %%: уголь даёт %d кДж электричества — около %d с на полной мощности" % (
        _thermal.get("max_output", 0), round(_thermal.get("efficiency", 0.5) * 100),
        _coal_kj * _thermal.get("efficiency", 0.5),
        round(_coal_kj * _thermal.get("efficiency", 0.5) / max(_thermal.get("max_output", 1), 1)))],
    ["Паровая цепочка", "насос → трубы → бойлер (вода слева, пар справа, R поворачивает) → паровой генератор (порты пара слева и справа, их можно ставить вплотную цепочкой)"],
    ["Бойлер", "уголь %g кВт даёт %g ед. пара/с, воды столько же" % (
        _boiler.get("fuel_power", 0), _boiler.get("steam_per_second", 0))],
    ["Паровой генератор", "%d ед. пара/с даёт %g кВт; один бойлер кормит %d таких" % (
        round(_steam_need), _steam.get("max_output", 0),
        round(_boiler.get("steam_per_second", 0) / max(_steam_need, 1)))],
    ["Трубы", "соседние трубы и порты построек — одна сеть с общим запасом; в сети одна жидкость"],
    ["Подземные трубы", "вход и выход соединяются под землёй (до %d тайлов) под постройками и скалами; сверху открыты с одной стороны" % params_of("underground_pipe").get("underground_range", 10)],
])
w("## 7. Исследования")
w("")
table(["Ветка", "Куда ведёт"], [
    ["Производство", "Добыча → Логистика → Промышленность → Автоматизация науки и Аккумуляторы"],
    ["Оборона", "Добыча → Оборона → Продвинутая оборона (после Микросхем)"],
    ["Площадка", "Добыча → Расширение площадки I–V"],
    ["Подземный этаж", "Подземный этаж → Передача предметов → Порты шлюза I–II; Расширение подземного этажа I–V (после I — Лифт)"],
    ["Нижние этажи", "Подземный этаж → Этаж добычи → Комнаты добычи; Этаж добычи и Паровая энергия → Котельная → Расширение котельной I–III"],
    ["Передача между этажами", "Подземный этаж → Передача энергии → Передача жидкостей"],
])
w("| Исследование | Стоимость | Нужно | Открывает |")
w("|---|---|---|---|")
EFFECT_TEXT = {
    "underground": "доступ на подземный этаж (16×16)",
    "mining_floor": "этаж добычи с центральной комнатой и шахтой вниз",
    "boiler_floor": "котельная: четвёртый этаж с полосой воды по краю и шахтой, которая проводит ток и трубы",
    "boiler_size": "котельная растёт на 8 тайлов по стороне, полоса воды переезжает к новому краю",
    "mining_room": "комната добычи с туннелем и платформой (её наводят на руду планеты с пульта)",
    "underground_size": "подземный этаж +6 тайлов по стороне",
    "pad_size": "площадка шлюза +4 тайла по стороне",
    "planet_time": "+2 минуты к сроку пребывания на планете",
    "science_speed": "исследования идут на четверть быстрее (цех и ручная сдача)",
    "gateway_speed": "шлюз и лифты пропускают предметы в полтора раза быстрее",
    "star_scan": "разведка: сначала виден тип планеты и появляется выбор цели, затем её ресурсы",
    "star_depth": "звёздная карта видна на шаг дальше",
    "teleport_charge": "−1 минута к перезарядке телепорта",
    "gateway_items": "шлюз передаёт предметы",
    "gateway_ports": "ещё вход и выход у шлюза",
    "gateway_power": "шлюз и лифты соединяют электросети этажей",
    "gateway_fluids": "шлюз и лифты соединяют трубы этажей",
    "drone_speed": "дрон быстрее летает",
    "drone_mining": "дрон быстрее добывает",
    "drone_health": "больше прочности дрона",
    "drone_gun": "больше урона автопушки",
    "drone_repair": "дрон быстрее чинит",
    "turret_damage": "турели бьют на 10 % сильнее (пули, горение, молния, пар)",
}
# Последняя ступень ветки делает больше, чем просто ещё один шаг.
EFFECT_OVERRIDE = {"warp_time_5": "последняя ступень: время на планете больше не ограничено"}
for rid, _, cost, pre, blds, recs, _effects in sorted(RESEARCH, key=lambda r: r[1]):
    # Рецепты автосборки перечислять незачем: их столько же, сколько построек.
    build_recipes = [r for r in recs if r.startswith("build_")]
    plain = [r for r in recs if not r.startswith("build_")]
    opens = [building_name(b) for b in blds] + [recipe_name(r) for r in plain] + [EFFECT_TEXT[e] for e in _effects]
    if build_recipes:
        opens.append("рецепты автосборки для всех открытых построек (%d)" % len(build_recipes))
    if rid in EFFECT_OVERRIDE:
        opens = [EFFECT_OVERRIDE[rid]]
    price = " + ".join("%d × %s" % (n, item_name(kit)) for kit, n in research_costs(rid, cost))
    w("| %s | %s | %s | %s |" % (research_name(rid), price,
                                 ", ".join(research_name(p) for p in pre) or "—", ", ".join(opens) or "—"))
w("")
table(["Правило", "Как работает"], [
    ["Что открыто сразу", ", ".join(building_name(b[0]) for b in BUILDINGS
        if b[7] and b[1] != "creative" and b[0] not in research_of) or "—"],
    ["Ручная сдача", "окно J, кнопка «Сдать наборы»: только наборы первого уровня, только в выбранное исследование, 12 с на набор"],
    ["Виды наборов", "первый (руками и в сборщике) → военный (стена и два разных вида патронов, сборщик) → второй (микросхема и сталь) → третий (резисторы и полимеры из нефти); кроме первого — только в научный цех"],
    ["Военный набор", "его рецепт открывает «Военное дело» (за первые наборы); им, а не первым набором, платят все военные исследования: %s" % ", ".join(
        research_name(r) for r in sorted(ns["MILITARY_RESEARCH"]))],
    ["Третий набор", "нужен прокачкам после первых одной-двух ступеней, вместе с набором II — по цепочкам в таблице ниже"],
    ["Очередь", "ПКМ по карточке ставит её в очередь (до 5); текущее завершилось — берётся первое доступное"],
    ["Научный цех", "берёт наборы с ленты или руками, %g с на набор, %g кВт" % (
        params_of("science_workshop").get("seconds_per_kit", 2), params_of("science_workshop").get("power_use", 0))],
    ["Где действуют", "общие для забега (база и все планеты), сохраняются; в творческом режиме открыто всё"],
])
# Набор III по цепочкам прокачки: сколько ступеней обходятся без нефти.
_chains = {}
for _r in RESEARCH:
    _head, _, _tail = _r[0].rpartition("_")
    if _head and _tail.isdigit():
        _chains[_head] = max(_chains.get(_head, 0), int(_tail))
_rows = []
for _head, _top in sorted(_chains.items(), key=lambda kv: research_name(kv[0] + "_1")):
    _need = sorted(int(r.rpartition("_")[2]) for r in ns["KIT3_RESEARCH"] if r.rpartition("_")[0] == _head)
    # У комнат добычи у каждой ступени своё имя (северная, восточная…) — цепочку называем целиком.
    _title = {"mining_room": "Комнаты добычи"}.get(_head, research_name(_head + "_1"))
    for _suffix in (" I", " 1"):
        if _title.endswith(_suffix):
            _title = _title[: -len(_suffix)]
    _rows.append([_title, _top, _top - len(_need), ("с %d-й" % _need[0]) if _need else "не нужен"])
table(["Прокачка", "Ступеней", "Без набора III", "Набор III"], _rows)
w("## 7а. Мобильная база: площадка, подземный этаж, шлюз")
w("")
_run = tres_values("world/run.tres")
_base = tres_values("world/base.tres")
_mining = tres_values("world/mining.tres")
_boiler_floor = tres_values("world/boiler.tres")
_gate = params_of("central_gateway")
_lift = params_of("lift")
_pad = int(_run.get("pad_start_size", 20))
table(["Этаж или проход", "Размер", "Как работает"], [
    ["Площадка шлюза (планета)", "%d на %d, дальше до %d на %d" % (_pad, _pad, _pad + 20, _pad + 20),
        "верхний этаж базы: всё на ней переезжает при телепорте; «Расширение площадки» даёт +4 по стороне, место под наибольшую расчищает генератор планет"],
    ["Подземный этаж", "%d на %d, дальше до %d на %d" % (_base.get("start_size", 16), _base.get("start_size", 16),
        _base.get("center_max", 46), _base.get("center_max", 46)),
        "открывается исследованием; за краем открытой части пустота, на ней не строят, дрон и камера за край не выходят"],
    ["Этаж добычи", "комнаты %d на %d, туннель %d на %d" % (_mining.get("room_size", 16), _mining.get("room_size", 16),
        _mining.get("tunnel_width", 6), _mining.get("room_gap", 42)),
        "центральная комната с шахтой вниз и четыре комнаты добычи с платформами"],
    ["Котельная", "%d на %d, дальше до %d на %d" % (_boiler_floor.get("start_size", 16), _boiler_floor.get("start_size", 16),
        _boiler_floor.get("center_max", 48), _boiler_floor.get("center_max", 48)),
        "полоса воды по краю открытой части; «Расширение котельной» даёт +%d по стороне, полоса переезжает к новому краю" % _boiler_floor.get("size_step", 8)],
    ["Центральный шлюз", "%d на %d, дальше %d на %d" % (_gate.get("start_size", 2), _gate.get("start_size", 2),
        _gate.get("grown_size", 4), _gate.get("grown_size", 4)),
        "проход между планетой и подземным этажом (F); предметы после «Передачи предметов», число портов — по «Портам шлюза I/II», очередь %d на порт" % _gate.get("buffer_capacity", 10)],
    ["Шахты вниз", "%d на %d" % (size_of("shaft"), size_of("shaft")),
        "по одной на этаж добычи и в котельную, ставятся сами вместе с этажом; четыре входа с одной стороны и четыре выхода с другой, k-й выход отдаёт то, что вошло в k-й вход"],
    ["Лифт", "%d на %d" % (size_of("lift"), size_of("lift")),
        "ставит игрок: на площадке или в открытой части этажа, пара появляется в том же месте другого этажа; один вход и один выход, буфер %d, направление — общая настройка пары" % _lift.get("buffer_capacity", 10)],
])
table(["Что передаётся между этажами", "После какого исследования"], [
    ["Предметы", "«Передача предметов» у шлюза, «Порты шлюза I–II» добавляют порты"],
    ["Электричество", "«Передача энергии» — опоры у шлюза и лифтов на обоих этажах становятся одной сетью"],
    ["Жидкости", "«Передача жидкостей» — трубы у шлюза и лифтов выравнивают заполненность сетей этажей"],
    ["Ток и трубы в котельную", "всегда: шахта котельной проводит их сама, ради этого этаж и нужен"],
])
w("## 8. Старт и угроза")
w("")
_threat = tres_values("enemies/threats/normal.tres")
_rich = tres_values("enemies/threats/rich.tres")
table(["Что", "Обычная планета", "Рудный мир"], [
    ["Первая волна", "через %d мин" % round(_threat.get("first_wave_seconds", 600) / 60),
        "через %d мин" % round(_rich.get("first_wave_seconds", 420) / 60)],
    ["Затишье между волнами", "%d с, каждое следующее — %g от предыдущего" % (
        _threat.get("first_gap_seconds", 240), _threat.get("gap_multiplier", 0.85)),
        "%d с, тот же множитель" % _rich.get("first_gap_seconds", 180)],
    ["Волны встык", "когда затишье короче %d с" % _threat.get("continuous_below_seconds", 10), "то же"],
    ["Бюджет волны", "%g + %g за волну + %g за минуту на планете" % (
        _threat.get("budget_base", 4), _threat.get("budget_per_wave", 3.4), _threat.get("budget_per_minute", 0.5)),
        "%g + %g за волну + %g за минуту" % (
        _rich.get("budget_base", 5), _rich.get("budget_per_wave", 4.2), _rich.get("budget_per_minute", 0.7))],
    ["Прочность врага", "+%d %% за волну, +%d %% за шаг звёздной карты, потолок %g" % (
        round(_threat.get("health_per_wave", 0.09) * 100), round(_threat.get("health_per_depth", 0.25) * 100),
        _threat.get("max_health_scale", 8)),
        "+%d %% за волну" % round(_rich.get("health_per_wave", 0.12) * 100)],
    ["Урон врага", "+%d %% за волну, +%d %% за шаг карты, потолок %g" % (
        round(_threat.get("damage_per_wave", 0.07) * 100), round(_threat.get("damage_per_depth", 0.2) * 100),
        _threat.get("max_damage_scale", 5)),
        "+%d %% за волну" % round(_rich.get("damage_per_wave", 0.09) * 100)],
    ["Развитие игрока", "исследования × производственные постройки планеты (в начале волны): бюджет +%g за единицу (не больше %g), прочность +%g %% за 100 единиц" % (
        _threat.get("progress_budget", 0.015), _threat.get("progress_budget_max", 80), _threat.get("progress_health", 0.0002) * 10000),
        "бюджет +%g за единицу" % _rich.get("progress_budget", 0.02)],
    ["Пример развития", "10 иссл. × 10 заводов = 100 → +%g очка; 40 × 40 = 1600 → +%g (≈ %d волн сверху)" % (
        _threat.get("progress_budget", 0.015) * 100, min(_threat.get("progress_budget", 0.015) * 1600, _threat.get("progress_budget_max", 80)),
        round(min(_threat.get("progress_budget", 0.015) * 1600, _threat.get("progress_budget_max", 80)) / _threat.get("budget_per_wave", 3.4))), "—"],
    ["Кто приходит", "ползуны с 1-й волны, солдаты с 4-й, громилы с 8-й",
        "то же, точек появления %d" % _rich.get("spawn_point_count", 4)],
])
table(["Старт забега", "Что даёт"], [
    ["Стартовый набор", stacks(START_ITEMS)],
    ["Время на планете", "%d мин; «Запас хода» добавляет по %d мин, последняя ступень снимает срок совсем" % (
        round(_run.get("planet_time_seconds", 600) / 60), round(_run.get("planet_time_step_seconds", 120) / 60))],
    ["Перезарядка телепорта", "%d мин; «Разгон телепорта» убирает по %d мин, последняя ступень — без перезарядки" % (
        round(_run.get("teleport_cooldown_seconds", 300) / 60), round(_run.get("teleport_cooldown_step_seconds", 60) / 60))],
])

open(os.path.join(ROOT, "docs", "CONTENT.md"), "w", encoding="utf-8", newline="\n").write("\n".join(out))
print("CONTENT.md", len(out), "lines")
