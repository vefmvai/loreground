#!/usr/bin/env python3
"""Перебор комплекта: где кодировка текста берётся у локали машины, а не названа явно.

Зачем. Кодировка, взятая у локали, — источник самых тихих поломок: на машине автора всё
сходится, на машине с другой локалью текст приезжает битым либо теряется целиком, и оба
исхода выглядят как штатная работа. Правило «кодировку называет комплект, а не машина»
без перебора живёт ровно до следующего файла.

Как читается вывод: по строке на находку, `путь:строка  что`. Пусто — ни одна из
перечисленных ниже форм не встретилась. Код выхода всегда 0: судит вызывающий.

**Что доказывает пустой вывод, а что нет.** Формы перечислены списком, и список неполон
настолько, насколько неполно воображение писавшего. Пустой вывод значит «ни одна из
ПЕРЕЧИСЛЕННЫХ форм не встретилась», а не «кодировка нигде не берётся у локали».

Почему разбор синтаксиса, а не поиск по тексту. Поиск по тексту не отличает код от
разговора о коде: строка документации, объясняющая, почему нельзя писать `open()` без
кодировки, для него неотличима от самого вызова. Страж, краснеющий на собственной
документации, будет выключен — и правильно сделает. Разбор синтаксиса видит вызов, а не
буквы: комментарии и строковые литералы для него не существуют, псевдоним импорта
разворачивается в настоящее имя, а аргументы принадлежат своему вызову, а не соседнему.

Чего в списке нет намеренно: `bytes.decode()` и `str.encode()`. Без аргумента они дают
UTF-8, а не локаль (проверяется прогоном), и внесение их сюда красило бы исправный код.
"""
import ast
import os
import re
import sys

ЗАПУСК = {"run", "Popen", "check_output", "check_call", "call"}
# Этим двум кодировку задать нечем по устройству: они всегда читают по локали.
ЗАПУСК_ВСЕГДА = {"subprocess.getoutput", "subprocess.getstatusoutput", "os.popen"}
ЧТЕНИЕ_ТЕКСТА = {"open", "io.open"}
ПУТЬ_ТЕКСТОМ = {"read_text", "write_text"}
# Слова, по которым payload вообще стоит разбирать: без них разбор не нужен.
ПОВОД = ("open(", "read_text", "write_text", "subprocess", "popen", "configparser")


def имя_узла(узел):
    """Точечное имя вызываемого: `run`, `subprocess.run`, `sp.run`. Иначе None."""
    if isinstance(узел, ast.Name):
        return узел.id
    if isinstance(узел, ast.Attribute):
        левое = имя_узла(узел.value)
        return (левое + "." + узел.attr) if левое else None
    return None


def псевдонимы(дерево):
    """Карта «как написано в файле → что это на самом деле».

    Без неё `import subprocess as sp` и `from subprocess import run` отключают признак:
    в тексте файла слова `subprocess.` уже нет, а вызов остался тем же.
    """
    карта = {}
    for узел in ast.walk(дерево):
        if isinstance(узел, ast.Import):
            for a in узел.names:
                карта[a.asname or a.name] = a.name
        elif isinstance(узел, ast.ImportFrom) and узел.module:
            for a in узел.names:
                карта[a.asname or a.name] = узел.module + "." + a.name
    return карта


def развернуть(имя, карта):
    if not имя:
        return None
    голова, _, хвост = имя.partition(".")
    настоящая = карта.get(голова, голова)
    return настоящая + ("." + хвост if хвост else "")


def есть(вызов, ключ):
    return any(k.arg == ключ for k in вызов.keywords)


def значение_истина(вызов, ключ):
    for k in вызов.keywords:
        if k.arg == ключ and isinstance(k.value, ast.Constant) and k.value.value is True:
            return True
    return False


def двоичный(вызов):
    """Режим с `b`: текста нет, кодировке взяться неоткуда."""
    for арг in list(вызов.args[1:2]) + [k.value for k in вызов.keywords if k.arg == "mode"]:
        if isinstance(арг, ast.Constant) and isinstance(арг.value, str) and "b" in арг.value:
            return True
    return False


def захватывает_вывод(вызов):
    """Вывод процесса читается — значит его придётся расшифровывать."""
    if значение_истина(вызов, "capture_output"):
        return True
    for k in вызов.keywords:
        if k.arg in ("stdout", "stderr") and имя_узла(k.value) in ("subprocess.PIPE", "PIPE"):
            return True
    return False


