"""Генерирует веб-вики по игре в docs/wiki/ из тех же данных, что и docs/CONTENT.md.

Источники: таблицы tools/data/make_content.py (предметы, жидкости, месторождения, рецепты,
постройки, исследования), враги из tools/data/make_enemies.py, типы планет и кривые угрозы
из world/planet_types/*.tres и enemies/threats/*.tres, дрон из player/drone.tres, русские
названия и описания из i18n/strings.csv, правила механик — таблицы docs/CONTENT.md, спрайты
зданий — art/buildings/<id>.png.

Результат — статический сайт без внешних зависимостей: открывается с диска (file://) и на
GitHub Pages, все ссылки относительные, индекс поиска — JS-файл с переменной (fetch на file://
не работает). Вывод детерминированный: без дат и случайностей, повторный запуск даёт те же байты.
Список своих файлов лежит в docs/wiki/.manifest — по нему удаляются устаревшие страницы.

Запуск из корня репозитория: python tools/data/make_wiki.py
"""
import ast
import csv
import glob
import html
import json
import math
import os
import posixpath
import re
import struct
import sys
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "docs", "wiki")
MANIFEST = ".manifest"

# Маркер корня сайта в ссылках. Страницы собираются с ним, а при записи он заменяется на
# относительный путь до корня ("" или "../"), поэтому код страниц не думает о вложенности.
R = "@@ROOT@@/"

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass


# =====================================================================================
# Загрузка данных
# =====================================================================================

def load_content():
    """Таблицы make_content.py: исполняется часть файла до def item_path( — как в make_content_doc.py.
    Помощники стоимости (research_costs, kit2_amount), если окажутся ниже, берутся отдельно."""
    path = os.path.join(HERE, "make_content.py")
    src = open(path, encoding="utf-8").read()
    ns = {"__file__": path}
    exec(src[:src.index("def item_path(")], ns)
    for node in ast.parse(src).body:
        if isinstance(node, ast.FunctionDef) and node.name in ("research_costs", "kit2_amount") \
                and node.name not in ns:
            exec(ast.get_source_segment(src, node), ns)
    return ns


def literal_from(path, name):
    """Значение литерала NAME = ... из скрипта без его исполнения (make_enemies.py и
    make_content_doc.py при исполнении пишут файлы, поэтому читаем их через ast)."""
    if not os.path.exists(path):
        return None
    tree = ast.parse(open(path, encoding="utf-8").read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            try:
                return ast.literal_eval(node.value)
            except ValueError:
                return None
    return None


def load_strings():
    """Строки интерфейса: ключ → (EN, RU)."""
    en, ru = {}, {}
    with open(os.path.join(ROOT, "i18n", "strings.csv"), encoding="utf-8") as f:
        for row in csv.reader(f):
            if len(row) >= 3:
                en[row[0]] = row[1]
                ru[row[0]] = row[2]
    return en, ru


def tres_value(raw, ext):
    """Значение поля .tres: число, строка, булево, массив, вектор, цвет или ссылка на ресурс."""
    if raw in ("true", "false"):
        return raw == "true"
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    if re.fullmatch(r"-?\d*\.\d+(e-?\d+)?|-?\d+e-?\d+", raw):
        return float(raw)
    if raw.startswith('&"') or raw.startswith('"'):
        return raw.lstrip("&").strip('"')
    if raw.startswith("Array[StringName]"):
        return re.findall(r'&"([^"]*)"', raw)
    m = re.fullmatch(r"(Packed\w+Array|Vector2i?|Color)\((.*)\)", raw)
    if m:
        return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", m.group(2))]
    m = re.fullmatch(r'ExtResource\("([^"]+)"\)', raw)
    if m:
        return ("res", ext.get(m.group(1), ""))
    return raw


def parse_tres(path):
    """Поля секции [resource] файла .tres (ссылки ExtResource раскрываются в пути res://)."""
    values, ext, section = {}, {}, None
    if not os.path.exists(path):
        return values
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("[ext_resource"):
            rid = re.search(r'id="([^"]+)"', line)
            rpath = re.search(r'path="([^"]+)"', line)
            if rid and rpath:
                ext[rid.group(1)] = rpath.group(1)
        elif line.startswith("["):
            section = line
        elif section == "[resource]" and " = " in line:
            key, _, raw = line.partition(" = ")
            values[key.strip()] = tres_value(raw.strip(), ext)
    return values


def res_to_path(res):
    """res://a/b.tres → абсолютный путь в репозитории."""
    return os.path.join(ROOT, *res[len("res://"):].split("/"))


def parse_content_md():
    """Таблицы docs/CONTENT.md: список (раздел, подраздел, заголовок таблицы, строки)."""
    path = os.path.join(ROOT, "docs", "CONTENT.md")
    blocks = []
    if not os.path.exists(path):
        return blocks
    section, sub, table = "", None, None

    def cells(line):
        return [c.strip() for c in line.strip().strip("|").split("|")]

    for line in open(path, encoding="utf-8").read().split("\n"):
        if line.startswith("## "):
            section, sub, table = line[3:].strip(), None, None
        elif line.startswith("### "):
            sub, table = line[4:].strip(), None
        elif line.startswith("|"):
            if table is None:
                table = {"section": section, "sub": sub, "header": cells(line), "rows": []}
                blocks.append(table)
            elif not re.fullmatch(r"\|[\s\-|:]+\|", line.strip()):
                table["rows"].append(cells(line))
        else:
            table = None
    return blocks


NS = load_content()
STR_EN, STR_RU = load_strings()
ENEMY_ROWS = literal_from(os.path.join(HERE, "make_enemies.py"), "ENEMIES") or []
EFFECT_TEXT = literal_from(os.path.join(HERE, "make_content_doc.py"), "EFFECT_TEXT") or {}
EFFECT_OVERRIDE = literal_from(os.path.join(HERE, "make_content_doc.py"), "EFFECT_OVERRIDE") or {}
DRONE = parse_tres(os.path.join(ROOT, "player", "drone.tres"))
CONTENT_TABLES = parse_content_md()


# =====================================================================================
# Форматирование
# =====================================================================================

def esc(s):
    return html.escape(str(s), quote=True)


def fmt(v):
    """Число без лишних нулей: 3.20 → 3.2, 4000.0 → 4000."""
    if isinstance(v, bool):
        return "да" if v else "нет"
    if isinstance(v, float):
        return ("%.2f" % v).rstrip("0").rstrip(".")
    return str(v)


def plural(n, one, few, many):
    """Русское окончание при числе: 1 тайл, 2 тайла, 5 тайлов; дробное — как «2.5 тайла»."""
    if isinstance(n, float) and not n.is_integer():
        return few
    n = abs(int(n))
    if n % 10 == 1 and n % 100 != 11:
        return one
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return few
    return many


def tiles(n):
    return "%s %s" % (fmt(n), plural(n, "тайл", "тайла", "тайлов"))


def pct(v):
    return "%s %%" % fmt(round(v * 100, 1))


def md_inline(text):
    """Строчная разметка из CONTENT.md: `код` и **жирный**."""
    s = esc(text)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)


def hex_rgb(h):
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_hex(r, g, b):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in (r, g, b))


def darken(h, a):
    """Как Color.darkened в Godot: каналы × (1 − a)."""
    return rgb_hex(*[c * (1 - a) for c in hex_rgb(h)])


def lighten(h, a):
    """Как Color.lightened в Godot: канал + (1 − канал) × a."""
    return rgb_hex(*[c + (255 - c) * a for c in hex_rgb(h)])


def color_floats(v, default="928374"):
    """Color(r, g, b, a) из .tres → hex без решётки."""
    if isinstance(v, list) and len(v) >= 3:
        return rgb_hex(v[0] * 255, v[1] * 255, v[2] * 255)[1:]
    return default


# =====================================================================================
# Модель: данные в словарях и перекрёстные индексы
# =====================================================================================

WARNINGS = set()   # что вики не смогла разобрать или назвать — печатается в конце, сборку не валит


def name_ru(key, fallback):
    if key not in STR_RU:
        WARNINGS.add("нет строки %s в i18n/strings.csv — на страницах будет «%s»" % (key, fallback))
    return STR_RU.get(key, fallback)


ITEM = {}
for _row in NS["ITEMS"]:
    _iid, _shape, _col, _order, _stack, _fuel, _tier = _row[:7]
    ITEM[_iid] = {"id": _iid, "shape": _shape, "color": _col, "order": _order, "stack": _stack,
                  "fuel": _fuel, "tier": _tier}

FLUID = {}
for _row in NS.get("FLUIDS", []):
    FLUID[_row[0]] = {"id": _row[0], "key": _row[1], "color": _row[2], "order": _row[3]}

ORE = {}
for _row in NS.get("ORES", []):
    _oid, (_kind, _target), _hard, _order = _row[:4]
    ORE[_oid] = {"id": _oid, "kind": _kind, "target": _target, "hardness": _hard, "order": _order}

BUILDING = {}
for _b in NS["BUILDINGS"]:
    (_bid, _kind, _logic, _cat, _size, _line, _removable, _buildable, _glyph, _col, _order, _cost,
     _params, (_hp, _solid), _craft) = _b[:15]
    BUILDING[_bid] = {"id": _bid, "kind": _kind, "logic": _logic, "cat": _cat, "size": _size, "line": _line,
                      "removable": _removable, "buildable": _buildable, "color": _col, "order": _order,
                      "cost": list(_cost), "params": _params, "hp": _hp, "solid": _solid, "craft": _craft,
                      "creative": _kind == "creative" or bool(_params.get("creative_only"))}

GROUPS = dict(NS.get("ITEM_GROUPS", {}))


def parse_ref(token, amount):
    """Вход или выход рецепта: ("any:<группа>", n), ("fluid:<жидкость>", n), предмет или постройка."""
    if token.startswith("any:"):
        return ("group", token[4:], amount)
    if token.startswith("fluid:"):
        return ("fluid", token[6:], amount)
    if token in BUILDING:
        return ("building", token, amount)
    if token in ITEM:
        return ("item", token, amount)
    if token in FLUID:
        return ("fluid", token, amount)
    return ("unknown", token, amount)


def stack_kind(token):
    """Предмет из стоимости или стартового набора: постройка это или обычный предмет."""
    return "building" if token in BUILDING else ("item" if token in ITEM else "unknown")


RECIPE = {}
for _r in NS["RECIPES"]:
    _rid, _ins, _outs, _time, _hand, _order = _r[:6]
    RECIPE[_rid] = {"id": _rid, "ins": [parse_ref(t, n) for t, n in _ins],
                    "outs": [parse_ref(t, n) for t, n in _outs], "time": float(_time), "hand": _hand, "order": _order}
    for _k, _t, _n in RECIPE[_rid]["ins"] + RECIPE[_rid]["outs"]:
        if _k == "unknown" or (_k == "group" and _t not in GROUPS) or (_k == "fluid" and _t not in FLUID):
            WARNINGS.add("рецепт %s: неизвестный %s «%s» — показан без ссылки" % (
                _rid, {"group": "группа", "fluid": "жидкость"}.get(_k, "предмет"), _t))


def is_autobuild(rid):
    """Рецепт автосборки: сборщик делает постройку по её же стоимости."""
    ids = NS.get("BUILD_RECIPE_IDS")
    if ids is not None:
        return rid in ids
    r = RECIPE[rid]
    if len(r["outs"]) != 1 or r["outs"][0][0] != "building":
        return False
    b = BUILDING[r["outs"][0][1]]
    return sorted((t, n) for _, t, n in r["ins"]) == sorted(b["cost"])


def creative_research_ids():
    """Исследования только для творческого режима: флаг creative_only в research/defs/<id>.tres;
    если файла ещё нет — исследование без требований, открытий и эффектов."""
    out = set()
    for rrow in NS["RESEARCH"]:
        rid, _, _, pre, blds, recs, effects = rrow[:7]
        tres = os.path.join(ROOT, "research", "defs", "%s.tres" % rid)
        if os.path.exists(tres):
            if parse_tres(tres).get("creative_only") is True:
                out.add(rid)
        elif not pre and not blds and not recs and not effects:
            out.add(rid)
    return out


def research_costs(rid, amount):
    """Стоимость исследования по видам наборов: research_costs из данных, а пока её нет —
    наборы первого уровня плюс второго по kit2_amount."""
    fn = NS.get("research_costs")
    if fn is not None:
        return [(i, n) for i, n in fn(rid, amount) if n > 0]
    out = [("science_kit", amount)]
    kit2 = NS.get("kit2_amount")
    if kit2 is not None:
        n = kit2(rid, amount)
        if n > 0:
            out.append(("science_kit_2", n))
    return out


_CREATIVE_RESEARCH = creative_research_ids()
RESEARCH = {}
for _rr in sorted(NS["RESEARCH"], key=lambda r: (r[1], r[0])):
    _rid, _order, _amount, _pre, _blds, _recs, _effects = _rr[:7]
    RESEARCH[_rid] = {"id": _rid, "order": _order, "amount": _amount, "pre": list(_pre), "buildings": list(_blds),
                      "recipes": list(_recs), "effects": list(_effects), "costs": research_costs(_rid, _amount),
                      "creative": _rid in _CREATIVE_RESEARCH}

START_ITEMS = list(NS.get("START_ITEMS", []))

# Страницы с такими id совпали бы со служебными (index.html, tree.html).
for _ids in (ITEM, BUILDING, RESEARCH, FLUID):
    for _reserved in ("index", "tree"):
        if _reserved in _ids:
            sys.exit("id «%s» совпадает со служебной страницей вики" % _reserved)


def by_order(ids, table):
    return sorted(ids, key=lambda i: (table[i]["order"], i))


ITEM_IDS = by_order(ITEM, ITEM)
FLUID_IDS = by_order(FLUID, FLUID)
ORE_IDS = by_order(ORE, ORE)
BUILDING_IDS = sorted(BUILDING, key=lambda b: (BUILDING[b]["cat"], BUILDING[b]["order"], b))
RECIPE_IDS = by_order(RECIPE, RECIPE)
RESEARCH_IDS = by_order(RESEARCH, RESEARCH)

# --- Перекрёстные индексы ---
MAKERS = {}            # рецепт → постройки, которые его выполняют
for _bid in BUILDING_IDS:
    for _rid in BUILDING[_bid]["params"].get("recipes", []):
        MAKERS.setdefault(_rid, []).append(_bid)

PRODUCED_BY = {}       # (вид, id) → рецепты, которые его делают
CONSUMED_BY = {}       # (вид, id) → рецепты, которым он нужен
for _rid in RECIPE_IDS:
    for _k, _t, _n in RECIPE[_rid]["outs"]:
        PRODUCED_BY.setdefault((_k, _t), []).append(_rid)
    for _k, _t, _n in RECIPE[_rid]["ins"]:
        if _rid not in CONSUMED_BY.get((_k, _t), []):
            CONSUMED_BY.setdefault((_k, _t), []).append(_rid)

COST_USERS = {}        # (вид, id) → [(постройка, количество)]
for _bid in BUILDING_IDS:
    for _t, _n in BUILDING[_bid]["cost"]:
        COST_USERS.setdefault((stack_kind(_t), _t), []).append((_bid, _n))

