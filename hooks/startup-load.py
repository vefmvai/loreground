#!/usr/bin/env python3
"""Исполнитель паспорта стартовой загрузки: событие SessionStart.

Паспорт (`core.md` § 6.3) объявляет, что агент несёт в каждой сессии. До этого хука он
был декларацией: строки `by: rules` грузит модель, прочитав инструкцию, то есть «грузится,
если не отвлеклась». Здесь исполняются строки `by: hook` — их кладёт в контекст код, и
пропустить их модель не может.

Что делает и чего не делает:
  • грузит ровно строки `by: hook` — `rules` и `env` трогать нельзя, там грузит не наш код;
  • меряет фактический вес и сверяет с объявленным `size`: § 6.3 п. 3 требует замера;
  • пробитый `budget` называет вслух и всё равно грузит — § 6.3 п. 4 говорит, что пробой
    это работа человека, а не повод оставить агента без памяти. Но и «превысили, но ладно»
    он не даёт: строка о пробое приходит вместе с загрузкой;
  • молчит, когда грузить нечего: нет метки, нет конфига, нет строк `by: hook`.
"""
import json
import os
import sys

MARKER = ".loreground"
CONFIG = "config.yaml"
HEAD = "Loreground, стартовая загрузка по паспорту"


def emit(message):
    json.dump(
        {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": message}},
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")
    sys.exit(0)


def inside(project, rel):
    """Адрес обязан оставаться внутри проекта: конфиг читает код, а не человек глазами.

    Разрешается путь ЦЕЛИКОМ, а не только его папка. Папка внутри проекта ничего не
    говорит о файле: `my/mem.md` бывает символьной ссылкой наружу, и тогда «папка внутри»
    пропускала бы чужой файл в контекст. Несуществующий путь realpath возвращает как есть —
    такая строка проходит сюда и обрывается ниже на чтении, где о ней и сказано.
    """
    if os.path.isabs(rel):
        return None
    full = os.path.normpath(os.path.join(project, rel))
    root = os.path.realpath(project)
    real = os.path.realpath(full)
    if real != root and not real.startswith(root + os.sep):
        return None
    if not full.startswith(os.path.normpath(project) + os.sep):
        return None
    return full


def main():
    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    # Ворота комплекта. Метка — обычный ФАЙЛ: папка с таким именем меткой не считается.
    # `isfile`, а не `exists`, — потому что ворота у всех хуков комплекта объявлены одни
    # (`hooks.json`), и разъезд на краю уже случался: `mkdir .loreground` глушил ровно
    # двух сторожей, пока двое других продолжали говорить. Агент выглядел оснащённым,
    # а слежение за версиями было мертво.
    if not os.path.isfile(os.path.join(project, MARKER)):
        return

    config_path = os.path.join(project, CONFIG)
    if not os.path.exists(config_path):
        return  # Паспорта нет — значит ничего и не объявлено. Это не отказ.

    try:
        import yaml
    except ImportError:
        emit(
            HEAD + ": паспорт есть, но PyYAML не установлен — прочитать его нечем. "
            "Объявленное этим паспортом в контекст НЕ загружено. Установить: pip install pyyaml"
        )

    try:
        with open(config_path, encoding="utf-8") as handle:
            config = yaml.safe_load(handle) or {}
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as err:
        emit(HEAD + ": " + CONFIG + " не разбирается (" + str(err)[:120] + "). Загрузка не состоялась.")

    startup = config.get("startup") or {}
    loads = startup.get("loads") or []
    if not isinstance(loads, list):
        emit(HEAD + ": в " + CONFIG + " ключ startup.loads не список. Загрузка не состоялась.")

    hook_rows = [row for row in loads if isinstance(row, dict) and row.get("by") == "hook"]
    if not hook_rows:
        return  # Ни одной строки нашего исполнения — молчим.

    problems = []
    chunks = []
    total = 0

    for row in hook_rows:
        what = str(row.get("what") or "<строка без имени>")
        rel = row.get("path")
        if not rel:
            problems.append("«" + what + "»: строка by: hook без path — грузить нечего")
            continue
        full = inside(project, str(rel))
        if full is None:
            problems.append("«" + what + "»: путь " + str(rel) + " ведёт наружу проекта — не читаю")
            continue
        try:
            with open(full, encoding="utf-8") as handle:
                text = handle.read()
        except (OSError, UnicodeDecodeError):
            problems.append("«" + what + "»: " + str(rel) + " не прочитан — объявлен обязательным, а его нет")
            continue
        size = len(text.encode("utf-8"))
        total += size
        declared = row.get("size")
        if isinstance(declared, int) and declared != size:
            problems.append(
                "«" + what + "»: в паспорте " + str(declared) + " Б, на диске " + str(size)
                + " Б — число в паспорте измеряется, а не оценивается"
            )
        chunks.append("── " + str(rel) + " (" + what + ") ──\n" + text.rstrip())

    lines = []
    budget = startup.get("budget")
    if isinstance(budget, int) and total > budget:
        lines.append(
            "ПОТОЛОК ПРОБИТ: загружено " + str(total) + " Б при budget " + str(budget) + " Б. "
            "Это работа, а не отметка: поднять потолок осознанным решением либо снять загрузчик. "
            "Скажи об этом человеку."
        )

    lines.append(HEAD + ": файлов " + str(len(chunks)) + ", " + str(total) + " Б" +
                 (" при потолке " + str(budget) + " Б" if isinstance(budget, int) else " (потолок не объявлен)") + ".")
    if problems:
        lines.append("Расхождения паспорта: " + "; ".join(problems) + ".")
    if not chunks and not problems:
        return

    emit("\n".join(lines) + ("\n\n" + "\n\n".join(chunks) if chunks else ""))




# Ответ на собственную поломку — общий для всех хуков, дом один: _broken.py.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _broken import сломался  # noqa: E402

if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        сломался("startup-load.py", err, "SessionStart")
    sys.exit(0)
