"""Проверка строк интерфейса: совпадает ли число подстановок в i18n/strings.csv с тем,
что подставляет код (`tr("KEY") % ...`), и не потерялся ли ключ.

Такие ошибки не ловят ни тесты, ни автопрогон: Godot печатает «String formatting error»
в консоль, а текст остаётся несобранным.

Запуск: python tools/data/check_strings.py
"""
import csv
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CODE_DIRS = ["net", "core", "ui", "buildings", "player", "world", "items", "render", "enemies", "research", "save",
             "fluids", "combat", "tools"]

rows = {}
with open(os.path.join(ROOT, "i18n", "strings.csv"), encoding="utf-8") as f:
    for row in csv.reader(f):
        if len(row) >= 3 and row[0] != "keys":
            rows[row[0]] = row[1:]


def placeholders(text):
    """Сколько значений подставляется в строку. %% — это просто знак процента, он не считается."""
    return len(re.findall(r"%[#0\- +]*[\d.*]*[a-zA-Z]", text.replace("%%", "")))


def args_count(text, start):
    """Сколько элементов в списке подстановки, который начинается со скобки [ на позиции start.
    Запятые внутри строк и вложенных скобок не считаются."""
    depth = 0
    count = 1
    in_string = False
    quote = ""
    i = start
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                in_string = False
        elif ch in "\"'":
            in_string = True
            quote = ch
        elif ch in "[({":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return count
        elif ch == "," and depth == 1:
            count += 1
        i += 1
    return count


CALL = re.compile(r'tr\(\s*"([A-Z0-9_]+)"\s*\)(\s*%\s*)?', re.S)
errors = []
seen = set()

for folder in CODE_DIRS:
    base = os.path.join(ROOT, folder)
    if not os.path.isdir(base):
        continue
    for dirpath, _dirnames, filenames in os.walk(base):
        for name in sorted(filenames):
            if not name.endswith(".gd"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            text = open(path, encoding="utf-8").read()
            for match in CALL.finditer(text):
                key, percent = match.group(1), match.group(2)
                line_no = text.count("\n", 0, match.start()) + 1
                seen.add(key)
                if key not in rows:
                    errors.append("%s:%d: нет строки %s в strings.csv" % (rel, line_no, key))
                    continue
                need = placeholders(rows[key][1])
                if percent is None:
                    if need > 0:
                        errors.append("%s:%d: %s ждёт %d подстановок, а подставляют 0" % (rel, line_no, key, need))
                    continue
                rest = text[match.end():].lstrip()
                given = args_count(text, text.index("[", match.end())) if rest.startswith("[") else 1
                if given != need:
                    errors.append("%s:%d: %s ждёт %d подстановок, а подставляют %d" % (rel, line_no, key, need, given))
                if placeholders(rows[key][0]) != need:
                    errors.append("%s: в английской строке %d подстановок, в русской %d"
                                  % (key, placeholders(rows[key][0]), need))

for line in sorted(set(errors)):
    print(line)
print("Проверено ключей в коде: %d, строк в файле: %d, ошибок: %d" % (len(seen), len(rows), len(errors)))
sys.exit(1 if errors else 0)
