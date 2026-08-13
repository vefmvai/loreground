#!/usr/bin/env python3
"""Перебор комплекта: путь пришёл из командной строки, файлов по нему не нашлось — и об этом молчат.

Зачем. Путь в команде прогона набирает человек. Ошибается он не только в имени папки:
папка бывает пустой, бывает без `.md`, бывает набита файлами, которые сам прогон
исключает (`_templates/`, `_personal/`). Во всех трёх случаях список файлов выходит
пустым — и дальше прогон идёт так, будто всё проверено. На экране «0 заметок» и следом
«ошибок нет», код выхода 0. **Артефакт непроверенной базы неотличим от артефакта
чистой.** Именно так жила опечатка в имени папки до 0.29.2: её починили по адресу
(несуществующая папка), а пустая осталась.

Правило перебора. Находка — **имя, в которое собрали файлы по пути из командной строки,
и которое нигде не проверено на пустоту с отказом**. Три условия вместе:

    files = собиратель(args.путь)   # 1. собрано собирателем, 2. путь из args
    if not files: return 2          # 3. вот этого нет — находка

*Собиратель* вычисляется по файлу, а не берётся списком имён: функция считается им,
если сама обходит диск (`os.walk`, `glob.glob`, `Path.rglob`, `os.listdir`, `os.scandir`)
или вызывает другого собирателя. Поэтому переименование `walk_md` перебор не ослепляет.

*Путь из args* — выражение, где упомянут атрибут разбора аргументов (`args.base_dir`)
либо переменная цикла по такому атрибуту (`for a in args.check_anon`).

*Отказ* — `return 2` или `sys.exit(2)` под условием, которое смотрит на **сам список**:
`not files`, `len(files) == 0`, `files == []`. Проверка соседнего имени или самого
аргумента (`if not args.base_dir`) отказом не считается: она ловит несуществующий путь
и молчит на пустом результате — то есть ровно ту половину класса, которая уже чинилась.

Промежуточный список закрыт гейтом того, кого из него отсеяли: если `отсев = [x for x in
всё if …]`, то непустой `отсев` означает непустое `всё`, и отдельного гейта тому не нужно.
Засчитывается только отсев перебором — сложение или дополнение из другого источника
непустоту исходного не доказывают, и такие имена перебор по-прежнему называет.

Смотрятся только функции, где разбираются аргументы (`parse_args()`): вход-путь бывает
там. Как читается вывод: по строке на находку, `путь:строка  что`. Код выхода всегда 0 —
судит вызывающий.

**Что доказывает пустой вывод, а что нет.** Он значит «непроверенных на пустоту
списков из путей командной строки не встретилось». Не значит «прогон не соврёт на
вырожденном входе»: перебор не видит путей, приехавших не через `argparse` (переменная
окружения, конфиг, чужая функция), и ничего не знает о том, ЧТО именно проверяется по
собранным файлам. Пустой список, законный по существу, он тоже назовёт — и это
осознанно: объявить его законным дешевле, чем не заметить.

Чего пустой вывод НЕ скрывает: файл, который не прочитался или не разобрался, назван
отдельной строкой. Отказ, спрятанный за вызов (`отказать_если_пусто(files)`), перебор
тоже назовёт — не как ограничение пустого вывода, а как находку: он не видит, что
проверка есть, и говорит об этом вслух. Такую находку снимает человек.

Почему разбор синтаксиса, а не поиск по тексту: см. `enc-sweep.py` — там та же причина
сказана целиком, здесь указатель.
"""
import ast
import os
import sys

# Прямые способы обойти диск. Список закрытый и короткий намеренно: он нужен лишь как
# ЗАТРАВКА — дальше собиратели считаются по вызовам друг друга, и собственное имя
# функции обхода (`walk_md`) в перебор не вписано.
ОБХОД = {"walk", "listdir", "scandir", "glob", "iglob", "rglob"}