def разобрать(текст, путь, сдвиг, находки):
    """Разбор одного куска кода. Не разобралось — говорим об этом, а не молчим."""
    try:
        дерево = ast.parse(текст)
    except SyntaxError:
        if any(п in текст for п in ПОВОД):
            находки.append((путь, сдвиг, "код с обращением к тексту не разобрался — проверить нечем"))
        return
    карта = псевдонимы(дерево)
    есть_configparser = any(развернуть(и, карта) and развернуть(и, карта).startswith("configparser")
                            for и in карта)
    for узел in ast.walk(дерево):
        if not isinstance(узел, ast.Call):
            continue
        строка = сдвиг + getattr(узел, "lineno", 1) - 1
        полное = развернуть(имя_узла(узел.func), карта)
        краткое = узел.func.attr if isinstance(узел.func, ast.Attribute) else полное

        if полное in ЗАПУСК_ВСЕГДА:
            находки.append((путь, строка, полное + ": кодировку задать нечем, читает по локали"))
            continue
        if полное in ЧТЕНИЕ_ТЕКСТА or краткое == "open" and полное and полное.endswith(".open") \
                and полное.split(".")[0] in ("Path", "pathlib"):
            if not двоичный(узел) and not есть(узел, "encoding"):
                находки.append((путь, строка, "open() без encoding="))
            continue
        if краткое in ПУТЬ_ТЕКСТОМ and not есть(узел, "encoding"):
            находки.append((путь, строка, краткое + "() без encoding="))
            continue
        if полное and полное.startswith("subprocess.") and полное.split(".")[-1] in ЗАПУСК:
            текстовый = (значение_истина(узел, "text") or значение_истина(узел, "universal_newlines")
                         or захватывает_вывод(узел))
            if текстовый and not есть(узел, "encoding"):
                находки.append((путь, строка, "запуск процесса читает вывод без encoding="))
            continue
        # `.read(файл)` у разборщика конфигов открывает файл сам — по локали. Без импорта
        # `configparser` в этом же файле не судим: `fh.read()` к делу не относится.
        if краткое == "read" and есть_configparser and узел.args and not есть(узел, "encoding"):
            находки.append((путь, строка, "configparser читает файл по локали"))


# ─── откуда доставать код ─────────────────────────────────────────────────────
# Экранированная кавычка внутри строки — часть строки, а не её конец. Без этого разбора
# кусок кода обрезается на первом же `\"`, и остаток вызовов уходит из-под проверки.
ВСТАВКА_C = re.compile(r"""python3?\s+(?:-\w+\s+)*-c\s+(['"])((?:\\.|(?!\1).)*)\1""", re.S)
ВСТАВКА_HEREDOC = re.compile(r"""python3?\s+-?\s*<<\s*['"]?(\w+)['"]?\n(.*?)\n\1""", re.S)
БЛОК_MD = re.compile(r"^```[^\n]*\n(.*?)^```", re.M | re.S)


def куски(путь, текст):
    """Пары «код, номер первой строки». Проза и разговор о коде сюда не попадают."""
    if путь.endswith(".py"):
        return [(текст, 1)]
    исходники = []
    if путь.endswith(".md"):
        # Только то, что лежит в блоках кода: обычное предложение про `open()` — не код.
        исходники = [(m.group(1), текст[:m.start(1)].count("\n") + 1) for m in БЛОК_MD.finditer(текст)]
    else:
        исходники = [(текст, 1)]
    вставки = []
    for кусок, сдвиг in исходники:
        for правило in (ВСТАВКА_C, ВСТАВКА_HEREDOC):
            for m in правило.finditer(кусок):
                вставки.append((m.group(2), сдвиг + кусок[:m.start(2)].count("\n")))
    return вставки


def смотреть(путь):
    if путь.endswith((".py", ".sh", ".md")):
        return True
    # Файл без расширения тоже исполняется — точка входа комплекта именно такая.
    if os.path.splitext(путь)[1]:
        return False
    try:
        with open(путь, "rb") as f:
            return f.read(2) == b"#!"
    except OSError:
        return False


def main():
    корень = sys.argv[1] if len(sys.argv) > 1 else "."
    находки = []
    for папка, подпапки, файлы in os.walk(корень):
        подпапки[:] = [d for d in подпапки if d not in ("__pycache__", ".git")]
        for имя in sorted(файлы):
            путь = os.path.join(папка, имя)
            if not смотреть(путь):
                continue
            try:
                текст = open(путь, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                находки.append((путь, 1, "файл не прочитан — проверить нечем"))
                continue
            for кусок, сдвиг in куски(путь, текст):
                разобрать(кусок, путь, сдвиг, находки)
    for путь, строка, что in находки:
        print(f"{os.path.relpath(путь, корень)}:{строка}  {что}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
