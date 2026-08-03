#!/usr/bin/env python3
"""Автопрогон валидатора после записи в базу: событие PostToolUse.

`core.md` § 11 п. 12 требует прогон после каждого ввода знания. Требование адресовано
модели, то есть исполняется, «если она не отвлеклась»: заметка записана — прогон забыт —
ошибка живёт до следующей ревизии. Здесь прогон делает код.

Что важно в поведении:
  • зелёный прогон молчит — «ошибок нет» это не новость, а расход контекста;
  • красный прогон приезжает целиком, сразу после записи, пока автор ещё в теме;
  • «прогон не состоялся» (код 2) говорится отдельно от «чисто»;
  • команда берётся из `config.yaml` пользователя — та же комплектация, что и при ручном
    прогоне (§ 9.3 п. 7). Своей команды хук не придумывает: придуманная отличалась бы
    флагами и давала бы другой ответ, чем ручной прогон.
"""
import json
import os
import shlex
import subprocess
import sys
import time

MARKER = ".loreground"
CONFIG = "config.yaml"
WRITERS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
HEAD = "Loreground, проверка базы после записи"
CAP = 4000
SLOW = 5.0


def emit(message):
    json.dump(
        {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": message}},
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")
    sys.exit(0)


def under(parent, child):
    parent = os.path.realpath(parent)
    child = os.path.realpath(child)
    return child == parent or child.startswith(parent + os.sep)


def main():
    try:
        event = json.load(sys.stdin)
    except (ValueError, OSError):
        return  # Без входа судить не о чем; сорвать работу инструмента нельзя.

    if event.get("tool_name") not in WRITERS:
        return

    project = os.environ.get("CLAUDE_PROJECT_DIR") or event.get("cwd") or os.getcwd()
    # Ворота комплекта. Метка — обычный ФАЙЛ: папка с таким именем меткой не считается.
    # `isfile`, а не `exists`, — потому что ворота у всех хуков комплекта объявлены одни
    # (`hooks.json`), и разъезд на краю уже случался: `mkdir .loreground` глушил ровно
    # двух сторожей, пока двое других продолжали говорить. Агент выглядел оснащённым,
    # а слежение за версиями было мертво.
    if not os.path.isfile(os.path.join(project, MARKER)):
        return

    path = (event.get("tool_input") or {}).get("file_path") or ""
    if not path.endswith(".md") or not under(project, path):
        return

    config_path = os.path.join(project, CONFIG)
    if not os.path.exists(config_path):
        return  # Комплектация не объявлена — своей команды хук не придумывает.

    try:
        import yaml
    except ImportError:
        # Отдельно от разбора: без PyYAML прогон не состоится НИКОГДА, а стартовый хук
        # говорит про паспорт и о мёртвой проверке записи не сообщает.
        emit(HEAD + ": PyYAML не установлен — комплектацию прогона прочитать нечем. "
             "Проверка после записи НЕ выполнена, и это не «чисто». Установить: pip install pyyaml")

    try:
        with open(config_path, encoding="utf-8") as handle:
            config = yaml.safe_load(handle) or {}
    except Exception:
        return  # Разбор конфига — забота стартовых хуков, здесь молчим, чтобы не дублировать.

    command = ((config.get("validate") or {}).get("command") or "").strip()
    if not command:
        return

    try:
        argv = shlex.split(command)
    except ValueError:
        emit(HEAD + ": команда из " + CONFIG + " не разбирается: " + command[:200])
    if not argv:
        return

    # Прогон запускается только если изменённый файл лежит в проверяемой базе. Папку берём
    # из самой команды — второго дома у неё не заводим. Не распозналась — прогоняем всё
    # равно: лишний прогон дешевле молчаливого пропуска.
    targets = [t for t in argv[1:] if not t.startswith("-")]
    if targets:
        base = os.path.join(project, targets[-1])
        if os.path.isdir(base) and not under(base, path):
            return

    started = time.time()
    try:
        run = subprocess.run(argv, cwd=project, capture_output=True, text=True, timeout=120)
    except FileNotFoundError:
        emit(HEAD + ": команда «" + argv[0] + "» не найдена. Прогон не состоялся — это не «чисто».")
    except subprocess.TimeoutExpired:
        emit(HEAD + ": прогон не уложился в 120 с и снят. Это не «чисто».")
    except OSError as err:
        # Всё остальное, чем ОС отвечает на «запусти»: нет бита +x (PermissionError),
        # битый интерпретатор в шебанге, слишком длинный аргумент. Раньше это уходило
        # в общий перехват внизу файла и означало молчание, неотличимое от зелёного.
        emit(HEAD + ": команда «" + argv[0] + "» не запустилась — " + type(err).__name__
             + ": " + str(err)[:120] + ". Прогон не состоялся, это не «чисто».")
    spent = time.time() - started

    if run.returncode == 0:
        return  # Зелёный молчит.

    output = ((run.stdout or "") + (run.stderr or "")).strip()
    if len(output) > CAP:
        output = output[:CAP] + "\n… отчёт обрезан; полный — прогнать команду вручную."

    if run.returncode == 2:
        head = HEAD + ": прогон НЕ СОСТОЯЛСЯ (код 2). Это не «база чистая» — проверка не выполнена."
    else:
        head = HEAD + ": найдены проблемы (код " + str(run.returncode) + "). Разбери их сейчас, пока правка свежая."

    tail = ""
    if spent > SLOW:
        tail = ("\n\nПрогон занял " + str(round(spent, 1)) + " с: инкрементального режима нет, "
                "проверяется вся база. На большой базе это налог на каждую запись.")

    emit(head + "\n\n" + output + tail)




# Ответ на собственную поломку — общий для всех хуков, дом один: _broken.py.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _broken import сломался  # noqa: E402

if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        сломался("validate-on-write.py", err, "PostToolUse")
    sys.exit(0)