def имя_узла(узел):
    """Точечное имя выражения: `os.walk` -> 'os.walk', `f` -> 'f'. Иначе None."""
    if isinstance(узел, ast.Name):
        return узел.id
    if isinstance(узел, ast.Attribute):
        слева = имя_узла(узел.value)
        return f"{слева}.{узел.attr}" if слева else узел.attr
    return None


def собиратели(дерево):
    """Имена функций файла, которые обходят диск сами или через другого собирателя."""
    функции = {ф.name: ф for ф in ast.walk(дерево)
               if isinstance(ф, (ast.FunctionDef, ast.AsyncFunctionDef))}
    найдено = set()
    while True:
        добавлено = False
        for имя, ф in функции.items():
            if имя in найдено:
                continue
            for узел in ast.walk(ф):
                if not isinstance(узел, ast.Call):
                    continue
                полное = имя_узла(узел.func)
                if not полное:
                    continue
                if полное.split(".")[-1] in ОБХОД or полное in найдено:
                    найдено.add(имя)
                    добавлено = True
                    break
        if not добавлено:
            return найдено


def прямой_обход(выражение):
    """В выражении есть обход диска без посредника: `os.walk(...)`, `Path(x).rglob(...)`."""
    for узел in ast.walk(выражение):
        if isinstance(узел, ast.Call):
            полное = имя_узла(узел.func)
            if полное and полное.split(".")[-1] in ОБХОД:
                return True
    return False


def зовёт(выражение, имена):
    """В выражении вызывается функция из набора имён."""
    for узел in ast.walk(выражение):
        if isinstance(узел, ast.Call):
            полное = имя_узла(узел.func)
            if полное and (полное in имена or полное.split(".")[-1] in имена):
                return True
    return False


def откуда_путь(выражение, разборы, путевые):
    """Имя аргумента, из которого пришёл путь, либо None.

    Атрибут разбора (`args.base_dir`) — прямой источник; переменная цикла по такому
    атрибуту — производный.
    """
    for узел in ast.walk(выражение):
        if isinstance(узел, ast.Attribute) and isinstance(узел.value, ast.Name):
            if узел.value.id in разборы:
                return f"{узел.value.id}.{узел.attr}"
    for узел in ast.walk(выражение):
        if isinstance(узел, ast.Name) and узел.id in путевые:
            return путевые[узел.id]
    return None


def отказывает(узел):
    """Внутри ветки есть отказ прогона кодом 2."""
    for вложенный in ast.walk(узел):
        if isinstance(вложенный, ast.Return):
            значение = вложенный.value
            if isinstance(значение, ast.Constant) and значение.value == 2:
                return True
        if isinstance(вложенный, ast.Call) and имя_узла(вложенный.func) == "sys.exit":
            if вложенный.args and isinstance(вложенный.args[0], ast.Constant) \
                    and вложенный.args[0].value == 2:
                return True
    return False


def смотрит_на_пустоту(тест, имя):
    """Условие судит о пустоте самого списка: `not имя`, `len(имя) == 0`, `имя == []`."""
    for узел in ast.walk(тест):
        if isinstance(узел, ast.UnaryOp) and isinstance(узел.op, ast.Not) \
                and isinstance(узел.operand, ast.Name) and узел.operand.id == имя:
            return True
        if isinstance(узел, ast.Compare) and len(узел.ops) == 1:
            левое, правое = узел.left, узел.comparators[0]
            пусто = (isinstance(правое, ast.Constant) and правое.value == 0) or \
                    (isinstance(правое, (ast.List, ast.Tuple, ast.Set)) and not правое.elts)
            если_len = (isinstance(левое, ast.Call) and имя_узла(левое.func) == "len"
                        and левое.args and isinstance(левое.args[0], ast.Name)
                        and левое.args[0].id == имя)
            если_сам = isinstance(левое, ast.Name) and левое.id == имя
            if пусто and (если_len or если_сам):
                return True
    return False