RESEARCH_COST_USERS = {}   # предмет → [(исследование, количество)]
RESEARCH_OF_BUILDING, RESEARCH_OF_RECIPE, DEPENDENTS = {}, {}, {}
for _rid in RESEARCH_IDS:
    _r = RESEARCH[_rid]
    for _t, _n in _r["costs"]:
        RESEARCH_COST_USERS.setdefault(_t, []).append((_rid, _n))
    for _b in _r["buildings"]:
        RESEARCH_OF_BUILDING.setdefault(_b, _rid)
    for _rec in _r["recipes"]:
        RESEARCH_OF_RECIPE.setdefault(_rec, _rid)
    for _p in _r["pre"]:
        DEPENDENTS.setdefault(_p, []).append(_rid)

AMMO_USERS = {}        # патрон → [(турель, строка патрона)]
for _bid in BUILDING_IDS:
    for _a in BUILDING[_bid]["params"].get("ammo", []) or []:
        AMMO_USERS.setdefault(_a[0], []).append((_bid, _a))

FUEL_BURNERS = [b for b in BUILDING_IDS if "fuel_capacity" in BUILDING[b]["params"] and not BUILDING[b]["creative"]]
WORKSHOPS = [b for b in BUILDING_IDS if BUILDING[b]["kind"] == "workshop"]
DRILLS = [b for b in BUILDING_IDS if BUILDING[b]["kind"] == "drill"]
ORE_OF_TARGET = {}     # (вид, id) → месторождения
for _oid in ORE_IDS:
    ORE_OF_TARGET.setdefault((ORE[_oid]["kind"], ORE[_oid]["target"]), []).append(_oid)

# Жидкости в параметрах построек: ключ → направление («in» — берёт, «out» — отдаёт).
# Генератор всегда только берёт (пар в паровом генераторе).
FLUID_KEY_ROLE = {"water_fluid": "in", "steam_fluid": "out", "input_fluid": "in", "output_fluid": "out",
                  "fluid": "out", "fluid_id": "out"}


def fluid_links(bid):
    """[(жидкость, "in"/"out")] постройки по её параметрам."""
    b = BUILDING[bid]
    out = []
    for key, value in b["params"].items():
        if isinstance(value, str) and value in FLUID and key.endswith(("fluid", "fluid_id")):
            role = "in" if b["kind"] == "generator" else FLUID_KEY_ROLE.get(key, "in" if "in" in key else "out")
            out.append((value, role))
    return out


FLUID_BUILDINGS = {}   # жидкость → [(постройка, направление)]
for _bid in BUILDING_IDS:
    for _f, _role in fluid_links(_bid):
        FLUID_BUILDINGS.setdefault(_f, []).append((_bid, _role))
# Насосы (pump_per_tile) качают жидкость месторождений, у которых нет своей добывающей постройки.
PUMPS = [b for b in BUILDING_IDS if "pump_per_tile" in BUILDING[b]["params"] and not BUILDING[b]["creative"]]


def bound_ores(bid):
    """Месторождения, к которым постройка привязана явно: параметр ore…/…fluid с их id."""
    out = []
    for key, value in BUILDING[bid]["params"].items():
        if not isinstance(value, str):
            continue
        for oid in ORE_IDS:
            if (key.startswith("ore") and value == oid) or (value == ORE[oid]["target"] and ORE[oid]["kind"] == "fluid"
                                                             and dict(fluid_links(bid)).get(value) == "out"):
                out.append(oid)
    return out


def ore_extractors(oid):
    """Постройки, добывающие месторождение: буры — по твёрдости; жидкость — постройки, явно
    привязанные к ней (и сами жидкостей не берущие), а если таких нет — насосы без привязки."""
    o = ORE[oid]
    if o["kind"] == "fluid":
        own = [b for b in BUILDING_IDS if not BUILDING[b]["creative"] and oid in bound_ores(b)
               and not any(role == "in" for _, role in fluid_links(b))]
        return own or [b for b in PUMPS if not bound_ores(b)]
    return [b for b in DRILLS if not BUILDING[b]["creative"] and BUILDING[b]["params"].get("tier", 0) >= o["hardness"]]


def drone_can_mine(oid):
    o = ORE[oid]
    return o["kind"] == "item" and o["hardness"] <= DRONE.get("mine_tier", 1)


def is_ammo_item(iid):
    """Боеприпас: патрон какой-то турели или то, что идёт только на патроны (гильза)."""
    if iid in AMMO_USERS:
        return True
    uses = CONSUMED_BY.get(("item", iid), [])
    return bool(uses) and all(all(t in AMMO_USERS for k, t, n in RECIPE[r]["outs"]) for r in uses) \
        and not COST_USERS.get(("item", iid)) and iid not in RESEARCH_COST_USERS


def item_category(iid):
    """Раздел списка предметов (по данным, без списков id)."""
    # Научный набор — с уровнем или просто то, чем платят за исследования (военный набор).
    if ITEM[iid]["tier"] > 0 or iid in RESEARCH_COST_USERS:
        return "science"
    if ("item", iid) in ORE_OF_TARGET:
        return "raw"
    if is_ammo_item(iid):
        return "ammo"
    # Материалы — то, что выходит из построек с автовыбором рецепта по сырью (печи).
    for rid in PRODUCED_BY.get(("item", iid), []):
        if any(BUILDING[b]["params"].get("recipe_mode") == 1 for b in MAKERS.get(rid, [])):
            return "material"
    return "component"


ITEM_CATEGORIES = [("raw", "Сырьё", "Добывается дроном и бурами на месторождениях."),
                   ("material", "Материалы", "Получаются переплавкой сырья в печах."),
                   ("component", "Компоненты", "Детали для построек и следующих рецептов."),
                   ("science", "Научные наборы", "Сдаются в исследования: руками или через научный цех."),
                   ("ammo", "Боеприпасы", "Патроны турелей и детали для них.")]

# Категории построек: TRANSPORT 0, PRODUCTION 1, POWER 2, DEFENSE 3 (как в make_content.py).
CATEGORY_KEYS = ["CATEGORY_TRANSPORT", "CATEGORY_PRODUCTION", "CATEGORY_POWER", "CATEGORY_DEFENSE"]
CATEGORY_FALLBACK = ["Логистика", "Производство", "Энергия", "Оборона"]


def category_name(cat):
    if 0 <= cat < len(CATEGORY_KEYS):
        return name_ru(CATEGORY_KEYS[cat], CATEGORY_FALLBACK[cat])
    return "Прочее"


# --- Планеты, угрозы, враги ---
PLANETS = []
for _path in sorted(glob.glob(os.path.join(ROOT, "world", "planet_types", "*.tres"))):
    _v = parse_tres(_path)
    if not _v.get("id"):
        continue
    _threat = _v.get("threat")
    _v["threat_values"] = parse_tres(res_to_path(_threat[1])) if isinstance(_threat, tuple) and _threat[1] else {}
    PLANETS.append(_v)
PLANETS.sort(key=lambda p: (bool(p.get("safe")), -float(p.get("weight", 0)), p["id"]))
PLANET = {p["id"]: p for p in PLANETS}

ENEMY = {}
for _e in ENEMY_ROWS:
    _eid, _order, _hp, _speed, _radius, _dmg, _interval, _rng, _cost, _col, _shape, _size = _e[:12]
    ENEMY[_eid] = {"id": _eid, "order": _order, "hp": _hp, "speed": _speed, "radius": _radius, "damage": _dmg,
                   "interval": _interval, "range": _rng, "cost": _cost, "color": _col, "shape": _shape}
if not ENEMY:
    # Запасной путь: уже сгенерированные enemies/defs/*.tres.
    for _path in sorted(glob.glob(os.path.join(ROOT, "enemies", "defs", "*.tres"))):
        _v = parse_tres(_path)
        ENEMY[_v["id"]] = {"id": _v["id"], "order": _v.get("sort_order", 0), "hp": _v.get("health", 0),
                           "speed": _v.get("speed", 0), "radius": _v.get("radius", 0), "damage": _v.get("damage", 0),
                           "interval": _v.get("attack_interval", 1), "range": _v.get("attack_range", 0),
                           "cost": _v.get("threat_cost", 0), "color": color_floats(_v.get("color")),
                           "shape": _v.get("shape", 0)}
ENEMY_IDS = by_order(ENEMY, ENEMY)


# --- Имена ---
def item_name(i):
    for key in ("ITEM_" + i.upper(), "BUILDING_" + i.upper(), "FLUID_" + i.upper()):
        if key in STR_RU:
            return STR_RU[key]
    WARNINGS.add("нет строки ITEM_%s в i18n/strings.csv — на страницах будет «%s»" % (i.upper(), i))
    return i


def building_name(b):
    return name_ru("BUILDING_" + b.upper(), b)


def research_name(r):
    return name_ru("RESEARCH_" + r.upper(), r)


def fluid_name(f):
    return name_ru(FLUID[f]["key"] if f in FLUID else "FLUID_" + f.upper(), f)


def ore_name(o):
    return name_ru("ORE_" + o.upper(), o)


def enemy_name(e):
    return name_ru("ENEMY_" + e.upper(), e)


def planet_name(p):
    return name_ru(PLANET[p].get("name_key", "PLANET_" + p.upper()), p)


def group_name(g):
    """«любой патрон»: строка ITEM_GROUP_<G>/GROUP_<G>, иначе общее начало названий до двоеточия."""
    for key in ("ITEM_GROUP_" + g.upper(), "GROUP_" + g.upper()):
        if key in STR_RU:
            return STR_RU[key]
    heads = {item_name(m).split(":")[0].strip() for m in GROUPS.get(g, []) if ":" in item_name(m)}
    if len(heads) == 1 and len(GROUPS.get(g, [])) > 1:
        head = heads.pop()
        return "любой " + head[:1].lower() + head[1:]
    return "любой из группы «%s»" % g


# =====================================================================================
# Иконки: inline SVG через <symbol> на странице (повторные иконки — короткий <use>)
# =====================================================================================

_symbols = {}   # символы текущей страницы: id → содержимое <symbol>


def _pts(points):
    return " ".join("%g,%g" % (round(x, 2), round(y, 2)) for x, y in points)


def _scale(points, cx, cy, k):
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in points]


def _ngon(cx, cy, r, n, rot=0.0):
    return [(cx + r * math.cos(rot + 2 * math.pi * i / n), cy + r * math.sin(rot + 2 * math.pi * i / n))
            for i in range(n)]


def _star(cx, cy, ro, ri, n):
    return [(cx + (ro if i % 2 == 0 else ri) * math.cos(-math.pi / 2 + math.pi * i / n),
             cy + (ro if i % 2 == 0 else ri) * math.sin(-math.pi / 2 + math.pi * i / n)) for i in range(n * 2)]


def _poly(points, fill):
    return '<polygon points="%s" fill="%s"/>' % (_pts(points), fill)


def _rect(x, y, w, h, fill, extra=""):
    return '<rect x="%g" y="%g" width="%g" height="%g" fill="%s"%s/>' % (x, y, w, h, fill, extra)


def _circle(cx, cy, r, fill):
    return '<circle cx="%g" cy="%g" r="%g" fill="%s"/>' % (cx, cy, r, fill)


def _line(x1, y1, x2, y2, w, color):
    return '<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="%g" stroke-linecap="round"/>' % (
        x1, y1, x2, y2, color, w)


def item_shape_svg(shape, col):
    """Иконка предмета по форме icon_shape — те же фигуры, что в render/placeholder_art.gd (32×32)."""
    c, o, s, h = "#" + col, darken(col, 0.6), darken(col, 0.2), lighten(col, 0.4)
    if shape == 1:      # SQUARE
        return _rect(5, 5, 22, 22, o) + _rect(7, 7, 18, 18, c) + _rect(15, 15, 10, 10, s) + _rect(8, 8, 4, 2, h)
    if shape == 2:      # DIAMOND
        d = [(16, 3), (29, 16), (16, 29), (3, 16)]
        return _poly(d, o) + _poly(_scale(d, 16, 16, 0.8), c) + _poly([(16, 16), (26, 16), (16, 26)], s) \
            + _rect(12, 9, 3, 2, h)
    if shape == 3:      # TRIANGLE
        t = [(16, 3), (30, 28), (2, 28)]
        return _poly(t, o) + _poly(_scale(t, 16, 19.5, 0.78), c) + _rect(14, 11, 3, 3, h)
    if shape == 4:      # HEXAGON
        hx = _ngon(16, 16, 13.5, 6, math.pi / 6)
        return _poly(hx, o) + _poly(_scale(hx, 16, 16, 0.82), c) + _poly(_ngon(18, 18, 7, 6, math.pi / 6), s) \
            + _rect(9, 10, 4, 2, h)
    if shape == 5:      # CROSS
        return _rect(11, 3, 10, 26, o) + _rect(3, 11, 26, 10, o) + _rect(13, 5, 6, 22, c) + _rect(5, 13, 22, 6, c) \
            + _rect(13, 5, 2, 6, h)
    if shape == 6:      # RING
        return ('<circle cx="16" cy="16" r="9" fill="none" stroke="%s" stroke-width="8"/>'
                '<circle cx="16" cy="16" r="9" fill="none" stroke="%s" stroke-width="4"/>' % (o, c)) \
            + _rect(9, 10, 1, 1, h) + _rect(10, 9, 1, 1, h)
    if shape == 7:      # BAR
        return _rect(3, 9, 26, 14, o) + _rect(5, 11, 22, 10, c) + _rect(5, 17, 22, 4, s) + _rect(7, 12, 8, 2, h)
    if shape == 8:      # STAR
        st = _star(16, 17, 14.5, 6.5, 5)
        return _poly(st, o) + _poly(_scale(st, 16, 17, 0.78), c) + _rect(15, 9, 2, 1, h)
    if shape == 9:      # FRAME
        return _rect(4, 4, 24, 24, o) + _rect(6, 6, 20, 20, c) \
            + _rect(10, 10, 12, 12, lighten(col, 0.5), ' fill-opacity="0.9"') \
            + _line(12, 20, 20, 12, 1.5, "#ffffff")
    if shape == 10:     # INGOT
        g = [(8, 8), (24, 8), (30, 25), (2, 25)]
        return _poly(g, o) + _poly(_scale(g, 16, 16.5, 0.8), c) + _rect(8, 20, 16, 3, s) + _rect(10, 11, 10, 2, h)
    # CIRCLE (0) и неизвестные формы
    return _circle(16, 16, 12.5, o) + _circle(16, 16, 10.5, c) + _circle(18, 18, 6, s) + _circle(12, 12, 2.5, h)


def fluid_svg(col):
    return ('<path d="M16 3C13 8 6 15 6 21a10 10 0 0 0 20 0C26 15 19 8 16 3Z" fill="#%s" stroke="%s" '
            'stroke-width="2"/><path d="M11 20a5 5 0 0 0 4 5" fill="none" stroke="%s" stroke-width="2" '
            'stroke-linecap="round"/>' % (col, darken(col, 0.6), lighten(col, 0.5)))


