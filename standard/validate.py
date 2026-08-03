#!/usr/bin/env python3
"""
Валидатор базы знаний по стандарту памяти агента (см. core.md § 10).

Запуск:
  python3 validate.py [ПАПКА_БАЗЫ]                    # база заметок (по умолчанию knowledge/)
  python3 validate.py --core <файл|папка> ...         # + проверка файлов ядра/стандарта
  python3 validate.py --core standard --kitchen-marker "internal/"  # маркеры кухни — параметром

Проверки (нумерация = core.md § 10):
  ОШИБКИ (влияют на код выхода):
   1. Дубли-сущности — одинаковое каноническое имя (title / имя файла) у нескольких заметок.
   2. Битые ссылки — цель не существует: [[wiki-ссылки]] (по title/aliases) и
      markdown-ссылки [текст](файл.md) — по пути на диске или по имени заметки
      (плейсхолдеры шаблонов вида [[<...>]] отфильтрованы).
   3. Сироты — заметка без входящих ссылок и без роли точки входа (не MOC, не 00-index).
   4. Frontmatter — валидный YAML + обязательные ключи; повторяющийся ключ (YAML молча
      берёт последний); непустой sources у type: knowledge
      и у доменных типов, объявленных знанием (--knowledge-type).
   5. Консенсус — consensus: confirmed при <2 независимых корнях: sources схлопываются
      по группам same_root И по общему root_id заметок-источников (core.md § 5.3, § 4.4).
   6. Архив как источник правды — упоминание архивного файла (status: archived
      или шапка «исторический снимок») в строке без пометки архивности.
   7. Ссылки статусов — [подтверждено — `путь`] ведёт в несуществующий файл. Слова-маркеры
      задаются --status-marker (по умолчанию RU+EN), путь ищется от каталога файла
      и вверх по его предкам — не от рабочего каталога запуска.
   8. Чистота ядра — в файле из --core встречается маркер рабочей кухни (--kitchen-marker).
  ПРЕДУПРЕЖДЕНИЯ (на код выхода не влияют — требуют суждения человека):
   9. Протухание — temporal: true старше порога (--stale-months, по умолч. 12), без as_of
      или с датой, которая не разобралась (неразобранная дата свежей НЕ считается).
      Сюда же: наступивший срок revisit_after (core.md § 3.4).
  10. Вычислимое значение — поле frontmatter хранит снимок пересчитываемого
      (count/total/progress/percent и *_count/*_total): замени пересборкой или указателем.
  11. Молчаливое занижение — у знания ≥2 независимых корня, но consensus: single:
      либо зависимость не заявлена (same_root/root_id), либо вердикт не пересчитан.
  12. Знание без вердикта — есть sources, нет consensus: минует и 5, и 11 разом.
  13. Индекс перерос потолок — 00-index.md больше лимита (§ 7.2): он читается
      ВСЕГДА, поэтому его размер оплачивается каждой сессией.
  14. Доменный тип вне слоя доверия — тип не объявлен знанием (--knowledge-type),
      провенанс с него не спрашивается.
  ОШИБКИ (продолжение нумерации):
  15. Нет Home-индекса — в базе отсутствует 00-index.md: нет точки входа (§ 7.2).
  16. Значение вне словаря — consensus/reliability не из словаря ядра (§ 3.5).
  17. sources ведёт не на источник — цель ссылки не type: source (§ 4).
  18. same_root не разобрался — список ссылок вместо списка групп (§ 5.3).
  19. Ключи frontmatter не EN/lowercase (§ 3.5): греп-рецепты стандарта их не находят.
  ПРЕДУПРЕЖДЕНИЕ:
  20. Неполный обязательный набор — нет status/created/tags из шести полей § 3.1.
  ОШИБКА:
  21. Недостижимые от индекса — входящие ссылки есть, но от 00-index.md до заметки
      не дойти по графу: замкнутый кластер сирот не даёт, а агент туда не попадёт (§ 7.2).
  22. Обезличенность (--check-anon) — в файле, объявленном обезличенным, найдены
      частности: IP, ключ, домашний путь, почта, токен (ошибка); домен, порт
      (предупреждение). Своя таксономия кодов: нет пути или нет .md → 2, не 0.
  Перечень выше — ПОЛНЫЙ: он сверяется со списком проверок в коде смоук-тестом.
  Шапка, отставшая от кода, — это файл, который врёт о себе там, где его читают,
  чтобы узнать, что он делает.

Зависимость: PyYAML — ОБЯЗАТЕЛЬНА. Без неё прогон не начинается (exit 2), потому что
частичный прогон ничем не отличим от чистого, а без библиотеки
не выполняются десять проверок, включая ловлю битого YAML.

Код выхода: 0 — чисто; 1 — найдены ошибки; 2 — прогон не состоялся (нет базы и не
задан --core; путь --core не найден; нет PyYAML). У 2 одно значение: «работа не
сделана», и его нельзя принять за «проблем не найдено».
Скрипт read-only: ничего не меняет, только сообщает.

ВАЖНО (core.md § 10.1): валидатор асимметричен — ошибками он ловит только ЗАВЫШЕНИЕ
доверия. `exit 0` означает «заявленное непротиворечиво», а НЕ «база здорова»:
незаявленную зависимость (§ 5.4) механика не видит в принципе, а занижение —
только предупреждением (11). Валидатор не заменяет аудит источников.
"""
import argparse
import glob
import os
import re
import sys
import unicodedata
from urllib.parse import unquote

try:
    import yaml  # PyYAML — строгий парс frontmatter. Зависимость обязательная, см. гейт в main()
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

class DuplicateKeyError(Exception):
    """Ключ frontmatter объявлен дважды."""


class StrictNoDuplicateLoader(yaml.SafeLoader if HAS_YAML else object):
    """SafeLoader, запрещающий повторение ключа.

    YAML разрешает дубль и молча берёт последний. Для слоя доверия это дыра:
    `consensus: confirmed` сверху и `consensus: single` снизу показывают
    читателю один вердикт, а машине — другой (§ 3.5).
    """
    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in seen:
                raise DuplicateKeyError(
                    f"ключ `{key}` объявлен дважды — YAML молча берёт последний, "
                    f"и вердикт для читателя расходится с вердиктом для машины")
            seen.add(key)
        return super().construct_mapping(node, deep=deep)


# Проверки, которые без PyYAML выполнить нечем (перечислены для сообщения гейта).
YAML_DEPENDENT_CHECKS = "4 (битый YAML), 5, 10, 11, 12, 16, 17, 18, 19, 20"

# § 3.1 объявляет обязательными шесть полей. Механика делит их не по важности,
# а по тому, что она способна утверждать:
#  — без этих трёх заметку нельзя ни опознать, ни мигрировать → ошибка;
REQUIRED_FRONTMATTER_KEYS = ("title", "type", "schema_version")
#  — эти три обязательны стандартом, но их отсутствие не ломает ни одну другую
#    проверку, а проставить их задним числом честно нельзя (какая дата у заметки,
#    созданной три года назад?) → предупреждение, проверка 20.
DECLARED_FRONTMATTER_KEYS = ("status", "created", "tags")

# Ключи frontmatter: английские, lowercase, без пробелов (§ 3.5). Проверка 19.
KEY_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# Служебные типы ядра (§ 2) — знанием не являются никогда.
CORE_NON_KNOWLEDGE_TYPES = ("source", "moc", "concept", "standard")


ZERO_WIDTH_RE = re.compile(r"[\u200b-\u200f\u202a-\u202e\u2060\ufeff]")


def plural(count: int, one: str, few: str, many: str) -> str:
    """«1 заметка / 2 заметки / 5 заметок» — отчёт читает человек."""
    n10, n100 = abs(count) % 10, abs(count) % 100
    if n10 == 1 and n100 != 11:
        return f"{count} {one}"
    if 2 <= n10 <= 4 and not 12 <= n100 <= 14:
        return f"{count} {few}"
    return f"{count} {many}"


def notes(count: int) -> str:
    return plural(count, "заметка", "заметки", "заметок")


def norm_name(raw) -> str:
    """Каноническая форма ИМЕНИ сущности для сравнения.

    Юникод нормализуется (NFC) и вычищается от невидимых символов: иначе два
    имени, неразличимые на экране, считаются разными сущностями, и правило
    «один дом у факта» обходится молча.
    """
    s = unicodedata.normalize("NFC", str(raw or ""))
    return ZERO_WIDTH_RE.sub("", s).lower().strip()


def norm_type(raw) -> str:
    """Каноническая форма значения `type`.

    `type: "knowledge"` — законный YAML и означает ровно `knowledge`, но сырое
    сравнение строк этого не видит: заметка молча выпадала из слоя доверия, а
    `--knowledge-type '"source"'` обходил защиту § 9.2. Один дом нормализации.
    """
    s = str(raw or "").strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        s = s[1:-1].strip()
    return s.lower()


# Словари enum-полей ядра (§ 3.5: значения ядра — английские, kebab-case).
# Значение вне словаря = заметка показывает читателю вердикт, невидимый для машины.
# ЗАКРЫТЫ только две оси доверия (§ 5): по ним механика выносит вердикт, и слово
# вне словаря делает вердикт невидимым для машины, оставаясь видимым для читателя.
# `status`, `tags`, `source_type`, доменные типы — словари ОТКРЫТЫЕ (§ 8 п. 6):
# домен вправе добавлять значения, и требовать с них закрытости значило бы ломать
# живые базы без выгоды для доверия.
CORE_ENUMS = {
    "consensus":   ("confirmed", "single", "disputed"),
    "reliability": ("a", "b", "c", "f"),
}