def разбор_функции(функция, свои):
    """Находки одной функции: [(строка, имя, откуда)]."""
    разборы = set()
    for узел in ast.walk(функция):
        if isinstance(узел, ast.Assign) and isinstance(узел.value, ast.Call) \
                and (имя_узла(узел.value.func) or "").endswith("parse_args"):
            разборы |= {ц.id for ц in узел.targets if isinstance(ц, ast.Name)}
    if not разборы:
        return []

    путевые, кандидаты, отсев = {}, {}, {}
    for узел in ast.walk(функция):
        # `отсев[A] = {B, …}` — B набран перебором по A, значит B ⊆ A.
        if isinstance(узел, ast.Assign) and len(узел.targets) == 1 \
                and isinstance(узел.targets[0], ast.Name) \
                and isinstance(узел.value, (ast.ListComp, ast.SetComp, ast.GeneratorExp)):
            for ген in узел.value.generators:
                if isinstance(ген.iter, ast.Name):
                    отсев.setdefault(ген.iter.id, set()).add(узел.targets[0].id)
    for узел in ast.walk(функция):
        # Переменная цикла по пути из аргументов — тоже путь.
        if isinstance(узел, ast.For):
            источник = откуда_путь(узел.iter, разборы, путевые)
            if источник and isinstance(узел.target, ast.Name):
                путевые[узел.target.id] = источник
        цели, значение = [], None
        if isinstance(узел, ast.Assign):
            цели, значение = узел.targets, узел.value
        elif isinstance(узел, (ast.AugAssign, ast.AnnAssign)) and узел.value is not None:
            цели, значение = [узел.target], узел.value
        if значение is None:
            continue
        if not (прямой_обход(значение) or зовёт(значение, свои)):
            continue
        источник = откуда_путь(значение, разборы, путевые)
        if not источник:
            continue
        for цель in цели:
            if isinstance(цель, ast.Name):
                кандидаты.setdefault(цель.id, (узел.lineno, источник))

    def есть_гейт(имя):
        return any(isinstance(у, ast.If) and смотрит_на_пустоту(у.test, имя) and отказывает(у)
                   for у in ast.walk(функция))

    def закрыто(имя, пройдено=None):
        пройдено = пройдено or set()
        if имя in пройдено:
            return False
        пройдено.add(имя)
        return есть_гейт(имя) or any(закрыто(п, пройдено) for п in отсев.get(имя, ()))

    найдено = []
    for имя, (строка, источник) in sorted(кандидаты.items(), key=lambda п: п[1][0]):
        if not закрыто(имя):
            найдено.append((строка, имя, источник))
    return найдено


def перебор(пути):
    находки = []
    for путь in пути:
        try:
            with open(путь, encoding="utf-8") as ф:
                текст = ф.read()
        except (OSError, UnicodeDecodeError):
            находки.append(f"{путь}:1  файл не прочитан — проверить нечем")
            continue
        try:
            дерево = ast.parse(текст, путь)
        except SyntaxError as err:
            находки.append(f"{путь}:{err.lineno or 1}  код не разобрался ({err.msg}) — "
                           f"проверить нечем")
            continue
        свои = собиратели(дерево)
        for функция in ast.walk(дерево):
            if not isinstance(функция, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for строка, имя, источник in разбор_функции(функция, свои):
                находки.append(
                    f"{путь}:{строка}  в «{имя}» собраны файлы по пути из {источник}, "
                    f"а пустой список нигде не отказ: путь есть, проверять нечего — "
                    f"прогон ответит как на успех"
                )
    return находки


def main(аргументы):
    пути = []
    for a in аргументы or ["."]:
        if os.path.isfile(a):
            пути.append(a)
            continue
        for корень, папки, файлы in os.walk(a):
            папки[:] = [p for p in папки if p not in ("__pycache__", ".git")]
            пути += [os.path.join(корень, f) for f in файлы if f.endswith(".py")]
    for строка in перебор(sorted(пути)):
        print(строка)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