def flask_svg(col):
    return ('<path d="M12 4h8v2h-1.5v7.5l7 11.5a2 2 0 0 1-1.7 3H7.2a2 2 0 0 1-1.7-3l7-11.5V6H12Z" fill="#%s" '
            'stroke="%s" stroke-width="2" stroke-linejoin="round"/><path d="M9 22h14" stroke="%s" '
            'stroke-width="2"/>' % (col, darken(col, 0.6), lighten(col, 0.45)))


def building_svg(bid):
    """Плашка постройки её цветом; у больших — сетка клеток по размеру."""
    b = BUILDING[bid]
    col = b["color"]
    parts = [_rect(1, 1, 30, 30, darken(col, 0.6), ' rx="4"'), _rect(3, 3, 26, 26, "#" + col, ' rx="3"'),
             _rect(3, 3, 26, 5, lighten(col, 0.25), ' rx="2" fill-opacity="0.6"')]
    n = max(1, int(b["size"]))
    for i in range(1, n):
        p = 3 + 26 * i / n
        parts.append(_line(p, 4, p, 28, 0.8, darken(col, 0.45)))
        parts.append(_line(4, p, 28, p, 0.8, darken(col, 0.45)))
    parts.append(_rect(11, 11, 10, 10, darken(col, 0.35), ' rx="2"'))
    return "".join(parts)


def enemy_svg(shape, col):
    """Враг по форме EnemyDef.Shape (48×48): ползун, стрелок, громила."""
    ink, fire, light = "#1d2021", "#fe8019", "#ebdbb2"
    c = "#" + col
    dark, lite = darken(col, 0.45), lighten(col, 0.35)
    if shape == 1:
        return (_rect(10, 9, 26, 6, ink) + _rect(10, 33, 26, 6, ink) + _rect(12, 13, 22, 22, ink)
                + _rect(14, 15, 18, 18, c) + _rect(26, 22, 20, 5, ink) + _rect(27, 23, 18, 3, lite)
                + _circle(23, 24, 5, dark) + _circle(23, 24, 2, fire))
    if shape == 2:
        return (_poly(_ngon(24, 24, 21, 6), ink) + _poly(_ngon(24, 24, 18, 6), c) + _poly(_ngon(22, 24, 10, 6), dark)
                + _line(36, 14, 46, 7, 4, light) + _line(36, 34, 46, 41, 4, light)
                + _circle(32, 19, 2.2, fire) + _circle(32, 29, 2.2, fire))
    legs = "".join(_line(16 + i * 7, 20, 12 + i * 7, 9, 2.5, ink) + _line(16 + i * 7, 28, 12 + i * 7, 39, 2.5, ink)
                   for i in range(3))
    return (legs + _circle(24, 24, 13, ink) + _circle(24, 24, 10.7, c) + _circle(21, 24, 5, dark)
            + _line(33, 20, 42, 17, 2.5, lite) + _line(33, 28, 42, 31, 2.5, lite)
            + _circle(31, 21, 1.6, fire) + _circle(31, 27, 1.6, fire))


def planet_svg(col):
    return ('<circle cx="16" cy="16" r="13" fill="#%s" stroke="%s" stroke-width="2"/>'
            '<path d="M8 12a10 10 0 0 1 8-6" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round"/>'
            '<ellipse cx="19" cy="20" rx="5" ry="3" fill="%s"/>' % (col, darken(col, 0.55), lighten(col, 0.45),
                                                                     darken(col, 0.2)))


def sym(sid, body, view=32):
    """Иконка через символ страницы: сам символ попадёт в <defs> при сборке страницы."""
    if sid not in _symbols:
        _symbols[sid] = '<symbol id="%s" viewBox="0 0 %d %d">%s</symbol>' % (sid, view, view, body)
    return sid


def svg_use(sid, cls=""):
    return '<svg class="ic%s" aria-hidden="true"><use href="#%s"/></svg>' % ((" " + cls) if cls else "", sid)