def enum_value(data, key):
    """Нормализованное значение enum-поля или None, если поля нет."""
    if not isinstance(data, dict) or data.get(key) is None:
        return None
    return norm_type(data.get(key))


def is_knowledge(note_type: str, declared=()) -> bool:
    """Кому обязателен провенанс (§ 3.2).

    `type: knowledge` — всегда. Доменный тип — ТОЛЬКО если домен объявил его
    специализацией знания (§ 9.1, параметр --knowledge-type).

    Почему не «всё, что не служебное»: стандарт покрывает **модуль знаний**
    (см. шапку файла), а модули состояния и журнала ещё не стандартизованы.
    База вправе держать доменные типы журнального рода (урок, инцидент), и
    требовать с них `sources` — значит выйти за объявленный охват стандарта.
    """
    nt = norm_type(note_type)
    return nt == "knowledge" or (bool(nt) and nt in {norm_type(d) for d in declared})


def is_undeclared_domain(note_type: str, declared=()) -> bool:
    """Доменный тип, про который домен не сказал, знание он или нет.

    Молчать про такие нельзя (проверка 14): именно из-за молчания доменные
    типы минуют весь слой доверия. Но и ошибкой это не является —
    домен мог завести журнальный тип, которому провенанс не положен.
    """
    nt = norm_type(note_type)
    return (bool(nt) and nt != "knowledge"
            and nt not in CORE_NON_KNOWLEDGE_TYPES
            and nt not in {norm_type(d) for d in declared})

PLACEHOLDER_LINKS = {"ссылки", "ссылка"}
PLACEHOLDER_RE = re.compile(r"^<.*>$")  # [[<имя источника>]] и т.п. — плейсхолдеры шаблонов

# `[` исключён из цели: иначе на вложенных YAML-списках (same_root: [["[[X]]", …]])
# внешняя пара [[ захватывает кавычку и ссылка «ломается» ложно
LINK_RE = re.compile(r"\[\[([^\[\]\|#\\]+)(?:[#\|][^\]]*)?\]\]")

# markdown-ссылки на заметки: [текст](файл.md) и [текст](путь/файл.md#якорь).
# Без их учёта база, связанная markdown-ссылками, получала бы «✅ Битых ссылок
# нет» при реальных битых и список ложных сирот: заметка, на которую ссылаются
# только так, выглядит ни с чем не связанной.
# `!` спереди исключает картинки.
MD_LINK_RE = re.compile(r"(?<!\!)\[[^\]\n]*\]\(\s*([^)\s]+?\.md)(?:#[^)\s]*)?\s*\)")
URL_SCHEME_RE = re.compile(r"^[a-z][a-z0-9+.-]*://|^mailto:", re.I)
TITLE_RE = re.compile(r"^title:\s*(.+)$", re.M)
ALIASES_RE = re.compile(r"^aliases:\s*\[(.*?)\]", re.M)
TEMPORAL_RE = re.compile(r"^temporal:\s*true\s*$", re.M)
ASOF_RE = re.compile(r"^as_of:\s*(\S+)", re.M)
REVISIT_RE = re.compile(r"^revisit_after:\s*(\S+)", re.M)
# Даты стандарта (§ 3.5): YYYY-MM или YYYY-MM-DD, месяц 01–12. Строго, потому что
# неразобранная дата не должна считаться свежей.
DATE_RE = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])(?:-(0[1-9]|[12]\d|3[01]))?$")
TYPE_RE = re.compile(r"^type:\s*(.+)$", re.M)

# --- архивы (проверка 6) ---
ARCHIVE_STATUS_RE = re.compile(r"^status:\s*archived\s*$", re.M)
ARCHIVE_HEAD_HINT_RE = re.compile(r"историческ\w*\s+снимок", re.I)
ARCHIVE_HEAD_LINES = 15  # шапку «исторический снимок» ищем только в начале файла
# слова, легализующие ссылку на архив (читатель предупреждён)
ARCHIVE_LINK_OK_RE = re.compile(
    r"архив|снимок|истори|провенанс|устарел|отмен|deprecated|archived", re.I
)

# --- статусы утверждений (проверка 7) ---
# Слова-маркеры статуса задаются параметром --status-marker и по умолчанию
# двуязычны. Литерал в коде сделал бы проверку 7 молча зелёной
# на базе на другом языке: ни одного статуса она бы там не увидела.
DEFAULT_STATUS_MARKERS = ("подтверждено", "confirmed", "verified")
BACKTICK_RE = re.compile(r"`([^`]+)`")
# Путь внутри статуса — и в бэктиках, и без них. Требование к оформлению не должно решать,
# проверяется утверждение или нет: путь без обратных кавычек ведёт в никуда
# ровно так же, как путь в них.
STATUS_PATH_RE = re.compile(r"[^\s`\[\]()<>«»,;]*/[^\s`\[\]()<>«»,;]+|[^\s`\[\]()<>«»,;]+\.md")


def status_marker_re(markers) -> re.Pattern:
    """Регэксп «[<маркер> …]» по списку слов-маркеров статуса.

    «Ё» и «е» различием не считаются — как и в проверке 8. Асимметрию нашёл
    соседняя проверка того же файла уже снимала
    это различие, а здесь маркер «подтверждено» не находил «подтверждёно».
    Один страж нормализует, соседний нет — это как раз то место, где проверка
    молчит, а читатель понимает молчание как «чисто».
    """
    def any_yo(m):
        return "".join(f"[её]" if ch in "её" else re.escape(ch) for ch in m)
    alt = "|".join(any_yo(m) for m in markers if m)
    return re.compile(rf"\[(?:{alt})[^\]\n]*\]", re.I)

# --- вычислимые поля (проверка 10) ---
COMPUTED_KEY_RE = re.compile(r"^(count|total|progress|percent)$|_(count|total)$")


def is_excluded(path: str) -> bool:
    p = path.replace(os.sep, "/")
    return "/_templates/" in p or "/_personal/" in p


def read(path: str):
    """(текст, проблема|None). Файл не в UTF-8 — это дефект базы, а не повод упасть.

    Падение трейсбеком на одном файле читается как «сломался инструмент»,
    а не «в базе один битый файл».
    """
    # Открывать разрешено только ОБЫЧНЫЙ файл. FIFO и символьное устройство
    # (`/dev/zero`) не ошибаются при открытии — они блокируются навсегда, и
    # прогон висит без вывода и без кода выхода. Отказ ошибкой шумит, зависание
    # молчит; второе хуже. Каталоги и битые симлинки отсекаются здесь же.
    if not os.path.isfile(path):
        return "", f"{path}: не обычный файл (FIFO, устройство, каталог или битая ссылка) — не прочитан"
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read(), None
    except UnicodeDecodeError:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read(), (f"{path}: файл не в UTF-8 — часть символов заменена "
                               f"при чтении; перекодируй, иначе поля читаются неверно")
    except OSError as e:
        # Отказ в доступе, битый симлинк, каталог с именем *.md — то же самое:
        # файл не прочитан, значит НЕ проверен. Молча пропустить нельзя (§ 8.1:
        # «отказ в доступе — это „не проверено“, а не „чисто“»), уронить
        # трейсбеком тоже: один файл не должен отменять прогон.
        return "", f"{path}: файл не прочитан ({type(e).__name__}) — считается непроверенным"


def parse_aliases(text: str):
    """Запасной разбор синонимов: только инлайновая форма `aliases: [A, B]`."""
    m = ALIASES_RE.search(text)
    if not m:
        return []
    out = []
    for a in m.group(1).split(","):
        a = a.strip().strip('"').strip("'").strip()
        if a:
            out.append(a)
    return out


def note_aliases(data, text: str) -> list:
    """Синонимы заметки из разобранного frontmatter — в ЛЮБОЙ форме YAML-списка.

    Регэксп `ALIASES_RE` видит только инлайновую форму `aliases: [A, B]`. Блочная
    форма (дефисами) для него не существует, и все её синонимы пропадали из
    множества известных имён: ссылка на законный alias объявлялась битой, а
    заметка, на которую ссылались только по синониму, — сиротой. Ложная ошибка
    на честной базе. Регэксп остаётся запасным путём: при битом YAML
    разобранных полей нет вовсе.
    """
    if isinstance(data, dict) and data.get("aliases") is not None:
        value = data.get("aliases")
        if isinstance(value, str):
            value = [value]
        if isinstance(value, list):
            return [str(a).strip() for a in value if str(a).strip()]
    return parse_aliases(text)


