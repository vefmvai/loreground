#!/usr/bin/env python3
"""Сторож свежести кодекса: событие SessionStart.

Кодекс лежит копией в файле правил агента, потому что обязательная загрузка не может
опираться на строку «прочитай там-то» (core.md § 9.3 п. 5). Цена копии — она стареет
молча: обновление комплекта файла правил не касается. Этот сторож делает старение
громким.

Три исхода, и они намеренно различимы:
  • версии совпали              — молчит (ни строки в контекст);
  • версии разошлись/копии нет  — называет расхождение;
  • проверить не удалось        — говорит именно это, а не молчит.

Третий исход отделён от первого по той же причине, по которой у валидатора есть код
выхода 2: «проверил и чисто» и «не смог проверить» — разные факты, и молчание вместо
второго читается как первое.
"""
import json
import os
import re
import sys

MARK_OPEN = "<!-- КОПИРОВАТЬ ОТСЮДА -->"
MARK_CLOSE = "<!-- КОПИРОВАТЬ ДО СЮДА -->"
VERSION_RE = re.compile(r"версия кодекса\s+(\d+)")
RULES_FILES = ("CLAUDE.md", "AGENTS.md", ".cursorrules")
MARKER = ".loreground"


def say(message):
    """Положить строку в контекст сессии и выйти."""
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": "Loreground: " + message,
            }
        },
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")
    sys.exit(0)


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError):
        return None


def copy_block(text):
    """Блок между маркерами. Вне блока версия не ищется: за маркерами живёт шапка."""
    start = text.find(MARK_OPEN)
    end = text.find(MARK_CLOSE)
    if start == -1 or end == -1 or end < start:
        return None
    return text[start + len(MARK_OPEN):end]


def main():
    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    # Ворота. Без метки сборки это чужой проект: сторож молчит и ничего не читает.
    if not os.path.exists(os.path.join(project, MARKER)):
        return

    # Источник: комплект рядом (режим «Указатель») либо перенесённая копия («Копия»).
    candidates = []
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        candidates.append(os.path.join(plugin_root, "standard", "codex.md"))
    candidates.append(os.path.join(project, "standard", "codex.md"))

    source_text = source_path = None
    for candidate in candidates:
        text = read(candidate)
        if text is not None:
            source_text, source_path = text, candidate
            break

    if source_text is None:
        say(
            "источник кодекса не найден (искал: "
            + ", ".join(candidates)
            + "). Свежесть копии в правилах агента проверить нечем — это не «всё в порядке»."
        )

    block = copy_block(source_text)
    if block is None:
        say(
            "в источнике " + source_path + " нет пары маркеров КОПИРОВАТЬ — "
            "непонятно, что считать кодексом. Проверка не состоялась."
        )

    source_version = VERSION_RE.search(block)
    if source_version is None:
        say(
            "в источнике " + source_path + " нет строки «версия кодекса N». "
            "Сравнивать не с чем — проверка не состоялась."
        )

    rules_path = None
    rules_text = None
    for name in RULES_FILES:
        path = os.path.join(project, name)
        text = read(path)
        if text is not None:
            rules_path, rules_text = path, text
            break

    if rules_text is None:
        say(
            "файл правил агента не найден (искал "
            + ", ".join(RULES_FILES)
            + "). Куда положена копия кодекса — неизвестно, проверка не состоялась."
        )

    copy_version = VERSION_RE.search(rules_text)
    if copy_version is None:
        say(
            "в файле правил " + rules_path + " кодекса нет: строки «версия кодекса N» "
            "в нём не найдено. Кодекс обязан лежать копией в начале правил "
            "(core.md § 9.3 п. 5). Скажи об этом человеку."
        )

    if copy_version.group(1) == source_version.group(1):
        return  # Совпало — молчим. Каждая строка на старте оплачивается всеми сессиями.

    say(
        "кодекс в правилах агента устарел: копия версии "
        + copy_version.group(1)
        + " в " + rules_path
        + ", источник версии " + source_version.group(1)
        + " в " + source_path
        + ". Скажи об этом человеку и предложи перенести блок между маркерами "
        "КОПИРОВАТЬ заново. Сам файл правил без его согласия не переписывай."
    )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Сторож не имеет права мешать работе: любая своя поломка — тихий выход,
        # а не сорванный старт сессии. Молчание здесь означает «сторож не сработал»,
        # и это осознанная цена: альтернатива — трейсбек в лицо человеку при каждом
        # старте.
        pass
    sys.exit(0)