# --- Спрайты зданий: art/buildings/<id>.png — полоса квадратных кадров, показывается первый ---
SPRITES = {}   # постройка → (число кадров, байты png)
for _bid in BUILDING_IDS:
    _p = os.path.join(ROOT, "art", "buildings", "%s.png" % _bid)
    if os.path.exists(_p):
        _data = open(_p, "rb").read()
        if _data[:8] == b"\x89PNG\r\n\x1a\n":
            _w, _h = struct.unpack(">II", _data[16:24])
            SPRITES[_bid] = (max(1, _w // max(_h, 1)), _data)


def icon(kind, eid, cls=""):
    """Иконка сущности любого вида."""
    if kind == "item" and eid in ITEM:
        return svg_use(sym("i-" + eid, item_shape_svg(ITEM[eid]["shape"], ITEM[eid]["color"])), cls)
    if kind == "building" and eid in BUILDING:
        if eid in SPRITES:
            return ('<span class="ic spr%s" style="background-image:url(%sassets/sprites/%s.png);'
                    'background-size:%d%% 100%%"></span>' % ((" " + cls) if cls else "", R, eid, SPRITES[eid][0] * 100))
        return svg_use(sym("b-" + eid, building_svg(eid)), cls)
    if kind == "fluid" and eid in FLUID:
        return svg_use(sym("f-" + eid, fluid_svg(FLUID[eid]["color"])), cls)
    if kind == "group" and GROUPS.get(eid):
        return icon(stack_kind(GROUPS[eid][0]), GROUPS[eid][0], cls)
    if kind == "research" and eid in RESEARCH:
        kits = [t for t, _ in RESEARCH[eid]["costs"] if t in ITEM]
        col = ITEM[kits[-1]]["color"] if kits else "928374"
        return svg_use(sym("r-" + col, flask_svg(col)), cls)
    if kind == "ore" and eid in ORE:
        o = ORE[eid]
        return icon("item" if o["kind"] == "item" else "fluid", o["target"], cls)
    if kind == "enemy" and eid in ENEMY:
        return svg_use(sym("e-" + eid, enemy_svg(ENEMY[eid]["shape"], ENEMY[eid]["color"]), 48), cls)
    if kind == "planet" and eid in PLANET:
        return svg_use(sym("p-" + eid, planet_svg(color_floats(PLANET[eid].get("map_color")))), cls)
    return svg_use(sym("u-unknown", _circle(16, 16, 12, "#665c54")), cls)


# =====================================================================================
# Адреса страниц и компоненты разметки
# =====================================================================================

def entity(kind, eid):
    """(название, адрес) сущности; адрес None — ссылки нет."""
    if kind == "item" and eid in ITEM:
        return item_name(eid), R + "items/%s.html" % eid
    if kind == "building" and eid in BUILDING:
        return building_name(eid), R + "buildings/%s.html" % eid
    if kind == "fluid" and eid in FLUID:
        return fluid_name(eid), R + "fluids/%s.html" % eid
    if kind == "research" and eid in RESEARCH:
        return research_name(eid), R + "research/%s.html" % eid
    if kind == "group" and eid in GROUPS:
        return group_name(eid), R + "items/index.html#group-%s" % eid
    if kind == "ore" and eid in ORE:
        return ore_name(eid), R + "world/index.html#ore-%s" % eid
    if kind == "planet" and eid in PLANET:
        return planet_name(eid), R + "world/index.html#planet-%s" % eid
    if kind == "enemy" and eid in ENEMY:
        return enemy_name(eid), R + "enemies/index.html#enemy-%s" % eid
    return eid, None


def chip(kind, eid, amount=None, note=None, extra_cls=""):
    """Ссылка-плашка: иконка, название, количество и пометка."""
    name, url = entity(kind, eid)
    amt = ""
    if amount is not None:
        amt = ' <b class="n">%s</b>' % (("%s ед." % fmt(amount)) if kind == "fluid" else "×" + fmt(amount))
    tag = ' <i class="tag">%s</i>' % esc(note) if note else ""
    cls = "chip" + (" any" if kind == "group" else "") + ((" " + extra_cls) if extra_cls else "")
    inner = "%s<span>%s</span>%s%s" % (icon(kind, eid), esc(name), amt, tag)
    if url:
        return '<a class="%s" href="%s">%s</a>' % (cls, url, inner)
    return '<span class="%s">%s</span>' % (cls, inner)


def chips(items, empty="—"):
    return '<span class="chips">%s</span>' % "".join(items) if items else '<span class="muted">%s</span>' % empty


def ref_chips(refs):
    """Входы или выходы рецепта. Несколько any: одной группы — обязательно разные предметы."""
    counts = {}
    for k, t, n in refs:
        if k == "group":
            counts[t] = counts.get(t, 0) + 1
    return [chip(k, t, n, "разные виды" if k == "group" and counts[t] > 1 else None) for k, t, n in refs]


def stack_chips(stacks):
    return [chip(stack_kind(t), t, n) for t, n in stacks]


def link(url, text):
    return '<a href="%s">%s</a>' % (url, esc(text))


def table(header, rows, cls="", labels=True):
    """Таблица. cls="stack" — на узком экране строки становятся карточками с подписями ячеек."""
    out = ['<div class="tw"><table class="%s">' % cls if cls else '<div class="tw"><table>',
           "<thead><tr>%s</tr></thead>" % "".join("<th>%s</th>" % esc(h) for h in header), "<tbody>"]
    for row in rows:
        tds = []
        for i, cell in enumerate(row):
            # В таблице из двух столбцов подпись второго на каждой карточке только мешает.
            if labels and "stack" in cls and i > 0 and header[i] and len(header) > 2:
                # Подпись и значение на узком экране стоят в строку; значение — одним блоком.
                tds.append('<td data-label="%s"><div>%s</div></td>' % (esc(header[i]), cell))
            else:
                tds.append("<td>%s</td>" % cell)
        out.append("<tr>%s</tr>" % "".join(tds))
    out.append("</tbody></table></div>")
    return "\n".join(out)


def facts(rows):
    """Таблица «свойство — значение» (значения уже в HTML)."""
    body = "\n".join("<tr><th>%s</th><td>%s</td></tr>" % (esc(k), v) for k, v in rows if v not in (None, ""))
    return '<div class="tw"><table class="facts"><tbody>\n%s\n</tbody></table></div>' % body


def section(title, body, sid=None):
    return '<section%s>\n<h2>%s</h2>\n%s\n</section>' % (' id="%s"' % sid if sid else "", esc(title), body)


def sub(title, body, sid=None):
    return '<h3%s>%s</h3>\n%s' % (' id="%s"' % sid if sid else "", esc(title), body)


def para(text_html, cls=""):
    return '<p%s>%s</p>' % (' class="%s"' % cls if cls else "", text_html)


def details(summary, body):
    return '<details><summary>%s</summary>\n%s\n</details>' % (summary, body)


def many_chips(items, limit=16):
    """Длинный список плашек сворачивается."""
    if len(items) <= limit:
        return chips(items)
    return details("Показать все (%d)" % len(items), chips(items))


def badge(text, color=""):
    return '<span class="badge%s">%s</span>' % ((" " + color) if color else "", esc(text))


def hero(kind, eid, title, subtitle_html, badges=""):
    return ('<div class="hero">%s<div><h1>%s</h1><div class="sub">%s</div>%s</div></div>'
            % (icon(kind, eid, "big"), esc(title), subtitle_html, ('<div class="badges">%s</div>' % badges) if badges else ""))


def recipe_block(rid, speed=1.0, show_where=True):
    """Рецепт: входы → выходы, время, где делается и чем открывается."""
    r = RECIPE[rid]
    t = r["time"] / speed if speed else r["time"]
    meta = ["%s с" % fmt(t) + (" (×%s)" % fmt(speed) if speed != 1.0 else "")]
    if show_where:
        where = [chip("building", b) for b in MAKERS.get(rid, [])]
        if r["hand"]:
            where.append('<span class="chip hand"><span>руками</span></span>')
        meta.append("где: " + (chips(where) if where else '<span class="muted">нигде</span>'))
    rs = RESEARCH_OF_RECIPE.get(rid)
    if rs:
        meta.append("открывает " + chip("research", rs))
    return ('<div class="recipe"><div class="flow">%s<span class="arrow">→</span>%s</div>'
            '<div class="meta">%s</div></div>' % ("".join(ref_chips(r["ins"])) or '<span class="muted">ничего</span>',
                                                   "".join(ref_chips(r["outs"])), " · ".join(meta)))


def recipes_list(rids, **kw):
    return "\n".join(recipe_block(r, **kw) for r in rids)


# =====================================================================================
# Страницы
# =====================================================================================

NAV = [("items", "Предметы", "items/index.html"), ("buildings", "Постройки", "buildings/index.html"),
       ("research", "Исследования", "research/index.html"), ("tree", "Дерево", "research/tree.html"),
       ("world", "Мир", "world/index.html"), ("enemies", "Враги", "enemies/index.html"),
       ("mechanics", "Механики", "mechanics/index.html")]
SECTION_TITLE = {"items": "Предметы", "buildings": "Постройки", "research": "Исследования",
                 "tree": "Дерево исследований", "world": "Месторождения и планеты", "enemies": "Враги и волны",
                 "mechanics": "Механики"}
SECTION_URL = {k: R + u for k, _, u in NAV}

PAGES = {}      # путь → html
SEARCH = []     # [название, адрес от корня, вид, ключевые слова]
PAGE_KIND = {}  # путь → вид страницы для сводки


def search_add(title, url, kind, keys=""):
    SEARCH.append([title, url[len(R):] if url.startswith(R) else url, kind, keys])


def en_name(key):
    return STR_EN.get(key, "")


# Значок вкладки прямо в странице: отдельный favicon.ico на file:// и в подпапке Pages не найдётся.
FAVICON = ("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect x='2' y='2' "
           "width='28' height='28' rx='6' fill='%23282828' stroke='%23fabd2f' stroke-width='3'/%3E%3Cpath d='M9 10l3 "
           "12 4-8 4 8 3-12' fill='none' stroke='%23fe8019' stroke-width='3' stroke-linejoin='round'/%3E%3C/svg%3E")


def page(path, title, nav, crumbs, body, kind, wide=False):
    """Собирает страницу: шапка, навигация, крошки, символы иконок, тело. crumbs — [(текст, адрес)],
    None — без крошек (главная); wide — без ограничения ширины (дерево исследований)."""
    depth = path.count("/")
    prefix = "../" * depth
    navs = "".join('<a href="%s"%s>%s</a>' % (R + u, ' class="on"' if k == nav else "", esc(t)) for k, t, u in NAV)
    trail = [link(R + "index.html", "Главная")] + [link(u, t) if u else esc(t) for t, u in crumbs or []]
    trail.append('<span aria-current="page">%s</span>' % esc(title))
    defs = ""
    if _symbols:
        defs = '<svg class="defs" aria-hidden="true"><defs>\n%s\n</defs></svg>\n' % "\n".join(
            _symbols[k] for k in sorted(_symbols))
    doc = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%(title)s — WarpFactor вики</title>
<link rel="icon" href="%(favicon)s">
<link rel="stylesheet" href="%(R)sassets/wiki.css">
</head>
<body data-root="%(prefix)s">
%(defs)s<header class="top">
<div class="bar"><a class="logo" href="%(R)sindex.html">WarpFactor <span>вики</span></a>
<div class="search"><input type="search" placeholder="Поиск: предмет, постройка, исследование…" aria-label="Поиск по вики" autocomplete="off" data-search><ul class="results" hidden></ul></div></div>
<nav class="sections">%(nav)s</nav>
</header>
<main%(main_cls)s>
%(trail)s%(body)s
</main>
<footer>Страница собрана из данных игры скриптом <code>tools/data/make_wiki.py</code>.</footer>
<script src="%(R)sassets/search-index.js"></script>
<script src="%(R)sassets/wiki.js"></script>
</body>
</html>
""" % {"title": esc(title), "R": R, "prefix": prefix, "defs": defs, "nav": navs,
       "trail": ('<nav class="crumbs">%s</nav>\n' % ' <span class="sep">›</span> '.join(trail))
       if crumbs is not None else "", "body": body, "favicon": FAVICON, "main_cls": ' class="wide"' if wide else ""}
    PAGES[path] = doc.replace(R, prefix)
    PAGE_KIND[path] = kind
    _symbols.clear()


def crumbs_for(nav):
    return [(SECTION_TITLE[nav], SECTION_URL[nav])]


# --- Правила из CONTENT.md: какие таблицы куда ---
# Таблицы-списки (предметы, рецепты, постройки, исследования) вики строит сама из данных,
# а таблицы правил переносятся как есть. Раздел выбирается по названию главы CONTENT.md.
CONTENT_SKIP = {"Про файл", "Месторождение", "Предмет", "Рецепт", "Патрон", "Постройка", "Исследование"}


def content_route(block):
    title = block["section"]
    if "Месторожден" in title or "Предмет" in title:
        return "world"
    if "Исследован" in title:
        return "research"
    return "mechanics"


def content_blocks(route, subsection=None):
    """Таблицы правил CONTENT.md для раздела вики (и, если задан, только из подраздела)."""
    out = []
    for b in CONTENT_TABLES:
        if not b["header"] or b["header"][0] in CONTENT_SKIP or content_route(b) != route:
            continue
        if subsection is not None and b["sub"] != subsection:
            continue
        out.append(b)
    return out


def content_table(block):
    return table(block["header"], [[md_inline(c) for c in row] for row in block["rows"]], "stack")


def clean_title(title):
    """«7а. Мобильная база: …» → «Мобильная база: …»."""
    return re.sub(r"^\d+\S*\.\s*", "", title)


# ---------------------------------------------------------------- предметы

def ore_sources_html(kind, eid):
    """Строки «где получить» про месторождения: кто и как быстро добывает."""
    rows = []
    for oid in ORE_OF_TARGET.get((kind, eid), []):
        o = ORE[oid]
        who = []
        if drone_can_mine(oid):
            sec = DRONE.get("mine_base_seconds", 0) + DRONE.get("mine_hardness_seconds", 0) * o["hardness"]
            who.append('<span class="chip hand"><span>дрон — %s с/шт.</span></span>' % fmt(float(sec)))
        drills = False
        for b in ore_extractors(oid):
            p = BUILDING[b]["params"]
            if "base_seconds" in p:
                cells = BUILDING[b]["size"] ** 2
                sec = (p["base_seconds"] + p.get("hardness_seconds", 0) * o["hardness"]) / max(cells, 1)
                who.append(chip("building", b, note="%s с/шт." % fmt(float(sec))))
                drills = True
            else:
                who.append(chip("building", b))
        rows.append(("Месторождение", chip("ore", oid) + ' <span class="muted">твёрдость %d</span>' % o["hardness"]))
        rows.append(("Добывают", chips(who, "никто") + (
            '<div class="muted small">Время бура — когда все клетки под ним средние; богатые клетки быстрее.</div>'
            if drills else "")))
    return rows


def item_page(iid):
    it = ITEM[iid]
    name = item_name(iid)
    cat = item_category(iid)
    cat_title = dict((k, t) for k, t, _ in ITEM_CATEGORIES)[cat]
    info = [("Раздел", link(R + "items/index.html#cat-" + cat, cat_title)), ("Стак", "%d шт." % it["stack"])]
    if it["fuel"] > 0:
        info.append(("Топливо", "%s кДж (%s МДж)" % (fmt(it["fuel"]), fmt(it["fuel"] / 1000.0))))
    if it["tier"] > 0:
        info.append(("Научный набор", "уровень %d" % it["tier"]))
    groups = [g for g in GROUPS if iid in GROUPS[g]]
    if groups:
        info.append(("Группа", chips([chip("group", g) for g in groups])))
    body = [hero("item", iid, name, '<code>%s</code>' % esc(iid)), facts(info)]

    # Где получить
    get = []
    src_rows = ore_sources_html("item", iid)
    if src_rows:
        get.append(facts(src_rows))
    made = [r for r in PRODUCED_BY.get(("item", iid), [])]
    if made:
        get.append(sub("Рецепты", recipes_list(made)))
    start = [n for t, n in START_ITEMS if t == iid]
    if start:
        get.append(para("Есть в стартовом наборе забега: <b>×%s</b>." % fmt(start[0])))
    body.append(section("Где получить", "\n".join(get) or para("Пока нигде: в данных нет рецепта или месторождения.",
                                                                 "muted")))

    # Где нужен
    use = []
    direct = [r for r in CONSUMED_BY.get(("item", iid), []) if not is_autobuild(r)]
    if direct:
        use.append(sub("В рецептах", recipes_list(direct)))
    for g in groups:
        via = CONSUMED_BY.get(("group", g), [])
        if via:
            use.append(sub("Как %s" % group_name(g), recipes_list(via)))
    costs = COST_USERS.get(("item", iid), [])
    if costs:
        use.append(sub("В стоимости построек", many_chips([chip("building", b, n) for b, n in costs], 24)
                       + para("Столько же уходит и на автосборку этих построек в сборщике.", "muted small")))
    rc = RESEARCH_COST_USERS.get(iid, [])
    if rc:
        total = sum(n for rid, n in rc if not RESEARCH[rid]["creative"])
        use.append(sub("В стоимости исследований",
                       para("%d %s, всего %s шт. без творческого режима." % (
                           len(rc), plural(len(rc), "исследование", "исследования", "исследований"), fmt(total)))
                       + many_chips([chip("research", r, n) for r, n in rc])))
    if it["tier"] > 0 and WORKSHOPS:
        text = "Сдаётся в " + chips([chip("building", b) for b in WORKSHOPS])
        use.append(sub("Изучение", para(text)))
    if it["fuel"] > 0 and FUEL_BURNERS:
        rows = []
        for b in FUEL_BURNERS:
            p = BUILDING[b]["params"]
            power = p.get("fuel_use") or p.get("fuel_power")
            if not power and p.get("efficiency"):
                power = p.get("max_output", 0) / p["efficiency"]
            rows.append([chip("building", b), "%s кВт" % fmt(float(power)) if power else "—",
                         "%s с" % fmt(round(it["fuel"] / power, 1)) if power else "—"])
        use.append(sub("Топливо", table(["Постройка", "Расход на полной мощности", "Одна штука горит"], rows, "stack")))
    if iid in AMMO_USERS:
        rows = []
        for b, a in AMMO_USERS[iid]:
            rows.append([chip("building", b), fmt(a[1]), fmt(a[2]), ammo_effect(a)])
        use.append(sub("Патрон турели", table(["Турель", "Выстрелов", "Урон", "Эффект"], rows, "stack")))
    body.append(section("Где нужен", "\n".join(use) or para("Пока нигде не используется.", "muted")))
    page("items/%s.html" % iid, name, "items", crumbs_for("items"), "\n".join(body), "item")
    search_add(name, R + "items/%s.html" % iid, "Предмет", "%s %s" % (iid, en_name("ITEM_" + iid.upper())))


def ammo_effect(a):
    """Эффект патрона, как в CONTENT.md: осколки, поджог, скорострельность."""
    _, shots, dmg, splash, speed, reload_mul, _, burn, burn_s = a[:9]
    fx = []
    if splash > 0:
        fx.append("осколки: взрыв радиусом %s при попадании" % tiles(splash))
    if burn > 0:
        fx.append("поджог: %s урона/с на %s с" % (fmt(burn), fmt(burn_s)))
    if reload_mul < 1.0:
        fx.append("скорострельность ×%s, пуля быстрее (%s тайла/с)" % (fmt(round(1 / reload_mul, 2)), fmt(speed)))
    if not fx:
        fx.append("повышенный урон" if dmg > 10 else "базовый")
    return esc("; ".join(fx))


def items_index():
    body = [para("Все предметы игры: сырьё, материалы, компоненты, научные наборы и боеприпасы. Постройки "
                 "тоже лежат в инвентаре как предметы — они в разделе %s." % link(SECTION_URL["buildings"], "Постройки"))]
    toc = []
    for key, title, desc in ITEM_CATEGORIES:
        ids = [i for i in ITEM_IDS if item_category(i) == key]
        if not ids:
            continue
        toc.append(link("#cat-" + key, "%s (%d)" % (title, len(ids))))
        cards = "".join('<a class="card" href="%s">%s<span>%s<small>стак %d%s</small></span></a>' % (
            entity("item", i)[1], icon("item", i, "mid"), esc(item_name(i)), ITEM[i]["stack"],
            ", топливо" if ITEM[i]["fuel"] > 0 else "") for i in ids)
        body.append(section(title, para(esc(desc), "muted") + '<div class="grid">%s</div>' % cards, "cat-" + key))
    if GROUPS:
        parts = []
        for g in GROUPS:
            users = CONSUMED_BY.get(("group", g), [])
            parts.append('<div class="group" id="group-%s"><h3>%s</h3>%s%s</div>' % (
                esc(g), esc(group_name(g)[:1].upper() + group_name(g)[1:]),
                para("Подходит любой из: " + chips(stack_chips([(m, None) for m in GROUPS[g]]))),
                para("Нужен в: " + chips([chip(*r["outs"][0][:2]) for r in (RECIPE[x] for x in users) if r["outs"]]))
                if users else ""))
            search_add(group_name(g), R + "items/index.html#group-%s" % g, "Группа", g)
        body.append(section("Группы предметов", para("В некоторых рецептах подходит любой предмет группы. "
                                                      "Если группа указана в рецепте несколько раз, предметы должны "
                                                      "быть <b>разных видов</b>.", "muted") + "\n".join(parts), "groups"))
    body.insert(1, '<nav class="toc">%s</nav>' % " · ".join(toc + ([link("#groups", "Группы")] if GROUPS else [])))
    page("items/index.html", "Предметы", "items", [], "<h1>Предметы</h1>\n" + "\n".join(body), "section")
    search_add("Предметы", R + "items/index.html", "Раздел", "items")


# ---------------------------------------------------------------- постройки

TURRET_KINDS = {0: "патронная", 1: "электрическая: молния по цепи", 2: "ремонтная", 3: "жидкостная: поливает область"}
GENERATOR_KINDS = {0: "на топливе", 1: "на паре"}
RECIPE_MODES = {0: "один рецепт", 1: "сама, по пришедшему сырью", 2: "в настройке постройки"}
# Внутренние параметры, которые игроку ничего не говорят.
PARAM_SKIP = {"rotatable", "role", "kind", "recipes", "ammo", "creative_only", "default_rate", "in_base",
              "inbound_side", "outbound_side", "is_core", "barrel_length", "shoot_cone", "artillery", "transfer_ticks",
              "hardness_seconds", "grown_size"}


def building_params(bid):
    """Параметры постройки человеческим языком: [(название, значение HTML)]."""
    b = BUILDING[bid]
    p = b["params"]
    rows = []
    if b["kind"] == "turret":
        rows.append(("Тип", esc(TURRET_KINDS.get(p.get("kind", 0), "турель"))))
    if b["kind"] == "generator" and "kind" in p:
        rows.append(("Тип", esc(GENERATOR_KINDS.get(p["kind"], "генератор"))))
    for key, v in p.items():
        if key in PARAM_SKIP:
            continue
        if key == "tiles_per_second":
            rows.append(("Скорость ленты", "%s/с" % tiles(v)))
        elif key == "capacity":
            rows.append(("Вмещает", "%d предм." % v))
        elif key == "link_range":
            rows.append(("Дальность", "до %s" % tiles(v)))
        elif key == "throughput":
            rows.append(("Пропускная способность", ("как у " + chip("building", v)) if v != bid else "своя"))
        elif key == "slots":
            rows.append(("Ячеек", "%d" % v))
        elif key == "recipe_mode":
            rows.append(("Выбор рецепта", esc(RECIPE_MODES.get(v, str(v)))))
        elif key == "item_capacity":
            rows.append(("Буфер предметов", "%d" % v))
        elif key == "fuel_use":
            rows.append(("Расход топлива", "%s кВт" % fmt(v)))
        elif key == "fuel_capacity":
            rows.append(("Запас топлива", "%d шт." % v))
        elif key == "craft_speed":
            rows.append(("Скорость работы", "×%s" % fmt(v)))
        elif key == "power_use":
            rows.append(("Электричество", "потребляет %s кВт" % fmt(v)))
        elif key == "tier":
            rows.append(("Твёрдость руды", "до %d" % v))
        elif key == "base_seconds":
            rows.append(("Время добычи", "(%s + %s × твёрдость) с на предмет с одной клетки руды; клетки под буром "
                         "складываются, богатые быстрее" % (fmt(v), fmt(p.get("hardness_seconds", 0)))))
        elif key == "seconds_per_kit":
            rows.append(("Изучение", "%s с на набор" % fmt(v)))
        elif key == "kit_capacity":
            rows.append(("Буфер наборов", "%d" % v))
        elif key == "wire_range":
            rows.append(("Провод", "до %s" % tiles(v)))
        elif key == "supply_size":
            rows.append(("Зона питания", "%d×%d" % (v, v)))
        elif key == "max_links":
            rows.append(("Проводов", "до %d" % v))
        elif key == "max_output":
            rows.append(("Выработка", "до %s кВт" % fmt(v)))
        elif key == "efficiency":
            rows.append(("КПД", pct(v)))
        elif key == "steam_energy":
            rows.append(("Энергия пара", "%s кДж за единицу" % fmt(v)))
        elif key == "pump_fluid" and v in FLUID:
            rows.append(("Качает только", chip("fluid", v)))
        elif key == "damage_per_upgrade":
            rows.append(("Урон за ступень исследования", "+%s (ветка «Урон турелей»)" % pct(v)))
        elif key.endswith(("fluid", "fluid_id")) and isinstance(v, str) and v in FLUID:
            role = dict(fluid_links(bid)).get(v, "in")
            rows.append(("Берёт" if role == "in" else "Отдаёт", chip("fluid", v)))
        elif key == "fluid_capacity":
            rows.append(("Вмещает", "%s ед. жидкости" % fmt(v)))
        elif key == "underground_range":
            rows.append(("Под землёй", "до %s" % tiles(v)))
        elif key == "allowed_on_fluid":
            if v:
                rows.append(("Можно ставить на воду", "да"))
        elif key == "pump_per_tile":
            fields = [o for o in ORE_IDS if ORE[o]["kind"] == "fluid" and bid in ore_extractors(o)]
            rows.append(("Качает", "%s ед./с с каждой клетки месторождения%s%s" % (
                fmt(v), (" " + chips([chip("ore", o) for o in fields])) if fields else "",
                "" if p.get("power_use") else ", без электричества")))
        elif key == "fuel_power":
            rows.append(("Сжигает топливо", "%s кВт" % fmt(v)))
        elif key == "steam_per_second":
            rows.append(("Даёт пара", "%s ед./с (воды берёт столько же)" % fmt(v)))
        elif key == "capacity_kj":
            rows.append(("Ёмкость", "%s МДж" % fmt(v / 1000.0)))
        elif key == "max_rate":
            rows.append(("Заряд и разряд", "до %s кВт" % fmt(v)))
        elif key == "buffer_capacity":
            rows.append(("Буфер", "%d предм." % v))
        elif key == "shoot_range":
            rows.append(("Радиус", tiles(v)))
        elif key == "reload_seconds":
            rows.append(("Пауза между выстрелами", "%s с" % fmt(v)))
        elif key == "rotate_speed":
            rows.append(("Поворот", "%s°/с" % fmt(v)))
        elif key == "inaccuracy":
            if v:
                rows.append(("Разброс", "%s°" % fmt(v)))
        elif key == "max_ammo":
            if v:
                rows.append(("Запас выстрелов", "%d, без электричества" % v))
        elif key == "chain_damage":
            rows.append(("Урон молнии", fmt(v)))
        elif key == "chain_targets":
            rows.append(("Целей в цепи", "до %d" % v))
        elif key == "chain_falloff":
            rows.append(("Ослабление на прыжке", "×%s" % fmt(v)))
        elif key == "chain_jump":
            rows.append(("Прыжок молнии", "до %s" % tiles(v)))
        elif key == "repair_amount":
            rows.append(("Ремонт", "%s прочности за раз" % fmt(v)))
        elif key == "spray_use":
            rows.append(("Расход жидкости", "%s ед. за залп" % fmt(v)))
        elif key == "spray_radius":
            rows.append(("Лужа", "радиус %s" % tiles(v)))
        elif key == "slow_factor":
            rows.append(("Вода замедляет", "скорость ×%s на %s с" % (fmt(v), fmt(p.get("slow_seconds", 0)))))
        elif key == "slow_seconds":
            continue
        elif key == "steam_dps":
            rows.append(("Пар жжёт", "%s урона/с на %s с" % (fmt(v), fmt(p.get("steam_seconds", 0)))))
        elif key == "steam_seconds":
            continue
        elif key == "rates":
            rows.append(("Скорости на выбор", ", ".join(fmt(x) for x in v)))
        elif key == "start_size":
            grown = p.get("grown_size")
            rows.append(("Размер", "%d×%d" % (v, v) + (", после исследований %d×%d" % (grown, grown) if grown else "")))
        elif key == "deploy_seconds":
            rows.append(("Развёртывание", "%s с" % fmt(v)))
        elif key == "energy_link":
            if v:
                rows.append(("Проводит", "ток и трубы между этажами"))
        elif isinstance(v, (int, float, str)):
            rows.append((key, "<code>%s</code>" % esc(fmt(v))))
    if b["line"]:
        rows.append(("Ставится", "линией, протягиванием"))
    return rows


def building_page(bid):
    b = BUILDING[bid]
    name = building_name(bid)
    badges = []
    if b["creative"]:
        badges.append(badge("творческий режим", "red"))
    elif not b["buildable"]:
        badges.append(badge("не строится игроком", "blue"))
    desc = STR_RU.get("BUILDING_%s_DESC" % bid.upper(), "")
    subtitle = '<code>%s</code> · %s' % (esc(bid), link(SECTION_URL["buildings"] + "#cat-%d" % b["cat"],
                                                        category_name(b["cat"])))
    body = [hero("building", bid, name, subtitle, "".join(badges))]
    if desc:
        body.append(para(esc(desc), "lead"))
    info = [("Размер", "%d×%d" % (b["size"], b["size"])), ("Прочность", fmt(b["hp"])),
            ("Твёрдая", "да, преграждает путь" if b["solid"] else "нет, проходима")]
    if not b["removable"]:
        info.append(("Снос", "нельзя"))
    if b["cost"]:
        info.append(("Стоимость", chips(stack_chips(b["cost"]))))
    if b["craft"]:
        t, batch, stack = b["craft"][:3]
        info.append(("Крафт", "%s с%s" % (fmt(float(t)), ", за раз %d шт." % batch if batch != 1 else "")))
        info.append(("Стак", "%d шт." % stack))
    rs = RESEARCH_OF_BUILDING.get(bid)
    if b["creative"]:
        info.append(("Открывается", "только в творческом режиме"))
    elif not b["buildable"]:
        info.append(("Открывается", "ставится сама вместе с этажом или базой"))
    else:
        info.append(("Открывается", chip("research", rs) if rs else "доступна с начала игры"))
    body.append(facts(info))

    params = building_params(bid)
    if params:
        body.append(section("Параметры", facts(params)))

    p = b["params"]
    ammo = p.get("ammo") or []
    if ammo:
        rows = [[chip("item", a[0]), fmt(a[1]), fmt(a[2]), "%s/с" % tiles(a[4]), ammo_effect(a)] for a in ammo]
        body.append(section("Патроны", table(["Патрон", "Выстрелов на патрон", "Урон", "Пуля", "Эффект"], rows, "stack")))

    if b["kind"] == "drill":
        rows = []
        cells = b["size"] ** 2
        for oid in ORE_IDS:
            o = ORE[oid]
            if o["kind"] != "item" or bid not in ore_extractors(oid):
                continue
            sec = p.get("base_seconds", 0) + p.get("hardness_seconds", 0) * o["hardness"]
            rows.append([chip("ore", oid), "%d" % o["hardness"], "%s с" % fmt(float(sec)),
                         "%s с" % fmt(round(sec / cells, 2))])
        if rows:
            body.append(section("Что добывает", table(
                ["Месторождение", "Твёрдость", "С одной средней клетки", "Все %d клетки средние" % cells
                 if cells > 1 else "На одной клетке"], rows, "stack")))

    recs = p.get("recipes", [])
    if recs:
        plain = [r for r in recs if r in RECIPE and not is_autobuild(r)]
        auto = [r for r in recs if r in RECIPE and is_autobuild(r)]
        parts = [recipes_list(plain, speed=float(p.get("craft_speed", 1.0)), show_where=False)]
        if auto:
            research = sorted({RESEARCH_OF_RECIPE[r] for r in auto if r in RESEARCH_OF_RECIPE},
                              key=lambda x: RESEARCH[x]["order"])
            parts.append(sub("Автосборка построек", para(
                "Ещё %d %s: постройки по их обычной стоимости%s." % (
                    len(auto), plural(len(auto), "рецепт", "рецепта", "рецептов"),
                    (", после исследования " + " ".join(chip("research", x) for x in research)) if research else ""))
                + many_chips([chip(*RECIPE[r]["outs"][0][:2]) for r in auto if RECIPE[r]["outs"]], 0)))
        body.append(section("Рецепты", "\n".join(parts)))

    # Где получить: ручной крафт, автосборка, стартовый набор
    get = []
    if b["craft"] and b["cost"]:
        t, batch = b["craft"][:2]
        get.append(para("Руками в окне крафта: %s → %s за %s с." % (
            chips(stack_chips(b["cost"])), chip("building", bid, batch), fmt(float(t)))))
    auto_recipes = [r for r in PRODUCED_BY.get(("building", bid), [])]
    if auto_recipes:
        get.append(recipes_list(auto_recipes))
    start = [n for t, n in START_ITEMS if t == bid]
    if start:
        get.append(para("Есть в стартовом наборе забега: <b>×%s</b>." % fmt(start[0])))
    if get:
        body.append(section("Где получить", "\n".join(get)))

    # Где нужна: постройка как ингредиент
    use = []
    direct = [r for r in CONSUMED_BY.get(("building", bid), []) if not is_autobuild(r)]
    if direct:
        use.append(recipes_list(direct))
    costs = COST_USERS.get(("building", bid), [])
    if costs:
        use.append(sub("В стоимости построек", chips([chip("building", x, n) for x, n in costs])))
    if use:
        body.append(section("Где нужна", "\n".join(use)))

    page("buildings/%s.html" % bid, name, "buildings", crumbs_for("buildings"), "\n".join(body), "building")
    search_add(name, R + "buildings/%s.html" % bid, "Постройка", "%s %s" % (bid, en_name("BUILDING_" + bid.upper())))


def building_card(bid):
    b = BUILDING[bid]
    extra = []
    p = b["params"]
    if p.get("power_use"):
        extra.append("%s кВт" % fmt(p["power_use"]))
    elif b["kind"] == "generator" and p.get("max_output"):
        extra.append("даёт %s кВт" % fmt(p["max_output"]))
    return '<a class="card" href="%s">%s<span>%s<small>%d×%d%s</small></span></a>' % (
        entity("building", bid)[1], icon("building", bid, "mid"), esc(building_name(bid)), b["size"], b["size"],
        "".join(", " + esc(e) for e in extra))


def buildings_index():
    body = ["<h1>Постройки</h1>", para("Всё, что ставится на карту: транспорт, производство, энергия и оборона. "
                                        "Постройки крафтятся руками или в сборщике и лежат в инвентаре как предметы.")]
    toc, parts, anchored = [], [], set()
    cats = sorted({BUILDING[b]["cat"] for b in BUILDING_IDS})
    for cat in cats:
        ids = [b for b in BUILDING_IDS if BUILDING[b]["cat"] == cat and BUILDING[b]["buildable"]
               and not BUILDING[b]["creative"]]
        if not ids:
            continue
        toc.append(link("#cat-%d" % cat, "%s (%d)" % (category_name(cat), len(ids))))
        parts.append(section(category_name(cat), '<div class="grid">%s</div>' % "".join(building_card(b) for b in ids),
                             "cat-%d" % cat))
        anchored.add(cat)
    fixed = [b for b in BUILDING_IDS if not BUILDING[b]["buildable"] and not BUILDING[b]["creative"]]
    if fixed:
        toc.append(link("#fixed", "Не строятся (%d)" % len(fixed)))
        parts.append(section("Не строятся игроком", para("Шлюзы, шахты и пульты ставятся сами — вместе с базой, "
                                                          "этажом или комнатой добычи.", "muted")
                             + '<div class="grid">%s</div>' % "".join(building_card(b) for b in fixed), "fixed"))
    creative = [b for b in BUILDING_IDS if BUILDING[b]["creative"]]
    if creative:
        toc.append(link("#creative", "Творческий режим (%d)" % len(creative)))
        parts.append(section("Творческий режим", para("Источники и поглотитель для замеров — есть только в "
                                                       "творческом режиме.", "muted")
                             + '<div class="grid">%s</div>' % "".join(building_card(b) for b in creative), "creative"))
    # Пустые категории тоже получают якорь: на них ссылаются страницы построек.
    for cat in cats:
        if cat not in anchored:
            parts.append('<span id="cat-%d"></span>' % cat)
    body.append('<nav class="toc">%s</nav>' % " · ".join(toc))
    body += parts
    page("buildings/index.html", "Постройки", "buildings", [], "\n".join(body), "section")
    search_add("Постройки", R + "buildings/index.html", "Раздел", "buildings")


# ---------------------------------------------------------------- исследования

# Шаги улучшений дрона из player/drone.tres — чтобы писать не «быстрее», а насколько.
DRONE_STEPS = {"drone_speed": ("speed_step", lambda v: "+%s/с к скорости" % tiles(v)),
               "drone_mining": ("mine_speed_step", lambda v: "+%s к скорости добычи" % pct(v)),
               "drone_health": ("health_step", lambda v: "+%s прочности" % fmt(v)),
               "drone_gun": ("gun_damage_step", lambda v: "+%s урона автопушки" % fmt(v)),
               "drone_repair": ("repair_step", lambda v: "+%s прочности/с к ремонту" % fmt(v))}


def effect_text(e):
    text = EFFECT_TEXT.get(e, e)
    if e in DRONE_STEPS and DRONE_STEPS[e][0] in DRONE:
        text += " (%s)" % DRONE_STEPS[e][1](DRONE[DRONE_STEPS[e][0]])
    return text


def research_opens(rid):
    """Что открывает исследование: плашки построек и рецептов, строки эффектов."""
    r = RESEARCH[rid]
    items = [chip("building", b) for b in r["buildings"]]
    plain = [x for x in r["recipes"] if x in RECIPE and not is_autobuild(x)]
    auto = [x for x in r["recipes"] if x in RECIPE and is_autobuild(x)]
    items += [chip(*RECIPE[x]["outs"][0][:2], note="рецепт") for x in plain if RECIPE[x]["outs"]]
    effects = [EFFECT_OVERRIDE[rid]] if rid in EFFECT_OVERRIDE else [effect_text(e) for e in r["effects"]]
    return items, plain, auto, effects


def all_prereqs(rid):
    seen, stack = [], list(RESEARCH[rid]["pre"])
    while stack:
        x = stack.pop()
        if x in RESEARCH and x not in seen:
            seen.append(x)
            stack.extend(RESEARCH[x]["pre"])
    return seen


def cost_chips(costs):
    return [chip("item", t, n) if t in ITEM else chip(stack_kind(t), t, n) for t, n in costs]


def research_page(rid):
    r = RESEARCH[rid]
    name = research_name(rid)
    badges = badge("только творческий режим", "red") if r["creative"] else ""
    subtitle = '<code>%s</code>' % esc(rid)
    if not r["creative"]:
        subtitle += " · " + link(R + "research/tree.html#node-%s" % rid, "показать на дереве")
    body = [hero("research", rid, name, subtitle, badges)]
    desc = STR_RU.get("RESEARCH_%s_DESC" % rid.upper(), "")
    if desc:
        body.append(para(esc(desc), "lead"))
    info = [("Стоимость", chips(cost_chips(r["costs"])))]
    pre_all = all_prereqs(rid)
    if pre_all and not r["creative"]:
        total = {}
        for x in pre_all + [rid]:
            for t, n in RESEARCH[x]["costs"]:
                total[t] = total.get(t, 0) + n
        order = [t for t in ITEM_IDS if t in total] + sorted(t for t in total if t not in ITEM)
        info.append(("С предшественниками", chips(cost_chips([(t, total[t]) for t in order]))
                     + ' <span class="muted">— %d %s до него</span>' % (
                         len(pre_all), plural(len(pre_all), "исследование", "исследования", "исследований"))))
    info.append(("Нужно до", chips([chip("research", p) for p in r["pre"]], "ничего — доступно сразу")))
    info.append(("Открывается после", chips([chip("research", d) for d in DEPENDENTS.get(rid, [])], "ничего")))
    body.append(facts(info))

    items, plain, auto, effects = research_opens(rid)
    parts = []
    if items:
        parts.append(chips(items))
    if effects:
        parts.append("<ul>%s</ul>" % "".join("<li>%s</li>" % esc(e) for e in effects))
    if plain:
        parts.append(sub("Рецепты", recipes_list(plain)))
    if auto:
        parts.append(sub("Автосборка", para("Рецепты сборки для %d %s в сборщике — по той же стоимости, что и "
                                            "ручной крафт." % (len(auto), plural(len(auto), "постройки", "построек",
                                                                                 "построек")))
                         + many_chips([chip(*RECIPE[x]["outs"][0][:2]) for x in auto if RECIPE[x]["outs"]], 0)))
    if r["creative"] and not parts:
        parts.append(para("Ничего не открывает: бесконечно принимает наборы, чтобы мерить скорость науки.", "muted"))
    body.append(section("Что открывает", "\n".join(parts) or para("—", "muted")))
    page("research/%s.html" % rid, name, "research", crumbs_for("research"), "\n".join(body), "research")
    search_add(name, R + "research/%s.html" % rid, "Исследование", "%s %s" % (rid, en_name("RESEARCH_" + rid.upper())))


def research_index():
    rows = []
    for rid in RESEARCH_IDS:
        r = RESEARCH[rid]
        items, plain, auto, effects = research_opens(rid)
        opens = "".join(items)
        if auto:
            opens += '<span class="muted">автосборка %d %s</span> ' % (len(auto), plural(len(auto), "постройки",
                                                                                         "построек", "построек"))
        if effects:
            opens += '<span class="small">%s</span>' % esc("; ".join(effects))
        name_cell = chip("research", rid) + (" " + badge("творческий", "red") if r["creative"] else "")
        rows.append([name_cell, chips(cost_chips(r["costs"])), chips([chip("research", p) for p in r["pre"]]),
                     opens or "—"])
    body = ["<h1>Исследования</h1>",
            para("Исследования общие для всего забега: база и все планеты. Наборы сдаются руками или через научный "
                 "цех. Граф зависимостей — на странице %s. Ветки и правила — %s." % (
                     link(SECTION_URL["tree"], "Дерево исследований"), link("#rules", "ниже")))]
    body.append(section("Все исследования (%d)" % len(RESEARCH_IDS),
                        table(["Исследование", "Стоимость", "Нужно до", "Открывает"], rows, "stack"), "all"))
    body.append(section("Ветки и правила", "\n".join(content_table(b) for b in content_blocks("research")), "rules"))
    page("research/index.html", "Исследования", "research", [], "\n".join(body), "section")
    search_add("Исследования", R + "research/index.html", "Раздел", "research")


def research_tree():
    """SVG-граф: столбцы по глубине (длине цепочки требований), внутри столбца — по среднему
    положению предшественников, чтобы цепочки шли ровными рядами."""
    ids = [r for r in RESEARCH_IDS if not RESEARCH[r]["creative"]]
    idset = set(ids)
    depth = {}

    def get_depth(r, trail=()):
        if r in depth:
            return depth[r]
        if r in trail:
            sys.exit("цикл в требованиях исследований: %s" % " → ".join(trail + (r,)))
        pre = [p for p in RESEARCH[r]["pre"] if p in idset]
        depth[r] = 1 + max(get_depth(p, trail + (r,)) for p in pre) if pre else 0
        return depth[r]

    for r in ids:
        get_depth(r)
    cols = {}
    for r in ids:
        cols.setdefault(depth[r], []).append(r)
    slot = {}
    for d in sorted(cols):
        col = cols[d]
        if d == 0:
            col.sort(key=lambda r: (RESEARCH[r]["order"], r))
            want = {r: i for i, r in enumerate(col)}
        else:
            want = {}
            for r in col:
                ps = [slot[p] for p in RESEARCH[r]["pre"] if p in slot]
                want[r] = sum(ps) / len(ps) if ps else 0
            col.sort(key=lambda r: (want[r], RESEARCH[r]["order"], r))
        last = -1
        for r in col:
            last = max(int(math.floor(want[r] + 0.5)), last + 1)
            slot[r] = last
    NODE_W, NODE_H, GAP_X, GAP_Y, PAD = 188, 46, 54, 10, 12
    width = PAD * 2 + (max(cols) + 1) * NODE_W + max(cols) * GAP_X if cols else 100
    height = PAD * 2 + (max(slot.values()) + 1) * (NODE_H + GAP_Y) - GAP_Y if slot else 100

    def pos(r):
        return PAD + depth[r] * (NODE_W + GAP_X), PAD + slot[r] * (NODE_H + GAP_Y)

    edges, nodes = [], []
    for r in ids:
        x2, y2 = pos(r)
        for p in RESEARCH[r]["pre"]:
            if p not in idset:
                continue
            x1, y1 = pos(p)
            x1 += NODE_W
            y1 += NODE_H / 2
            yy = y2 + NODE_H / 2
            mx = (x1 + x2) / 2 if depth[r] - depth[p] == 1 else x2 - GAP_X / 2
            edges.append('<path class="edge" data-a="%s" data-b="%s" d="M%g %gC%g %g %g %g %g %g"/>' % (
                p, r, x1, y1, mx, y1, mx, yy, x2, yy))
    for r in ids:
        x, y = pos(r)
        lines = wrap(research_name(r), 25)
        text = "".join('<text x="%g" y="%g">%s</text>' % (x + 10, y + (18 if len(lines) > 1 else 27) + i * 15, esc(t))
                       for i, t in enumerate(lines[:2]))
        dots = "".join('<circle cx="%g" cy="%g" r="4" fill="#%s"/>' % (x + NODE_W - 10 - j * 11, y + 9,
                                                                       ITEM[t]["color"] if t in ITEM else "928374")
                       for j, (t, _) in enumerate(reversed(RESEARCH[r]["costs"])))
        amount = '<text class="amt" x="%g" y="%g">%s</text>' % (x + NODE_W - 8, y + NODE_H - 8,
                                                             esc(" + ".join(fmt(n) for _, n in RESEARCH[r]["costs"])))
        nodes.append('<a href="%sresearch/%s.html"><g class="tn" id="node-%s" data-id="%s">'
                     '<rect x="%g" y="%g" width="%d" height="%d" rx="6"/>%s%s%s<title>%s</title></g></a>' % (
                         R, r, r, r, x, y, NODE_W, NODE_H, text, dots, amount, esc(research_name(r))))
    svg = ('<svg class="tree" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="Дерево исследований">'
           '\n<g class="edges">\n%s\n</g>\n<g class="nodes">\n%s\n</g>\n</svg>' % (
               width, height, width, height, "\n".join(edges), "\n".join(nodes)))
    kits = []
    for t in ITEM_IDS:
        if any(t == c for r in ids for c, _ in RESEARCH[r]["costs"]):
            kits.append('<span class="legend"><i style="background:#%s"></i>%s</span>' % (ITEM[t]["color"],
                                                                                         esc(item_name(t))))
    body = ["<h1>Дерево исследований</h1>",
            para("Столбцы — шаги от корня: исследование стоит правее всех, без которых его не начать. Клик по узлу "
                 "открывает страницу исследования, наведение подсвечивает связи. Точки справа — виды наборов, "
                 "число внизу — их количество.", "muted"),
            para("Наборы: " + " ".join(kits)),
            '<div class="treewrap">\n%s\n</div>' % svg]
    creative = [r for r in RESEARCH_IDS if RESEARCH[r]["creative"]]
    if creative:
        body.append(para("Не показаны — только для творческого режима: " + chips([chip("research", r) for r in creative])))
    page("research/tree.html", "Дерево исследований", "tree", [("Исследования", SECTION_URL["research"])],
         "\n".join(body), "section", wide=True)
    search_add("Дерево исследований", R + "research/tree.html", "Раздел", "tree граф")


def wrap(text, width):
    """Перенос по словам для подписей в SVG."""
    lines, cur = [], ""
    for word in text.split():
        if cur and len(cur) + 1 + len(word) > width:
            lines.append(cur)
            cur = word
        else:
            cur = (cur + " " + word).strip()
    if cur:
        lines.append(cur)
    if len(lines) > 2:
        lines = [lines[0], " ".join(lines[1:])]
        if len(lines[1]) > width:
            lines[1] = lines[1][:width - 1] + "…"
    return lines


# ---------------------------------------------------------------- жидкости

def fluid_page(fid):
    name = fluid_name(fid)
    body = [hero("fluid", fid, name, '<code>%s</code> · жидкость' % esc(fid)),
            para("Жидкости живут в трубах и портах построек: в инвентарь и на ленты не попадают. В одной сети труб — "
                 "одна жидкость.", "lead")]
    get, listed = [], set()
    for oid in ORE_OF_TARGET.get(("fluid", fid), []):
        listed.update(ore_extractors(oid))
        get.append(facts([("Месторождение", chip("ore", oid)),
                          ("Добывают", chips([chip("building", b) for b in ore_extractors(oid)], "никто"))]))
    producers = [b for b, role in FLUID_BUILDINGS.get(fid, []) if role == "out" and b not in listed]
    if producers:
        get.append(sub("Постройки", chips([chip("building", b) for b in producers])))
    made = PRODUCED_BY.get(("fluid", fid), [])
    if made:
        get.append(sub("Рецепты", recipes_list(made)))
    body.append(section("Где получить", "\n".join(get) or para("Пока нигде.", "muted")))
    use = []
    consumers = [b for b, role in FLUID_BUILDINGS.get(fid, []) if role == "in"]
    if consumers:
        use.append(sub("Постройки", chips([chip("building", b) for b in consumers])))
    need = CONSUMED_BY.get(("fluid", fid), [])
    if need:
        use.append(sub("Рецепты", recipes_list(need)))
    body.append(section("Где нужна", "\n".join(use) or para("Пока нигде.", "muted")))
    page("fluids/%s.html" % fid, name, "world", crumbs_for("world"), "\n".join(body), "fluid")
    search_add(name, R + "fluids/%s.html" % fid, "Жидкость", "%s %s" % (fid, en_name(FLUID[fid]["key"])))


# ---------------------------------------------------------------- мир

def planet_ore_chances(p):
    ids = p.get("ore_ids") or []
    chances = p.get("ore_chances") or []
    return [(o, chances[i] if i < len(chances) else 1.0) for i, o in enumerate(ids)]


def world_page():
    body = ["<h1>Месторождения и планеты</h1>",
            para("База телепортируется между планетами разных типов. На каждой — свой набор руд, их богатство и "
                 "угроза. На стартовой планете есть все руды её типа, дальше каждая руда выпадает со своим шансом.")]
    total_weight = sum(float(p.get("weight", 0)) for p in PLANETS) or 1.0
    rows = []
    for oid in ORE_IDS:
        o = ORE[oid]
        target = chip("item" if o["kind"] == "item" else "fluid", o["target"])
        who = []
        if drone_can_mine(oid):
            who.append('<span class="chip hand"><span>дрон</span></span>')
        who += [chip("building", b) for b in ore_extractors(oid)]
        where = ["%s %s" % (esc(planet_name(p["id"])), pct(c)) for p in PLANETS for o2, c in planet_ore_chances(p)
                 if o2 == oid]
        rows.append(['<span id="ore-%s">%s</span>' % (oid, chip("ore", oid)), target, "%d" % o["hardness"],
                     chips(who, "никто"), ", ".join(where) or '<span class="muted">нигде</span>'])
        search_add(ore_name(oid), R + "world/index.html#ore-%s" % oid, "Месторождение",
                   "%s %s" % (oid, en_name("ORE_" + oid.upper())))
    body.append(section("Месторождения", table(["Месторождение", "Даёт", "Твёрдость", "Кто добывает",
                                                "Шанс на планете"], rows, "stack"), "ores"))
    # Подразделы CONTENT.md (например, «Богатство клеток руды») — отдельными разделами.
    subs = []
    for b in content_blocks("world"):
        if b["sub"] and b["sub"] not in subs:
            subs.append(b["sub"])
    for i, title in enumerate(subs, 1):
        body.append(section(title, "\n".join(content_table(b) for b in content_blocks("world", subsection=title)),
                            "world-%d" % i))

    cards = []
    for p in PLANETS:
        pid = p["id"]
        info = [("Опасность", "враг не нападает" if p.get("safe") else link(R + "enemies/index.html#threat-%s" % pid,
                                                                             "волны врагов"))]
        info.append(("Как часто выпадает", pct(float(p.get("weight", 0)) / total_weight)))
        if p.get("min_size") and p.get("max_size"):
            info.append(("Размер карты", "от %d×%d до %d×%d тайлов" % tuple(int(x) for x in p["min_size"][:2]
                                                                          + p["max_size"][:2])))
        ores = planet_ore_chances(p)
        info.append(("Руды", chips([chip("ore", o, note=pct(c)) for o, c in ores if o in ORE], "нет")))
        if p.get("deposits_per_10k") is not None:
            info.append(("Залежей на 10 000 тайлов", fmt(p["deposits_per_10k"])))
        if p.get("ore_richness"):
            info.append(("Бонус богатства руды", "+%s" % fmt(p["ore_richness"])))
        if p.get("lakes_per_10k"):
            info.append(("Озёр на 10 000 тайлов", fmt(p["lakes_per_10k"])))
        if p.get("rock_density") is not None:
            info.append(("Плотность скал", pct(p["rock_density"])))
        desc = STR_RU.get(p.get("description_key", ""), "")
        cards.append('<div class="planet" id="planet-%s"><h3>%s %s</h3>%s%s</div>' % (
            esc(pid), icon("planet", pid, "mid"), esc(planet_name(pid)), para(esc(desc)) if desc else "", facts(info)))
        search_add(planet_name(pid), R + "world/index.html#planet-%s" % pid, "Планета",
                   "%s %s" % (pid, en_name(p.get("name_key", ""))))
    body.append(section("Типы планет", "\n".join(cards), "planets"))

    fl = "".join('<a class="card" href="%s">%s<span>%s</span></a>' % (entity("fluid", f)[1], icon("fluid", f, "mid"),
                                                                     esc(fluid_name(f))) for f in FLUID_IDS)
    blocks = [b for b in content_blocks("world") if not b["sub"]]
    fluid_rules = [b for b in blocks if b["header"][0].startswith("Жидкост")]
    body.append(section("Жидкости", '<div class="grid">%s</div>' % fl + "\n".join(content_table(b) for b in fluid_rules),
                        "fluids"))
    rules = [b for b in blocks if b not in fluid_rules]
    if rules:
        body.append(section("Правила добычи и карты", "\n".join(content_table(b) for b in rules), "rules"))
    page("world/index.html", "Месторождения и планеты", "world", [], "\n".join(body), "section")
    search_add("Месторождения и планеты", R + "world/index.html", "Раздел", "world мир руды планеты")


# ---------------------------------------------------------------- враги

def enemies_page():
    body = ["<h1>Враги и волны</h1>",
            para("Враги идут к центральному шлюзу по полю потоков, по дороге бьют постройки и дрона в радиусе атаки "
                 "и ломают постройки, перегородившие путь. Атака мгновенная, без снарядов. Из бюджета волны "
                 "набираются враги по их стоимости угрозы.")]
    rows = []
    for eid in ENEMY_IDS:
        e = ENEMY[eid]
        rows.append(['<span id="enemy-%s">%s</span>' % (eid, chip("enemy", eid)), fmt(e["hp"]), "%s/с" % tiles(e["speed"]),
                     fmt(e["damage"]), "%s с" % fmt(e["interval"]),
                     fmt(round(e["damage"] / e["interval"], 1)) if e["interval"] else "—", tiles(e["range"]),
                     fmt(e["cost"])])
        search_add(enemy_name(eid), R + "enemies/index.html#enemy-%s" % eid, "Враг",
                   "%s %s" % (eid, en_name("ENEMY_" + eid.upper())))
    body.append(section("Враги", table(["Враг", "Прочность", "Скорость", "Урон", "Пауза", "Урон в секунду",
                                        "Дальность атаки", "Стоимость угрозы"], rows, "stack"), "list"))
    danger = [p for p in PLANETS if not p.get("safe") and p.get("threat_values")]
    if danger:
        head = ["Что"] + [planet_name(p["id"]) for p in danger]

        def row(title, fn):
            return [esc(title)] + [fn(p["threat_values"]) for p in danger]

        def enemies_of(t):
            out = []
            for i, eid in enumerate(t.get("enemy_ids", [])):
                wave = t.get("enemy_from_wave", [])
                weight = t.get("enemy_weights", [])
                note = "с %d-й волны" % int(wave[i]) if i < len(wave) else ""
                if i < len(weight):
                    note += ", вес %s" % fmt(float(weight[i]))
                out.append(chip("enemy", eid, note=note))
            return chips(out)

        rows = [row("Первая волна", lambda t: "через %s мин" % fmt(t.get("first_wave_seconds", 0) / 60.0)),
                row("Затишье между волнами", lambda t: "%s с, дальше каждое × %s" % (
                    fmt(t.get("first_gap_seconds", 0)), fmt(t.get("gap_multiplier", 1)))),
                row("Волны встык", lambda t: "когда затишье короче %s с" % fmt(t.get("continuous_below_seconds", 0))),
                row("Предупреждение", lambda t: "за %s с" % fmt(t.get("warning_seconds", 0))),
                row("Появление волны", lambda t: "%s с + %s с за волну, не дольше %s с" % (
                    fmt(t.get("spawn_seconds", 0)), fmt(t.get("spawn_seconds_per_wave", 0)),
                    fmt(t.get("max_spawn_seconds", 0)))),
                row("Бюджет волны", lambda t: "%s + %s за волну + %s за минуту на планете" % (
                    fmt(t.get("budget_base", 0)), fmt(t.get("budget_per_wave", 0)), fmt(t.get("budget_per_minute", 0)))),
                row("Прочность врагов", lambda t: "+%s за волну, +%s за шаг звёздной карты, не больше ×%s" % (
                    pct(t.get("health_per_wave", 0)), pct(t.get("health_per_depth", 0)),
                    fmt(t.get("max_health_scale", 0)))),
                row("Урон врагов", lambda t: "+%s за волну, +%s за шаг карты, не больше ×%s" % (
                    pct(t.get("damage_per_wave", 0)), pct(t.get("damage_per_depth", 0)),
                    fmt(t.get("max_damage_scale", 0)))),
                row("Точек появления", lambda t: fmt(t.get("spawn_point_count", 0))),
                row("Врагов на карте", lambda t: "до %s" % fmt(t.get("max_alive", 0))),
                row("Кто приходит", enemies_of)]
        anchors = "".join('<span id="threat-%s"></span>' % p["id"] for p in danger)
        safe = [p for p in PLANETS if p.get("safe") or not p.get("threat_values")]
        note = para("Без врагов: " + chips([chip("planet", p["id"]) for p in safe])) if safe else ""
        for p in safe:
            anchors += '<span id="threat-%s"></span>' % p["id"]
        body.append(section("Волны по типам планет", anchors + table(head, rows, "stack") + note, "threats"))
    defense = [b for b in BUILDING_IDS if BUILDING[b]["cat"] == 3 and BUILDING[b]["buildable"]
               and not BUILDING[b]["creative"]]
    if defense:
        body.append(section("Чем обороняться", '<div class="grid">%s</div>' % "".join(building_card(b) for b in defense),
                            "defense"))
    page("enemies/index.html", "Враги и волны", "enemies", [], "\n".join(body), "section")
    search_add("Враги и волны", R + "enemies/index.html", "Раздел", "enemies угроза волны")


# ---------------------------------------------------------------- механики

def drone_section():
    d = DRONE
    if not d:
        return ""
    rows = [("Скорость", "%s/с" % tiles(d.get("speed", 0))), ("Дальность действия", tiles(d.get("reach", 0))),
            ("Инвентарь", "%d ячеек" % int(d.get("inventory_slots", 0))),
            ("Добыча", "руда твёрдостью до %d, (%s + %s × твёрдость) с на предмет" % (
                int(d.get("mine_tier", 1)), fmt(d.get("mine_base_seconds", 0)), fmt(d.get("mine_hardness_seconds", 0)))),
            ("Прочность", fmt(d.get("health", 0))),
            ("Возрождение", "через %s с, потом %s с неуязвимости" % (fmt(d.get("respawn_seconds", 0)),
                                                                   fmt(d.get("invulnerable_seconds", 0)))),
            ("Автопушка", "урон %s, пауза %s с, дальность %s" % (fmt(d.get("gun_damage", 0)),
                                                                 fmt(d.get("gun_reload_seconds", 0)),
                                                                 tiles(d.get("gun_range", 0)))),
            ("Ремонт построек", "%s прочности/с" % fmt(d.get("repair_per_second", 0)))]
    ups = []
    for effect in DRONE_STEPS:
        steps = [r for r in RESEARCH_IDS if effect in RESEARCH[r]["effects"]]
        if steps:
            ups.append([esc(effect_text(effect)), chips([chip("research", r) for r in steps])])
    out = facts(rows)
    if ups:
        out += sub("Улучшения", table(["Ступень даёт", "Исследования"], ups, "stack"))
    return out


def mechanics_page():
    body = ["<h1>Механики</h1>", para("Краткие правила: добыча, производство, энергия и жидкости, мобильная база и "
                                      "этажи, телепорт и угроза. Таблицы переносятся из <code>docs/CONTENT.md</code>, "
                                      "числа в них — из данных игры. Добыча и устройство карты — в разделе %s, "
                                      "волны — в разделе %s." % (link(R + "world/index.html#rules", "Месторождения и планеты"),
                                                                link(SECTION_URL["enemies"], "Враги и волны")))]
    groups, order = {}, []
    for b in content_blocks("mechanics"):
        if b["section"] not in groups:
            groups[b["section"]] = []
            order.append(b["section"])
        groups[b["section"]].append(b)
    toc, parts = [], []
    for i, title in enumerate(order, 1):
        sid = "rules-%d" % i
        toc.append(link("#" + sid, clean_title(title)))
        parts.append(section(clean_title(title), "\n".join(content_table(b) for b in groups[title]), sid))
        search_add(clean_title(title), R + "mechanics/index.html#" + sid, "Механика", "")
    drone = drone_section()
    if drone:
        toc.append(link("#drone", "Дрон"))
        parts.append(section("Дрон", drone, "drone"))
        search_add("Дрон", R + "mechanics/index.html#drone", "Механика", "drone")
    body.append('<nav class="toc">%s</nav>' % " · ".join(toc))
    body += parts
    page("mechanics/index.html", "Механики", "mechanics", [], "\n".join(body), "section")
    search_add("Механики", R + "mechanics/index.html", "Раздел", "mechanics правила")


# ---------------------------------------------------------------- главная

def home_page():
    counts = {"items": len(ITEM_IDS), "buildings": len(BUILDING_IDS), "research": len(RESEARCH_IDS)}
    cards = [("items", "Сырьё, материалы, компоненты, наборы и патроны: где добыть и куда потратить.", counts["items"]),
             ("buildings", "Транспорт, производство, энергия и оборона: размеры, стоимость, параметры.",
              counts["buildings"]),
             ("research", "Что стоит, что нужно до него и что открывает.", counts["research"]),
             ("tree", "Граф зависимостей исследований.", None),
             ("world", "Руды и их шансы, богатство клеток, типы планет, жидкости.", len(ORE_IDS) + len(PLANETS)),
             ("enemies", "Характеристики врагов и волны по типам планет.", len(ENEMY_IDS)),
             ("mechanics", "Добыча, энергия, жидкости, шлюз и этажи, телепорт, дрон.", None)]
    grid = "".join('<a class="card sec" href="%s"><span><b>%s</b>%s<small>%s</small></span></a>' % (
        SECTION_URL[k], esc(SECTION_TITLE[k]), (' <span class="count">%d</span>' % n) if n else "", esc(desc))
        for k, desc, n in cards)
    free = [b for b in BUILDING_IDS if BUILDING[b]["buildable"] and not BUILDING[b]["creative"]
            and b not in RESEARCH_OF_BUILDING]
    roots = [r for r in RESEARCH_IDS if not RESEARCH[r]["pre"] and not RESEARCH[r]["creative"]]
    start = facts([("Стартовый набор", chips(stack_chips(START_ITEMS)) if START_ITEMS else "—"),
                   ("Доступно сразу", chips([chip("building", b) for b in free])),
                   ("Первые исследования", chips([chip("research", r) for r in roots]))])
    body = ['<div class="intro"><h1>WarpFactor — вики</h1>',
            para("WarpFactor — 2D-игра про фабрику, выживание и оборону мобильной базы. Вы — ИИ, который добывает "
                 "руду, строит конвейеры, печи и сборщики, налаживает энергию и исследования. База путешествует между "
                 "одноразовыми планетами: рано или поздно враг находит фабрику, и нужно успеть собрать ресурсы и "
                 "телепортироваться дальше. Всё, что стоит на площадке шлюза и подземных этажах, переезжает вместе "
                 "с базой.", "lead"),
            '<div class="search big"><input type="search" placeholder="Что ищем? Например, «шестерня» или «бур»" '
            'aria-label="Поиск по вики" autocomplete="off" data-search><ul class="results" hidden></ul></div></div>',
            section("Разделы", '<div class="grid wide">%s</div>' % grid, "sections"),
            section("С чего начать", start, "start")]
    page("index.html", "Главная", "", None, "\n".join(body), "section")


# =====================================================================================
# Оформление и скрипты
# =====================================================================================

CSS = """/* WarpFactor вики: тёмная тема в духе интерфейса игры (Gruvbox). Файл генерируется make_wiki.py. */
:root{--bg:#1d2021;--bg1:#282828;--bg2:#32302f;--bg3:#3c3836;--line:#504945;--fg:#ebdbb2;--fg2:#d5c4a1;
--muted:#a89984;--yellow:#fabd2f;--orange:#fe8019;--blue:#83a598;--aqua:#8ec07c;--red:#fb4934;color-scheme:dark}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans",sans-serif;overflow-wrap:break-word}
a{color:var(--blue);text-decoration:none}
a:hover{color:var(--yellow);text-decoration:underline}
code{font:13px/1.3 ui-monospace,Consolas,"Cascadia Mono",monospace;background:var(--bg2);border:1px solid var(--bg3);border-radius:4px;padding:0 4px;color:var(--aqua)}
svg.defs{position:absolute;width:0;height:0;overflow:hidden}
header.top{background:var(--bg1);border-bottom:2px solid var(--bg3);position:sticky;top:0;z-index:10}
.bar{max-width:1100px;margin:0 auto;padding:8px 16px;display:flex;gap:8px 16px;align-items:center;flex-wrap:wrap}
.logo{font-weight:700;color:var(--yellow);font-size:18px;white-space:nowrap}
.logo span{color:var(--muted);font-weight:400}
.logo:hover{text-decoration:none;color:var(--orange)}
.search{position:relative;flex:1 1 220px;min-width:0}
.search input{width:100%;background:var(--bg);color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:6px 10px;font:inherit}
.search input:focus{outline:none;border-color:var(--yellow)}
.search.big{margin:14px 0 4px;max-width:640px}
.search.big input{font-size:17px;padding:10px 14px}
.results{position:absolute;left:0;right:0;top:100%;margin:4px 0 0;padding:4px;list-style:none;background:var(--bg1);border:1px solid var(--line);border-radius:6px;max-height:60vh;overflow:auto;z-index:20;box-shadow:0 6px 18px rgba(0,0,0,.5)}
.results li a{display:flex;gap:8px;align-items:baseline;padding:6px 8px;border-radius:4px;color:var(--fg)}
.results li a.on,.results li a:hover{background:var(--bg3);text-decoration:none;color:var(--yellow)}
.results .k{color:var(--muted);font-size:12px;margin-left:auto;white-space:nowrap}
.results .none{padding:6px 8px;color:var(--muted)}
nav.sections{max-width:1100px;margin:0 auto;padding:0 16px 8px;display:flex;flex-wrap:wrap;gap:2px 16px;font-size:14px}
nav.sections a{color:var(--fg2)}
nav.sections a.on{color:var(--yellow);font-weight:600}
main{max-width:1100px;margin:0 auto;padding:10px 16px 40px}
main.wide{max-width:none}
.crumbs{font-size:13px;color:var(--muted);margin:2px 0 10px}
.crumbs a{color:var(--muted)}
.crumbs .sep{margin:0 2px;color:var(--line)}
h1{color:var(--yellow);font-size:26px;line-height:1.2;margin:4px 0 12px}
h2{color:var(--orange);font-size:19px;line-height:1.3;margin:28px 0 10px;border-bottom:1px solid var(--bg3);padding-bottom:4px}
h3{color:var(--aqua);font-size:16px;margin:18px 0 8px;display:flex;align-items:center;gap:8px}
p{margin:8px 0}
.lead{font-size:16px;color:var(--fg2);max-width:780px}
.muted{color:var(--muted)}
.small{font-size:13px}
ul{margin:6px 0;padding-left:22px}
details{margin:6px 0}
summary{cursor:pointer;color:var(--blue)}
summary:hover{color:var(--yellow)}
.toc{font-size:14px;margin:8px 0 4px;color:var(--muted)}
.hero{display:flex;gap:14px;align-items:center;margin:4px 0 14px}
.hero h1{margin:0 0 2px}
.hero .sub{color:var(--muted);font-size:14px}
.badges{margin-top:6px}
.badge{display:inline-block;font-size:12px;padding:1px 8px;border-radius:10px;border:1px solid var(--line);color:var(--fg2);margin:2px 6px 2px 0}
.badge.red{color:var(--red);border-color:var(--red)}
.badge.blue{color:var(--blue);border-color:var(--blue)}
.ic{width:20px;height:20px;flex:none;display:inline-block;vertical-align:middle}
.ic.mid{width:32px;height:32px}
.ic.big{width:64px;height:64px}
svg.ic.big{background:var(--bg1);border:1px solid var(--bg3);border-radius:10px;padding:6px}
.spr{background-repeat:no-repeat;background-position:0 0;image-rendering:pixelated;border-radius:3px}
.chips{display:inline}
.chip{display:inline-flex;align-items:center;gap:5px;padding:2px 9px 2px 4px;margin:2px 4px 2px 0;background:var(--bg2);border:1px solid var(--bg3);border-radius:14px;color:var(--fg);font-size:14px;line-height:1.35;max-width:100%;vertical-align:middle}
.chip>span{min-width:0}
a.chip:hover{border-color:var(--yellow);text-decoration:none;color:var(--fg)}
.chip .n{color:var(--yellow);font-weight:600;white-space:nowrap}
.chip .tag{font-style:normal;color:var(--muted);font-size:12px;white-space:nowrap}
.chip.any{border-style:dashed;border-color:var(--aqua)}
.chip.hand{padding-left:9px;color:var(--fg2)}
.recipe{background:var(--bg1);border:1px solid var(--bg3);border-radius:8px;padding:6px 10px;margin:8px 0}
.recipe .flow{display:flex;flex-wrap:wrap;align-items:center}
.recipe .arrow{color:var(--orange);font-weight:700;margin:0 8px 0 4px}
.recipe .meta{font-size:13px;color:var(--muted);margin-top:2px}
.recipe .meta .chip{font-size:13px}
.tw{overflow-x:auto;margin:8px 0 14px}
table{border-collapse:collapse;width:100%;font-size:14px}
th,td{border-bottom:1px solid var(--bg3);padding:6px 8px;text-align:left;vertical-align:top}
thead th{color:var(--fg2);background:var(--bg1);font-weight:600}
table.facts{width:auto;min-width:min(100%,520px)}
table.facts th{color:var(--muted);font-weight:400;width:13em;min-width:9em}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(172px,1fr));gap:8px;margin:8px 0}
.grid.wide{grid-template-columns:repeat(auto-fill,minmax(250px,1fr))}
.card{display:flex;gap:10px;align-items:center;padding:8px 10px;background:var(--bg1);border:1px solid var(--bg3);border-radius:8px;color:var(--fg);min-width:0}
a.card:hover{border-color:var(--yellow);text-decoration:none;color:var(--fg)}
.card>span{min-width:0;overflow-wrap:normal;-webkit-hyphens:auto;hyphens:auto}
.card small{display:block;color:var(--muted);font-size:12px}
.card.sec b{color:var(--yellow)}
.card .count{color:var(--muted);font-size:13px}
.planet,.group{background:var(--bg1);border:1px solid var(--bg3);border-radius:8px;padding:4px 12px;margin:10px 0}
.planet h3,.group h3{margin:10px 0 4px}
.legend{display:inline-flex;align-items:center;gap:5px;margin-right:12px}
.legend i{width:10px;height:10px;border-radius:50%;display:inline-block}
.treewrap{overflow:auto;border:1px solid var(--bg3);border-radius:8px;background:var(--bg1);max-height:80vh;margin:10px 0}
svg.tree{display:block}
.tree .edge{fill:none;stroke:#665c54;stroke-width:1.4}
.tree .edge.hl{stroke:var(--yellow);stroke-width:2.4}
.tree .tn rect{fill:var(--bg2);stroke:var(--line);stroke-width:1.2}
.tree a:hover rect,.tree .tn.hl rect{stroke:var(--yellow);stroke-width:2}
.tree .tn:target rect,.tree .tn.focus rect{stroke:var(--orange);stroke-width:3}
.tree text{fill:var(--fg);font-size:12px}
.tree text.amt{fill:var(--muted);font-size:10px;text-anchor:end}
.tree a:hover text{fill:var(--yellow)}
.tree a:hover text.amt{fill:var(--muted)}
footer{max-width:1100px;margin:0 auto;padding:16px;color:var(--muted);font-size:13px;border-top:1px solid var(--bg3)}
@media (max-width:640px){
body{font-size:14px}
header.top{position:static}
td,th{overflow-wrap:anywhere}
h1{font-size:22px}
.hero .ic.big{width:48px;height:48px}
.grid{grid-template-columns:repeat(auto-fill,minmax(140px,1fr))}
.grid.wide{grid-template-columns:1fr}
.card{gap:8px;padding:8px}
.card .ic.mid{width:24px;height:24px}
table.stack thead{display:none}
table.stack,table.stack tbody,table.stack tr,table.stack td{display:block;width:100%}
table.stack tr{border:1px solid var(--bg3);border-radius:8px;margin:8px 0;background:var(--bg1);padding:4px 0}
table.stack td{border:0;padding:3px 10px}
table.stack td[data-label]{display:flex;gap:10px;align-items:baseline}
table.stack td[data-label]::before{content:attr(data-label);flex:0 0 36%;font-size:12px;color:var(--muted);overflow-wrap:normal}
table.stack td[data-label]>div{flex:1 1 auto;min-width:0}
table.facts th{width:36%;min-width:0;overflow-wrap:normal;padding-right:4px}
.tw{overflow-x:visible}
table.facts{min-width:0;width:100%}
}
"""

JS = r"""// WarpFactor вики: поиск по заранее собранному индексу и подсветка связей в дереве.
// Файл генерируется make_wiki.py. Индекс — window.WIKI_INDEX из search-index.js (fetch на file:// не работает).
(function () {
  "use strict";
  var root = document.body.getAttribute("data-root") || "";
  var index = (window.WIKI_INDEX || []).map(function (e) {
    return {t: e[0], u: e[1], k: e[2], n: norm(e[0]), x: norm(e[0] + " " + (e[3] || ""))};
  });

  function norm(s) { return String(s).toLowerCase().replace(/ё/g, "е"); }

  function find(q) {
    q = norm(q).trim();
    if (!q) return [];
    var words = q.split(/\s+/), out = [];
    index.forEach(function (e, i) {
      for (var w = 0; w < words.length; w++) if (e.x.indexOf(words[w]) < 0) return;
      var score = e.n === q ? 0 : e.n.indexOf(q) === 0 ? 1 : e.n.indexOf(q) >= 0 ? 2 : 3;
      if (e.k === "Раздел") score -= 0.5;
      out.push([score, i, e]);
    });
    out.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
    return out.slice(0, 40).map(function (x) { return x[2]; });
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]; });
  }

  Array.prototype.forEach.call(document.querySelectorAll("[data-search]"), function (input) {
    var list = input.parentNode.querySelector(".results"), active = -1, found = [];
    function render() {
      found = find(input.value);
      active = found.length ? 0 : -1;
      if (!input.value.trim()) { list.hidden = true; return; }
      list.innerHTML = found.length ? found.map(function (e, i) {
        return '<li><a href="' + esc(root + e.u) + '"' + (i === active ? ' class="on"' : "") + ">" + esc(e.t) +
          '<span class="k">' + esc(e.k) + "</span></a></li>";
      }).join("") : '<li class="none">Ничего не нашлось</li>';
      list.hidden = false;
    }
    function mark() {
      Array.prototype.forEach.call(list.querySelectorAll("a"), function (a, i) {
        a.className = i === active ? "on" : "";
        if (i === active) a.scrollIntoView({block: "nearest"});
      });
    }
    input.addEventListener("input", render);
    input.addEventListener("focus", function () { if (input.value.trim()) render(); });
    input.addEventListener("keydown", function (ev) {
      if (ev.key === "ArrowDown" && found.length) { active = (active + 1) % found.length; mark(); ev.preventDefault(); }
      else if (ev.key === "ArrowUp" && found.length) { active = (active - 1 + found.length) % found.length; mark(); ev.preventDefault(); }
      else if (ev.key === "Enter" && active >= 0) { location.href = root + found[active].u; ev.preventDefault(); }
      else if (ev.key === "Escape") { list.hidden = true; input.blur(); }
    });
    document.addEventListener("click", function (ev) { if (!input.parentNode.contains(ev.target)) list.hidden = true; });
  });

  // Горячая клавиша: «/» — в поиск.
  document.addEventListener("keydown", function (ev) {
    var t = ev.target.tagName;
    if (ev.key === "/" && t !== "INPUT" && t !== "TEXTAREA") {
      var input = document.querySelector("[data-search]");
      if (input) { input.focus(); ev.preventDefault(); }
    }
  });

  // Дерево исследований: наведение на узел подсвечивает его связи и соседей.
  var tree = document.querySelector("svg.tree");
  if (tree) {
    var edges = tree.querySelectorAll(".edge");
    function light(id, on) {
      Array.prototype.forEach.call(edges, function (e) {
        var a = e.getAttribute("data-a"), b = e.getAttribute("data-b");
        if (a === id || b === id) {
          e.classList.toggle("hl", on);
          var other = tree.querySelector('[data-id="' + (a === id ? b : a) + '"]');
          if (other) other.classList.toggle("hl", on);
        }
      });
    }
    Array.prototype.forEach.call(tree.querySelectorAll(".tn"), function (n) {
      var id = n.getAttribute("data-id");
      n.addEventListener("mouseenter", function () { light(id, true); });
      n.addEventListener("mouseleave", function () { light(id, false); });
    });
    var focus = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (focus && tree.contains(focus)) {
      focus.classList.add("focus");
      light(focus.getAttribute("data-id"), true);
      var wrap = tree.parentNode, box = focus.getBBox();
      wrap.scrollLeft = Math.max(0, box.x - wrap.clientWidth / 2 + box.width / 2);
      wrap.scrollTop = Math.max(0, box.y - wrap.clientHeight / 2 + box.height / 2);
      wrap.scrollIntoView({block: "start"});
    }
  }
})();
"""


# =====================================================================================
# Запись, чистка устаревшего, проверка ссылок
# =====================================================================================

def build_files():
    """Все файлы сайта: путь от docs/wiki → байты."""
    home_page()
    items_index()
    for i in ITEM_IDS:
        item_page(i)
    buildings_index()
    for b in BUILDING_IDS:
        building_page(b)
    research_index()
    research_tree()
    for r in RESEARCH_IDS:
        research_page(r)
    for f in FLUID_IDS:
        fluid_page(f)
    world_page()
    enemies_page()
    mechanics_page()
    search_add("Главная", R + "index.html", "Раздел", "home главная")

    files = {path: doc.encode("utf-8") for path, doc in sorted(PAGES.items())}
    files["assets/wiki.css"] = CSS.encode("utf-8")
    files["assets/wiki.js"] = JS.encode("utf-8")
    entries = ",\n".join(json.dumps(e, ensure_ascii=False, separators=(",", ":")) for e in SEARCH)
    files["assets/search-index.js"] = ("// Индекс поиска вики: [название, адрес от корня, вид, ключевые слова].\n"
                                       "// Генерируется make_wiki.py.\nwindow.WIKI_INDEX = [\n%s\n];\n" % entries
                                       ).encode("utf-8")
    for bid, (_, data) in sorted(SPRITES.items()):
        files["assets/sprites/%s.png" % bid] = data
    return files


def write_files(files):
    """Пишет изменившиеся файлы и удаляет свои устаревшие (по прошлому .manifest)."""
    manifest_path = os.path.join(OUT, MANIFEST)
    old = []
    if os.path.exists(manifest_path):
        old = [line.strip() for line in open(manifest_path, encoding="utf-8") if line.strip()]
    written = 0
    for rel, data in files.items():
        full = os.path.join(OUT, *rel.split("/"))
        if os.path.exists(full) and open(full, "rb").read() == data:
            continue
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(data)
        written += 1
    removed = 0
    for rel in old:
        if rel in files or rel.startswith("..") or os.path.isabs(rel):
            continue
        full = os.path.join(OUT, *rel.split("/"))
        if os.path.isfile(full):
            os.remove(full)
            removed += 1
            parent = os.path.dirname(full)
            while parent != OUT and os.path.isdir(parent) and not os.listdir(parent):
                os.rmdir(parent)
                parent = os.path.dirname(parent)
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(rel + "\n" for rel in sorted(files)))
    return written, removed


class LinkCollector(HTMLParser):
    """Собирает id и ссылки страницы (href, src, url(...) в style)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.dup = set(), [], []

    def handle_starttag(self, tag, attrs):
        for k, v in attrs:
            if v is None:
                continue
            if k == "id":
                if v in self.ids:
                    self.dup.append(v)
                self.ids.add(v)
            elif k in ("href", "src"):
                self.links.append(v)
            elif k == "style":
                self.links += re.findall(r"url\(([^)]+)\)", v)

    handle_startendtag = handle_starttag