def frontmatter_block(text: str):
    """Вернуть (блок, None) или (None, описание проблемы структуры).

    Границы ищутся по СТРОКЕ, которая целиком состоит из `---`. Резать по первому
    попавшемуся `---` нельзя: длинное тире внутри значения — `ref: "Иванов ---
    Петров"` — обрезало бы frontmatter посередине, и поля ниже разреза
    перестали бы существовать. Ложь про здоровый файл дороже пропущенной
    ошибки: по ней идут чинить то, что не сломано (§ 10.2).
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, "нет frontmatter (файл не начинается со строки ---)"
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), None
    return None, "нет закрывающего --- у frontmatter"


def parse_frontmatter(path: str, text: str):
    """Вернуть (dict|None, [проблемы]). dict есть только при валидном YAML.

    Ветки «без PyYAML» здесь нет намеренно: прогон без библиотеки не начинается
    вовсе (гейт в main()). Мягкая деградация означала бы exit 0 на базе
    с ошибками: битый YAML некому заметить.
    """
    problems = []
    block, structural = frontmatter_block(text)
    if structural:
        return None, [f"{path}: {structural}"]
    try:
        data = yaml.load(block, Loader=StrictNoDuplicateLoader)
    except DuplicateKeyError as e:
        return None, [f"{path}: {e}"]
    except RecursionError:
        return None, [f"{path}: frontmatter вложен слишком глубоко — не разобран"]
    except yaml.YAMLError as e:
        first = str(e).splitlines()[0]
        where = yaml_error_place(e)
        return None, [f"{path}{where}: YAML-ошибка — {first}"]
    if not isinstance(data, dict):
        return None, [f"{path}: frontmatter не разобрался в набор полей (ключ: значение)"]
    for key in REQUIRED_FRONTMATTER_KEYS:
        if key not in data:
            problems.append(f"{path}: нет обязательного ключа `{key}`")
    return data, problems


def yaml_error_place(err) -> str:
    """«:строка:столбец» из исключения PyYAML, если координаты есть.

    Сообщение без координат заставляет искать ошибку глазами по всему блоку —
    на чужой базе это первое, обо что спотыкается починка (§ 10.2).
    """
    mark = getattr(err, "problem_mark", None)
    if mark is None:
        return ""
    return f":{mark.line + 1}:{mark.column + 1}"


def link_names(value) -> list:
    """Из YAML-значения (список строк '[[Имя]]' / строк) — чистые имена."""
    names = []
    if not isinstance(value, list):
        return names
    for item in value:
        if not isinstance(item, str):
            continue
        m = LINK_RE.search(item)
        if m:
            names.append(m.group(1).strip())
            continue
        # Markdown-форма `[текст](файл.md)` — та же ссылка, записанная иначе. Пока
        # её здесь не было, `sources: ["[[И]]", "[И](И.md)"]` считались ДВУМЯ разными
        # корнями: проверка 5 печатала «✅ Консенсус обеспечен корнями» на одном файле,
        # названном дважды. Базу при этом краснила проверка 17 («не ведёт ни в одну
        # заметку»), то есть зелёного прогона обход не давал — но в отчёте стояла
        # неправда, а отчёт и есть то, что человек читает. Ту же слепоту к markdown-
        # форме граф пережил отдельно: дом у разбора ссылок должен быть один.
        md = MD_LINK_RE.search(item)
        if md:
            names.append(os.path.basename(md.group(1))[:-3].strip())
            continue
        names.append(item.strip())
    return [n for n in names if n]


def root_ids(data) -> set:
    """root_id заметки-источника (§ 4.4) — всегда множество, даже если записан строкой."""
    if not isinstance(data, dict):
        return set()
    value = data.get("root_id")
    if value is None:
        return set()
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list):
        return set()
    # Идентификатор нормализуется ТОЙ ЖЕ функцией, что и имена, — иначе нормализация
    # сделана наполовину, а половинчатая опаснее отсутствующей: она создаёт впечатление,
    # что класс закрыт. Одного регистра мало: `reg-2024-017` против
    # `reg-2024-<U+200B>017` (невидимый пробел, на экране неотличимо) снова давали два
    # корня — тот же обход, ради которого правка и делалась. `norm_name` берёт NFC,
    # чистку невидимых символов и регистр разом.
    return {norm_name(v) for v in value if str(v).strip()}


def independent_roots(data: dict, source_roots=None, name_to_base=None, with_groups=False):
    """Число независимых корней: sources, схлопнутые по same_root и общему root_id (§ 5.3 п. 5).

    source_roots: имя источника (lowercase) -> set(root_id). Источники, делящие
    хотя бы один root_id, — один корень в ЛЮБОЙ заметке (§ 4.4).
    """
    raw_sources = link_names(data.get("sources"))
    if not raw_sources:
        return 0

    # Один и тот же источник, названный двумя своими законными именами (title и
    # alias, имя файла и заголовок), — ОДИН корень. Счёт сырых строк разрешал бы
    # прачечную из одного файла.
    #
    # Приведение к каноническому имени делается ОДИН раз и применяется ко ВСЕМУ
    # дальнейшему счёту — и к `sources`, и к группам `same_root`. Пока канон был
    # только у `sources`, оставалась дыра ровно в той половине, где зависимость
    # объявлена честно: источник процитирован алиасом, группа названа заголовком,
    # строки не совпали, группа не связалась — и `confirmed` проходил на одном
    # корне. Обход бил в проверку 5, единственную машину слоя доверия, и обходился
    # он не подлогом, а законным вторым именем.
    def canon(name):
        key = norm_name(name)
        return name_to_base.get(key, key) if name_to_base else key

    sources, seen_canon = [], set()
    for src in raw_sources:
        key = canon(src)
        if key not in seen_canon:
            seen_canon.add(key); sources.append(key)

    groups = []
    for grp in data.get("same_root") or []:
        names = {canon(n) for n in link_names(grp)} if isinstance(grp, list) else set()
        if names:
            groups.append(names)
    # группы по общему root_id: свойство пары источников, не утверждения (§ 4.4)
    if source_roots:
        canon_roots = {}
        for name, rids in source_roots.items():
            canon_roots.setdefault(canon(name), set()).update(rids)
        by_root = {}
        for s in sources:
            for rid in canon_roots.get(s, ()):
                by_root.setdefault(rid, set()).add(s)
        groups.extend(g for g in by_root.values() if len(g) > 1)
    # объединить пересекающиеся группы (общий член = общий корень)
    merged = []
    for g in groups:
        g = set(g)
        rest = []
        for m in merged:
            if m & g:
                g |= m
            else:
                rest.append(m)
        merged = rest + [g]
    # Разбиение источников на корни собирается ЦЕЛИКОМ, а не считается на лету:
    # прежде функция возвращала одно число, и сообщение проверки 5 говорило «sources
    # схлопнуты», не называя — какие именно и во что. Чинящий заметку был вынужден
    # пересобирать разбиение в голове по same_root и root_id, то есть повторять
    # работу, которую машина только что сделала и выбросила.
    partition, seen = [], set()
    for s in sources:
        if s in seen:
            continue
        grp = next((m for m in merged if s in m), None)
        члены = [x for x in sources if x in grp] if grp else [s]
        seen |= set(члены)
        partition.append(члены)
    return (len(partition), partition) if with_groups else len(partition)


def parse_month(value):
    """(год, месяц) из даты стандарта или None, если дата не разобралась.

    None здесь означает «не знаю», и вызывающий обязан считать это дефектом, а
    не свежестью. Разбор fail-open означал бы, что `2024-5` и `май 2024`
    молча выпадают из отчёта о протухании и выглядят свежими, — а § 3.4
    объявляет подделку свежести роднёй выдуманного источника.
    """
    m = DATE_RE.match(str(value or "").strip().strip('"').strip("'"))
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def months_between(a, b) -> int:
    """Сколько месяцев от (год, месяц) a до (год, месяц) b."""
    return (b[0] - a[0]) * 12 + (b[1] - a[1])


def homoglyph_hint(value) -> str:
    """Подсказка про не-латинские буквы в значении enum-поля.

    `reliability: 'А'` кириллической буквой выглядит на экране как правильное
    значение, и сообщение «не из словаря ядра ('a','b','c','f')» читается как
    баг валидатора, а не как ошибка в базе. Называем букву по коду — тогда
    видно, что она не та.
    """
    s = str(value or "")
    odd = {ch for ch in s if ord(ch) > 127}
    if not odd:
        return ""
    names = ", ".join(f"«{ch}» U+{ord(ch):04X}" for ch in sorted(odd))
    return f" ← не латиница: {names} (омоглиф: буква выглядит как латинская, но другая)"


def is_archived(text: str) -> bool:
    if ARCHIVE_STATUS_RE.search(text):
        return True
    # Шапка ищется в ТЕЛЕ, а не в первых строках файла: frontmatter — структурные
    # данные, и объявление архивности там уже есть, это `status: archived`. Слово
    # «архив» во frontmatter почти всегда говорит о ЧУЖОЙ заметке, а не об этой —
    # например пометка архивности на строке `sources:`, которую требует § 7.4.
    # Пока шапку искали по всему началу файла, такая пометка объявляла архивной
    # саму ссылающуюся заметку, и валидатор начинал требовать пометку уже на неё.
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        for n, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                lines = lines[n + 1:]
                break
    # ШАПКА — ЭТО ПЕРВАЯ СТРОКА ТЕЛА, и только она. Не «где-то в первых пятнадцати»:
    # § 7.4 требует помечать словом «архив» КАЖДУЮ ссылку на архив, поэтому такие
    # слова законно встречаются по всей заметке — в том числе у той, которая сама
    # архивом не является. Пока самообъявление искали в куске текста, любая заметка,
    # честно исполнившая § 7.4, объявляла архивом СЕБЯ, а архив исключён из проверки
    # ссылок целиком: правило наказывало собственное исполнение и заодно снимало
    # проверку. Чаще всего под это попадал индекс — у него ссылок больше всех.
    # Сужение до одной строки нужно потому, что отличить самообъявление от рассказа
    # о чужой заметке по словам нельзя: слова те же самые. Отличает МЕСТО — шапка
    # стоит первой и ни на что не ссылается. Ровно поэтому у структурного объявления
    # (`status: archived`) ограничений нет: оно однозначно по форме, а не по месту.
    первая = next((l for l in lines if l.strip()), "")
    # Различает не «есть ли на строке ссылка», а СТОИТ ЛИ МАРКЕР ДО НЕЁ.
    #   «**Исторический снимок.** Правила отменены; актуальное — [[Новый]].» — шапка:
    #      заметка объявляет архивом СЕБЯ и по § 6 п. 4 кладёт указатель на преемника;
    #   «- [[Приказ]] — исторический снимок» — пометка ЧУЖОЙ ссылки, шапкой не является.
    # Отбрасывать любую строку со ссылкой нельзя: идиоматичная шапка с указателем
    # перестала бы быть шапкой. Цена такой ошибки — не «одна ссылка не проверена»:
    # заметка перестаёт считаться архивом вовсе, а вместе с этим проверка 6
    # выключается для неё целиком.
    m = ARCHIVE_HEAD_HINT_RE.search(первая)
    if not m:
        return False
    ссылка = re.search(r"\[\[[^\]]+\]\]|\]\([^)]+\)", первая)
    return ссылка is None or m.start() < ссылка.start()


MAX_STATUS_PATH_UP = 6  # сколько уровней вверх искать путь статуса


def resolve_status_path(token: str, file_dir: str) -> bool:
    """Найти файл по точному пути или префиксу — от каталога файла и его предков.

    Рабочего каталога здесь нет намеренно. Иначе один и тот же файл проверялся бы
    по-разному в зависимости от того, откуда запущен валидатор. Привязка к
    каталогу самого файла делает результат воспроизводимым — и честно роняет
    прогон на комплекте, скопированном без соседей (§ 9.3, режим «копия»).

    **Токен приходит из ТЕКСТА заметки, то есть это чужой ввод**, и обращаться
    с ним надо соответственно. Отсюда три ограничения:

    1. **Глоб-метасимволы экранируются.** Строка вида `/*/*/*/*/*/nope.md`
       раскрывалась глобом по всей файловой системе — и заново для каждого
       предка: прогон не заканчивался за минуты. Одна чужая заметка вешала
       проверку целиком, а стандарт рассчитан на заимствование чужих заметок.
    2. **Абсолютные пути и выходы вверх (`..`, `~`) не резолвятся вовсе.**
       Иначе по выводу валидатора можно было выяснять, какие файлы есть на
       чужой машине: `/etc/passwd` молчал (значит, есть), выдуманный путь —
       ругался. Ссылка статуса адресует документ рядом, а не всю ФС.
    3. **Подъём ограничен** — уровнями и границей репозитория (каталог с
       `.git`). Дальше корня проекта искать нечего: там начинается чужое.
    """
    token = (token or "").strip()
    if not token or token.startswith(("/", "~")) or ".." in token.split("/"):
        return False
    escaped = glob.escape(token)
    root = os.path.abspath(file_dir)
    for _ in range(MAX_STATUS_PATH_UP + 1):
        if os.path.exists(os.path.join(root, token)):
            return True
        if glob.glob(os.path.join(root, escaped) + "*"):
            return True
        parent = os.path.dirname(root)
        if os.path.isdir(os.path.join(root, ".git")) or parent == root:
            return False
        root = parent
    return False


def walk_md(root: str):
    """Все `.md` под каталогом, БЕЗ захода в симлинки-каталоги.

    Обход по символическим ссылкам на одной петле (`ln -s . x`) даёт
    комбинаторный взрыв путей: прогон не заканчивается, а один файл
    превращается в десятки «заметок» и ложных дублей.
    """
    out = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if not os.path.islink(os.path.join(dirpath, d))]
        out.extend(os.path.join(dirpath, fn) for fn in filenames if fn.endswith(".md"))
    return sorted(out)


def collect_md(paths):
    """Файлы .md из списка путей (файл — как есть, папка — рекурсивно)."""
    out = []
    for p in paths:
        if os.path.isfile(p):
            out.append(p)
        elif os.path.isdir(p):
            out.extend(walk_md(p))
        else:
            print(f"ОШИБКА: путь --core не найден: {p}")
            sys.exit(2)
    # Фикстуры смоук-теста из --core выведены. Они СЛОМАНЫ НАМЕРЕННО — на них
    # проверяется, что валидатор ловит подсаженную ошибку. Пока их не отсекали,
    # человек, скопировавший комплект вместе с tests/ (таблица § 9.3 объявляет их
    # необязательными, но не запрещает), получал на первом же прогоне красный экран
    # из чужих заготовок — и ни одна из ошибок не была про его базу. Тот же отказ,
    # что у рецепта «потрогать»: первое знакомство с продуктом, у которого «зелёный
    # молчит», не должно начинаться с красного, за которым ничего нет.
    out = [f for f in out if "/tests/fixtures/" not in f.replace(os.sep, "/")]
    return [f for f in out if not is_excluded(f)]


def main():
    ap = argparse.ArgumentParser(description="Валидатор базы знаний (core.md § 10)")
    ap.add_argument("base_dir", nargs="?", default="knowledge",
                    help="папка базы заметок (по умолчанию knowledge/)")
    ap.add_argument("--core", action="append", default=[],
                    help="файл/папка ядра или стандарта (повторяемо). Файлы ядра входят "
                         "в проверки 6, 7, 8 и 10 — то есть в те, что работают с текстом "
                         "документа, а не с базой заметок")
    ap.add_argument("--kitchen-marker", action="append", default=[],
                    help="маркер рабочей кухни проекта для проверки 8, напр. 'internal/' (повторяемо)")
    ap.add_argument("--check-anon", action="append", default=[],
                    help="папка/файл, который обязан быть обезличен: проверка 22 ищет в нём "
                         "адреса, ключи, почту, домашние пути (повторяемо). Типичный адрес — "
                         "архив разборов сессии")
    ap.add_argument("--stale-months", type=int, default=12,
                    help="порог протухания temporal-знаний в месяцах (по умолчанию 12)")
    ap.add_argument("--knowledge-type", action="append", default=[],
                    help="доменный тип — специализация знания (§ 9.1): требовать с него "
                         "sources/consensus наравне с `knowledge` (повторяемо). "
                         "Необъявленные доменные типы дают предупреждение 14, а не ошибку")
    ap.add_argument("--no-trust-layer", action="store_true",
                    help="слой доверия (core.md § 4, § 5) при сборке не поставлен — "
                         "не выполнять проверки 4-sources, 5, 11, 12, 14, 17, 18 (§ 0.1). "
                         "Комплектация, а не ослабление: см. core.md § 0.1")
    ap.add_argument("--status-marker", action="append", default=[],
                    help="слово-маркер статуса утверждения для проверки 7 (повторяемо). "
                         "По умолчанию: " + ", ".join(DEFAULT_STATUS_MARKERS) + ". "
                         "Язык базы задаётся здесь, а не зашит в код")
    ap.add_argument("--index-limit-kb", type=float, default=25.0,
                    help="потолок Home-индекса 00-index.md в КБ (по умолчанию 25, core.md § 7.2); "
                         "0 — проверку 13 не выполнять")
    args = ap.parse_args()

    # ── гейт: без PyYAML прогон не начинается ────────────────────────────────
    # Без библиотеки десять проверок выполнить нечем, включая ловлю битого YAML.
    # Отказ прямо здесь — единственная форма, при которой невыполненная
    # проверка не может быть принята за пройденную (core.md § 10.1).
    if not HAS_YAML:
        print("ОШИБКА: не установлен PyYAML — прогон невозможен.")
        print(f"    Без него не выполняются проверки: {YAML_DEPENDENT_CHECKS}.")
        print("    Прогон с частью проверок ничем не отличим от чистого — поэтому его нет.")
        print("    Установить: pip install pyyaml")
        return 2

    trust_layer = not args.no_trust_layer
    # § 9.2: домен не может переопределять типы ядра. Объявить `source` знанием —
    # значит потребовать провенанс с самих заметок-источников; это не комплектация,
    # а поломка семантики ядра, поэтому такие значения отбрасываются вслух.
    bad_decl = [x for x in args.knowledge_type
                if norm_type(x) in CORE_NON_KNOWLEDGE_TYPES or norm_type(x) == "knowledge"]
    if bad_decl:
        print(f"ℹ️  --knowledge-type проигнорирован для типов ядра: {', '.join(bad_decl)}")
        print("    домен не переопределяет типы ядра (core.md § 9.2)\n")
        args.knowledge_type = [x for x in args.knowledge_type if x not in bad_decl]

    core_files = collect_md(args.core)
    base_files = []
    if os.path.isdir(args.base_dir):
        base_files = [f for f in walk_md(args.base_dir) if not is_excluded(f)]
    elif not core_files and not args.check_anon:
        print(f"ОШИБКА: папка {args.base_dir}/ не найдена, --core и --check-anon не заданы. "
              f"Нечего проверять.")
        return 2

    scan_files = base_files + [f for f in core_files if f not in base_files]
    texts, encoding_problems = {}, []
    for f in scan_files:
        texts[f], enc_problem = read(f)
        if enc_problem:
            encoding_problems.append(enc_problem)

    # Разобранный frontmatter — один раз на файл. Один дом разбора: повторный
    # парс тех же файлов удваивал бы самую дорогую операцию прогона.
    parsed_cache = {}

    def frontmatter_of(f):
        if f not in parsed_cache:
            parsed_cache[f] = parse_frontmatter(f, texts[f])[0]
        return parsed_cache[f]

    if not trust_layer:
        # Без этой строки сохранённый лог прогона со снятым слоем
        # доверия отличается от полного ОТСУТСТВИЕМ строки — а отсутствие никто
        # не замечает. Комплектацию от сокрытия по артефакту было не отличить.
        print("⚠️  СЛОЙ ДОВЕРИЯ НЕ ПРОВЕРЯЛСЯ (--no-trust-layer): проверки 4-sources,")
        print("    5, 11, 12, 14, 17, 18 не выполнялись. Это комплектация (core.md § 0.1),")
        print("    а не оценка базы: о провенансе и консенсусе этот прогон не говорит НИЧЕГО.\n")
    print(f"📊 База: {notes(len(base_files))}"
          + (f" · файлов ядра: {len(core_files)}" if core_files else "") + "\n")
    ok = True

    # ── сбор имён по базе (для проверок 1–3, 5) ─────────────────────────────
    known = set()          # всё, на что валидна [[ссылка]]
    canon_owner = {}       # нормализ. каноническое имя -> файлы (дубль-сущность)
    alias_owner = {}       # нормализ. alias -> файлы (мягко: омонимы)
    name_to_base = {}      # любое имя/alias -> имя файла (для графа входящих)
    note_type = {}
    note_data = {}         # имя файла -> frontmatter dict (если распарсился)
    temporal_notes = []
    revisit_notes = []     # заметки со сроком перепроверки (§ 3.4)
    fm_problems = list(encoding_problems)
    for f in base_files:
        text = texts[f]
        base = os.path.basename(f)[:-3]
        known.add(base)
        data, problems = parse_frontmatter(f, text)
        parsed_cache[f] = data
        fm_problems.extend(problems)
        note_data[base] = data
        title_m = TITLE_RE.search(text)
        title = title_m.group(1).strip().strip('"').strip("'") if title_m else base
        known.add(title)
        aliases = note_aliases(data, text)
        known.update(aliases)
        # Тип — из РАЗОБРАННОГО frontmatter: регэксп по сырому тексту не видит ни
        # `"type": knowledge` в кавычках, ни flow-стиль, и заметка молча выпадала
        # бы из слоя доверия при законном YAML.
        if isinstance(data, dict) and data.get("type") is not None:
            note_type[base] = str(data.get("type")).strip()
        else:
            tm = TYPE_RE.search(text)
            note_type[base] = tm.group(1).strip() if tm else ""
        # Значения тоже из разобранного YAML: `temporal: True` — законная запись
        # того же самого, а регистрозависимый регэксп стирал такую заметку из
        # отчёта о протухании.
        if isinstance(data, dict):
            if data.get("temporal") is True or norm_type(data.get("temporal")) == "true":
                asof = data.get("as_of")
                temporal_notes.append((base, str(asof).strip() if asof is not None else None))
            if data.get("revisit_after") is not None:
                revisit_notes.append((base, str(data.get("revisit_after")).strip()))
        else:
            if TEMPORAL_RE.search(text):
                asof_m = ASOF_RE.search(text)
                temporal_notes.append((base, asof_m.group(1).strip() if asof_m else None))
            revisit_m = REVISIT_RE.search(text)
            if revisit_m:
                revisit_notes.append((base, revisit_m.group(1).strip()))
        # знание без провенанса — в frontmatter-проблемы (проверка 4)
        if trust_layer and is_knowledge(note_type[base], args.knowledge_type):
            has_sources = (isinstance(data, dict) and link_names(data.get("sources"))) or \
                          (data is None and re.search(r"^sources:\s*\S", text, re.M))
            if not has_sources:
                fm_problems.append(f"{f}: знание (type: {note_type[base]}) без sources — провенанс обязателен")
        for claim in {title, base}:
            canon_owner.setdefault(norm_name(claim), set()).add(f)
        for a in aliases:
            alias_owner.setdefault(norm_name(a), set()).add(f)
        for nm in {base, title, *aliases}:
            name_to_base[norm_name(nm)] = base

    # ── 1. дубли-сущности ────────────────────────────────────────────────────
    dupes = {k: sorted(v) for k, v in canon_owner.items() if len(v) > 1}
    if dupes:
        ok = False
        print(f"❌ ДУБЛИ-СУЩНОСТИ ({len(dupes)}): одно каноническое имя у нескольких заметок — свести:")
        for key, fs in sorted(dupes.items()):
            print(f"    • «{key}»: " + ", ".join(fs))
        print()
    elif base_files:
        print("✅ Дублей-сущностей нет\n")

    alias_clashes = {k: sorted(v) for k, v in alias_owner.items() if len(v) > 1}
    if alias_clashes:
        print(f"ℹ️  Пересечения по aliases ({len(alias_clashes)}): одно имя ведёт в несколько заметок.")
        print("    Обычно законно — омоним, класс над несколькими сущностями, один концепт в разных")
        print("    ролях. Проверь глазами, что это не дубль-сущности под разными именами:")
        for key, fs in sorted(alias_clashes.items()):
            print(f"    • alias «{key}»: {', '.join(os.path.basename(x) for x in fs)}")
        print()

    # ── 2. битые ссылки + входящие связи ────────────────────────────────────
    broken = []
    incoming = {os.path.basename(f)[:-3]: 0 for f in base_files}

    def count_incoming(target_base, from_base):
        if target_base and target_base != from_base and target_base in incoming:
            incoming[target_base] += 1

    for f in base_files:
        base = os.path.basename(f)[:-3]
        for m in LINK_RE.finditer(texts[f]):
            target = m.group(1).strip()
            if not target or target in PLACEHOLDER_LINKS or PLACEHOLDER_RE.match(target):
                continue
            if target not in known:
                broken.append((f, f"[[{target}]]"))
                continue
            count_incoming(name_to_base.get(norm_name(target)), base)
        # markdown-ссылки — вторая законная форма связи (§ 7.2)
        for m in MD_LINK_RE.finditer(texts[f]):
            raw = m.group(1).strip()
            if URL_SCHEME_RE.match(raw):
                continue
            target_path = os.path.normpath(
                os.path.join(os.path.dirname(f), unquote(raw)))
            if os.path.exists(target_path):
                count_incoming(os.path.basename(target_path)[:-3], base)
                continue
            name = unquote(os.path.basename(raw))[:-3]
            if name in known or norm_name(name) in name_to_base:
                count_incoming(name_to_base.get(norm_name(name)), base)
                continue
            broken.append((f, f"({raw})"))
    if broken:
        ok = False
        print(f"❌ БИТЫЕ ССЫЛКИ ({len(set(broken))}):")
        for f, t in sorted(set(broken)):
            print(f"    • {f}: {t}")
        print()
    elif base_files:
        print("✅ Битых ссылок нет\n")

    # ── 3. сироты ────────────────────────────────────────────────────────────
    orphans = sorted(
        b for f in base_files
        if (b := os.path.basename(f)[:-3]).lower() != "00-index"
        and incoming.get(b, 0) == 0 and note_type.get(b, "") != "moc"
    )
    if orphans:
        ok = False
        print(f"❌ СИРОТЫ ({len(orphans)}): нет входящих [[ссылок]] — через граф не дойти, привязать:")
        for o in orphans:
            print(f"    • {o}")
        print()
    elif base_files:
        print("✅ Сирот нет\n")

    # ── 21. недостижимые от точки входа (ошибка, § 7.2) ─────────────────────
    # Входящая ссылка ещё не значит достижимость: замкнутый кластер взаимно
    # ссылающихся заметок сирот не даёт, а от индекса до него не дойти.
    if base_files and any(os.path.basename(f).lower() == "00-index.md" for f in base_files):
        edges = {}
        for f in base_files:
            b = os.path.basename(f)[:-3]
            tgts = {name_to_base.get(norm_name(m.group(1).strip()))
                    for m in LINK_RE.finditer(texts[f])}
            for m in MD_LINK_RE.finditer(texts[f]):
                raw = m.group(1).strip()
                if URL_SCHEME_RE.match(raw):
                    continue
                tgts.add(name_to_base.get(norm_name(unquote(os.path.basename(raw))[:-3])))
            edges[b] = {t for t in tgts if t}
        index_base = next(os.path.basename(f)[:-3] for f in base_files
                          if os.path.basename(f).lower() == "00-index.md")
        reached, stack = set(), [index_base]
        while stack:
            cur = stack.pop()
            if cur in reached:
                continue
            reached.add(cur)
            stack.extend(edges.get(cur, ()))
        # Сироты (проверка 3) сюда не попадают: у них входящих ссылок нет вовсе,
        # и заголовок «входящие ссылки есть» был бы про них неправдой. 21 — про
        # заметки, на которые ссылаются, но до которых от индекса не дойти.
        unreachable = sorted(b for f in base_files
                             if (b := os.path.basename(f)[:-3]) not in reached
                             and note_type.get(b, "") != "moc"
                             and incoming.get(b, 0) > 0)
        if unreachable:
            ok = False
            print(f"❌ НЕДОСТИЖИМЫЕ ОТ ИНДЕКСА ({len(unreachable)}): входящие ссылки есть,")
            print("    но от 00-index.md до них не дойти по графу — агент их не найдёт (§ 7.2):")
            for u in unreachable:
                print(f"    • {u}")
            print()
        else:
            print("✅ Все заметки достижимы от индекса\n")

    # ── 4. frontmatter ───────────────────────────────────────────────────────
    if fm_problems:
        ok = False
        print(f"❌ FRONTMATTER ({len(set(fm_problems))}):")
        for p in sorted(set(fm_problems)):
            print(f"    • {p}")
        print()
    elif base_files:
        print("✅ Frontmatter валиден (строгий YAML-парс)\n")

    # ── индекс корней: имя источника -> его root_id (§ 4.4) ─────────────────
    # Строится по заметкам-источникам и разрешается через name_to_base,
    # поэтому знание может ссылаться на источник любым его именем или alias.
    source_roots = {}
    for name, base in name_to_base.items():
        rids = root_ids(note_data.get(base))
        if rids:
            source_roots[name] = rids

    # ── 5. консенсус: confirmed требует ≥2 независимых корней (§ 5.3) ───────
    # Слой доверия — 🔧-раздел (§ 0.1): не поставлен при сборке → не выполняются
    # 4-sources, 5, 11, 12, 14, 17, 18. Это комплектация, а не ослабление.
    # Полный список объявлен в трёх местах (здесь, в справке и в баннере прогона)
    # и обязан совпадать с core.md § 0.1.
    if trust_layer:
        consensus_problems = []
        for f in base_files:
            base = os.path.basename(f)[:-3]
            data = note_data.get(base)
            if enum_value(data, "consensus") == "confirmed":
                roots, группы = independent_roots(
                    data, source_roots, name_to_base, with_groups=True)
                if roots < 2:
                    # Схлопнутая группа называется поимённо: без этого сообщение
                    # говорило «sources схлопнуты» и оставляло чинящего пересобирать
                    # разбиение вручную — по same_root и root_id всех источников.
                    расклад = "; ".join(
                        ("корень: " + " = ".join(g)) if len(g) > 1 else ("корень: " + g[0])
                        for g in группы) or "источников нет"
                    consensus_problems.append(
                        f"{f}: consensus: confirmed при {plural(roots, 'независимом корне', 'независимых корнях', 'независимых корнях')} — "
                        f"нужно ≥2. Как разложились: {расклад}. "
                        f"Знак «=» значит «один корень» (same_root или общий root_id)")
        if consensus_problems:
            ok = False
            print(f"❌ КОНСЕНСУС ({len(consensus_problems)}): подтверждённость не обеспечена корнями:")
            for p in consensus_problems:
                print(f"    • {p}")
            print()
        elif base_files:
            print("✅ Консенсус обеспечен корнями\n")

    # ── 6. архив как источник правды ────────────────────────────────────────
    # § 7.4 и таблица § 10 говорят про ССЫЛКУ на архивный файл — значит ищем
    # ссылку, а не вхождение имени в строку. Поиск подстрокой (`name in line`)
    # превращал бы архивную заметку «План» в ошибку на каждой строке со словом
    # «планируем», и починить это было бы нечем — флага у проверки 6 нет.
    # Побочно снимается квадратичный рост по числу архивных имён.
    archived = {os.path.basename(f)[:-3]: f for f in scan_files if is_archived(texts[f])}
    archive_problems = []
    archived_names = set(archived)
    for f in scan_files if archived_names else ():
        if f in archived.values():
            continue
        for i, line in enumerate(texts[f].splitlines(), 1):
            # Маркер ищется ВНЕ имени ссылки. Пока он искался по всей строке, имя
            # самой архивной заметки работало пометкой само на себя: у заметки
            # «Отмена приказа» или «История цен» ЛЮБАЯ ссылка выглядела помеченной,
            # и проверка молча пропускала её. Это зеркало дефекта, про который
            # предупреждает комментарий выше (подстрока «планируем» ловила «План»),
            # только в сторону ложного зелёного — а он дороже.
            вне_ссылок = re.sub(r"\]\(\s*[^)\s]+?\.md(?:#[^)\s]*)?\s*\)", "]",
                                 LINK_RE.sub("", line))
            if ARCHIVE_LINK_OK_RE.search(вне_ссылок):
                continue
            # Цель приводится к ИМЕНИ ФАЙЛА через name_to_base — так же, как в
            # проверке 2. Иначе ссылка `[[Старый план]]` на архивный `План.md`
            # (законная для проверки 2, потому что это title) для проверки 6
            # невидима: она сравнивала имя файла с текстом ссылки. Ложный
            # зелёный в проверке класса «ошибка».
            raw_targets = {m.group(1).strip() for m in LINK_RE.finditer(line)}
            for m in MD_LINK_RE.finditer(line):
                raw_targets.add(unquote(os.path.basename(m.group(1)))[:-3].strip())
            targets = {name_to_base.get(norm_name(t), t) for t in raw_targets}
            for name in sorted(targets & archived_names):
                archive_problems.append(
                    f"{f}:{i}: ссылка на архив «{name}» без пометки архивности — "
                    f"читатель примет за источник правды")
    if archive_problems:
        ok = False
        print(f"❌ АРХИВ КАК ИСТОЧНИК ПРАВДЫ ({len(archive_problems)}):")
        for p in archive_problems:
            print(f"    • {p}")
        print()
    else:
        print(f"✅ Ссылки на архивы помечены (архивных файлов: {len(archived)})\n")

    # ── 7. ссылки статусов [подтверждено — `путь`] ───────────────────────────
    status_problems = []
    status_re = status_marker_re(args.status_marker or DEFAULT_STATUS_MARKERS)
    for f in scan_files:
        fdir = os.path.dirname(os.path.abspath(f))
        for m in status_re.finditer(texts[f]):
            # Токен в бэктиках — заявленный путь: достаточно «/» или «.md».
            # Токен БЕЗ бэктиков — просто слова в скобках, и требования строже:
            # только имя файла `.md` и не URL. Иначе ложными ошибками становятся
            # честные `[подтверждено — https://doi.org/…]`, «A/B-тест», «50/50» —
            # то есть валидатор врёт про исправный текст.
            # URL не путь — ни в бэктиках, ни без них. Отсев стоял только у голого
            # токена, и получалась асимметрия наизнанку: `[подтверждено — https://…]`
            # проходил, а тот же адрес, аккуратно взятый в бэктики, объявлялся битым
            # путём. Небрежная запись прощалась, аккуратная наказывалась — правило
            # ловило ровно того, кто ему следует. Отсев поднят до общего для обеих форм.
            quoted = {t.strip() for t in BACKTICK_RE.findall(m.group(0))
                      if not URL_SCHEME_RE.match(t.strip())}
            bare = {t.strip() for t in STATUS_PATH_RE.findall(m.group(0))
                    if t.strip().endswith(".md") and not URL_SCHEME_RE.match(t.strip())}
            for tok in sorted(quoted | bare):
                if ("/" in tok or tok.endswith(".md")) and not resolve_status_path(tok, fdir):
                    status_problems.append(f"{f}: статус ссылается на несуществующий `{tok}`")
    if status_problems:
        ok = False
        print(f"❌ ССЫЛКИ СТАТУСОВ ({len(status_problems)}): статус висит в воздухе:")
        for p in status_problems:
            print(f"    • {p}")
        print()
    else:
        print("✅ Ссылки статусов ведут в существующие файлы"
              f" (маркеры: {', '.join(args.status_marker or DEFAULT_STATUS_MARKERS)})\n")

    # ── 8. чистота ядра (маркеры кухни в --core) ─────────────────────────────
    if core_files and args.kitchen_marker:
        # Маркер и строка приводятся к одному виду до сравнения: регистр, «ё»/«е» и
        # набор пробелов различием не считаются. Иначе маркер «черновик отдела» не
        # находил «Черновик отдела» и «черновик  отдела», то есть проверка молчала
        # ровно там, где кухня и просачивается — при пересказе своими словами.
        # ГРАНИЦА: сравнение идёт ВНУТРИ строки, чтобы в отчёте был её номер.
        # Маркер, разорванный переносом строки, эта проверка не увидит.
        def _one_form(s):
            return re.sub(r"\s+", " ", s.replace("ё", "е")).strip().lower()
        markers = [(m, _one_form(m)) for m in args.kitchen_marker]
        kitchen_problems = []
        for f in core_files:
            for i, line in enumerate(texts[f].splitlines(), 1):
                one = _one_form(line)
                for marker, m_one in markers:
                    if m_one and m_one in one:
                        kitchen_problems.append(f"{f}:{i}: маркер кухни «{marker}»")
        if kitchen_problems:
            ok = False
            print(f"❌ ЧИСТОТА ЯДРА ({len(kitchen_problems)}): кухня проекта в переносимом файле:")
            for p in kitchen_problems:
                print(f"    • {p}")
            print()
        else:
            print(f"✅ Ядро чисто (маркеров: {len(args.kitchen_marker)})\n")

    # ── 9. протухание temporal-знаний (предупреждение) ──────────────────────
    from datetime import date
    today_ym = (date.today().year, date.today().month)
    if temporal_notes:
        stale = []
        for name, asof in temporal_notes:
            if not asof:
                stale.append((name, "без as_of"))
                continue
            ym = parse_month(asof)
            if ym is None:
                # Дата, которую механика не понимает, — НЕ свежая дата.
                stale.append((name, f"as_of `{asof}` не разобрался — ожидается YYYY-MM или YYYY-MM-DD"))
                continue
            months = months_between(ym, today_ym)
            if months >= args.stale_months:
                stale.append((name, f"{asof} → ~{months} мес назад"))
        print(f"ℹ️  Временны́е знания (temporal: true): {len(temporal_notes)} шт.")
        if stale:
            print(f"    ⏳ Пора перепроверить ({len(stale)}, старше {args.stale_months} мес, "
                  "без as_of или с неразобранной датой):")
            for name, why in stale:
                print(f"        • {name} ({why})")
        else:
            print(f"    Все свежее {args.stale_months} мес — ок.")
        print()

    # ── 9б. просроченный revisit_after (предупреждение, § 3.4) ──────────────
    # § 3.4 обещает: «оставить как есть — предупреждение продолжает гореть».
    # Здесь оно и горит: без этой проверки просроченная заметка давала бы
    # зелёный, а обещание без механизма хуже отсутствия обещания.
    if revisit_notes:
        overdue, unparsed = [], []
        for name, value in revisit_notes:
            ym = parse_month(value)
            if ym is None:
                unparsed.append((name, value))
            elif ym <= today_ym:
                overdue.append((name, value))
        if overdue or unparsed:
            print(f"⚠️  ПЕРЕПРОВЕРКА ПРОСРОЧЕНА ({len(overdue) + len(unparsed)}): "
                  "срок `revisit_after` наступил (core.md § 3.4).")
            print("    Два честных хода: перепроверить и сдвинуть as_of — либо оставить,")
            print("    зная, что предупреждение горит. Сдвинуть дату без работы нельзя.")
            for name, value in overdue:
                print(f"        • {name} (revisit_after: {value})")
            for name, value in unparsed:
                print(f"        • {name} (revisit_after `{value}` не разобрался)")
            print()

    # ── 10. вычислимые значения (предупреждение) ────────────────────────────
    # frontmatter уже разобран выше — второй разбор тех же файлов был чистой
    # потерей: он удваивает самую дорогую операцию прогона.
    computed = []
    for f in scan_files:
        data = frontmatter_of(f)
        if isinstance(data, dict):
            for key in data:
                if isinstance(key, str) and COMPUTED_KEY_RE.search(key):
                    computed.append(f"{f}: поле `{key}`")
    if computed:
        print(f"⚠️  ВЫЧИСЛИМЫЕ ЗНАЧЕНИЯ ({len(computed)}): поле хранит снимок пересчитываемого —")
        print("    протухнет; замени пересборкой из реальности или указателем (core.md § 6 п. 5):")
        for p in computed:
            print(f"    • {p}")
        print()

    # ── 11. молчаливое занижение консенсуса (предупреждение, § 10.1) ────────
    # Зеркало проверки 5: там ловится завышение, здесь — занижение.
    # Намеренно предупреждение, а не ошибка: single при двух корнях бывает
    # законным (зависимость реальна, но не заявлена), а мигрирующая база иначе
    # не пройдёт вовсе. Задача — заставить ответить вслух, а не починить.
    if trust_layer:
        understated = []
        for f in base_files:
            base = os.path.basename(f)[:-3]
            data = note_data.get(base)
            if not isinstance(data, dict) or enum_value(data, "consensus") != "single":
                continue
            if len(link_names(data.get("sources"))) < 2:
                continue
            roots = independent_roots(data, source_roots, name_to_base)
            if roots >= 2:
                understated.append(f"{f}: {plural(roots, 'независимый корень', 'независимых корня', 'независимых корней')} при consensus: single")
        if understated:
            print(f"⚠️  МОЛЧАЛИВОЕ ЗАНИЖЕНИЕ ({len(understated)}): корней ≥2, а вердикт single —")
            print("    заяви зависимость (same_root / root_id) либо пересчитай вердикт (core.md § 5.3):")
            for p in understated:
                print(f"    • {p}")
            print()

    # ── 12. знание с провенансом, но без вердикта (предупреждение) ──────────
    # Без consensus заметка минует и 5, и 11: у 5 нет `confirmed`, у 11 нет `single`.
    # Самый дешёвый способ обойти слой доверия целиком — просто не ставить поле.
    if trust_layer:
        verdictless = []
        for f in base_files:
            base = os.path.basename(f)[:-3]
            data = note_data.get(base)
            if not isinstance(data, dict) or not is_knowledge(note_type.get(base, ""), args.knowledge_type):
                continue
            if link_names(data.get("sources")) and enum_value(data, "consensus") is None:
                verdictless.append(f)
        if verdictless:
            print(f"⚠️  ЗНАНИЕ БЕЗ ВЕРДИКТА ({len(verdictless)}): есть sources, нет consensus —")
            print("    заметка минует проверки 5 и 11; поле условно-обязательно (core.md § 3.2):")
            for p in verdictless:
                print(f"    • {p}")
            print()

    # ── 13. индекс перерос потолок (предупреждение, § 7.2) ──────────────────
    # Индекс — единственная заметка, которую агент читает ВСЕГДА: его размер
    # оплачивается каждой сессией, а окно контекста исчерпаемо.
    # Предупреждение, а не ошибка: целостность базы это не ломает, а решение
    # «что убрать» — суждение человека (§ 7.2).
    if args.index_limit_kb < 0:
        print("ℹ️  --index-limit-kb отрицателен — проверка 13 не выполнялась.")
        print("    Чтобы выключить её осознанно, передай 0.\n")
    if args.index_limit_kb > 0:
        limit_b = int(args.index_limit_kb * 1024)
        for f in base_files:
            if os.path.basename(f).lower() != "00-index.md":
                continue
            size = len(texts[f].encode("utf-8"))
            if size > limit_b:
                print(f"⚠️  ИНДЕКС ПЕРЕРОС ПОТОЛОК: {f} — {size} Б при лимите {limit_b} Б "
                      f"({args.index_limit_kb} КБ)")
                print("    индекс читается всегда; разгрузи в MOC, слей устаревшее либо")
                print("    осознанно подними потолок --index-limit-kb (core.md § 7.2)\n")

    # ── 17. sources ведёт не на источник (ошибка, § 4) ──────────────────────
    # Обход, который закрывает эта проверка: `confirmed` без единой заметки type: source —
    # «источниками» назначены два знания, ссылающиеся друг на друга. § 4 объявляет
    # источник ОТДЕЛЬНОЙ заметкой; механика проверяла только разрешимость ссылки.
    # ── 18. same_root не разобрался в группы (ошибка, § 5.3) ────────────────
    # Он же: `same_root: ["[[A]]","[[B]]"]` (естественная форма) молча игнорируется,
    # и `confirmed` проходит. Правило наказывало того, кто честно заявил зависимость.
    if trust_layer:
        wrong_src, flat_sr = [], []
        for f in base_files:
            base = os.path.basename(f)[:-3]
            data = note_data.get(base)
            if not isinstance(data, dict):
                continue
            for nm in link_names(data.get("sources")):
                tgt_base = name_to_base.get(norm_name(nm))
                if tgt_base is None:
                    # Источника нет в базе вовсе. Именно так `confirmed` получают
                    # на выдуманных выходных данных — против чего написан § 4.3.
                    wrong_src.append(
                        f"{f}: sources → «{nm}» не ведёт ни в одну заметку базы — "
                        f"источник должен быть отдельной заметкой `type: source` (§ 4)")
                    continue
                target_type = note_type.get(tgt_base)
                if target_type is not None and norm_type(target_type) != "source":
                    wrong_src.append(f"{f}: sources → [[{nm}]] это `{target_type}`, а не `source`")
            sr = data.get("same_root")
            if isinstance(sr, list) and sr and not all(isinstance(x, list) for x in sr):
                flat_sr.append(f"{f}: same_root — список ссылок вместо списка ГРУПП")
        if wrong_src:
            print(f"❌ SOURCES ВЕДЁТ НЕ НА ИСТОЧНИК ({len(wrong_src)}): § 4 — источник это")
            print("    отдельная заметка `type: source`; иначе консенсус считается по пустоте:")
            for x in wrong_src:
                print(f"    • {x}")
            print()
            ok = False
        if flat_sr:
            print(f"❌ SAME_ROOT НЕ РАЗОБРАЛСЯ ({len(flat_sr)}): нужен список ГРУПП —")
            print("    [[\"[[A]]\", \"[[B]]\"]]. Плоский список молча не схлопывает корни (§ 5.3):")
            for x in flat_sr:
                print(f"    • {x}")
            print()
            ok = False

    # ── 16. значение enum-поля вне словаря (ошибка, § 3.5) ──────────────────
    # Обход, который закрывает эта проверка: `consensus: Confirmed` с заглавной минует
    # 5, 11 и 12 разом — заметка показывает читателю вердикт, невидимый машине.
    # Нормализация (enum_value) лечит регистр и кавычки; эта проверка ловит то,
    # что нормализацией не лечится: слово не из словаря вообще.
    enum_bad = []
    for f in base_files:
        data = note_data.get(os.path.basename(f)[:-3])
        if not isinstance(data, dict):
            continue
        for key, vocab in CORE_ENUMS.items():
            v = enum_value(data, key)
            if v is not None and v not in vocab:
                enum_bad.append(f"{f}: {key}: {data.get(key)!r} — не из словаря ядра {vocab}"
                                + homoglyph_hint(data.get(key)))
    if enum_bad:
        print(f"❌ ЗНАЧЕНИЕ ВНЕ СЛОВАРЯ ({len(enum_bad)}): поле показывает вердикт,")
        print("    которого механика не понимает — проверки консенсуса его не видят (core.md § 3.5):")
        for x in enum_bad:
            print(f"    • {x}")
        print()
        ok = False

    # ── 15. нет Home-индекса (ошибка, § 7.2) ────────────────────────────────
    # § 7.2 объявляет `knowledge/00-index.md` точкой входа, § 9.3 шаг 4 велит его
    # создать, проверка 13 меряет его размер — а существование проверяется здесь.
    # Проверки 3 (сироты) для этого мало: она ловит заметку без входящих ссылок,
    # а замкнутый граф взаимных ссылок без точки входа для неё нормален.
    # Ошибка, а не предупреждение: агенту негде начать чтение.
    if base_files and not any(os.path.basename(f).lower() == "00-index.md" for f in base_files):
        print(f"❌ НЕТ HOME-ИНДЕКСА: в {args.base_dir}/ отсутствует 00-index.md —")
        print("    у базы нет точки входа, агенту негде начать чтение (core.md § 7.2)\n")
        ok = False

    # ── 14. доменный тип не объявлен знанием (предупреждение, § 9.1) ────────
    # Дыра, которую закрывает эта проверка: при точном сравнении типа с
    # "knowledge" любой доменный тип минует слой доверия МОЛЧА — при том
    # что § 3.2 объявляет sources обязательным «для knowledge и доменных».
    # Ошибкой быть не может: домен вправе завести журнальный тип (урок, инцидент),
    # которому провенанс не положен, — стандарт покрывает модуль знаний, а журнал
    # ещё не стандартизован. Поэтому предупреждение: оно заставляет ОТВЕТИТЬ вслух —
    # либо объяви тип знанием (--knowledge-type), либо знай, что он вне слоя доверия.
    if trust_layer:
        undeclared = {}
        for f in base_files:
            base = os.path.basename(f)[:-3]
            ty = note_type.get(base, "")
            if is_undeclared_domain(ty, args.knowledge_type):
                undeclared.setdefault(ty, []).append(f)
        if undeclared:
            total = sum(len(v) for v in undeclared.values())
            print(f"⚠️  ДОМЕННЫЙ ТИП ВНЕ СЛОЯ ДОВЕРИЯ ({total}): тип не объявлен знанием —")
            print("    провенанс с него не спрашивается. Если это специализация знания (§ 9.1),")
            print("    объяви: --knowledge-type <тип>. Если это журнальный тип — так и есть.")
            for ty, files in sorted(undeclared.items()):
                print(f"    • type: {ty} — {notes(len(files))}")
            print()

    # ── 19. ключи frontmatter не по-английски (ошибка, § 3.5) ───────────────
    # § 11 п. 12 обещал: «валидировать — теги из словаря, ключи EN». Ключи EN не
    # проверял никто, и русский ключ проходил молча: заметка выглядит нормальной,
    # а все греп-рецепты стандарта (§ 3.5) по ней не работают. Словарь тегов
    # проверить нельзя в принципе: ядро не знает словаря домена (§ 9.1).
    key_problems = []
    for f in base_files:
        data = note_data.get(os.path.basename(f)[:-3])
        if not isinstance(data, dict):
            continue
        for key in data:
            if not KEY_RE.match(str(key)):
                key_problems.append(f"{f}: ключ `{key}` — не EN/lowercase (§ 3.5)"
                                    + homoglyph_hint(key))
    if key_problems:
        ok = False
        print(f"❌ КЛЮЧИ FRONTMATTER ({len(key_problems)}): ключи полей — английские,")
        print("    lowercase, без пробелов; иначе греп-рецепты стандарта не находят заметку:")
        for p in key_problems:
            print(f"    • {p}")
        print()

    # ── 20. неполный обязательный набор (предупреждение, § 3.1) ─────────────
    incomplete = []
    for f in base_files:
        data = note_data.get(os.path.basename(f)[:-3])
        if not isinstance(data, dict):
            continue
        # Незаполненный плейсхолдер шаблона (`created: <ГГГГ-ММ-ДД …>`) — это НЕ
        # значение. Раньше он проходил молча, и заметка с датой-заглушкой
        # давала зелёный прогон: поле формально «есть». Шаблоны комплекта при этом
        # везли `created: 2026-01-01` — выдуманную дату, которую § 3.1 запрещает
        # прямым текстом («выдуманная дата хуже отсутствующей»), а шаг 5 навыка
        # копировал её дословно в живой файл. Продукт нарушал собственное правило
        # в станке, рождающем каждую новую базу.
        def не_заполнено(k):
            if k not in data:
                return True
            v = data[k]
            if isinstance(v, str) and PLACEHOLDER_RE.match(v.strip()):
                return True
            # tags: [<тег из словаря домена>] — плейсхолдер внутри списка
            if isinstance(v, list) and v and all(
                    isinstance(x, str) and PLACEHOLDER_RE.match(x.strip()) for x in v):
                return True
            return False

        missing = [k for k in DECLARED_FRONTMATTER_KEYS if не_заполнено(k)]
        if missing:
            incomplete.append(f"{f}: нет {', '.join('`' + k + '`' for k in missing)}")
    if incomplete:
        print(f"⚠️  НЕПОЛНЫЙ ОБЯЗАТЕЛЬНЫЙ НАБОР ({len(incomplete)}): § 3.1 объявляет обязательными")
        print("    шесть полей; здесь есть не все. Предупреждение, а не ошибка: механику это")
        print("    не ломает, а проставить дату задним числом честно нельзя (core.md § 3.1).")
        for p in incomplete:
            print(f"    • {p}")
        print()

    # ── 22. обезличенность объявленных файлов (ошибка, § 9.4 п. 2) ───────────
    # Зачем машина там, где была просьба: обезличенность отчёта разбора держалась
    # на одной строке инструкции суб-агенту. Просьба ошибается МОЛЧА, и поймать
    # это было нечем. Проверка не заменяет обезличенность — она ловит то, что
    # оступившийся агент вписывает чаще всего.
    #
    # ГРАНИЦА, которую надо знать: это распознавание образцов, а не понимание.
    # Пересказанный секрет («наш прод в третьем датацентре у Иванова») пройдёт.
    # Зелёный прогон означает «известных форм нет», а не «утечки нет».
    if args.check_anon:
        anon_files = []
        missing_anon = []
        for a in args.check_anon:
            if os.path.isdir(a):
                anon_files += [f for f in walk_md(a)]
            elif os.path.isfile(a):
                anon_files.append(a)
            else:
                missing_anon.append(a)
        # Путь не найден — прогон НЕ СОСТОЯЛСЯ, код 2. Иначе «проверять было нечего»
        # печаталось зелёным и читалось как «частностей нет»: ровно «пустой вывод как
        # доказательство», причём в проверке, которая стоит между личным адресом и
        # публикацией. У --core этот гейт есть с самого начала, у --check-anon не было.
        if missing_anon:
            print("ОШИБКА: путь --check-anon не найден: " + ", ".join(missing_anon))
            print("    Проверка обезличенности НЕ выполнена. Это не «частностей нет».")
            return 2
        if not anon_files:
            print("ОШИБКА: по путям --check-anon не найдено ни одного .md: "
                  + ", ".join(args.check_anon))
            print("    Проверка обезличенности НЕ выполнена. Это не «частностей нет».")
            return 2
        # Твёрдые признаки: в обезличенном тексте им места нет ни при каком смысле.
        HARD = [
            (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"),          "IP-адрес"),
            (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY"),          "приватный ключ"),
            (re.compile(r"\bssh-(?:rsa|ed25519|dss)\s+[A-Za-z0-9+/]{20,}"), "публичный ключ SSH"),
            (re.compile(r"/(?:home|Users)/[A-Za-z0-9._-]+"),         "домашний путь с именем"),
            (re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "почта"),
            (re.compile(r"\b(?:sk|pk|ghp|gho|xox[baprs])[-_][A-Za-z0-9_-]{16,}\b"), "похоже на токен"),
        ]
        # Мягкие: у них бывает законный смысл, поэтому предупреждение, а не ошибка.
        # Ошибка здесь наказывала бы за фразу «открой issue на github.com».
        SOFT = [
            (re.compile(r"\b[a-z0-9][a-z0-9-]{1,60}\.(?:ru|com|net|org|io|dev|local|su|рф)\b", re.I), "домен"),
            (re.compile(r":\d{4,5}\b"),                             "похоже на порт"),
        ]
        anon_errors, anon_warns = [], []
        for f in anon_files:
            body, _ = read(f)
            for i, line in enumerate(body.splitlines(), 1):
                for rx, why in HARD:
                    # finditer, а не search: на одной строке частностей бывает две
                    # («ключ /Users/имя/.ssh/x на 192.0.2.10»), и сообщённая первая
                    # прятала бы вторую до следующего прогона — починка по одному
                    # экземпляру вместо класса, ровно то, что этот файл проверяет.
                    for m in rx.finditer(line):
                        anon_errors.append(f"{f}:{i}: {why} — «{m.group(0)[:40]}»")
                for rx, why in SOFT:
                    m = rx.search(line)
                    if m:
                        anon_warns.append(f"{f}:{i}: {why} — «{m.group(0)[:40]}»")
        if anon_errors:
            ok = False
            print(f"❌ ОБЕЗЛИЧЕННОСТЬ ({len(anon_errors)}): в файле, объявленном обезличенным, есть частности:")
            for e in anon_errors:
                print(f"    • {e}")
            print("    Обезличенность пишется сразу, а не чистится потом (§ 9.4 п. 2): к моменту")
            print("    отправки о правиле уже забыли. Убери частность — она относится к содержанию")
            print("    задачи, а не к тому, как агент с ней обошёлся.\n")
        elif anon_files:
            print(f"✅ Обезличенность: частностей не найдено (файлов: {len(anon_files)})")
            print("   Это «известных форм нет», а не «утечки нет»: пересказанный секрет машина")
            print("   не видит (§ 10.1).\n")
        if anon_warns:
            print(f"⚠️  ВОЗМОЖНЫЕ ЧАСТНОСТИ ({len(anon_warns)}): предупреждение, не ошибка — у них бывает")
            print("    законный смысл («открой issue на github.com»). Глянь глазами:")
            for w in anon_warns:
                print(f"    • {w}")
            print()

    if ok:
        # Честная формулировка вердикта (core.md § 10.1): не «база здорова».
        print("🟢 Ошибок нет: заявленное непротиворечиво.")
        if not trust_layer:
            print("   ⚠️  НО слой доверия в этом прогоне не проверялся (--no-trust-layer).")
        print("   Это НЕ значит «база здорова»: незаявленную зависимость источников механика")
        print("   не видит, а занижение вердиктов — только предупреждение. Валидатор не заменяет аудит.")
        return 0
    print("🔴 Найдены проблемы — см. выше. Почини и прогони снова.")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RecursionError:
        # Прогон не состоялся — это код 2, а не 1: иначе падение неотличимо от
        # честного «найдены проблемы», и по нему пойдут чинить не то (§ 10).
        print("ОШИБКА: разбор упёрся в предел вложенности — прогон не состоялся.")
        sys.exit(2)
    except KeyboardInterrupt:
        print("\nПрогон прерван — результат неполон.")
        sys.exit(2)