def check_links(files):
    """Все внутренние ссылки ведут на существующие файлы и якоря. Возвращает список ошибок."""
    parsed = {}
    for rel in files:
        if rel.endswith(".html"):
            c = LinkCollector()
            c.feed(open(os.path.join(OUT, *rel.split("/")), encoding="utf-8").read())
            parsed[rel] = c
    errors = []
    for rel, c in sorted(parsed.items()):
        for d in c.dup:
            errors.append("%s: повторяется id «%s»" % (rel, d))
        for href in c.links:
            href = href.strip("'\"")
            if href.startswith("data:"):
                continue
            if re.match(r"^[a-z]+:", href):
                errors.append("%s: внешняя ссылка %s (вики должна работать без сети)" % (rel, href))
                continue
            path, _, frag = href.partition("#")
            target = posixpath.normpath(posixpath.join(posixpath.dirname(rel), path)) if path else rel
            if target.startswith(".."):
                errors.append("%s: ссылка за пределы вики %s" % (rel, href))
            elif target not in files:
                errors.append("%s: нет файла %s" % (rel, href))
            elif frag and target in parsed and frag not in parsed[target].ids:
                errors.append("%s: нет якоря #%s в %s" % (rel, frag, target))
    for title, url, _, _ in SEARCH:
        path, _, frag = url.partition("#")
        if path not in files:
            errors.append("индекс поиска: нет файла %s (%s)" % (url, title))
        elif frag and frag not in parsed[path].ids:
            errors.append("индекс поиска: нет якоря %s (%s)" % (url, title))
    return errors


def main():
    files = build_files()
    written, removed = write_files(files)
    errors = check_links(files)
    kinds = {}
    for path, kind in PAGE_KIND.items():
        kinds[kind] = kinds.get(kind, 0) + 1
    total = sum(len(d) for d in files.values())
    labels = [("item", "предметы"), ("building", "постройки"), ("research", "исследования"), ("fluid", "жидкости"),
              ("section", "разделы")]
    print("wiki: " + ", ".join("%s %d" % (t, kinds.get(k, 0)) for k, t in labels)
          + "; всего страниц %d, файлов %d, %.1f КБ" % (len(PAGES), len(files), total / 1024.0))
    print("wiki: записано %d, удалено устаревших %d, записей в поиске %d" % (written, removed, len(SEARCH)))
    for w in sorted(WARNINGS):
        print("внимание: " + w)
    if errors:
        for e in errors:
            print("ОШИБКА: " + e)
        print("wiki: битых ссылок %d" % len(errors))
        sys.exit(1)
    print("wiki: ссылки в порядке")


if __name__ == "__main__":
    main()
