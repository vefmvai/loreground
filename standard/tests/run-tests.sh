#!/usr/bin/env bash
# Смоук-тест валидатора (core.md § 10).
# Чистые фикстуры обязаны давать exit 0; ломаные — exit 1,
# и каждый класс проверки обязан поймать свою подсаженную ошибку.
# Запуск: bash run-tests.sh (из любой папки). Exit 0 = все проверки прошли.
set -u
cd "$(dirname "$0")"
V=../validate.py
PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
has() { if echo "$OUT" | grep -qF -- "$2"; then ok "$1"; else bad "$1 — в выводе нет «$2»"; fi; }

echo "── Чистая база: ожидаем exit 0 ──"
OUT=$(python3 "$V" fixtures/clean/knowledge 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then ok "код выхода 0"; else bad "код выхода $RC (ожидали 0)"; fi
has "вердикт «ошибок нет»" "🟢"
if echo "$OUT" | grep -q "❌"; then bad "чистая база не должна давать ошибок"; else ok "ошибок нет"; fi
# Вердикт обязан быть честным (core.md § 10.1): «exit 0» ≠ «база здорова».
has "вердикт не обещает здоровья базы" "НЕ значит «база здорова»"
# root_id схлопывает корни и в правильную сторону: single при общем корне — не занижение.
if echo "$OUT" | grep -q "ЗАНИЖЕНИЕ"; then
  bad "ложное срабатывание 11 на чистой базе (root_id должен схлопнуть корни)"
else ok "11 не срабатывает там, где зависимость заявлена через root_id"; fi
# 13: на умолчании (25 КБ) маленький индекс фикстуры не должен давать ложного срабатывания.
if echo "$OUT" | grep -q "ИНДЕКС ПЕРЕРОС"; then
  bad "ложное срабатывание 13 на умолчании 25 КБ"
else ok "13 не срабатывает на индексе под потолком"; fi
# 14 не должна срабатывать там, где доменных типов нет вовсе.
if echo "$OUT" | grep -q "ДОМЕННЫЙ ТИП ВНЕ СЛОЯ"; then
  bad "ложное срабатывание 14 на базе без доменных типов"
else ok "14 не срабатывает без доменных типов"; fi

echo "── Проверка 13: индекс над потолком — предупреждение, а НЕ ошибка ──"
# Подсаживаем не фикстуру на 25 КБ, а низкий потолок: класс тот же, вес фикстур не растёт.
OUT=$(python3 "$V" fixtures/clean/knowledge --index-limit-kb 0.1 2>&1); RC=$?
has "13 индекс перерос потолок" "ИНДЕКС ПЕРЕРОС ПОТОЛОК"
has "13 названы факт и лимит"   "при лимите 102 Б"
# Ключевая половина класса: § 7.2 объявил это предупреждением. Ошибка сломала бы
# любую живую базу с большим индексом.
if [ "$RC" -eq 0 ]; then ok "13 не влияет на код выхода (предупреждение)"; else bad "13 уронила exit в $RC — должна быть предупреждением"; fi

echo "── Проверка 8: маркер кухни и строка сравниваются в одном виде ──"
# Регресс-тест на нормализацию: буквальное сравнение подстрокой молчало на
# «Черновик отдела» при маркере «черновик отдела». Без этих случаев починка
# была бы механизмом без команды за ним.
TMP8="$(mktemp -d)"
printf '# Ядро\n\nЗдесь Черновик   отдела с большой буквы и двойным пробелом.\n' > "$TMP8/core.md"
OUT=$(python3 "$V" --core "$TMP8/core.md" --kitchen-marker "черновик отдела" 2>&1)
case "$OUT" in *"ЧИСТОТА ЯДРА"*) ok "8 регистр и двойной пробел не мешают" ;;
               *) bad "8 пропустила «Черновик   отдела» при маркере «черновик отдела»" ;; esac
printf '# Ядро\n\nЗдесь чёрновик отдела с буквой ё.\n' > "$TMP8/core.md"
OUT=$(python3 "$V" --core "$TMP8/core.md" --kitchen-marker "черновик отдела" 2>&1)
case "$OUT" in *"ЧИСТОТА ЯДРА"*) ok "8 «ё» и «е» не различаются" ;;
               *) bad "8 пропустила «чёрновик» при маркере «черновик»" ;; esac
printf '# Ядро\n\nЗдесь про базу знаний и ничего лишнего.\n' > "$TMP8/core.md"
OUT=$(python3 "$V" --core "$TMP8/core.md" --kitchen-marker "черновик отдела" 2>&1)
case "$OUT" in *"Ядро чисто"*) ok "8 молчит на чистом ядре" ;;
               *) bad "8 ложно сработала на чистом ядре" ;; esac
rm -rf "$TMP8"

echo "── Проверка 22: обезличенность объявленного файла ──"
# Механизм ставится там, где раньше была просьба к суб-агенту: без этих случаев
# проверка была бы обещанием без команды за ним.
TMP22="$(mktemp -d)"; mkdir -p "$TMP22/retro"
printf '# Разбор\n\nКлюч /Users/ivan/.ssh/k лежал на 192.0.2.10, писать на a@b.ru.\n' > "$TMP22/retro/грязный.md"
OUT=$(python3 "$V" --check-anon "$TMP22/retro" 2>&1); RC=$?
case "$OUT" in *"ОБЕЗЛИЧЕННОСТЬ"*) ok "22 ловит адрес, путь и почту" ;;
               *) bad "22 пропустила частности" ;; esac
if [ "$RC" -eq 1 ]; then ok "22 роняет код выхода в 1"; else bad "22 дала код $RC (ожидали 1)"; fi
# Две частности на ОДНОЙ строке обязаны быть названы обе: сообщённая первая
# прятала бы вторую до следующего прогона.
case "$OUT" in *"192.0.2.10"*) case "$OUT" in *"/Users/ivan"*) ok "22 называет обе частности одной строки" ;;
                                           *) bad "22 назвала только первую частность строки" ;; esac ;;
                          *) bad "22 не назвала адрес" ;; esac
rm "$TMP22/retro/грязный.md"
printf '# Разбор\n\nАгент заявил «проверено», не приведя команды.\n' > "$TMP22/retro/чистый.md"
OUT=$(python3 "$V" --check-anon "$TMP22/retro" 2>&1); RC=$?
case "$OUT" in *"частностей не найдено"*) ok "22 молчит на обезличенном отчёте" ;;
               *) bad "22 ложно сработала на чистом отчёте" ;; esac
if [ "$RC" -eq 0 ]; then ok "22 не роняет код на чистом"; else bad "22 дала код $RC на чистом (ожидали 0)"; fi
rm -rf "$TMP22"

echo "── Ломаная база: ожидаем exit 1 и все классы ошибок ──"
OUT=$(python3 "$V" fixtures/broken/knowledge --core fixtures/broken/core --kitchen-marker "internal/" 2>&1); RC=$?
if [ "$RC" -eq 1 ]; then ok "код выхода 1"; else bad "код выхода $RC (ожидали 1)"; fi
has "1  дубль-сущность"        "ДУБЛИ-СУЩНОСТИ"
has "2  битая ссылка"          "Несуществующая заметка"
has "3  сирота — секция"       "СИРОТЫ"
has "3  сирота — имя"          "Заброшенная заметка"
# Сирота обязана быть ТОЛЬКО в секции сирот: проверка 21 про заметки со входящими
# ссылками, и печатать сироту вторично значит утверждать про неё неправду.
if [ "$(echo "$OUT" | sed -n '/НЕДОСТИЖИМЫЕ ОТ ИНДЕКСА/,/^$/p' | grep -c 'Заброшенная заметка')" -eq 0 ]; then
  ok "3/21 не дублируют сироту"; else bad "сирота попала и в 21 — заголовок 21 про неё лжёт"; fi
# Сообщение обязано вести к следующему шагу, а не только называть нарушенное правило.
# Обе строки прежде описывали болезнь и молчали о лекарстве: чинящий знал, что не так,
# и не знал, чем закрыть, — а рядом с одной из них лежал бесплатный обход (сменить type
# и остаться без провенанса молча).
has "4b знание без провенанса ведёт к карантину, а не в тупик" "status: draft"
# Заметка вовсе без frontmatter в ломаной фикстуре не лежит — этой строке нужен свой стенд.
TFM=$(mktemp -d); mkdir -p "$TFM/knowledge"
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Ч]]\n' > "$TFM/knowledge/00-index.md"
printf 'черновик без шапки\n' > "$TFM/knowledge/Ч.md"
OUTFM=$(python3 "$V" "$TFM/knowledge" 2>&1)
if echo "$OUTFM" | grep -qF "templates/knowledge.md"; then ok "4a отсутствие frontmatter называет образец"; else
  bad "4a отсутствие frontmatter: сказано, что не так, и не сказано, чем закрыть"; fi
if echo "$OUTFM" | grep -qF "§ 3.1"; then ok "4a названы обязательные поля"; else
  bad "4a отсутствие frontmatter: обязательные поля не названы адресом"; fi
rm -rf "$TFM"
has "4b карантин назван адресом в стандарте" "§ 10.2"
has "4a YAML-ошибка"           "YAML-ошибка"
has "4b знание без провенанса" "без sources"
# Ассерции по ИМЕНИ заметки, а не по заголовку секции: иначе один класс
# маскирует другой (обе фикстуры печатаются под «КОНСЕНСУС»).
has "5a ложный консенсус (same_root)" "Ложный консенсус.md"
has "5b прачечная по общему root_id"  "Прачечная по общему корню.md"
has "11 молчаливое занижение"         "Заниженный вердикт.md"
has "12 знание без вердикта"          "Знание без вердикта.md"
has "6  архив как правда"      "АРХИВ КАК ИСТОЧНИК ПРАВДЫ"
has "7  ссылка статуса в пустоту" "research/nonexistent.md"
has "8  кухня в ядре"          "маркер кухни"
has "9  протухание temporal"   "Протухшее знание"
has "10 вычислимое значение"   "notes_count"
# 14: необъявленный доменный тип — ПРЕДУПРЕЖДЕНИЕ, провенанс с него не спрашивается.
has "14 доменный тип вне слоя доверия" "ДОМЕННЫЙ ТИП ВНЕ СЛОЯ ДОВЕРИЯ"
if echo "$OUT" | grep -q "знание (type: добавка) без sources"; then
  bad "необъявленный доменный тип не должен давать ОШИБКУ (стандарт покрывает модуль знаний)"
else ok "14 необъявленный тип не ошибка, а предупреждение"; fi

echo "── Ни один ключ шаблона конфига не остаётся без читателя ──"
# Класс, а не адрес. Ключ, который человек честно заполняет, а код не читает, — это
# видимость сделанной работы: артефакт заполненного конфига неотличим от артефакта
# незаполненного, и обнаруживается это только тем, что «почему-то не действует».
# Так жили `knowledge_types` и `trust_layer`: оба записаны в шаблоне, оба не читались
# никем, а текст стандарта при этом называл конфиг ДОМОМ этих решений.
#
# Ключи берутся из самих шаблонов навыка, а не из списка по памяти: список не растёт
# вместе с шаблоном, и следующий такой ключ прошёл бы молча.
CFG_HUMAN="why"   # поля дисциплины: их читает человек, и это объявлено в § 6.3
OUT=$(python3 - "$CFG_HUMAN" <<'PY2'
import re, glob, sys
человеческие = set(sys.argv[1].split())
текст = open("../../skills/init/SKILL.md", encoding="utf-8").read()
ключи = set()
for блок in re.findall(r"```yaml\n(.*?)```", текст, re.S):
    for строка in блок.split("\n"):
        m = re.match(r"^\s*#?\s*([а-яa-z_][\w-]*)\s*:", строка)
        if m:
            ключи.add(m.group(1))
код = "".join(open(f, encoding="utf-8").read()
              for f in glob.glob("../../hooks/*.py") + glob.glob("../*.py"))
print("CFG_KEYS", len(ключи))
for к in sorted(ключи):
    if к in человеческие:
        continue
    if not re.search(r"[\"']" + re.escape(к) + r"[\"']", код):
        print("БЕЗ ЧИТАТЕЛЯ", к)
PY2
)
CFG_KEYS=$(echo "$OUT" | sed -n 's/^CFG_KEYS //p')
CFG_ORPHANS=$(echo "$OUT" | grep -c "^БЕЗ ЧИТАТЕЛЯ" || true)
if [ "${CFG_KEYS:-0}" -ge 8 ]; then ok "ключи конфига взяты из шаблона навыка ($CFG_KEYS штук), а не из списка по памяти"; else
  bad "ключей найдено ${CFG_KEYS:-0} — перебор выродился, и его зелёный ничего не значит"; fi
if [ "$CFG_ORPHANS" -eq 0 ]; then ok "у каждого ключа конфига есть читатель в коде (кроме объявленных человеческих)"; else
  bad "$CFG_ORPHANS ключ(ей) конфига не читает никто: $(echo "$OUT" | sed -n 's/^БЕЗ ЧИТАТЕЛЯ //p' | tr '\n' ' ')"; fi
# Полнота: подсаженный ключ-сирота обязан быть пойман. Проверяется на копии шаблона,
# исходный файл не трогаем.
CFG_SEED=$(mktemp -d); mkdir -p "$CFG_SEED/skills/init" "$CFG_SEED/hooks" "$CFG_SEED/standard/tests"
cp ../../skills/init/SKILL.md "$CFG_SEED/skills/init/"
cp ../../hooks/*.py "$CFG_SEED/hooks/"; cp ../*.py "$CFG_SEED/standard/"
python3 - "$CFG_SEED" <<'PY3'
import sys, re
п = sys.argv[1] + "/skills/init/SKILL.md"
т = open(п, encoding="utf-8").read()
т = т.replace("  trust_layer:", "  выдуманный_ключ: да\n  trust_layer:", 1)
open(п, "w", encoding="utf-8").write(т)
PY3
CFG_SEED_HIT=$(cd "$CFG_SEED/standard/tests" && python3 - <<'PY4'
import re, glob
текст = open("../../skills/init/SKILL.md", encoding="utf-8").read()
ключи = set()
for блок in re.findall(r"```yaml\n(.*?)```", текст, re.S):
    for строка in блок.split("\n"):
        m = re.match(r"^\s*#?\s*([а-яa-z_][\w-]*)\s*:", строка)
        if m: ключи.add(m.group(1))
код = "".join(open(f, encoding="utf-8").read()
              for f in glob.glob("../../hooks/*.py") + glob.glob("../*.py"))
print(sum(1 for к in ключи if к not in {"why"} and not re.search(r"[\"']" + re.escape(к) + r"[\"']", код)))
PY4
)
if [ "$CFG_SEED_HIT" -eq 1 ]; then ok "подсаженный ключ-сирота пойман — перебор ловит признак"; else
  bad "подсаженный ключ-сирота НЕ пойман (нашлось $CFG_SEED_HIT): проверка ничего не доказывает"; fi
rm -rf "$CFG_SEED"

echo "── Объявление доменных типов живёт в config.yaml и действительно читается ──"
# § 9.1 говорит прямо: «у объявления есть дом, и это не командная строка». Довод верный —
# решение живёт вечно, а команда меняется. Но пока ключ `knowledge_types` не читал никто,
# настоящим домом оставались флаги в команде: человек, честно заполнивший ключ и не
# тронувший команду, получал РОВНО НИЧЕГО — слой доверия молчал, предупреждение 14 горело,
# а работа выглядела сделанной. Проверяются обе стороны: объявление включает слой доверия,
# его отсутствие — не включает.
TCFG=$(mktemp -d); mkdir -p "$TCFG/knowledge"
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Пре]]\n' > "$TCFG/knowledge/00-index.md"
printf -- '---\ntitle: Пре\ntype: препарат\nschema_version: "1.0"\n---\nТекст.\n' > "$TCFG/knowledge/Пре.md"
VABS2="$(cd "$(dirname "$V")" && pwd)/$(basename "$V")"
OUT=$(cd "$TCFG" && python3 "$VABS2" knowledge 2>&1); RC=$?
has "конфига нет: тип остаётся вне слоя доверия" "ДОМЕННЫЙ ТИП ВНЕ СЛОЯ ДОВЕРИЯ"
if [ "$RC" -eq 0 ]; then ok "конфига нет: необъявленный тип — предупреждение, не ошибка"; else
  bad "конфига нет: код $RC, необъявленный тип стал ошибкой"; fi

printf 'validate:\n  knowledge_types: [препарат]\n' > "$TCFG/config.yaml"
OUT=$(cd "$TCFG" && python3 "$VABS2" knowledge 2>&1); RC=$?
has "объявление из конфига подхвачено" "Доменные типы объявлены знанием"
has "названо, откуда взято объявление" "config.yaml: препарат"
if [ "$RC" -eq 1 ]; then ok "объявление ВКЛЮЧАЕТ слой доверия: знание без sources стало ошибкой"; else
  bad "объявление из конфига не сработало: код $RC — ключ прочитан, а проверки не включились"; fi
if echo "$OUT" | grep -qF "ДОМЕННЫЙ ТИП ВНЕ СЛОЯ ДОВЕРИЯ"; then
  bad "объявленный тип продолжает числиться необъявленным"; else
  ok "объявленный тип ушёл из предупреждения 14"; fi

# Битый конфиг не должен молчать: непрочитанный конфиг = необъявленные типы = выключенный
# слой доверия, и выглядит это как обычный прогон.
printf 'validate:\n  knowledge_types: [препарат\n' > "$TCFG/config.yaml"
OUT=$(cd "$TCFG" && python3 "$VABS2" knowledge 2>&1)
has "битый конфиг назван, а не проглочен" "не прочитан"
has "битый конфиг: сказано, что слой доверия не действует" "НЕ объявлены"
rm -rf "$TCFG"

echo "── Домен объявил свой тип знанием (--knowledge-type) ──"
# Вторая половина класса: объявил — значит слой доверия действует полностью.
OUT=$(python3 "$V" fixtures/broken/knowledge --knowledge-type "добавка" 2>&1); RC=$?
has "4c объявленный доменный тип требует sources" "знание (type: добавка) без sources"
if echo "$OUT" | grep -q "ДОМЕННЫЙ ТИП ВНЕ СЛОЯ"; then bad "объявленный тип не должен попадать в 14"; else ok "объявленный тип ушёл из 14"; fi
if [ "$RC" -eq 1 ]; then ok "объявленный тип без sources роняет прогон"; else bad "exit $RC — ошибка не сработала"; fi

echo "── Слой доверия не поставлен (--no-trust-layer, core.md § 0.1) ──"
# Комплектация, а не ослабление: сборщик вправе не ставить § 4/§ 5, и тогда
# проверки 4-sources, 5, 11, 12, 14, 17, 18 не выполняются. Разрешённая стандартом сборка
# обязана проходить валидатор.
OUT=$(python3 "$V" fixtures/broken/knowledge --no-trust-layer 2>&1); RC=$?
if echo "$OUT" | grep -q "без sources"; then bad "флаг не снял проверку 4-sources"; else ok "4-sources снята флагом"; fi
if echo "$OUT" | grep -q "КОНСЕНСУС"; then bad "флаг не снял проверку 5"; else ok "5 снята флагом"; fi
if echo "$OUT" | grep -q "ЗАНИЖЕНИЕ"; then bad "флаг не снял проверку 11"; else ok "11 снята флагом"; fi
if echo "$OUT" | grep -q "БЕЗ ВЕРДИКТА"; then bad "флаг не снял проверку 12"; else ok "12 снята флагом"; fi
# Ключевая половина: флаг снимает ТОЛЬКО слой доверия. Структурные проверки
# обязаны продолжать ловить — иначе это не комплектация, а отключение валидатора.
has "флаг НЕ трогает 1 (дубли)"   "ДУБЛИ-СУЩНОСТИ"
has "флаг НЕ трогает 2 (ссылки)"  "Несуществующая заметка"
has "флаг НЕ трогает 3 (сироты)"  "СИРОТЫ"
if [ "$RC" -eq 1 ]; then ok "структурные ошибки остались ошибками"; else bad "exit $RC — флаг проглотил структурные ошибки"; fi
# Покрытие «флаг не трогает структурные» — по всем восьми, а не по трём:
# гашение флагом 6, 7, 8, 9, 10 иначе прошло бы зелёным.
OUT=$(python3 "$V" fixtures/broken/knowledge --core fixtures/broken/core --kitchen-marker "internal/" --no-trust-layer 2>&1)
has "флаг НЕ трогает 6 (архив)"     "АРХИВ КАК ИСТОЧНИК ПРАВДЫ"
has "флаг НЕ трогает 7 (статусы)"   "research/nonexistent.md"
has "флаг НЕ трогает 8 (кухня)"     "маркер кухни"
has "флаг НЕ трогает 9 (протухание)" "Протухшее знание"
has "флаг НЕ трогает 10 (вычислимое)" "notes_count"

echo "── Проверка 15: без Home-индекса база не зеленеет (§ 7.2) ──"
# § 7.2 объявляет индекс обязательным. Без проверки 15 замкнутый граф взаимных
# ссылок без точки входа проходил бы зелёным.
TMP=$(mktemp -d)
printf -- '---\ntitle: А\ntype: concept\nschema_version: "1.0"\n---\n[[Б]]\n' > "$TMP/А.md"
printf -- '---\ntitle: Б\ntype: concept\nschema_version: "1.0"\n---\n[[А]]\n' > "$TMP/Б.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "15 нет Home-индекса" "НЕТ HOME-ИНДЕКСА"
if [ "$RC" -eq 1 ]; then ok "15 — ошибка, а не предупреждение"; else bad "exit $RC: база без точки входа зеленеет"; fi
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[А]]\n- [[Б]]\n' > "$TMP/00-index.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "НЕТ HOME-ИНДЕКСА"; then bad "15 ложно срабатывает при наличии индекса"; else ok "15 молчит, когда индекс есть"; fi
if [ "$RC" -eq 0 ]; then ok "база с индексом зеленеет"; else bad "exit $RC на корректной базе"; fi
rm -rf "$TMP"

echo "── Написание типа не должно снимать слой доверия (нормализация) ──"
# Атака на код: `type: "knowledge"` — законный YAML, а сырое сравнение
# строк его не узнавало: заметка молча выпадала из слоя доверия.
# Тем же путём обходилась защита § 9.2: --knowledge-type '"source"'.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[З]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: З\ntype: "knowledge"\nschema_version: "1.0"\n---\nТело.\n' > "$TMP/З.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "тип в кавычках остаётся знанием" "без sources"
if [ "$RC" -eq 1 ]; then ok "кавычки не снимают слой доверия"; else bad "exit $RC: type в кавычках обошёл проверку 4"; fi
OUT=$(python3 "$V" "$TMP" --knowledge-type '"source"' 2>&1)
has "защита § 9.2 не обходится кавычками" "проигнорирован для типов ядра"
OUT=$(python3 "$V" "$TMP" --knowledge-type "SOURCE" 2>&1)
has "защита § 9.2 не обходится регистром" "проигнорирован для типов ядра"
rm -rf "$TMP"

echo "── Проверка 15: точность имени и охрана пустой базы ──"
# Ложное срабатывание: на регистронезависимой ФС 00-Index.md существует, а 15 ругалась.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-Index\ntype: moc\nschema_version: "1.0"\n---\n- [[A]]\n' > "$TMP/00-Index.md"
printf -- '---\ntitle: A\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/A.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "НЕТ HOME-ИНДЕКСА"; then bad "15 ложно срабатывает на 00-Index.md (регистр)"; else ok "15 не зависит от регистра имени"; fi
rm -rf "$TMP"
# Охрана: без базы (только --core) проверка 15 обязана молчать.
OUT=$(python3 "$V" --core ../core.md 2>&1)
if echo "$OUT" | grep -q "НЕТ HOME-ИНДЕКСА"; then bad "15 сработала там, где базы нет вовсе"; else ok "15 молчит, когда база не задана"; fi
# Индекс в служебной папке точкой входа не считается.
TMP=$(mktemp -d); mkdir -p "$TMP/_templates"
printf -- '---\ntitle: шаблон\ntype: moc\nschema_version: "1.0"\n---\nx\n' > "$TMP/_templates/00-index.md"
printf -- '---\ntitle: A\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/A.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "индекс в _templates не считается точкой входа" "НЕТ HOME-ИНДЕКСА"
rm -rf "$TMP"

echo "── Проверка 14 — предупреждение, а не ошибка ──"
# Нужна база, где 14 срабатывает, а других ошибок нет: иначе exit 1 приходит
# от них, и превращение 14 в ошибку тест не заметит.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Урок]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: Урок\ntype: урок\nschema_version: "1.0"\n---\nТело.\n' > "$TMP/Урок.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "14 срабатывает на доменном типе" "• type: урок — 1 заметка"
if [ "$RC" -eq 0 ]; then ok "14 не влияет на код выхода (предупреждение)"; else bad "14 уронила exit в $RC"; fi
echo "── --knowledge-type не переопределяет типы ядра (§ 9.2) ──"
OUT=$(python3 "$V" "$TMP" --knowledge-type source --knowledge-type moc 2>&1); RC=$?
has "служебный тип отброшен вслух" "проигнорирован для типов ядра"
if [ "$RC" -eq 0 ]; then ok "объявление типа ядра не ломает базу"; else bad "exit $RC — типы ядра приняты как знание"; fi
rm -rf "$TMP"

echo "── Слой доверия против обхода дисциплины ──"
# Четыре способа показать читателю вердикт, невидимый для механики.
TMP=$(mktemp -d)
mk_index() { printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n%s\n' "$1" > "$TMP/00-index.md"; }

# 16: вердикт вне словаря — заметка показывает читателю то, чего машина не видит.
mk_index '- [[Ф]]
- [[И1]]'
printf -- '---\ntitle: Ф\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]"]\nconsensus: Одобрено\n---\nx\n' > "$TMP/Ф.md"
printf -- '---\ntitle: И1\ntype: source\nschema_version: "1.0"\nreliability: A\n---\nx\n' > "$TMP/И1.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "16 вердикт вне словаря" "ЗНАЧЕНИЕ ВНЕ СЛОВАРЯ"
if [ "$RC" -eq 1 ]; then ok "16 — ошибка"; else bad "exit $RC: вердикт вне словаря прошёл"; fi
# и обратное: регистр/кавычки лечатся нормализацией, а не падают в 16
printf -- '---\ntitle: Ф\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]"]\nconsensus: "Confirmed"\n---\nx\n' > "$TMP/Ф.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
if echo "$OUT" | grep -q "ВНЕ СЛОВАРЯ"; then bad "нормализация не сработала: Confirmed в кавычках"; else ok "регистр и кавычки лечатся нормализацией"; fi
has "5 видит нормализованный Confirmed" "КОНСЕНСУС"

# 17: sources ведёт не на источник — confirmed без единой заметки type: source.
mk_index '- [[Ф]]
- [[A]]'
printf -- '---\ntitle: Ф\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[A]]"]\nconsensus: single\n---\nx [[A]]\n' > "$TMP/Ф.md"
printf -- '---\ntitle: A\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[Ф]]"]\nconsensus: single\n---\nx [[Ф]]\n' > "$TMP/A.md"
rm -f "$TMP/И1.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "17 sources ведёт не на источник" "SOURCES ВЕДЁТ НЕ НА ИСТОЧНИК"
if [ "$RC" -eq 1 ]; then ok "17 — ошибка"; else bad "exit $RC: консенсус считается по пустоте"; fi

# 18: same_root плоским списком — правило наказывало честного.
mk_index '- [[Ф]]
- [[И1]]
- [[И2]]'
printf -- '---\ntitle: Ф\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]","[[И2]]"]\nsame_root: ["[[И1]]","[[И2]]"]\nconsensus: confirmed\n---\nx\n' > "$TMP/Ф.md"
printf -- '---\ntitle: И1\ntype: source\nschema_version: "1.0"\nreliability: A\n---\nx\n' > "$TMP/И1.md"
printf -- '---\ntitle: И2\ntype: source\nschema_version: "1.0"\nreliability: A\n---\nx\n' > "$TMP/И2.md"
rm -f "$TMP/A.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "18 same_root не разобрался" "SAME_ROOT НЕ РАЗОБРАЛСЯ"
if [ "$RC" -eq 1 ]; then ok "18 — ошибка"; else bad "exit $RC: заявленная зависимость молча пропала"; fi
# каноническая форма проходит
printf -- '---\ntitle: Ф\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]","[[И2]]"]\nsame_root: [["[[И1]]","[[И2]]"]]\nconsensus: single\n---\nx\n' > "$TMP/Ф.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "SAME_ROOT НЕ РАЗОБРАЛСЯ"; then bad "18 ложно срабатывает на канонической форме"; else ok "18 молчит на списке групп"; fi
if [ "$RC" -eq 0 ]; then ok "каноническая форма зеленеет"; else bad "exit $RC на корректной базе"; fi

# Прогон обязан объявлять, что слой доверия не проверялся.
OUT=$(python3 "$V" "$TMP" --no-trust-layer 2>&1)
has "флаг объявляет себя в шапке" "СЛОЙ ДОВЕРИЯ НЕ ПРОВЕРЯЛСЯ"
has "флаг объявляет себя в вердикте" "НО слой доверия в этом прогоне не проверялся"
rm -rf "$TMP"

echo "── --core на папке без документов ядра: прогон не состоялся, а не «ядро чисто» ──"
# Флаг задан, путь существует, документов ядра там нет. Прежде прогон шёл так, будто флага
# не было: проверки 6, 7, 8, 10 не выполнялись, отчёт получался тем же, и единственной
# приметой оставался отсутствующий кусок шапки — а заметить, что чего-то НЕТ, нельзя.
TCORE=$(mktemp -d); mkdir -p "$TCORE/knowledge" "$TCORE/пусто"
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[П]]\n' > "$TCORE/knowledge/00-index.md"
printf -- '---\ntitle: П\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TCORE/knowledge/П.md"
cp ../validate.py "$TCORE/пусто/"      # не .md: для ядра это пустая папка
OUT=$(python3 "$V" "$TCORE/knowledge" --core "$TCORE/пусто" 2>&1); RC=$?
if [ "$RC" -eq 2 ]; then ok "--core без документов ядра: код 2"; else
  bad "--core без документов ядра: код $RC — невыполненные проверки прошли как выполненные"; fi
has "--core без документов: названы непройденные проверки" "6, 7, 8, 10"
has "--core без документов: сказано, что это не «ядро чистое»" "не «ядро чистое»"
if echo "$OUT" | grep -q "🟢"; then bad "--core без документов: зелёный вердикт при невыполненных проверках"; else
  ok "--core без документов: зелёного вердикта нет"; fi
# Обратная сторона: с настоящим ядром прогон обязан идти как прежде. Иначе починка
# ложного зелёного куплена ложным красным, и флаг станет невозможно использовать.
cp ../core.md "$TCORE/пусто/"
python3 "$V" "$TCORE/knowledge" --core "$TCORE/пусто" >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "--core с настоящим ядром: прогон идёт, код 0"; else
  bad "--core с настоящим ядром: код $RC — сломан обычный путь"; fi
# Та же беда с другой стороны: НАЗВАННАЯ папка базы, которой нет на диске. Прежде она
# прощалась, если задан --core: прогон шёл по одному ядру и печатал «📊 База: 0 заметок»,
# а следом «🟢 Ошибок нет». Опечатка в имени папки давала зелёный экран при нуле
# проверенных заметок — приметой был только ноль в шапке, а ноль не бросается в глаза.
OUT=$(python3 "$V" "$TCORE/kknowledge" --core "$TCORE/пусто" 2>&1); RC=$?
if [ "$RC" -eq 2 ]; then ok "опечатка в имени папки базы: код 2, а не зелёный"; else
  bad "опечатка в имени папки базы: код $RC — ноль проверенных заметок прошёл как «чисто»"; fi
has "опечатка в имени базы: сказано, что это не «чисто»" "не «в базе всё чисто»"
if echo "$OUT" | grep -q "🟢"; then bad "опечатка в имени базы: зелёный вердикт при нуле заметок"; else
  ok "опечатка в имени базы: зелёного вердикта нет"; fi
# А вот НЕназванная база при названном ядре — законный прогон «проверь одно ядро».
# Он обязан идти, но обязан и сказать о себе: отчёт без этой строки отличается от полного
# только отсутствием раздела про базу, а отсутствие никто не замечает.
OUT=$(python3 "$V" --core "$TCORE/пусто" 2>&1); RC=$?   # запуск из tests/: папки knowledge тут нет
if [ "$RC" -eq 0 ]; then ok "прогон только по ядру: остаётся законным"; else
  bad "прогон только по ядру: код $RC — сломан законный способ проверить одно ядро"; fi
has "прогон только по ядру: объявляет себя неполным" "ТОЛЬКО документы ядра"
rm -rf "$TCORE"

echo "── Гейт PyYAML: без библиотеки прогон не начинается ──"
# Класс «ложный зелёный»: без PyYAML часть проверок молча не выполнялась, и база
# с ошибками давала exit 0 — а строка «PyYAML не установлен» печаталась ПОСЛЕ
# зелёного вердикта. Невыполненная проверка не должна отличаться от пройденной
# только внимательностью читателя.
TMP=$(mktemp -d)
printf 'raise ImportError("PyYAML спрятан для теста")\n' > "$TMP/yaml.py"
OUT=$(PYTHONPATH="$TMP" python3 "$V" fixtures/broken/knowledge 2>&1); RC=$?
if [ "$RC" -eq 2 ]; then ok "без PyYAML код выхода 2"; else bad "код выхода $RC — прогон без PyYAML состоялся"; fi
has "гейт называет причину"            "не установлен PyYAML"
has "гейт перечисляет непройденное"    "не выполняются проверки"
if echo "$OUT" | grep -q "🟢"; then bad "ложный зелёный без PyYAML"; else ok "зелёного вердикта без PyYAML нет"; fi
OUT=$(python3 "$V" fixtures/broken/knowledge 2>&1); RC=$?
if [ "$RC" -eq 1 ]; then ok "с PyYAML та же база проверяется полностью"; else bad "exit $RC на ломаной базе"; fi
rm -rf "$TMP"

echo "── Совет «поставь PyYAML» называет интерпретатор, а не просто pip ──"
# Отчёт с macOS: на машине два Python (системный и из Homebrew), и слово `python3` значит
# в разных местах разное. Голое `pip install pyyaml` клало библиотеку в один интерпретатор,
# пока прогон шёл другим, — исход «поставил, а он всё равно не видит». Спрашивать у
# пользователя нечего: кто печатает совет, тот и знает свой путь.
SELF=$(python3 -c "import sys; print(sys.executable)")
TMP=$(mktemp -d); printf 'raise ImportError("PyYAML спрятан для теста")\n' > "$TMP/yaml.py"
OUT=$(PYTHONPATH="$TMP" python3 "$V" fixtures/broken/knowledge 2>&1)
has "гейт называет свой интерпретатор полным путём" "$SELF -m pip install pyyaml"
rm -rf "$TMP"
# Класс, а не адрес: перебираются ВСЕ файлы продукта, где вообще советуют ставить PyYAML.
# Список берётся поиском, а не памятью, — иначе следующий такой совет пройдёт молча.
#
# Скоуп здесь весь комплект, а не только код, и это не роскошь: прежняя редакция
# смотрела `hooks/` и `standard/*.py`, из-за чего сам стандарт (`core.md`, § 10)
# продолжал советовать голое `pip install pyyaml` и вдобавок обещал, что это «единственное,
# что требуется от машины». Проверка была зелёной при открытом классе — в документе,
# который читают внимательнее всего.
#
# Годным считается один из двух ответов, потому что места разной природы: код обязан
# назвать СВОЙ интерпретатор (`sys.executable`), проза обязана назвать сам вопрос — в ней
# подставить путь неоткуда, но и промолчать о нём нельзя.
VAGUE=0; ADVICE=0
for f in $(grep -rl "pip install pyyaml" ../.. --include='*.py' --include='*.md' --include='*.sh' 2>/dev/null | grep -v '/fixtures/'); do
  ADVICE=$((ADVICE+1))
  grep -q "sys\.executable" "$f" || grep -qi "интерпретатор" "$f" || VAGUE=$((VAGUE+1))
done
[ "$ADVICE" -gt 0 ] || bad "совет про PyYAML: перебор пуст — искать нечего, а не «чисто»"
if [ "$VAGUE" -eq 0 ]; then ok "совет про PyYAML ($ADVICE мест) везде называет интерпретатор"
else bad "$VAGUE из $ADVICE мест советуют голое «pip install pyyaml» — библиотека уедет не в тот Python"; fi

echo "── Markdown-ссылки видимы валидатору ──"
# Класс «ложный зелёный»: [текст](файл.md) для валидатора не существовали —
# ложные сироты и «✅ битых ссылок нет» при реальных битых.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [Заметка](Заметка.md)\n' > "$TMP/00-index.md"
printf -- '---\ntitle: Заметка\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/Заметка.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "СИРОТЫ"; then bad "md-ссылка не засчитана — ложная сирота"; else ok "md-ссылка считается входящей связью"; fi
if [ "$RC" -eq 0 ]; then ok "база на md-ссылках зеленеет"; else bad "exit $RC на корректной базе"; fi
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [Заметка](Заметка.md)\n- [Нет](Нет-такой.md)\n' > "$TMP/00-index.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "битая md-ссылка поймана" "(Нет-такой.md)"
if echo "$OUT" | grep -q "Битых ссылок нет"; then bad "«битых нет» при реальной битой"; else ok "зелёного о ссылках больше нет"; fi
if [ "$RC" -eq 1 ]; then ok "битая md-ссылка — ошибка"; else bad "exit $RC"; fi
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [Заметка](Заметка.md)\n- [док](https://example.com/readme.md)\n![карта](map.md)\n' > "$TMP/00-index.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then ok "внешний URL и картинка не считаются битыми ссылками"; else bad "exit $RC — http/картинка приняты за файл базы"; fi
rm -rf "$TMP"

echo "── Синонимы блочным YAML-списком видимы ──"
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Синоним]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: Заметка\ntype: concept\nschema_version: "1.0"\naliases:\n  - Синоним\n  - Alias2\n---\nx\n' > "$TMP/Заметка.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "БИТЫЕ ССЫЛКИ"; then bad "ссылка на блочный alias объявлена битой"; else ok "блочные синонимы читаются"; fi
if [ "$RC" -eq 0 ]; then ok "база с блочными aliases зеленеет"; else bad "exit $RC — ложная ошибка на честной базе"; fi
rm -rf "$TMP"

echo "── as_of разбирается строго, а не в пользу свежести ──"
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[В]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: В\ntype: concept\nschema_version: "1.0"\ntemporal: true\nas_of: май-2024\n---\nx\n' > "$TMP/В.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "неразобранная дата не считается свежей" "не разобрался"
printf -- '---\ntitle: В\ntype: concept\nschema_version: "1.0"\ntemporal: true\nas_of: %s\n---\nx\n' "$(date +%Y-%m)" > "$TMP/В.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
if echo "$OUT" | grep -q "Пора перепроверить"; then bad "ложное срабатывание на свежей дате"; else ok "свежая дата в отчёт не попадает"; fi

echo "── revisit_after: обещанное предупреждение действительно горит ──"
printf -- '---\ntitle: В\ntype: concept\nschema_version: "1.0"\nrevisit_after: 2020-01\n---\nx\n' > "$TMP/В.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "просроченный revisit_after горит" "ПЕРЕПРОВЕРКА ПРОСРОЧЕНА"
if [ "$RC" -eq 0 ]; then ok "revisit_after — предупреждение, не ошибка"; else bad "exit $RC — предупреждение уронило прогон"; fi
printf -- '---\ntitle: В\ntype: concept\nschema_version: "1.0"\nrevisit_after: 2099-01\n---\nx\n' > "$TMP/В.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
if echo "$OUT" | grep -q "ПЕРЕПРОВЕРКА ПРОСРОЧЕНА"; then bad "ложное срабатывание на будущем сроке"; else ok "будущий срок не горит"; fi
rm -rf "$TMP"

echo "── Проверка 7: не зашита на русский и не зависит от рабочего каталога ──"
VABS="$(pwd)/../validate.py"
TMP=$(mktemp -d)
printf -- '# Core\n\nClaim [confirmed — `docs/absent.md`] here.\n' > "$TMP/core-en.md"
OUT=$(python3 "$V" --core "$TMP/core-en.md" 2>&1); RC=$?
has "английский маркер статуса виден" "docs/absent.md"
if [ "$RC" -eq 1 ]; then ok "англоязычная база не зеленеет молча"; else bad "exit $RC — проверка 7 промолчала"; fi
# cwd больше не спасает: рядом с местом запуска путь есть, рядом с файлом — нет
CWDT=$(mktemp -d); mkdir -p "$CWDT/docs"; : > "$CWDT/docs/absent.md"
OUT=$(cd "$CWDT" && python3 "$VABS" --core "$TMP/core-en.md" 2>&1)
has "запуск из чужого каталога не резолвит путь" "docs/absent.md"
rm -rf "$CWDT" "$TMP"

echo "── Проверка 19: ключи frontmatter — английские ──"
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[З]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: З\ntype: concept\nschema_version: "1.0"\nзаголовок: x\n---\nx\n' > "$TMP/З.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "19 не-английский ключ пойман" "КЛЮЧИ FRONTMATTER"
has "19 буква названа по коду"     "не латиница"
if [ "$RC" -eq 1 ]; then ok "19 — ошибка"; else bad "exit $RC — русский ключ прошёл молча"; fi

echo "── Проверка 20: неполный обязательный набор — предупреждение ──"
printf -- '---\ntitle: З\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/З.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "20 неполный набор назван"      "НЕПОЛНЫЙ ОБЯЗАТЕЛЬНЫЙ НАБОР"
has "20 названы недостающие поля"   'нет `status`, `created`, `tags`'
if [ "$RC" -eq 0 ]; then ok "20 не влияет на код выхода"; else bad "20 уронила exit в $RC"; fi
rm -rf "$TMP"

echo "── Сообщение об омоглифе читаемо ──"
# Читаемость сообщения: `reliability: 'А'` кириллической читается как баг валидатора.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[И]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: И\ntype: source\nschema_version: "1.0"\nreliability: А\n---\nx\n' > "$TMP/И.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "омоглиф назван по коду символа" "U+0410"
rm -rf "$TMP"

echo "── YAML-ошибка называет координаты ──"
OUT=$(python3 "$V" fixtures/broken/knowledge 2>&1)
if echo "$OUT" | grep -qE 'Сломанный YAML\.md:[0-9]+:[0-9]+: YAML-ошибка'; then
  ok "у YAML-ошибки есть строка и столбец"
else bad "YAML-ошибка без координат — искать глазами по всему блоку"; fi

echo '── Границы frontmatter ищутся по строке из трёх дефисов, а не по любому вхождению ──'
# Ложь про ИСПРАВНЫЙ файл: длинное тире в значении (`ref: \"Иванов --- Петров\"`)
# резало блок посередине. Валидатор печатал YAML-ошибку там, где YAML валиден,
# а поля ниже разреза для него переставали существовать.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-07-27\ntags: [i]\n---\n- [[Тире]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: Тире\ntype: knowledge\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-07-27\ntags: [t]\nref: "Иванов --- Петров"\nsources: ["[[И]]"]\nconsensus: single\n---\nтело\n' > "$TMP/Тире.md"
printf -- '---\ntitle: И\ntype: source\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-07-27\ntags: [s]\nreliability: A\n---\nтело\n' > "$TMP/И.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "YAML-ошибка"; then bad "выдуманная YAML-ошибка в валидном файле"; else ok "--- в значении не ломает разбор"; fi
if echo "$OUT" | grep -q "без sources"; then bad "поля ниже --- пропали: провенанс объявлен отсутствующим"; else ok "поля после --- в значении видны"; fi
if [ "$RC" -eq 0 ]; then ok "исправная база зеленеет"; else bad "exit $RC на исправной базе"; fi
# и обратная сторона: настоящий незакрытый frontmatter обязан ловиться
printf -- '---\ntitle: Рваный\ntype: concept\nschema_version: "1.0"\nтело без закрытия\n' > "$TMP/Рваный.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "незакрытый frontmatter ловится" "нет закрывающего"
rm -rf "$TMP"

echo "── Проверка 6 ловит ССЫЛКУ на архив, а не вхождение имени в строку ──"
# Архивная заметка «План» превращала в ошибку каждую строку со словом
# «планируем»: честная база не могла позеленеть, а флага у проверки 6 нет.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Живая]]\n- [[План]] (архив)\n' > "$TMP/00-index.md"
printf -- '---\ntitle: План\ntype: concept\nschema_version: "1.0"\nstatus: archived\n---\nстарое\n' > "$TMP/План.md"
# Регистр важен: подстрочный поиск регистрозависим, и фикстура со строчной
# «планируем» была бы зелёной на самом дефекте.
printf -- '---\ntitle: Живая\ntype: concept\nschema_version: "1.0"\n---\nПланируем выпуск. Планка высока.\n' > "$TMP/Живая.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "АРХИВ КАК ИСТОЧНИК"; then bad "ложное срабатывание 6 на слове «Планируем»"; else ok "6 не срабатывает на подстроке"; fi
if [ "$RC" -eq 0 ]; then ok "честная база с архивом зеленеет"; else bad "exit $RC на честной базе"; fi
# вторая половина: настоящая ссылка на архив без пометки — по-прежнему ошибка
printf -- '---\ntitle: Живая\ntype: concept\nschema_version: "1.0"\n---\nСмотри [[План]] — там всё.\n' > "$TMP/Живая.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
has "6 ловит wiki-ссылку на архив" "ссылка на архив «План»"
if [ "$RC" -eq 1 ]; then ok "6 осталась ошибкой"; else bad "exit $RC — ссылка на архив прошла"; fi
# и markdown-форму тоже
printf -- '---\ntitle: Живая\ntype: concept\nschema_version: "1.0"\n---\nСмотри [план](План.md) — там всё.\n' > "$TMP/Живая.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "6 ловит markdown-ссылку на архив" "ссылка на архив «План»"
# третья форма: ссылка по title/alias, а не по имени файла. Проверка 2 такую
# ссылку считает валидной — значит и проверка 6 обязана её видеть.
printf -- '---\ntitle: Старый план\ntype: concept\nschema_version: "1.0"\nstatus: archived\naliases: [План-2024]\n---\nстарое\n' > "$TMP/План.md"
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Живая]]\n- [[Старый план]] (архив)\n' > "$TMP/00-index.md"
printf -- '---\ntitle: Живая\ntype: concept\nschema_version: "1.0"\n---\nСмотри [[Старый план]] — там всё.\n' > "$TMP/Живая.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "6 ловит ссылку по title архивной заметки" "ссылка на архив «План»"
printf -- '---\ntitle: Живая\ntype: concept\nschema_version: "1.0"\n---\nСмотри [[План-2024]] — там всё.\n' > "$TMP/Живая.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "6 ловит ссылку по alias архивной заметки" "ссылка на архив «План»"
rm -rf "$TMP"

echo "── Проверка 7 видит путь и без бэктиков ──"
# Оформление не должно решать, проверяется утверждение или нет: путь
# без обратных кавычек был для проверки пустым статусом и молча зеленел.
TMP=$(mktemp -d)
printf -- 'Утверждение [подтверждено — docs/absent.md] тут.\n' > "$TMP/doc.md"
# и обратная сторона: голый текст в скобках — не путь. DOI, «A/B-тест», «50/50»
# содержат «/», но файлами не являются: ошибка на них = враньё про исправный текст.
printf -- 'Раз [подтверждено — https://doi.org/10.1000/xyz123].\nДва [подтверждено — см. A/B-тест в теле].\nТри [подтверждено — 50/50 по опросу].\n' > "$TMP/prose.md"
OUT=$(python3 "$V" --core "$TMP/prose.md" 2>&1); RCP=$?
if echo "$OUT" | grep -q "ССЫЛКИ СТАТУСОВ"; then bad "ложная ошибка на DOI/URL или тексте со слешем"; else ok "DOI, A/B-тест и 50/50 не считаются путями"; fi
# URL, КОНЧАЮЩИЙСЯ на .md — единственная форма, которую фильтр `.md` пропускает,
# и ради которой написан отсев схемы.
printf -- 'Ссылка [подтверждено — https://raw.githubusercontent.com/a/b/README.md].\n' > "$TMP/urlmd.md"
OUT=$(python3 "$V" --core "$TMP/urlmd.md" 2>&1); RCU=$?
if echo "$OUT" | grep -q "ССЫЛКИ СТАТУСОВ"; then bad "URL на .md принят за путь к файлу"; else ok "URL на .md не считается путём"; fi
if [ "$RCU" -eq 0 ]; then ok "статус со ссылкой на веб зеленеет"; else bad "exit $RCU"; fi
if [ "$RCP" -eq 0 ]; then ok "честная проза со слешами зеленеет"; else bad "exit $RCP на исправном тексте"; fi
OUT=$(python3 "$V" --core "$TMP/doc.md" 2>&1); RC=$?
has "статус без бэктиков проверяется" "docs/absent.md"
if [ "$RC" -eq 1 ]; then ok "путь без бэктиков роняет прогон"; else bad "exit $RC — статус молча зелёный"; fi
# существующий путь без бэктиков ложной ошибки не даёт
mkdir -p "$TMP/docs" && printf 'x\n' > "$TMP/docs/present.md"
printf -- 'Утверждение [подтверждено — docs/present.md] тут.\n' > "$TMP/doc2.md"
OUT=$(python3 "$V" --core "$TMP/doc2.md" 2>&1); RC=$?
if echo "$OUT" | grep -q "ССЫЛКИ СТАТУСОВ"; then bad "ложная ошибка на существующем пути без бэктиков"; else ok "существующий путь без бэктиков — не ошибка"; fi
if [ "$RC" -eq 0 ]; then ok "существующий путь не роняет прогон"; else bad "exit $RC на исправном статусе"; fi
rm -rf "$TMP"

echo "── Токен статуса — чужой ввод: ни зависания, ни разведки чужой ФС ──"
# Путь внутри [подтверждено — …] приходит из ТЕКСТА заметки, а стандарт рассчитан
# на заимствование чужих заметок. Без экранирования глоб-метасимволы раскрываются по всей
# файловой системе (прогон не заканчивался минутами), а абсолютный путь работал
# как оракул: существующий молчал, выдуманный ругался.
# Прогон под таймаутом: иначе поломка повесила бы сам смоук-тест.
run_limited() {
  local lim="$1"; shift
  python3 - "$lim" "$@" <<'PY'
import subprocess, sys
lim = float(sys.argv[1]); cmd = sys.argv[2:]
try:
    # Кодировка названа явно, а не взята у локали: `text=True` — тот самый идиом,
    # из-за которого отчёт прогона терялся целиком на машине с русской локалью.
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", timeout=lim)
    print(p.stdout, end="")
    sys.exit(p.returncode)
except subprocess.TimeoutExpired:
    print("ТАЙМАУТ-ПРОГОНА")
    sys.exit(99)
PY
}
TMP=$(mktemp -d)
printf 'Факт [подтверждено — `/*/*/*/*/*/*/*/*/nope.md`].\n' > "$TMP/bomb.md"
OUT=$(run_limited 15 python3 "$V" --core "$TMP/bomb.md"); RC=$?
if [ "$RC" -eq 99 ]; then bad "глоб в токене вешает прогон"; else ok "глоб в токене не вешает прогон"; fi
has "глоб-токен объявлен несуществующим" "ССЫЛКИ СТАТУСОВ"
# оракул: существующий абсолютный путь обязан быть неотличим от выдуманного
printf 'Факт [подтверждено — `/etc/passwd`].\n' > "$TMP/abs1.md"
printf 'Факт [подтверждено — `/etc/definitely-not-here-xyz.md`].\n' > "$TMP/abs2.md"
O1=$(run_limited 15 python3 "$V" --core "$TMP/abs1.md" | grep -c "ССЫЛКИ СТАТУСОВ")
O2=$(run_limited 15 python3 "$V" --core "$TMP/abs2.md" | grep -c "ССЫЛКИ СТАТУСОВ")
if [ "$O1" = "$O2" ]; then ok "абсолютный путь не работает оракулом чужой ФС"; else bad "по выводу видно, есть ли файл на чужой машине"; fi
printf 'Факт [подтверждено — `../../../../etc/passwd`].\n' > "$TMP/up.md"
OUT=$(run_limited 15 python3 "$V" --core "$TMP/up.md")
has "выход вверх (..) не резолвится" "ССЫЛКИ СТАТУСОВ"
# ОТНОСИТЕЛЬНЫЙ глоб: страж абсолютных путей его не отсекает, значит эта фикстура
# проверяет именно экранирование. Без неё поломка `glob.escape` прошла бы молча —
# бомба выше абсолютная, и её ловил другой страж.
printf -- 'Факт [подтверждено — `*/*/*/*/*/*/*/*/nope.md`].\n' > "$TMP/relbomb.md"
OUT=$(run_limited 15 python3 "$V" --core "$TMP/relbomb.md"); RC=$?
if [ "$RC" -eq 99 ]; then bad "относительный глоб вешает прогон (экранирование снято?)"; else ok "относительный глоб экранируется"; fi
has "относительный глоб-токен объявлен несуществующим" "ССЫЛКИ СТАТУСОВ"
rm -rf "$TMP"

echo "── Файл не в UTF-8: сообщение, а не трейсбек ──"
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Кривой]]\n' > "$TMP/00-index.md"
python3 -c "import sys; open(sys.argv[1],'wb').write('---\ntitle: Кривой\ntype: concept\nschema_version: \"1.0\"\n---\n'.encode('utf-8') + b'\xff\xfe \x80\x81\n')" "$TMP/Кривой.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "Traceback"; then bad "прогон упал трейсбеком на файле в чужой кодировке"; else ok "не-UTF-8 не роняет прогон"; fi
has "кодировка названа в отчёте" "не в UTF-8"
if [ "$RC" -eq 1 ]; then ok "битая кодировка — ошибка базы"; else bad "exit $RC"; fi
rm -rf "$TMP"

echo "── Нечитаемый файл: сообщение, а не трейсбек ──"
# Тот же класс, что битая кодировка: один файл не должен отменять прогон.
# § 8.1: «отказ в доступе — это „не проверено“, а не „чисто“» — значит ошибка.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[Закрытая]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: Закрытая\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/Закрытая.md"
chmod 000 "$TMP/Закрытая.md"
ln -s "$TMP/nowhere-zzz.md" "$TMP/Битый симлинк.md"
mkdir -p "$TMP/Каталог.md"
OUT=$(python3 "$V" "$TMP" 2>&1); RC=$?
if echo "$OUT" | grep -q "Traceback"; then bad "прогон упал трейсбеком на нечитаемом файле"; else ok "нечитаемый файл не роняет прогон"; fi
has "нечитаемый файл назван непроверенным" "не прочитан"
if [ "$RC" -eq 1 ]; then ok "непрочитанный файл — ошибка, а не тишина"; else bad "exit $RC"; fi
chmod 644 "$TMP/Закрытая.md" 2>/dev/null
# FIFO и символьное устройство не ОШИБАЮТСЯ при открытии — они блокируются
# навсегда: прогон висит без вывода и без кода выхода. Зависание хуже отказа.
mkfifo "$TMP/Труба.md" 2>/dev/null && {
  OUT=$(run_limited 15 python3 "$V" "$TMP"); RCF=$?
  if [ "$RCF" -eq 99 ]; then bad "FIFO вешает прогон навсегда"; else ok "FIFO не вешает прогон"; fi
  has "не обычный файл назван" "не обычный файл"
}
rm -rf "$TMP"

echo

echo "── Слой доверия: атаки, дающие ложный зелёный ──"
TMP=$(mktemp -d)
idx() { printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n%s\n' "$2" > "$1/00-index.md"; }

mkdir -p "$TMP/phantom"; idx "$TMP/phantom" "- [[Факт]]"
printf -- '---\ntitle: Факт\ntype: knowledge\nschema_version: "1.0"\nsources: ["Smith 2021, JAMA", "Lee 2022, Lancet"]\nconsensus: confirmed\n---\nx\n' > "$TMP/phantom/Факт.md"
OUT=$(python3 "$V" "$TMP/phantom" 2>&1); RC=$?
has "17б выдуманный источник — ошибка" "не ведёт ни в одну заметку базы"
if [ "$RC" -eq 1 ]; then ok "17б роняет прогон"; else bad "exit $RC: confirmed на выдумке зеленеет"; fi

mkdir -p "$TMP/twoname"; idx "$TMP/twoname" "- [[Факт]]\n- [[И1]]"
printf -- '---\ntitle: Факт\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[Иванов 2019]]", "[[И1]]"]\nconsensus: confirmed\n---\nx [[И1]]\n' > "$TMP/twoname/Факт.md"
printf -- '---\ntitle: Иванов 2019\ntype: source\nschema_version: "1.0"\nreliability: A\n---\nx\n' > "$TMP/twoname/И1.md"
OUT=$(python3 "$V" "$TMP/twoname" 2>&1); RC=$?
has "5в один файл ≠ два корня" "КОНСЕНСУС"
if [ "$RC" -eq 1 ]; then ok "5в роняет прогон"; else bad "exit $RC: прачечная из одного файла зеленеет"; fi

# 5г/5д. Зависимость ЗАЯВЛЕНА честно, но источник и группа `same_root` названы РАЗНЫМИ
# законными именами одной заметки (заголовок и alias). Строки не совпадали — группа не
# связывалась — confirmed проходил на одном корне. Обход бил в единственную машину слоя
# доверия и обходился не подлогом, а вторым законным именем. § 5.4 снимает с машины
# только НЕзаявленную зависимость; эта заявлена, значит это была дыра, а не граница.
#
# Случаев ДВА, и одной фикстурой они не проверяются. Канон нужен и на `sources`, и на
# группах, а фикстура ловит только тот, чьё имя разошлось с именем файла. Если alias
# стоит лишь в `sources`, группа совпадёт с базой файла и без канона — тест зеленеет
# на невылеченном коде. Поэтому фикстур две.
aliasfix() { # $1 — имя папки, $2 — как назван источник в sources, $3 — как в same_root
  mkdir -p "$TMP/$1"; idx "$TMP/$1" "- [[Факт]]\n- [[Обзор]]\n- [[Практик]]"
  printf -- '---\ntitle: Факт\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[Практик]]", "[[%s]]"]\nsame_root: [["[[Практик]]", "[[%s]]"]]\nconsensus: confirmed\n---\nx\n' "$2" "$3" > "$TMP/$1/Факт.md"
  printf -- '---\ntitle: Обзор\naliases: ["Обзор 2019 (кратко)"]\ntype: source\nschema_version: "1.0"\nreliability: A\n---\nx [[Факт]]\n' > "$TMP/$1/Обзор.md"
  printf -- '---\ntitle: Практик\ntype: source\nschema_version: "1.0"\nreliability: C\n---\nx [[Факт]]\n' > "$TMP/$1/Практик.md"
}
aliasfix aliasgrp1 "Обзор 2019 (кратко)" "Обзор"
OUT=$(python3 "$V" "$TMP/aliasgrp1" 2>&1); RC=$?
has "5г алиас в sources, заголовок в same_root" "КОНСЕНСУС"
if [ "$RC" -eq 1 ]; then ok "5г роняет прогон"; else bad "exit $RC: прачечная через алиас в sources зеленеет"; fi

aliasfix aliasgrp2 "Обзор" "Обзор 2019 (кратко)"
OUT=$(python3 "$V" "$TMP/aliasgrp2" 2>&1); RC=$?
has "5д заголовок в sources, алиас в same_root" "КОНСЕНСУС"
if [ "$RC" -eq 1 ]; then ok "5д роняет прогон"; else bad "exit $RC: прачечная через алиас в группе зеленеет"; fi

# 5д. root_id в другом регистре — та же работа, а корня было два. Пробел проверка
# нормализовала, регистр нет; имена заметок при этом нормализуются регистронезависимо.
# Половина анти-прачечной нормализации была сделана, половина нет.
mkdir -p "$TMP/ridcase"; idx "$TMP/ridcase" "- [[Факт]]\n- [[И1]]\n- [[И2]]"
printf -- '---\ntitle: Факт\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]", "[[И2]]"]\nconsensus: confirmed\n---\nx\n' > "$TMP/ridcase/Факт.md"
printf -- '---\ntitle: И1\ntype: source\nschema_version: "1.0"\nreliability: A\nroot_id: ["reg-2024-017"]\n---\nx [[Факт]]\n' > "$TMP/ridcase/И1.md"
printf -- '---\ntitle: И2\ntype: source\nschema_version: "1.0"\nreliability: A\nroot_id: ["Reg-2024-017"]\n---\nx [[Факт]]\n' > "$TMP/ridcase/И2.md"
OUT=$(python3 "$V" "$TMP/ridcase" 2>&1); RC=$?
has "5е root_id в разном регистре — один корень" "КОНСЕНСУС"
if [ "$RC" -eq 1 ]; then ok "5е роняет прогон"; else bad "exit $RC: регистр root_id разводит корни надвое"; fi

mkdir -p "$TMP/dupkey"; idx "$TMP/dupkey" "- [[Факт]]\n- [[И1]]"
printf -- '---\ntitle: Факт\ntype: knowledge\nschema_version: "1.0"\nconsensus: confirmed\nsources: ["[[И1]]"]\nconsensus: single\n---\nx\n' > "$TMP/dupkey/Факт.md"
printf -- '---\ntitle: И1\ntype: source\nschema_version: "1.0"\n---\nx\n' > "$TMP/dupkey/И1.md"
OUT=$(python3 "$V" "$TMP/dupkey" 2>&1); RC=$?
has "4з дубль ключа frontmatter" "объявлен дважды"
if [ "$RC" -eq 1 ]; then ok "4з роняет прогон"; else bad "exit $RC: дубль ключа зеленеет"; fi

mkdir -p "$TMP/quoted"; idx "$TMP/quoted" "- [[Голое знание]]"
printf -- '---\ntitle: Голое знание\n"type": knowledge\nschema_version: "1.0"\n---\nбез источников\n' > "$TMP/quoted/Голое знание.md"
OUT=$(python3 "$V" "$TMP/quoted" 2>&1); RC=$?
has "4и type в кавычках не снимает провенанс" "без sources"
if [ "$RC" -eq 1 ]; then ok "4и роняет прогон"; else bad "exit $RC: знание без источника зеленеет"; fi

mkdir -p "$TMP/nfd"; idx "$TMP/nfd" "- [[A]]\n- [[B]]"
python3 - "$TMP/nfd" <<'PYX'
import sys, unicodedata, pathlib
d = pathlib.Path(sys.argv[1]); T = "Настройка Xray"; N = unicodedata.normalize("NFD", T)
for f, t, body in (("A.md", T, "Порт 1080"), ("B.md", N, "Порт 1081")):
    (d / f).write_text(f'---\ntitle: {t}\ntype: concept\nschema_version: "1.0"\n---\n{body}\n', encoding="utf-8")
PYX
OUT=$(python3 "$V" "$TMP/nfd" 2>&1); RC=$?
has "1б юникод-дубль имени" "ДУБЛИ-СУЩНОСТИ"
if [ "$RC" -eq 1 ]; then ok "1б роняет прогон"; else bad "exit $RC: два дома под одним именем зеленеют"; fi

mkdir -p "$TMP/island"; idx "$TMP/island" "- [[Живая]]"
printf -- '---\ntitle: Живая\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/island/Живая.md"
printf -- '---\ntitle: Тайная А\ntype: concept\nschema_version: "1.0"\n---\n[[Тайная Б]]\n' > "$TMP/island/Тайная А.md"
printf -- '---\ntitle: Тайная Б\ntype: concept\nschema_version: "1.0"\n---\n[[Тайная А]]\n' > "$TMP/island/Тайная Б.md"
OUT=$(python3 "$V" "$TMP/island" 2>&1); RC=$?
has "21 недостижимый кластер" "НЕДОСТИЖИМЫЕ ОТ ИНДЕКСА"
if [ "$RC" -eq 1 ]; then ok "21 роняет прогон"; else bad "exit $RC: остров зеленеет"; fi
OUT=$(python3 "$V" fixtures/clean/knowledge 2>&1)
if echo "$OUT" | grep -q "НЕДОСТИЖИМЫЕ"; then bad "21 ложно срабатывает на чистой базе"; else ok "21 молчит на достижимой базе"; fi
# Регистр имени индекса: вход в проверку регистронезависим (как у 15), обход обязан
# стартовать с ТОГО ЖЕ файла, иначе достижимая база объявляется недостижимой.
mkdir -p "$TMP/upper"
printf -- '---\ntitle: 00-Index\ntype: moc\nschema_version: "1.0"\n---\n- [[A]]\n' > "$TMP/upper/00-Index.md"
printf -- '---\ntitle: A\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/upper/A.md"
OUT=$(python3 "$V" "$TMP/upper" 2>&1); RC=$?
if echo "$OUT" | grep -q "НЕДОСТИЖИМЫЕ"; then bad "21 ложно срабатывает при 00-Index.md"; else ok "21 не зависит от регистра имени индекса"; fi
if [ "$RC" -eq 0 ]; then ok "база с 00-Index.md зеленеет"; else bad "exit $RC на достижимой базе"; fi
# Согласование числительных: отчёт читает человек.
has "число заметок склоняется" "📊 База: 2 заметки"
# Регистр имени индекса — один класс на четыре проверки (3, 13, 15, 21).
# Проверка 3: индекс с заглавной не должен объявляться сиротой.
mkdir -p "$TMP/upper2"
printf -- '---\ntitle: 00-Index\ntype: concept\nschema_version: "1.0"\n---\n- [[A]]\n' > "$TMP/upper2/00-Index.md"
printf -- '---\ntitle: A\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/upper2/A.md"
OUT=$(python3 "$V" "$TMP/upper2" 2>&1)
if echo "$OUT" | grep -q "СИРОТЫ"; then bad "3 объявляет 00-Index.md сиротой"; else ok "3 не зависит от регистра имени индекса"; fi
# Проверка 13: потолок обязан меряться и у 00-Index.md.
OUT=$(python3 "$V" "$TMP/upper2" --index-limit-kb 0.05 2>&1)
has "13 не зависит от регистра имени индекса" "ИНДЕКС ПЕРЕРОС ПОТОЛОК"

echo "── Устойчивость: чужая база не должна вешать инструмент ──"
mkdir -p "$TMP/loop"; idx "$TMP/loop" "x"; ln -s . "$TMP/loop/a"; ln -s . "$TMP/loop/b"
S=$(date +%s); OUT=$(python3 "$V" "$TMP/loop" 2>&1); E=$(date +%s)
if [ $((E-S)) -le 10 ]; then ok "симлинк-петля не вешает прогон ($((E-S)) с)"; else bad "прогон занял $((E-S)) с"; fi
if echo "$OUT" | grep -q "ДУБЛИ-СУЩНОСТИ"; then bad "петля даёт ложные дубли"; else ok "петля не порождает ложных дублей"; fi

mkdir -p "$TMP/deep"; idx "$TMP/deep" "x"
python3 -c "
import sys; d=sys.argv[1]
open(d+'/x.md','w',encoding='utf-8').write('---\ntitle: D\ntype: concept\nschema_version: \"1.0\"\ndeep: '+'['*3000+']'*3000+'\n---\nx\n')" "$TMP/deep"
OUT=$(python3 "$V" "$TMP/deep" 2>&1)
if echo "$OUT" | grep -q "Traceback"; then bad "аномальная вложенность роняет трейсбеком"; else ok "аномальная вложенность — сообщение, не трейсбек"; fi
has "вложенность названа поимённо" "вложен слишком глубоко"

echo "── Проверки, у которых легко остаться без покрытия ──"
mkdir -p "$TMP/nokeys"; idx "$TMP/nokeys" "- [[Безключа]]"
printf -- '---\ntitle: Безключа\n---\nни type, ни schema_version\n' > "$TMP/nokeys/Безключа.md"
OUT=$(python3 "$V" "$TMP/nokeys" 2>&1); RC=$?
has "4а нет обязательного ключа type" 'нет обязательного ключа `type`'
has "4а нет обязательного ключа schema_version" 'нет обязательного ключа `schema_version`'
if [ "$RC" -eq 1 ]; then ok "4а роняет прогон"; else bad "exit $RC"; fi

mkdir -p "$TMP/noasof"; idx "$TMP/noasof" "- [[Безсрока]]"
printf -- '---\ntitle: Безсрока\ntype: concept\nschema_version: "1.0"\ntemporal: true\n---\nx\n' > "$TMP/noasof/Безсрока.md"
OUT=$(python3 "$V" "$TMP/noasof" 2>&1)
has "9б temporal без as_of назван" "без as_of"
printf -- '---\ntitle: Безсрока\ntype: concept\nschema_version: "1.0"\ntemporal: True\n---\nx\n' > "$TMP/noasof/Безсрока.md"
OUT=$(python3 "$V" "$TMP/noasof" 2>&1)
has "9б temporal: True не теряется" "без as_of"

mkdir -p "$TMP/denied"; idx "$TMP/denied" "- [[Закрытая]]"
printf -- '---\ntitle: Закрытая\ntype: concept\nschema_version: "1.0"\n---\nx\n' > "$TMP/denied/Закрытая.md"
chmod 000 "$TMP/denied/Закрытая.md"
OUT=$(python3 "$V" "$TMP/denied" 2>&1); RC=$?
chmod 644 "$TMP/denied/Закрытая.md"
if [ "$(id -u)" -eq 0 ]; then ok "4е пропущен: запуск от root"; else
  has "4е отказ в доступе назван непроверенным" "считается непроверенным"
  if [ "$RC" -eq 1 ]; then ok "4е непрочитанный файл — ошибка"; else bad "exit $RC: отказ в доступе прошёл как чисто"; fi
fi
rm -rf "$TMP"

echo "── Автопрогон валидатора после записи (PostToolUse-хук) ──"
# § 11 п. 12 требует прогон после каждого ввода знания — требование к модели, то есть
# «если не отвлеклась». Проверяется, что код делает это за неё и что зелёный молчит.
KIT="$(cd ../.. && pwd)"     # дом обоих помощников — здесь: ниже они используются всеми хуками
ctx() { python3 -c "
import sys, json
raw = sys.stdin.read().strip()
sys.stdout.write(json.loads(raw)['hookSpecificOutput']['additionalContext'] if raw else '')"; }
TVW="$(mktemp -d)"
mkdir -p "$TVW/knowledge"
cp fixtures/clean/knowledge/*.md "$TVW/knowledge/" 2>/dev/null
printf 'validate:\n  command: python3 %s/standard/validate.py knowledge\n' "$KIT" > "$TVW/config.yaml"
# Заметка без frontmatter: база заведомо красная, значит молчание может быть только
# от ворот, а не от «нечего сказать». Без этой предпосылки тест ворот ложно-зелёный:
# молчание на чистой базе ничего не доказывает.
printf 'черновик\n' > "$TVW/knowledge/Битая.md"
vw() { printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "${1}" "$TVW" "${2}" \
       | (cd "$TVW" && CLAUDE_PROJECT_DIR="$TVW" python3 "$KIT/hooks/validate-on-write.py"); }

OUT=$(vw Write "$TVW/knowledge/Битая.md"); RC=$?
if [ -z "$OUT" ]; then ok "валидатор-хук: без метки молчит, хотя база красная"; else bad "валидатор-хук: сработал в проекте без метки"; fi
if [ "$RC" -eq 0 ]; then ok "валидатор-хук: код выхода 0 без метки"; else bad "валидатор-хук: код выхода $RC помешает работе"; fi

printf 'имя: тест\n' > "$TVW/.loreground"
OUT=$(vw Write "$TVW/knowledge/Битая.md" | ctx)
has "валидатор-хук: красная база доложена" "найдены проблемы"
has "валидатор-хук: отчёт валидатора приехал целиком" "FRONTMATTER"

OUT=$(vw Read "$TVW/knowledge/Битая.md")
if [ -z "$OUT" ]; then ok "валидатор-хук: на чтение не реагирует"; else bad "валидатор-хук: сработал на Read"; fi

OUT=$(vw Write "$TVW/knowledge/Битая.txt")
if [ -z "$OUT" ]; then ok "валидатор-хук: не-md не проверяется"; else bad "валидатор-хук: сработал на не-md"; fi

OUT=$(vw Write "$TVW/просто-файл.md")
if [ -z "$OUT" ]; then ok "валидатор-хук: файл вне базы не запускает прогон"; else bad "валидатор-хук: прогнал базу из-за файла вне неё"; fi

rm -f "$TVW/knowledge/Битая.md"
OUT=$(vw Write "$TVW/knowledge/00-index.md")
if [ -z "$OUT" ]; then ok "валидатор-хук: зелёный прогон молчит"; else bad "валидатор-хук: шумит на чистой базе"; fi
printf 'черновик\n' > "$TVW/knowledge/Битая.md"

# Код 2 обязан звучать иначе, чем «чисто»: это главный класс ошибок проекта.
printf 'validate:\n  command: python3 %s/standard/validate.py нет-такой-папки\n' "$KIT" > "$TVW/config.yaml"
OUT=$(vw Write "$TVW/knowledge/Битая.md" | ctx); has "валидатор-хук: код 2 назван «не состоялся»" "НЕ СОСТОЯЛСЯ"

printf 'validate:\n  command: заведомо-нет-такой-команды knowledge\n' > "$TVW/config.yaml"
OUT=$(vw Write "$TVW/knowledge/Битая.md" | ctx); has "валидатор-хук: отсутствие команды названо" "не найдена"

printf "validate:\n  command: 'lore-validate \"knowledge'\n" > "$TVW/config.yaml"
OUT=$(vw Write "$TVW/knowledge/Битая.md" | ctx); has "валидатор-хук: неразбираемая команда названа" "не разбирается"

# «Команда есть, но не запускается» — не то же, что «команды нет»: ОС отвечает
# PermissionError, а он ловился общим перехватом внизу файла и означал тишину,
# неотличимую от зелёного прогона. Случай бытовой: базу скопировали без бита +x.
printf '#!/usr/bin/env python3\nimport sys; sys.exit(1)\n' > "$TVW/невыполнимый.py"
chmod -x "$TVW/невыполнимый.py"
printf 'validate:\n  command: ./невыполнимый.py knowledge\n' > "$TVW/config.yaml"
OUT=$(vw Write "$TVW/knowledge/Битая.md" | ctx)
has "валидатор-хук: неисполнимая команда названа" "не запустилась"
has "валидатор-хук: неисполнимая команда — это не «чисто»" "не состоялся"

# Без PyYAML прогон не состоится НИКОГДА, а стартовый хук говорит только про паспорт.
# Молчание тут означало бы, что проверка записи мертва и об этом никто не узнает.
NOY="$(mktemp -d)"; printf 'raise ImportError("нет yaml")\n' > "$NOY/yaml.py"
printf 'validate:\n  command: python3 %s/standard/validate.py knowledge\n' "$KIT" > "$TVW/config.yaml"
OUT=$(PYTHONPATH="$NOY" vw Write "$TVW/knowledge/Битая.md" | ctx)
has "валидатор-хук: отсутствие PyYAML названо" "PyYAML не установлен"
has "валидатор-хук: без PyYAML проверка объявлена невыполненной" "НЕ выполнена"
has "валидатор-хук: назван интерпретатор, в который ставить" "$SELF -m pip install pyyaml"
rm -rf "$NOY"

# Два РАЗНЫХ пути к молчанию, и оба надо пройти: без файла конфига выход происходит
# раньше, чем проверка пустой команды: на первом случае исполнение до этой ветки не
# доходит, и проверять её надо отдельным входом.
printf 'validate:\n  trust_layer: true\n' > "$TVW/config.yaml"
OUT=$(vw Write "$TVW/knowledge/Битая.md" | ctx)
# Две половины одного требования, и обе обязательны. Команду хук не придумывает (§ 9.3
# п. 7: у комплектации прогона один дом), но и молчать не вправе: его молчание значит
# «чисто», и без строки в контексте автопрогон был мёртв, а выглядел работающим.
has "валидатор-хук: отсутствие команды прогона названо" "нет строки validate.command"
has "валидатор-хук: сказано, что это не «чисто»" "не «чисто»"
if echo "$OUT" | grep -qF "FRONTMATTER"; then
  bad "валидатор-хук: придумал команду сам — прогон состоялся без строки в конфиге"; else
  ok "валидатор-хук: команды не придумывает, только называет её отсутствие"; fi

rm -f "$TVW/config.yaml"
OUT=$(vw Write "$TVW/knowledge/Битая.md")
if [ -z "$OUT" ]; then ok "валидатор-хук: без config.yaml молчит"; else bad "валидатор-хук: заговорил без конфига"; fi
rm -rf "$TVW"

echo "── Автопрогон на команде ИЗ ИНСТРУКЦИИ, а не выдуманной тестом ──"
# Тут жила самая дорогая поломка комплекта, и прожила она до пользователя ровно потому,
# что тесты выше гоняют СВОЮ короткую команду (`validate.py knowledge`), которой нет ни в
# одной инструкции. Хук угадывает папку базы по словам команды и до 0.27.0 брал последнее
# слово без дефиса — а в канонической команде режима «копия» последним стоит значение
# флага: `knowledge --core standard`. Хук объявлял базой `standard/`, запись в `knowledge/`
# считал не своим делом и молчал — а молчание хука по его же дизайну значит «чисто».
# Автопрогон был мёртв у КАЖДОГО, кто взял команду из документации.
#
# Поэтому команда берётся из шаблона конфига в самом навыке сборки — тем же приёмом, что
# в тесте навыка разбора ниже: переписанная сюда копия разошлась бы с оригиналом при
# первой правке, и тест снова проверял бы не то, чем пользуются люди.
DOC_CMD=$(sed -n 's/^ *command: *//p' ../../skills/init/SKILL.md | head -1)
if [ -n "$DOC_CMD" ]; then ok "автопрогон: команда найдена в skills/init/SKILL.md — «${DOC_CMD}»"; else
  bad "автопрогон: в SKILL.md не найдена строка command: — тест проверяет пустоту"; fi
case "$DOC_CMD" in
  *" --"*) ok "автопрогон: в команде из инструкции есть флаг — угадывание папки испытывается" ;;
  *) bad "автопрогон: в команде из инструкции пропали флаги — тест выродился в прежний" ;;
esac

TDC="$(mktemp -d)"; mkdir -p "$TDC/knowledge" "$TDC/standard"
cp ../validate.py ../core.md "$TDC/standard/"   # режим «копия»: комплект ядра лежит у агента
# `core.md` здесь не для красоты: комплект «Копия» (§ 9.3) обязан его нести, и без него
# команде `--core standard` проверять нечего. Стенд с одним `validate.py` изображал бы
# недособранного агента — то есть проверял бы не тот случай, что у людей.
printf 'имя: тест\n' > "$TDC/.loreground"
printf 'validate:\n  command: %s\n' "$DOC_CMD" > "$TDC/config.yaml"
printf 'черновик\n' > "$TDC/knowledge/Битая.md"   # база заведомо красная: молчать не о чем
OUT=$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' \
        "$TDC" "$TDC/knowledge/Битая.md" \
      | (cd "$TDC" && CLAUDE_PROJECT_DIR="$TDC" python3 "$KIT/hooks/validate-on-write.py") | ctx)
has "автопрогон: на команде из инструкции хук ЗАГОВОРИЛ" "найдены проблемы"
has "автопрогон: отчёт приехал целиком" "FRONTMATTER"

# Обратная сторона того же: расширенное распознавание не должно гонять базу из-за файла,
# который к ней не относится. Иначе починка тишины куплена шумом на каждой правке.
mkdir -p "$TDC/my"
OUT=$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' \
        "$TDC" "$TDC/my/личное.md" \
      | (cd "$TDC" && CLAUDE_PROJECT_DIR="$TDC" python3 "$KIT/hooks/validate-on-write.py"))
if [ -z "$OUT" ]; then ok "автопрогон: файл вне названных папок прогон не запускает"; else
  bad "автопрогон: прогнал базу из-за файла, которого в ней нет"; fi

# Остаточные пути к тишине — те, что оставались после первой правки. Общее у всех одно:
# распозналось ТОЛЬКО значение флага, а сама база в команде не названа или названа не так,
# как лежит на диске, — и запасной выход «не распозналось, прогоняем» глушился значением
# флага. Первая редакция правки на всех четырёх молчала, то есть чинила один вход в
# тишину из пяти. Во всех случаях ниже хук обязан ЗАГОВОРИТЬ.
vwd() {   # $1 — команда прогона в config.yaml; печатает то, что хук положил в контекст
  printf 'validate:\n  command: %s\n' "$1" > "$TDC/config.yaml"
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "$TDC" "$TDC/knowledge/Битая.md" \
    | (cd "$TDC" && CLAUDE_PROJECT_DIR="$TDC" python3 "$KIT/hooks/validate-on-write.py") | ctx
}
say() { if [ -n "$1" ]; then ok "$2"; else bad "$2 — хук промолчал, а молчание значит «чисто»"; fi; }

say "$(vwd 'python3 standard/validate.py --core standard')" \
    "автопрогон: база не названа (умолчание валидатора) — прогон всё равно идёт"
say "$(vwd 'python3 standard/validate.py kknowledge --core standard')" \
    "автопрогон: опечатка в имени базы не глушит хук"
say "$(vwd 'python3 standard/validate.py Knowledge --core standard')" \
    "автопрогон: регистр имени базы не глушит хук (ФС его не различает, строки различают)"
chmod +x "$TDC/standard/validate.py"
say "$(vwd './standard/validate.py knowledge --core standard')" \
    "автопрогон: команда без интерпретатора впереди распознаётся так же"

# Чужой код выхода — не «найдены проблемы». У валидатора исходов три (§ 10); 127 приходит
# от оболочки, отрицательное — от сигнала. Прежде любой такой ответ объявлялся находкой
# в базе, и агента отправляли чинить базу, которую никто не проверял.
printf '#!/usr/bin/env bash\nexec заведомо-нет-такого-интерпретатора "$@"\n' > "$TDC/обёртка.sh"
chmod +x "$TDC/обёртка.sh"
OUT=$(vwd './обёртка.sh knowledge')
has "автопрогон: чужой код выхода не назван «найденными проблемами»" "такого исхода у валидатора нет"
if echo "$OUT" | grep -qF "найдены проблемы (код"; then
  bad "автопрогон: чужой код выхода выдан за находки в базе"; else
  ok "автопрогон: вердикт «найдены проблемы (код …)» на чужой код не выносится"; fi
rm -rf "$TDC"

echo "── Консоль не в UTF-8: прогон не падает и не врёт кодом ──"
# Windows-консоль работает в cp1251, и первая же строка отчёта (📊) роняла прогон
# UnicodeEncodeError'ом — ДО единой выполненной проверки. Python отдавал при этом код 1,
# то есть «в базе найдены проблемы»: невыполненная проверка представлялась находкой.
# Чинится обработкой непечатаемого, а НЕ подменой кодировки на utf-8: подмена превратила
# бы в кракозябры весь русский текст отчёта, а он весь русский.
OUT=$(PYTHONIOENCODING=cp1251 python3 ../validate.py fixtures/clean/knowledge 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then ok "не-UTF-8 консоль: чистая база даёт 0, а не падение"; else
  bad "не-UTF-8 консоль: чистая база дала код $RC — прогон сорвался"; fi
if echo "$OUT" | grep -qF "UnicodeEncodeError"; then
  bad "не-UTF-8 консоль: прогон упал на кодировке вывода"; else
  ok "не-UTF-8 консоль: UnicodeEncodeError не случился"; fi
# Текст обязан остаться читаемым: значки теряются, слова — нет.
# `iconv` проверяется отдельно: без него эта проверка краснела бы словами «текст нечитаем»
# и посылала чинить кодировку вместо того, чтобы сказать «проверить нечем» (§ 10.1 в лицах).
if ! command -v iconv >/dev/null 2>&1; then
  bad "не-UTF-8 консоль: нет iconv — читаемость русского текста ПРОВЕРИТЬ НЕЧЕМ (это не «ок»)"
elif echo "$OUT" | iconv -f cp1251 -t utf-8 2>/dev/null | grep -qF "Ошибок нет"; then
  ok "не-UTF-8 консоль: русский текст отчёта читаем"; else
  bad "не-UTF-8 консоль: русский текст отчёта нечитаем — подменена кодировка, а не обработка"; fi

OUT=$(PYTHONIOENCODING=cp1251 python3 ../validate.py fixtures/broken/knowledge 2>&1); RC=$?
if [ "$RC" -eq 1 ]; then ok "не-UTF-8 консоль: ломаная база даёт 1 — вердикт настоящий"; else
  bad "не-UTF-8 консоль: ломаная база дала код $RC вместо 1"; fi

echo "── Хуки при чужой локали: говорят UTF-8 и не теряют отчёт ──"
# Раздел выше — про валидатор на КОНСОЛИ. Здесь другая сторона: хуки и то, что они
# отдают хозяину сессии. По отчёту с русской Windows (локаль cp1251) обе стороны разговора
# брали кодировку у системы, и обе ошибались.
#   • Хуки печатали JSON в `sys.stdout` как есть: байты уезжали в cp1251, а читающая
#     сторона ждёт UTF-8.
#   • Автопрогон читал ответ валидатора через `text=True`, то есть тоже по локали. Ответ
#     приходил в UTF-8, расшифровка падала внутри чтения, и отчёт пропадал ЦЕЛИКОМ —
#     а шапка «найдены проблемы, чини сейчас» оставалась. Худший из возможных исходов:
#     содержания нет, а выглядит содержательным.
# Локаль подменяется переменной окружения — стенда на русской Windows у нас нет, и
# «работает на Windows» этим не доказывается: доказывается, что кодировка больше не
# берётся у системы ни с одной из двух сторон.
TEN="$(mktemp -d)"; mkdir -p "$TEN/knowledge" "$TEN/standard" "$TEN/hooks"
cp ../validate.py ../core.md "$TEN/standard/"   # комплект «Копия» несёт и стандарт (§ 9.3)
printf 'имя: тест\n' > "$TEN/.loreground"
printf 'validate:\n  command: python3 standard/validate.py knowledge --core standard\n' > "$TEN/config.yaml"
printf 'черновик\n' > "$TEN/knowledge/Битая.md"   # база заведомо красная: молчать не о чем
utf8ok() {   # $1 — файл с байтами вывода; печатает ДА / НЕТ / ПУСТО
  python3 -c "
import sys
d = open(sys.argv[1], 'rb').read()
if not d: print('ПУСТО'); raise SystemExit
try:
    d.decode('utf-8'); print('ДА')
except UnicodeDecodeError: print('НЕТ')" "$1"
}
ctxf() {   # $1 — файл с выводом хука; печатает то, что хук положил в контекст
  python3 -c "
import json, sys
print(json.load(open(sys.argv[1], encoding='utf-8'))['hookSpecificOutput']['additionalContext'])" "$1"
}

# 1. Перебор ВСЕХ хуков папки, список — с диска: имена, набранные по памяти, не растут
# вместе с папкой. Заговорить каждого заставляем его же поломкой: ответ на неё идёт через
# ту же единственную печать, что и штатные сообщения (hooks/_out.py).
HOOKS_E=$(ls "$KIT"/hooks/*.py | xargs -n1 basename | sed 's/\.py$//' | grep -v '^_')
HOOKS_EN=$(echo "$HOOKS_E" | grep -c .)
[ "$HOOKS_EN" -gt 0 ] || bad "кодировка: в hooks/ не найдено ни одного хука — перебор пуст, а не чист"
BADENC=0; BADTXT=0
for h in $HOOKS_E; do
  cp "$KIT"/hooks/*.py "$TEN/hooks/"
  sed "s|^def main():|def main():\n    raise RuntimeError('сбой изнутри хука')|" \
    "$KIT/hooks/$h.py" > "$TEN/hooks/$h.py"
  (cd "$TEN" && echo '{}' | PYTHONIOENCODING=cp1251 CLAUDE_PROJECT_DIR="$TEN" \
     python3 "$TEN/hooks/$h.py" > "$TEN/o.bin" 2>/dev/null)
  [ "$(utf8ok "$TEN/o.bin")" = "ДА" ] || BADENC=$((BADENC+1))
  ctxf "$TEN/o.bin" 2>/dev/null | grep -qF "не отработал" || BADTXT=$((BADTXT+1))
done
if [ "$BADENC" -eq 0 ]; then ok "кодировка: все хуки папки ($HOOKS_EN) отдают UTF-8 при локали cp1251"
else bad "кодировка: $BADENC хук(ов) отдали байты не в UTF-8 — кодировка взята у системы"; fi
if [ "$BADTXT" -eq 0 ]; then ok "кодировка: русский текст при этом цел, а не потерян"
else bad "кодировка: у $BADTXT хук(ов) текст не дочитался — починка кодировки съела содержание"; fi

# 2. Структурная половина того же: печать живёт ОДНИМ домом. Пока `json.dump` стоял в
# пяти файлах, решение о кодировке копировалось вместе с ним — и неверным оказалось во
# всех пяти сразу. Новый хук со своей печатью вернул бы ровно это.
OWNJSON=$(grep -l "json\.dump" "$KIT"/hooks/*.py | grep -cv "_out\.py$")
if [ "$OWNJSON" -eq 0 ]; then ok "кодировка: печать в контекст живёт одним домом (hooks/_out.py)"
else bad "кодировка: $OWNJSON файл(ов) в hooks/ печатают JSON сами — решение о кодировке снова в копиях"; fi

# 3. Запасной выход. Кодировку потока назначить можно не всегда: под обёрткой `sys.stdout`
# бывает подменён и метода `reconfigure` не имеет. Тогда текст уходит в ASCII-escape'ы —
# некрасиво, зато побайтово совпадает с UTF-8 при любой локали. Проверяется обе половины:
# байты чистые И содержание на месте.
OUT=$(cd "$KIT/hooks" && python3 -c "
import json, sys
import _out

class Подменённый:            # поток без reconfigure — как обёртка поверх stdout
    def __init__(self): self.куски = []
    def write(self, s): self.куски.append(s)

настоящий, sys.stdout = sys.stdout, Подменённый()
_out.сказать('SessionStart', 'Проверка русского текста')
собрано = ''.join(sys.stdout.куски)
sys.stdout = настоящий
print('ТОЛЬКО-ASCII' if собрано.isascii() else 'ЕСТЬ-НЕ-ASCII')
print(json.loads(собрано)['hookSpecificOutput']['additionalContext'])")
has "кодировка: подменённый поток уводит вывод в ASCII" "ТОЛЬКО-ASCII"
has "кодировка: содержание при этом не теряется" "Проверка русского текста"

# 4. Отчёт прогона при чужой локали. Здесь жила вторая половина находки: шапка приезжала,
# тело — нет. Проверяется не «нет ошибки», а наличие самих находок в тексте.
vwe() {   # $1 — значение PYTHONIOENCODING; печатает то, что хук положил в контекст
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "$TEN" "$TEN/knowledge/Битая.md" \
    | (cd "$TEN" && PYTHONIOENCODING="$1" CLAUDE_PROJECT_DIR="$TEN" \
         python3 "$KIT/hooks/validate-on-write.py") > "$TEN/vw.bin"
  ctxf "$TEN/vw.bin"
}
OUT=$(vwe cp1251)
has "кодировка: при локали cp1251 шапка отчёта приехала" "найдены проблемы"
has "кодировка: тело отчёта приехало вместе с шапкой, а не потерялось" "FRONTMATTER"
has "кодировка: находки отчёта читаемы по-русски" "СИРОТЫ"
[ "$(utf8ok "$TEN/vw.bin")" = "ДА" ] && ok "кодировка: сам вывод автопрогона — валидный UTF-8" \
  || bad "кодировка: вывод автопрогона не в UTF-8"

# 5. Вторая сторона того же разговора: кодировку назначаем и ДОЧЕРНЕМУ процессу. Иначе
# он взял бы её у той же локали, и одностороннее «читать как UTF-8» превратило бы русский
# отчёт в мусор — починка одного входа ценой нового.
cat > "$TEN/эхо.sh" <<'SH'
#!/usr/bin/env bash
exec python3 -c 'import sys; print("кодировка вывода прогона:", sys.stdout.encoding); sys.exit(1)'
SH
chmod +x "$TEN/эхо.sh"
printf 'validate:\n  command: ./эхо.sh knowledge\n' > "$TEN/config.yaml"
OUT=$(vwe cp1251)
has "кодировка: прогону назначена кодировка вывода, а не взята у локали" "кодировка вывода прогона: utf-8"

# 6. Перебор ВСЕГО комплекта на кодировку, взятую у локали. Смотреть только хуки мало:
# класс уже жил в навыке сборки (чтение манифеста без кодировки — молчаливая потеря версии
# агента) и в этом самом файле. Дом перебора один — `enc-sweep.py` рядом; там же сказано,
# что доказывает его пустой вывод, а что нет.
ENC_HITS=$(python3 enc-sweep.py "$KIT" | grep -c . || true)
if [ "$ENC_HITS" -eq 0 ]; then ok "кодировка: во всём комплекте нет мест, где её берут у системы"
else bad "кодировка: $ENC_HITS мест(а) в комплекте берут кодировку у системы — $(python3 enc-sweep.py "$KIT" | tr '\n' '; ')"; fi

# Самопроверка перебора идёт В ОБЕ СТОРОНЫ, и это не педантизм. Проверка, которая только
# ловит, чинится ослеплением: достаточно расширить любое послабление, и она останется
# зелёной, перестав что-либо значить. Проверка, которая только молчит, чинится наоборот.
# Поэтому рядом с приманками лежат ЧЕСТНЫЕ файлы, и красный на них — такой же провал:
# страж, шумящий на исправном коде и на собственной документации, будет выключен человеком,
# и правильно сделает.
#
# Приманки собираются подстановкой: этот файл входит в перебор наравне с остальными, и
# форма, записанная тут буквально, красила бы проверку собственным текстом.
ENCSEED="$TEN/подсадка"; rm -rf "$ENCSEED"; mkdir -p "$ENCSEED/fixtures"
S_O=open; S_R=run; S_P=popen; S_RT=read_text; S_CP=ConfigParser; S_GO=getoutput
# ── приманки: каждая обязана быть поймана ──
printf 'import subprocess as sp\nsp.check_output(["ls"], capture_output=True)\n'   > "$ENCSEED/п01.py"
printf 'from subprocess import %s\n%s(["ls"], capture_output=True)\n' "$S_R" "$S_R" > "$ENCSEED/п02.py"
printf 'from os import %s\n%s("ls").read()\n' "$S_P" "$S_P"                        > "$ENCSEED/п03.py"
printf 'from configparser import %s\n%s().read("н.ini")\n' "$S_CP" "$S_CP"         > "$ENCSEED/п04.py"
printf 'р = "#"; д = %s("з.md").read()\n' "$S_O"                                   > "$ENCSEED/п05.py"
printf 'м = %s("p.json").read()\nwith %s("c.yaml", encoding="utf-8") as h:\n    pass\n' "$S_O" "$S_O" > "$ENCSEED/п06.py"
printf 'from pathlib import Path\nт = Path("з.md").%s()  # encoding= не указан\n' "$S_RT" > "$ENCSEED/п07.py"
printf '```bash\ngrep "#" з.md && python3 -c "print(%s(\x27з.md\x27).read())"\n```\n' "$S_O" > "$ENCSEED/п08.md"
printf '#!/usr/bin/env bash\nВ=$(python3 -c "import json;print(json.load(%s(\x27p.json\x27))[\x27v\x27])")\n' "$S_O" > "$ENCSEED/п09"
printf 'import subprocess\nsubprocess.%s("ls")\n' "$S_GO"                          > "$ENCSEED/п10.py"
printf 'x = %s("а.md").read()\n' "$S_O"                                            > "$ENCSEED/fixtures/п11.py"
printf 'from pathlib import Path\nд = Path("з.md").%s().read()\n' "$S_O"          > "$ENCSEED/п12.py"
printf 'from pathlib import Path\nп = Path("з.md")\nд = п.%s().read()\n' "$S_O"   > "$ENCSEED/п13.py"
# ── честные: каждый обязан промолчать ──
printf 'import webbrowser\nwebbrowser.%s("https://пример")\n' "$S_O"               > "$ENCSEED/ч1.py"
printf 'import os\nos.%s("з", os.O_CREAT)\n' "$S_O"                                > "$ENCSEED/ч2.py"
printf 'import zipfile\nzipfile.ZipFile("a.zip").%s("и").read()\n' "$S_O"          > "$ENCSEED/ч3.py"
printf 'import subprocess\nsubprocess.%s(["ls"], check=True)\n' "$S_R"             > "$ENCSEED/ч4.py"
printf 'import configparser\nc = configparser.%s()\nc.read_string("[a]\\nb=1")\n' "$S_CP" > "$ENCSEED/ч5.py"
printf 'Читать файл вызовом %s() без явной кодировки нельзя — она придёт от машины.\n' "$S_O" > "$ENCSEED/ч6.md"
printf '| Вызов | Беда |\n|---|---|\n| subprocess.%s(cmd) | берёт кодировку у локали |\n' "$S_R" > "$ENCSEED/ч7.md"
printf 'x = %s("а.md", "rb").read().decode("utf-8")\n' "$S_O"                      > "$ENCSEED/ч8.py"
printf 'x = %s("а.md", encoding="utf-8").read()\n' "$S_O"                          > "$ENCSEED/ч9.py"
# Три честных на границе `.open()`: метод с этим именем есть у многого, и кодировке там
# взяться неоткуда. Красный на любом из них означал бы, что признак цепляется за имя
# метода, а не за то, чем этот метод является.
printf 'from pathlib import Path\nimport zipfile\nzipfile.ZipFile("a.zip").%s("и").read()\n' "$S_O" > "$ENCSEED/ч10.py"
printf 'from pathlib import Path\nPath("з.md").%s("rb").read()\n' "$S_O"          > "$ENCSEED/ч11.py"
printf 'from pathlib import Path\nPath("з.md").%s(encoding="utf-8").read()\n' "$S_O" > "$ENCSEED/ч12.py"
ENC_CAUGHT=$(python3 enc-sweep.py "$ENCSEED" | grep -c '^п\|^fixtures/п' || true)
ENC_FALSE=$(python3 enc-sweep.py "$ENCSEED" | grep -c '^ч' || true)
if [ "$ENC_CAUGHT" -eq 13 ]; then ok "кодировка: перебор ловит все 13 приманок, включая псевдоним импорта, соседний верный вызов и путь через переменную"
else bad "кодировка: из 13 приманок перебор поймал $ENC_CAUGHT — его зелёный ничего не значит"; fi
if [ "$ENC_FALSE" -eq 0 ]; then ok "кодировка: на 12 честных файлах перебор молчит (в том числе на прозе о коде и на .open() у архива)"
else bad "кодировка: $ENC_FALSE ложных срабатываний на честном коде — такого стража выключат"; fi
rm -rf "$ENCSEED"
# 7. Последний рубеж: команду прогона пишет пользователь, и чужой скрипт отдаёт что
# угодно. Нерасшифруемый байт обязан испортить знак, а не съесть отчёт целиком.
printf '#!/usr/bin/env bash\nprintf "РАЗБОР: \\377\\376 и дальше текст\\n"\nexit 1\n' > "$TEN/кривой.sh"
chmod +x "$TEN/кривой.sh"
printf 'validate:\n  command: ./кривой.sh knowledge\n' > "$TEN/config.yaml"
OUT=$(vwe utf-8)
has "кодировка: нерасшифруемый байт прогона не съедает отчёт" "РАЗБОР"
if echo "$OUT" | grep -qF "не отработал"; then
  bad "кодировка: на нерасшифруемом байте хук объявил СВОЮ поломку вместо отчёта"; else
  ok "кодировка: хук на этом не ломается — портится знак, а не отчёт"; fi
rm -rf "$TEN"

echo "── Падение валидатора — это код 2, а не 1 ──"
# Прежде ловились два ИМЕНИ (RecursionError, KeyboardInterrupt), а любая другая поломка
# уходила кодом 1 — неотличимо от честного «найдены проблемы», и чинить по нему шли базу
# вместо инструмента. Здесь ломается разбор YAML: подменный модуль импортируется, но
# роняет прогон в середине — то есть ровно «неучтённая поломка с новым именем».
TBOOM="$(mktemp -d)"
cat > "$TBOOM/yaml.py" <<'PY'
class YAMLError(Exception):
    pass


class SafeLoader:
    def __init__(self, *a, **k):
        pass

    @classmethod
    def add_constructor(cls, *a, **k):
        pass


def load(*a, **k):
    raise RuntimeError("подложенный yaml: бум")


def safe_load(*a, **k):
    raise RuntimeError("подложенный yaml: бум")
PY
OUT=$(PYTHONPATH="$TBOOM" python3 ../validate.py fixtures/clean/knowledge 2>&1); RC=$?
if [ "$RC" -eq 2 ]; then ok "падение валидатора: код 2 («прогон не состоялся»)"; else
  bad "падение валидатора: код $RC — поломка инструмента неотличима от находок в базе"; fi
has "падение валидатора: сказано, что прогон НЕ состоялся" "НЕ СОСТОЯЛСЯ"
has "падение валидатора: трассировка приехала, а не съедена" "RuntimeError"
rm -rf "$TBOOM"

# Обрыв вывода — тот же класс, но общий перехват его не ловил: он печатает трассировку
# в поток, который только что оборвался, падает вторично, и Python отдавал 120 при
# обещанных двух. Порог в 1200 заметок взят прогоном: на меньшем отчёт целиком влезает
# в буфер трубы, запись успевает пройти и обрыва не случается вовсе.
TPIPE="$(mktemp -d)"; mkdir -p "$TPIPE/knowledge"
python3 -c "
import sys
for i in range(1200): open(f'{sys.argv[1]}/knowledge/z{i}.md','w',encoding='utf-8').write('черновик\n')" "$TPIPE"
python3 ../validate.py "$TPIPE/knowledge" 2>/dev/null | head -1 >/dev/null; RC=${PIPESTATUS[0]}
if [ "$RC" -eq 2 ]; then ok "обрыв вывода (| head): код 2 — прогон не состоялся"; else
  bad "обрыв вывода: код $RC вместо 2 — обещание «любое падение даёт 2» шире правды"; fi
rm -rf "$TPIPE"

echo "── Исполнитель паспорта стартовой загрузки (SessionStart-хук) ──"
# Паспорт § 6.3 до этого хука был декларацией. Проверяется ровно граница исполнения:
# by: hook грузится, by: rules и by: env — нет, и молчание отличимо от «нечего грузить».
TSL="$(mktemp -d)"          # KIT и ctx определены выше, в блоке автопрогона валидатора
sl() { (cd "$TSL" && CLAUDE_PROJECT_DIR="$TSL" python3 "$KIT/hooks/startup-load.py"); }

# Ворота проверяются на проекте, которому ЕСТЬ что грузить: иначе молчание объясняется
# отсутствием конфига, и снятие ворот проходит незамеченным: без этого входа тест
# ложно-зелёный — снятые ворота его не роняют.
mkdir -p "$TSL/my"
printf 'СЛОВО-ЧАСОВОЙ\n' > "$TSL/my/mem.md"
MSZ=$(wc -c < "$TSL/my/mem.md" | tr -d ' ')
printf 'startup:\n  loads:\n    - what: память\n      by: hook\n      path: my/mem.md\n' > "$TSL/config.yaml"

OUT=$(sl); RC=$?
if [ -z "$OUT" ]; then ok "паспорт: без метки молчит, хотя грузить есть что"; else bad "паспорт: залез в проект без метки"; fi
if [ "$RC" -eq 0 ]; then ok "паспорт: код выхода 0 без метки"; else bad "паспорт: код выхода $RC сорвёт старт"; fi

printf 'имя: тест\n' > "$TSL/.loreground"
OUT=$(sl | ctx)
has "паспорт: с меткой тот же конфиг исполняется" "СЛОВО-ЧАСОВОЙ"

rm -f "$TSL/config.yaml"
OUT=$(sl)
if [ -z "$OUT" ]; then ok "паспорт: без config.yaml молчит (ничего не объявлено)"; else bad "паспорт: шумит без конфига"; fi

# Граница: чужие способы загрузки исполнитель не трогает.
printf 'startup:\n  loads:\n    - what: правила\n      by: rules\n      path: my/mem.md\n' > "$TSL/config.yaml"
OUT=$(sl)
if [ -z "$OUT" ]; then ok "паспорт: by: rules не исполняется хуком"; else bad "паспорт: хук залез в чужую строку by: rules"; fi

printf 'startup:\n  loads:\n    - what: без адреса\n      by: hook\n' > "$TSL/config.yaml"
OUT=$(sl | ctx); has "паспорт: by: hook без path назван" "без path"

printf 'startup:\n  loads:\n    - what: наружу\n      by: hook\n      path: ../../../etc/hosts\n' > "$TSL/config.yaml"
OUT=$(sl | ctx); has "паспорт: путь наружу проекта отвергнут" "наружу проекта"

# Симлинк — вторая форма того же класса, и форму с «..» она обходит: папка лежит внутри
# проекта, а файл в ней указывает наружу. Канарейка кладётся ВНЕ проекта: если она доедет
# до контекста, значит хук вынес наружное содержимое в сессию.
SLOUT="$(mktemp -d)"
printf 'КАНАРЕЙКА-СНАРУЖИ\n' > "$SLOUT/чужое.md"
ln -s "$SLOUT/чужое.md" "$TSL/my/ссылка.md"
printf 'startup:\n  loads:\n    - what: симлинк\n      by: hook\n      path: my/ссылка.md\n' > "$TSL/config.yaml"
OUT=$(sl | ctx)
has "паспорт: симлинк-файл наружу отвергнут" "наружу проекта"
case "$OUT" in *КАНАРЕЙКА-СНАРУЖИ*) bad "паспорт: содержимое файла ВНЕ проекта уехало в контекст" ;;
               *) ok "паспорт: наружное содержимое в контекст не попало" ;; esac
rm -f "$TSL/my/ссылка.md"; rm -rf "$SLOUT"

printf 'startup:\n  loads:\n    - what: пропавший\n      by: hook\n      path: my/нет.md\n' > "$TSL/config.yaml"
OUT=$(sl | ctx); has "паспорт: объявленный, но отсутствующий файл назван" "объявлен обязательным, а его нет"

printf 'startup:\n  budget: 9000\n  loads:\n    - what: память\n      by: hook\n      path: my/mem.md\n      size: %s\n' "$MSZ" > "$TSL/config.yaml"
OUT=$(sl | ctx)
has "паспорт: содержимое файла доехало" "СЛОВО-ЧАСОВОЙ"
has "паспорт: фактический вес назван" "$MSZ Б"
case "$OUT" in *"Расхождения паспорта"*) bad "паспорт: ложное расхождение при верном size" ;;
               *) ok "паспорт: верный size расхождением не считается" ;; esac

printf 'startup:\n  budget: 9000\n  loads:\n    - what: память\n      by: hook\n      path: my/mem.md\n      size: 99999\n' > "$TSL/config.yaml"
OUT=$(sl | ctx); has "паспорт: враньё в size поймано" "на диске $MSZ Б"

printf 'startup:\n  budget: 3\n  loads:\n    - what: память\n      by: hook\n      path: my/mem.md\n' > "$TSL/config.yaml"
OUT=$(sl | ctx)
has "паспорт: пробитый потолок назван" "ПОТОЛОК ПРОБИТ"
# § 6.3 п. 4: пробой — работа человека, а не повод оставить агента без памяти.
has "паспорт: при пробое груз всё равно доехал" "СЛОВО-ЧАСОВОЙ"

printf 'startup:\n  loads:\n   - what: кривой\n  by: [\n' > "$TSL/config.yaml"
OUT=$(sl | ctx); has "паспорт: битый YAML назван, а не проглочен" "не разбирается"
rm -rf "$TSL"

echo "── Сборка на живом агенте: чужое не затирается ──"
# Навык обещает «существующие заметки не переписывает». Обещание проверяется прогоном
# его же команды по живой базе: Home-индекс — точка входа во всё остальное (§ 7.2),
# и подмена его шаблоном осиротит базу целиком, причём тихо — шаблон выглядит рабочим.
TIN="$(mktemp -d)"
python3 - "$KIT/skills/init/SKILL.md" "$TIN/step5.sh" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
b = next(x for x in re.findall(r"```bash\n(.*?)```", t, re.S) if "00-index.md" in x and "BASE" in x)
open(sys.argv[2], "w", encoding="utf-8").write(b)
PY
mkdir -p "$TIN/knowledge"
printf -- '---\ntitle: 00-index\ntype: moc\n---\n- [[Кофеин]] — год работы\n- [[Сон]] — 40 заметок\n' > "$TIN/knowledge/00-index.md"
( cd "$TIN" && CLAUDE_PLUGIN_ROOT="$KIT" bash step5.sh ) >/dev/null 2>&1
if grep -q 'Кофеин' "$TIN/knowledge/00-index.md"; then
  ok "сборка: существующий Home-индекс не затёрт"
else bad "сборка: живой Home-индекс заменён шаблоном — база осиротела"; fi

# И обратная сторона: на пустой папке индекс обязан появиться, иначе защита превратится
# в «навык ничего не делает».
rm -rf "$TIN/knowledge"; mkdir -p "$TIN/knowledge"
( cd "$TIN" && CLAUDE_PLUGIN_ROOT="$KIT" bash step5.sh ) >/dev/null 2>&1
if [ -f "$TIN/knowledge/00-index.md" ]; then ok "сборка: на пустой базе индекс создаётся"; else
  bad "сборка: на пустой базе индекс не создан"; fi

# Метка — тот же класс: файл слоя пользователя под записью. В ней дата сборки, и
# повторный запуск на живом агенте сдвинул бы её на сегодня, соврав о том, когда
# агента собрали. Защита индекса без защиты метки закрыла бы адрес, а не класс.
python3 - "$KIT/skills/init/SKILL.md" "$TIN/step8.sh" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
b = next(x for x in re.findall(r"```bash\n(.*?)```", t, re.S) if ".loreground" in x)
open(sys.argv[2], "w", encoding="utf-8").write(b)
PY
printf 'собран_на_версии: 0.1.0\nсобран: 2020-01-01\nимя: старый\n' > "$TIN/.loreground"
( cd "$TIN" && CLAUDE_PLUGIN_ROOT="$KIT" NAME=x MODE=копия bash step8.sh ) >/dev/null 2>&1
if grep -q '2020-01-01' "$TIN/.loreground"; then ok "сборка: дата в существующей метке не сдвинута"; else
  bad "сборка: метка перезаписана — дата сборки агента подменена сегодняшней"; fi

# Метка новой сборки обязана нести РЕЖИМ: без него сторож расхождения версий не может
# сказать, сменились ли правила под базой, и прежде выводил режим из наличия папки —
# то есть угадывал, а на переведённом наполовину агенте угадывал неверно.
#
# Проверяется САМ СТАНОК, а не прогон с подставленным значением: скрипт присваивает
# MODE сам, поэтому переменная окружения его не перекрывает, и прогон показал бы то,
# что подложил тест, а не то, что делает навык.
grep -q 'режим: %s' "$TIN/step8.sh" \
  && ok "сборка: метка несёт поле режима" \
  || bad "сборка: в метке нет поля режима — сторож версий будет его угадывать"
grep -qE '^MODE=' "$TIN/step8.sh" \
  && ok "сборка: MODE присваивается, а не берётся из ниоткуда" \
  || bad "сборка: MODE подставляется в метку, но нигде не присвоен — поле уйдёт пустым"
grep -q 'собран_на_версии: %s' "$TIN/step8.sh" \
  && ok "сборка: метка несёт версию сборки" \
  || bad "сборка: в метке нет версии сборки"
rm -rf "$TIN"

echo "── Разбор сессии: прошлый отчёт не затирается ──"
# Тот же класс, что затирание Home-индекса при сборке: файл слоя пользователя под
# безусловной записью. Архив разборов — не черновик: следующий разбор читает его,
# чтобы увидеть повтор беды, и затирание уничтожает смысл самого архива.
TRP="$(mktemp -d)"
python3 - "$KIT/skills/retro/SKILL.md" "$TRP/step5.sh" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
b = next(x for x in re.findall(r"```bash\n(.*?)```", t, re.S) if "my/retro" in x)
open(sys.argv[2], "w", encoding="utf-8").write(b)
PY
( cd "$TRP" && printf 'имя: агент\n' > .loreground && mkdir -p my/retro
  SID=abc12345 bash -c 'SID="$SID"; source step5.sh' > first.txt 2>/dev/null
  P=$(tail -1 first.txt); printf 'ПЕРВЫЙ ОТЧЁТ\n' > "$P"
  SID=abc12345 bash -c 'SID="$SID"; source step5.sh' > second.txt 2>/dev/null
  Q=$(tail -1 second.txt)
  [ "$P" != "$Q" ] && grep -q 'ПЕРВЫЙ ОТЧЁТ' "$P" ) \
  && ok "разбор: повторный отчёт не затирает прошлый" \
  || bad "разбор: второй отчёт за день затёр первый"
rm -rf "$TRP"

echo "── Чужая машина: отсутствие python3 ──"
# «Нечем проверить» обязано звучать одинаково, чем бы ни было нечем. Про PyYAML
# валидатор говорит человеческим текстом с командой установки; про сам python3
# раньше говорила оболочка кодом 127, и это выглядело поломкой плагина, а не
# отсутствием зависимости на машине.
TNP="$(mktemp -d)"; mkdir -p "$TNP/bin"
for d in /usr/bin /bin; do for f in "$d"/*; do n=$(basename "$f")
  [ "$n" = "python3" ] && continue
  [ -e "$TNP/bin/$n" ] || ln -sf "$f" "$TNP/bin/$n" 2>/dev/null; done; done
OUT=$(env -i PATH="$TNP/bin" HOME="$HOME" "$KIT/bin/lore-validate" "$KIT/standard/tests/fixtures/clean/knowledge" 2>&1)
RC=$?
has "чужая машина: отсутствие python3 названо" "не найден python3"
has "чужая машина: сказано, что это не «чисто»" "проверка не выполнялась"
if [ "$RC" -eq 2 ]; then ok "чужая машина: без python3 код 2 («не состоялся»), а не 127"; else
  bad "чужая машина: без python3 код $RC — «не смог» неотличим от поломки"; fi
rm -rf "$TNP"

echo "── Разбор сессии: шаг 1 навыка retro ──"
# Команда берётся ИЗ САМОГО НАВЫКА, а не переписывается сюда: копия разошлась бы с
# оригиналом при первой же правке, и тест проверял бы вчерашний конвейер.
TRT="$(mktemp -d)"
python3 - "$KIT/skills/retro/SKILL.md" "$TRT/step1.sh" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
block = next(b for b in re.findall(r"```bash\n(.*?)```", text, re.S) if "_digest.md" in b)
open(sys.argv[2], "w", encoding="utf-8").write(block)
PY
if grep -q 'jq код' "$TRT/step1.sh"; then ok "retro: шаг 1 проверяет код выхода jq отдельно"; else
  bad "retro: код выхода jq не проверяется — битая стенограмма даст «разбирать нечего»"; fi

# Битая стенограмма обязана валить шаг, а не выдавать короткую выжимку с кодом 0:
# «нечего разбирать» и «разбор не состоялся» — разные ответы (кодекс: пустой вывод
# не доказательство).
( cd "$TRT" && printf '{"type":"user","message":{"content":"раз"}}\nне json\n{"обрыв\n' > t.jsonl
  F="$TRT/t.jsonl" bash -c 'F="$F"; source step1.sh' >/dev/null 2>&1 )
RC=$?
if [ "$RC" -ne 0 ]; then ok "retro: битая стенограмма роняет шаг 1 (код $RC)"; else
  bad "retro: битая стенограмма прошла с кодом 0 — молчаливое «разбирать нечего»"; fi

# Правило игнора обязано встать ДО первой записи: между ними не должно быть шагов.
( cd "$TRT" && rm -rf g && mkdir g && cd g && printf 'node_modules/\n' > .gitignore
  cp "$TRT/step1.sh" . && printf '{"type":"user","message":{"content":"раз"}}\n' > t.jsonl
  F="$TRT/g/t.jsonl" bash -c 'F="$F"; source step1.sh' >/dev/null 2>&1
  grep -qx '_retro/' .gitignore ) \
  && ok "retro: _retro/ попал в .gitignore тем же шагом" \
  || bad "retro: выжимка записана, а _retro/ в .gitignore не попал"
rm -rf "$TRT"

echo "── Сторож свежести кодекса (SessionStart-хук) ──"
# Три исхода обязаны быть различимы: молчание, расхождение и «проверить не удалось».
# Слить второе с третьим — тот же класс, что exit 0 при невыполненных проверках.
HK=../../hooks/codex-freshness.py
KIT="$(cd ../.. && pwd)"
THK="$(mktemp -d)"
hook() { (cd "$THK" && CLAUDE_PROJECT_DIR="$THK" CLAUDE_PLUGIN_ROOT="$1" python3 "$KIT/hooks/codex-freshness.py"); }

# Ворота: без метки сборки сторож не смеет вмешиваться в чужой проект.
OUT=$(hook "$KIT"); RC=$?
if [ -z "$OUT" ]; then ok "хук: без метки .loreground молчит"; else bad "хук: заговорил в чужом проекте"; fi
if [ "$RC" -eq 0 ]; then ok "хук: код выхода 0 без метки"; else bad "хук: код выхода $RC (сорвёт старт сессии)"; fi

printf 'собран_на_версии: 0\nимя: тест\n' > "$THK/.loreground"

# «Не смог проверить» обязано звучать, а не молчать.
OUT=$(hook "/заведомо/нет/такого/пути")
has "хук: недоступный источник назван" "проверить нечем"

OUT=$(hook "$KIT")
has "хук: отсутствие файла правил названо" "не состоялась"

printf '# Правила\n\nникакого кодекса тут нет\n' > "$THK/CLAUDE.md"
OUT=$(hook "$KIT")
has "хук: отсутствие кодекса в правилах названо" "кодекса нет"

# Версия берётся из ЖИВОГО файла комплекта, а не из константы теста: если формат
# строки версии в codex.md изменят, сторож ослепнет молча — этот случай ловит подмену.
SRCV=$(python3 - "$KIT/standard/codex.md" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
b = t[t.find("<!-- КОПИРОВАТЬ ОТСЮДА -->"):t.find("<!-- КОПИРОВАТЬ ДО СЮДА -->")]
m = re.search(r"версия кодекса\s+(\d+)", b)
print(m.group(1) if m else "")
PY
)
if [ -n "$SRCV" ]; then ok "хук: версия кодекса читается из комплекта ($SRCV)"; else
  bad "хук: в codex.md не нашлась строка «версия кодекса N» — сторож ослеп"; fi

# Строка копии берётся ЖИВОЙ из codex.md, а не сочиняется здесь. Голое «версия кодекса N»
# — это проза, а не копия; фикстура из такой строки делает тест ложно-зелёным, потому что
# не воспроизводит того, что проверяется.
copyline() { python3 - "$KIT/standard/codex.md" "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
b = t[t.find("<!-- КОПИРОВАТЬ ОТСЮДА -->"):t.find("<!-- КОПИРОВАТЬ ДО СЮДА -->")]
line = next(l for l in b.splitlines() if re.search(r"версия кодекса\s+\d+", l))
print(re.sub(r"(версия кодекса\s+)\d+", r"\g<1>" + sys.argv[2], line))
PY
}

# Настоящая копия — это ВЕСЬ блок, а не одна строка про версию. Фикстура из одной строки
# версии есть ровно та заглушка, которую сторож обязан ловить: она проверяет сверку
# номера на файле, где кодекса нет ни строки, и тест зеленеет, не воспроизводя дефекта.
copyblock() { python3 - "$KIT/standard/codex.md" "$1" <<'PYB'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
o = t.find("<!-- КОПИРОВАТЬ ОТСЮДА -->")
c = t.find("<!-- КОПИРОВАТЬ ДО СЮДА -->")
b = t[o + len("<!-- КОПИРОВАТЬ ОТСЮДА -->"):c]
print(re.sub(r"(версия кодекса\s+)\d+", r"\g<1>" + sys.argv[2], b))
PYB
}

printf '# Правила\n\n%s\n' "$(copyblock "$SRCV")" > "$THK/CLAUDE.md"
OUT=$(hook "$KIT")
if [ -z "$OUT" ]; then ok "хук: совпавшие версии — молчание"; else bad "хук: шумит на свежей копии"; fi

# Ложное молчание: версия названа в прозе, копии нет вовсе. Молчание здесь читается
# как «всё в порядке» — самый дорогой из трёх исходов сторожа.
printf '# Правила\n\nмы решили, что версия кодекса %s нас устраивает\n' "$SRCV" > "$THK/CLAUDE.md"
OUT=$(hook "$KIT")
has "хук: упоминание версии в прозе копией не считается" "кодекса нет"

# Копия в соседнем файле правил: судить по первому существующему значит обвинять в
# пропаже того, что лежит рядом, и толкать человека завести кодексу второй дом.
printf '# Правила\n\nникакого кодекса тут нет\n' > "$THK/CLAUDE.md"
printf '# Агенты\n\n%s\n' "$(copyblock "$SRCV")" > "$THK/AGENTS.md"
OUT=$(hook "$KIT")
if [ -z "$OUT" ]; then ok "хук: копия в AGENTS.md при пустом CLAUDE.md — молчание"; else bad "хук: не увидел копию в соседнем файле правил"; fi
rm -f "$THK/AGENTS.md"

# Заглушка вместо кодекса: строка про источник и версию есть, текста блока нет ни
# строки. Сторож молчал — то есть объявлял здоровым файл правил, где кодекса не было
# вовсе. Это ровно та форма, ради отказа от которой кодекс кладут копией (§ 9.3 п. 5).
printf '# Правила\n\nКодекс: см. standard/codex.md, версия кодекса %s.\n' "$SRCV" > "$THK/CLAUDE.md"
OUT=$(hook "$KIT")
has "хук: строка про кодекс без текста кодекса названа" "неполна: из"

printf '# Правила\n\n%s\n' "$(copyblock 0)" > "$THK/CLAUDE.md"
OUT=$(hook "$KIT"); RC=$?
has "хук: расхождение названо" "устарел"
has "хук: названа версия источника" "источник версии $SRCV"
has "хук: правку без согласия человека запрещает" "без его согласия не переписывай"
if [ "$RC" -eq 0 ]; then ok "хук: код выхода 0 и при находке"; else bad "хук: код выхода $RC сорвёт старт"; fi

# Вывод обязан быть разбираемым: сломанный JSON хост молча выбросит.
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['hookSpecificOutput']['hookEventName']=='SessionStart' else 1)" 2>/dev/null; then
  ok "хук: вывод — валидный JSON нужного события"
else bad "хук: вывод не разбирается как JSON события SessionStart"; fi
# Порядок источников: свой стандарт агента старше комплекта рядом. Спроси сначала
# комплект — и агент, сознательно стоящий на прошлой версии, получит ложную тревогу
# про кодекс, который в порядке. Ложная тревога убивает сторожа надёжнее молчания.
THK2="$(mktemp -d)"
mkdir -p "$THK2/standard"
python3 - "$KIT/standard/codex.md" "$THK2/standard/codex.md" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(
    re.sub(r"(версия кодекса\s+)\d+", r"\g<1>777", t))
PY
printf 'собран_на_версии: 0\nимя: тест\n' > "$THK2/.loreground"
printf '# Правила\n\n%s\n' "$(copyblock 777)" > "$THK2/CLAUDE.md"
OUT=$( (cd "$THK2" && CLAUDE_PROJECT_DIR="$THK2" CLAUDE_PLUGIN_ROOT="$KIT" python3 "$KIT/hooks/codex-freshness.py") )
if [ -z "$OUT" ]; then ok "хук: свой стандарт агента старше комплекта рядом"; else
  bad "хук: сверился с комплектом вместо своего стандарта — ложная тревога у автономного агента"; fi
rm -rf "$THK2"

echo "── Сторож расхождения версий (SessionStart-хук) ──"
# Расхождение версии сборки с версией комплекта обязано звучать: обновление агента —
# осознанное действие, а не то, что случается само (core.md § 9.3).
TVD="$(mktemp -d)"; mkdir -p "$TVD/proj" "$TVD/kit/.claude-plugin"
printf '{"name":"loreground","version":"9.9.9"}\n' > "$TVD/kit/.claude-plugin/plugin.json"
# Присваивание-префикс обязано быть литералом: подставленное из переменной bash
# принимает за имя команды и падает с 127. Отсюда две явные ветки, а не ${1:+...}.
vd() {
  # ${1:-}, а не $1: прогон идёт под set -u, и голое $1 при вызове без аргумента роняет
  # функцию. Вывод при этом пуст — то есть тест «молчит» зеленел бы, не запустив хук.
  if [ -n "${1:-}" ]; then
    (cd "$TVD/proj" && CLAUDE_PROJECT_DIR="$TVD/proj" CLAUDE_PLUGIN_ROOT="$TVD/kit" python3 "$KIT/hooks/version-drift.py")
  else
    (cd "$TVD/proj" && CLAUDE_PROJECT_DIR="$TVD/proj" env -u CLAUDE_PLUGIN_ROOT python3 "$KIT/hooks/version-drift.py")
  fi
}

OUT=$(vd 1); RC=$?
if [ -z "$OUT" ]; then ok "версии: без метки .loreground молчит"; else bad "версии: заговорил в чужом проекте"; fi
if [ "$RC" -eq 0 ]; then ok "версии: код выхода 0 без метки"; else bad "версии: код выхода $RC сорвёт старт"; fi

printf 'собран_на_версии: 9.9.9\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
if [ -z "$OUT" ]; then ok "версии: совпали — молчание"; else bad "версии: шумит на совпавших версиях"; fi

# Комплекта на машине нет — штатное состояние увезённого агента, а не дефект.
# Ругаться тут значит ругать ровно то, ради чего копия сделана умолчанием.
printf 'собран_на_версии: 1.0.0\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd)
if [ -z "$OUT" ]; then ok "версии: без комплекта рядом молчит (сравнивать не с чем)"; else
  bad "версии: ругается на агента, у которого комплекта на машине нет"; fi

# Диагноз ветвится по РЕЖИМУ ИЗ МЕТКИ, а не по наличию папки standard/. Пока режим
# угадывался по файловой системе, наполовину переведённый агент (правила зовут комплект,
# забытая папка лежит рядом) получал не молчание, а ПРОТИВОПОЛОЖНЫЙ правде диагноз —
# «само ничего не сменилось», тогда как правила уже сменились. Ложный красный
# обесценивает сторожа так же надёжно, как ложный зелёный.
printf 'собран_на_версии: 1.0.0\nрежим: указатель\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1); RC=$?
has "версии: расхождение названо" "агент собран на версии 1.0.0"
has "версии: названа версия комплекта" "9.9.9"
has "версии: при указателе сказано, что правила уже сменились" "работает прямо сейчас"
if [ "$RC" -eq 0 ]; then ok "версии: код выхода 0 и при находке"; else bad "версии: код выхода $RC сорвёт старт"; fi

# Забытая папка от прошлого режима лежит рядом — диагноз не должен от неё зависеть.
mkdir -p "$TVD/proj/standard" && : > "$TVD/proj/standard/core.md"
OUT=$(vd 1)
has "версии: забытая папка standard/ диагноз не переворачивает" "работает прямо сейчас"

printf 'собран_на_версии: 1.0.0\nрежим: Копия\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
has "версии: при копии сказано, что само ничего не сменилось" "осознанное действие"

# Режим не объявлен — третий исход, а не выбор одной из двух концовок наугад.
printf 'собран_на_версии: 1.0.0\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
has "версии: необъявленный режим назван, а не угадан" "подключения ядра в метке не объявлен"

printf 'имя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
has "версии: незаписанная версия сборки названа, а не проглочена" "отследить нечем"

# Метка ровно того вида, что пишет init: между версией и именем стоит строка «собран:».
# Без неё подмена «собран_на_версии» на «собран» проходит незамеченной, и у правила
# § 9.3 п. 6 («записывается „собран на версии“, а не „версия“») машины нет, хотя тесты
# выглядят покрытием.
printf 'собран_на_версии: 1.0.0\nсобран: 2020-01-01\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
has "версии: настоящая форма метки разбирается" "агент собран на версии 1.0.0"

# Пустое значение поля. Класс пробелов в выражении был `\s`, то есть перешагивал перевод
# строки и забирал соседнюю строку как версию: сторож, чья работа не дать выдумать
# версию, подставлял дату сборки и велел сказать это человеку.
printf 'собран_на_версии:\nсобран: 2020-01-01\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
has "версии: пустое значение не подхватывает соседнюю строку" "отследить нечем"
case "$OUT" in *2020-01-01*) bad "версии: дата сборки выдана за номер версии";;
  *) ok "версии: дата сборки за версию не выдана";; esac

# Навык сборки штатно пишет «неизвестна», когда манифест прочитать не удалось.
printf 'собран_на_версии: неизвестна\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
has "версии: «неизвестна» считается отсутствием версии, а не версией" "отследить нечем"

# Кавычки вокруг значения — косметика записи, а не расхождение.
printf 'собран_на_версии: "9.9.9"\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
if [ -z "$OUT" ]; then ok "версии: кавычки вокруг номера не считаются расхождением"; else
  bad "версии: ложная тревога на кавычках в метке"; fi

# Манифест-не-объект и version-не-строка: комплекта фактически нет, сравнивать не с чем.
printf 'собран_на_версии: 1.0.0\nимя: тест\n' > "$TVD/proj/.loreground"
printf '["не объект"]\n' > "$TVD/kit/.claude-plugin/plugin.json"
OUT=$(vd 1); RC=$?
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "версии: манифест-не-объект не роняет и не выдумывает"; else
  bad "версии: на манифесте-массиве выдал «$OUT» (rc=$RC)"; fi
printf '{"name":"loreground","version":123}\n' > "$TVD/kit/.claude-plugin/plugin.json"
OUT=$(vd 1)
if [ -z "$OUT" ]; then ok "версии: нестроковая version отсеивается"; else
  bad "версии: сравнил номер с нестроковым значением"; fi
printf '{"name":"loreground","version":"9.9.9"}\n' > "$TVD/kit/.claude-plugin/plugin.json"

# Ворота у ВСЕХ ЧЕТЫРЁХ хуков комплекта объявлены одни (`hooks.json`) — значит совпадают
# и на краях. Пока их было два сорта, `mkdir .loreground` глушил ровно двух сторожей, а
# двое других продолжали говорить: агент выглядел полностью оснащённым (баннер загрузки
# каждую сессию, автопрогон после каждой записи), а слежение за версиями было мертво.
rm -f "$TVD/proj/.loreground"; mkdir -p "$TVD/proj/.loreground"
mkdir -p "$TVD/proj/knowledge"; printf 'title: x\n' > "$TVD/proj/knowledge/00-index.md"
printf 'СТАНДАРТ: standard/core.md\n' > "$TVD/proj/CLAUDE.md"
printf 'startup:\n  loads:\n    - what: правила агента\n      by: hook\n      path: CLAUDE.md\nvalidate:\n  command: python3 %s/standard/validate.py knowledge\n' "$KIT" > "$TVD/proj/config.yaml"
# Вход каждому хуку даётся НАСТОЯЩИЙ. На пустом входе `validate-on-write` падает на
# чтении события РАНЬШЕ ворот — молчит по другой причине, а тест засчитывает это как
# «ворота держат». Подмена `isfile`→`exists` при этом не ловится: машина выглядит
# покрытием и им не является.
printf 'title: x\n' > "$TVD/proj/knowledge/новая.md"
EVENT='{"tool_name":"Write","tool_input":{"file_path":"'"$TVD"'/proj/knowledge/новая.md"}}'
GATE_TALKERS=""
# Список берётся С ДИСКА, как и у проверки поломки ниже. Пока здесь стояли четыре
# имени, пятый хук проходил смоук молча — а тест при этом печатал зелёное
# утверждение «ни один из четырёх», то есть говорил про машину то, чего она не
# делает. Правка «перебирай папку, а не имена» доехала до одного цикла из двух
# в этом же файле: класс починен, машина под него поставлена по адресу.
GATE_HOOKS=$(ls ../../hooks/*.py | xargs -n1 basename | sed 's/\.py$//' | grep -v '^_')
GATE_N=$(echo "$GATE_HOOKS" | grep -c .)
[ "$GATE_N" -gt 0 ] || bad "ворота: в hooks/ не найдено ни одного хука — перебор пуст, а не чист"
for h in $GATE_HOOKS; do
  GO=$( (cd "$TVD/proj" && CLAUDE_PROJECT_DIR="$TVD/proj" CLAUDE_PLUGIN_ROOT="$KIT" python3 "$KIT/hooks/$h.py" <<< "$EVENT" 2>&1) )
  [ -n "$GO" ] && GATE_TALKERS="$GATE_TALKERS $h"
done
if [ -z "$GATE_TALKERS" ]; then ok "ворота: папку с именем метки меткой не считает ни один хук папки ($GATE_N)"; else
  bad "ворота: на папке-метке заговорили —$GATE_TALKERS (ворота разъехались)"; fi
rm -rf "$TVD/proj/.loreground" "$TVD/proj/knowledge" "$TVD/proj/CLAUDE.md" "$TVD/proj/config.yaml"

# Вход этой проверке даётся СВОЙ, а не унаследованный от соседней: проверка на чужом
# $OUT молча меняет смысл, стоит вставить между ними ещё один случай.
printf 'собран_на_версии: 1.0.0\nимя: тест\n' > "$TVD/proj/.loreground"
OUT=$(vd 1)
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['hookSpecificOutput']['hookEventName']=='SessionStart' else 1)" 2>/dev/null; then
  ok "версии: вывод — валидный JSON нужного события"
else bad "версии: вывод не разбирается как JSON события SessionStart"; fi
rm -rf "$TVD"

# --check-anon: «проверять было нечего» обязано быть кодом 2, а не зелёным нулём.
# Иначе навык разбора читает ноль как «частностей нет» — пустой вывод как доказательство,
# причём в проверке, стоящей между личным адресом и публикацией.
TAN="$(mktemp -d)"; mkdir -p "$TAN/пусто"
python3 "$V" --check-anon "$TAN/нет-такого" >/dev/null 2>&1
if [ $? -eq 2 ]; then ok "22: несуществующий путь --check-anon даёт код 2"; else
  bad "22: несуществующий путь --check-anon не дал кода 2 — «не проверяли» читается как «чисто»"; fi
python3 "$V" --check-anon "$TAN/пусто" >/dev/null 2>&1
if [ $? -eq 2 ]; then ok "22: пустая папка --check-anon даёт код 2"; else
  bad "22: пустая папка --check-anon не дала кода 2"; fi
printf 'чисто\n' > "$TAN/пусто/о.md"
python3 "$V" --check-anon "$TAN/пусто" >/dev/null 2>&1
if [ $? -eq 0 ]; then ok "22: чистый отчёт даёт код 0"; else bad "22: чистый отчёт не зелёный"; fi
rm -rf "$TAN"

echo "── Режимы подключения: два, равноправные ──"
# Режимы живут в двух домах — норме (core.md § 9.3) и процедуре (init). Разъезд домов
# и есть тот дефект, ради которого этот тест написан: текст можно поправить в одном
# месте и не заметить второго.
CORE=../core.md
INIT=../../skills/init/SKILL.md
for f in "$CORE" "$INIT"; do
  n=$(grep -cE '^\| \*\*(Копия|Указатель)\*\*' "$f")
  [ "$n" -eq 2 ] && ok "режимы: в $(basename "$(dirname "$f")")/$(basename "$f") ровно два режима" \
    || bad "режимы: в $f строк режимов $n, а должно быть 2"
done
# «Реплика» убрана как режим: ни один живой случай не подключал ею ЯДРО — тот кейс был
# про базу знаний. Тест сторожит от возврата обобщения впрок.
grep -qE '^\| \*\*Реплика\*\*' "$CORE" "$INIT" \
  && bad "режимы: «Реплика» вернулась в таблицу режимов подключения ядра" \
  || ok "режимы: «Реплика» в таблицах режимов отсутствует"
grep -qE '«Реплика»|режим «реплика»' "$CORE" \
  && bad "режимы: стандарт всё ещё говорит о режиме «Реплика»" \
  || ok "режимы: стандарт о режиме «Реплика» не говорит"
# Равноправие: ни один режим не помечен умолчанием ни в одном доме.
grep -qE '\*\*(Копия|Указатель)\*\* \((по умолчанию|умолчание)\)' "$CORE" "$INIT" \
  && bad "режимы: один из режимов снова помечен умолчанием — равноправие сломано" \
  || ok "режимы: умолчанием не помечен ни один"
# Но у процедуры обязан быть ответ на «не знаю»: сборка не имеет права встать.
grep -q 'не может выбрать — брать копию' "$INIT" \
  && ok "режимы: у навыка есть ответ на «не могу выбрать»" \
  || bad "режимы: навык оставляет сборку висеть на вопросе без ответа"
# Обещание без механизма — отдельный класс дефекта: § 9.3 опирается на записанную
# версию сборки, и если требования о ней в стандарте нет, довод висит в воздухе.
grep -q 'Версия ядра, на которой собран агент, записывается при сборке' "$CORE" \
  && ok "режимы: требование записать версию сборки стоит в стандарте" \
  || bad "режимы: § 9.3 ссылается на версию сборки, а требования записать её нет"
# Дом версии сборки ровно один. Пока стандарт разрешал «либо конфиг, либо метку»,
# сторож знал только метку и говорил «не записано» о записанном — ложный красный.
grep -q 'Дом у этого поля один, и это метка, а не конфиг' "$CORE" \
  && ok "режимы: у версии сборки объявлен один дом" \
  || bad "режимы: стандарт снова разрешает версии сборки два места, а сторож знает одно"
# «Один дом» не запрещает держать базу на двух машинах — но только через систему
# версионирования. Облачная синхронизация переносит правки в обе стороны молча, то есть
# делает ровно то, от чего правило защищает. Без этой оговорки § 6 читается запретом
# законного устройства, и человек либо нарушит его втихую, либо откажется от удобного.
grep -q 'Вся база в двух местах — это не два дома, а дом и его копия' "$CORE" \
  && ok "один дом: две машины разрешены явно" \
  || bad "один дом: § 6 снова читается запретом базы на двух машинах"
grep -q 'системой версионирования (git) — и никак иначе' "$CORE" \
  && ok "один дом: способ синхронизации сужен до git" \
  || bad "один дом: не сказано, что синхронизация только через git — облако разойдётся молча"
# Дубль этой проверки (та же команда под именем «умолчание: …») удалён: он надувал
# счёт на единицу и отчитывался о ЛЮБОМ снятии фразы дважды, создавая видимость двух
# независимых страховок там, где страховка одна.
grep -q '^### 9.3.1' "$CORE" \
  && ok "умолчание: процедура обновления собранного агента заведена" \
  || bad "умолчание: § 9.3.1 (обновление) не найден — путь обновления не закрыт"


echo "── Шаблоны не везут выдуманную дату ──"
# Шаблоны везли created: 2026-01-01, шаг 5 навыка копировал её дословно в живой файл,
# а § 3.1 запрещает выдуманную дату прямым текстом. Класс шире, чем был назван:
# дату везли ТРИ шаблона, а в реестре стоял один.
# Ловим КЛАСС, а не литерал: поиск конкретной даты `created: 2026-01-01` молчал бы
# на любой другой подставленной, хотя дефект в том, что дата ЗАГОТОВЛЕНА, а не
# в конкретных цифрах.
#
# СПИСКА ИМЁН ЗДЕСЬ НЕТ. Словарь дат стандарта — `created`, `updated` (§ 3.3), `as_of`,
# `revisit_after`, и он пополняется; машина со списком имён внутри слепа ровно к тем
# полям, которых в списке нет, а список пишется по памяти. Поэтому берётся признак:
# ЛЮБОЙ ключ frontmatter, чьё значение — голая дата ISO. Новое поле-дата попадёт под
# проверку само, не дожидаясь, пока о нём вспомнят.
DATES=$(python3 - <<'PYD'
import re, glob
плохие = []
for f in sorted(glob.glob('../templates/*.md')):
    for n, line in enumerate(open(f, encoding='utf-8'), 1):
        m = re.match(r'\s*#?\s*([a-z_]+)\s*:\s*(\d{4}-\d{2}(?:-\d{2})?)\s*(?:#.*)?$', line)
        if m:
            плохие.append(f"{f}:{n} {m.group(1)}: {m.group(2)}")
print("\n".join(плохие))
PYD
)
if [ -n "$DATES" ]; then
  bad "шаблон везёт заготовленную дату: $(echo "$DATES" | tr '\n' ' ')"
else ok "ни один шаблон не везёт заготовленную дату (любое поле-дата, оба формата)"; fi
grep -q 'выдуманная дата хуже отсутствующей' ../templates/00-index.md \
  && ok "шаблон индекса называет причину плейсхолдера" \
  || bad "плейсхолдер даты без причины — вернут число «чтобы не ругалось»"
grep -q 'date +%F' "$INIT" \
  && ok "навык подставляет настоящую дату, а не копирует заготовку" \
  || bad "шаг 5 снова копирует дату из шаблона дословно"
# Машина: незаполненный плейсхолдер — НЕ значение. Прежде created: <...> проходил молча.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\nstatus: stable\ncreated: <ГГГГ-ММ-ДД>\ntags: [и]\n---\n- [[A]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: A\ntype: concept\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-08-03\ntags: [и]\n---\nx\n' > "$TMP/A.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "плейсхолдер даты считается незаполненным" "нет \`created\`"
# Обратная сторона: настоящая дата обязана молчать, иначе это ложный красный.
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-08-03\ntags: [и]\n---\n- [[A]]\n' > "$TMP/00-index.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
if echo "$OUT" | grep -q "НЕПОЛНЫЙ"; then bad "настоящая дата даёт ложное предупреждение"; else ok "настоящая дата молчит"; fi
rm -rf "$TMP"

echo "── Проверка 5 называет схлопнутую группу поимённо ──"
# Сообщение говорило «sources схлопнуты», не называя — какие и во что. Чинящий
# пересобирал разбиение вручную, повторяя работу, которую машина уже сделала.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[К]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: К\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]", "[[И2]]"]\nconsensus: confirmed\nsame_root: [["[[И1]]", "[[И2]]"]]\n---\nт [[И1]] [[И2]]\n' > "$TMP/К.md"
for n in И1 И2; do
  printf -- '---\ntitle: %s\ntype: source\nschema_version: "1.0"\nsource_type: research\nreliability: A\n---\nт [[К]]\n' "$n" > "$TMP/$n.md"
done
OUT=$(python3 "$V" "$TMP" 2>&1)
has "расклад по корням напечатан" "Как разложились:"
has "схлопнутые источники названы поимённо" "И1 = И2"
has "знак равенства объяснён" "Знак «=» значит «один корень»"
rm -rf "$TMP"

echo "── Рецепты README и режимы подключения ──"
README=../../README.md
grep -q '00-index.md proba/' "$README" \
  && ok "рецепт «потрогать» берёт индекс, а не только две заметки" \
  || bad "рецепт снова гарантированно даёт красный — без индекса база не зеленеет"
# Ловим РЕЦЕПТ, а не упоминание: `lore-validate --help` разрешено называть в прозе
# («прежде здесь стоял он, и вот почему не годится»), но не подавать как команду
# внутри блока кода. Греп по всему файлу краснел бы на собственном объяснении:
# слово-маркер не отличает утверждение от рассказа о нём.
if python3 -c "
import sys,re
t=open('$README',encoding='utf-8').read()
блоки=re.findall(r'^\`\`\`.*?^\`\`\`', t, re.S|re.M)
sys.exit(1 if any('lore-validate --help' in b for b in блоки) else 0)
"; then ok "справка больше не подаётся как проверка обновления"
else bad "в рецепте снова стоит lore-validate --help — он ничего не проверяет"; fi
grep -q 'слой пользователя' "$INIT" \
  && ok "загрузчик слоя пользователя объявлен в паспорте шага 7" \
  || bad "шаг 6 заводит загрузчик, а паспорт о нём молчит — § 6.3 п. 1 нарушен"
grep -q 'Когда вернуться и закрыть петлю' "$INIT" \
  && ok "сказано, когда возвращаться к доменным типам" \
  || bad "петля доменных типов снова не закрыта ни одним документом"
grep -q 'python3 standard/validate.py knowledge' "$INIT" \
  && ok "в режиме «копия» навык зовёт локальный валидатор" \
  || bad "прогон снова уезжает в версию комплекта"
grep -q 'ведёт в \*\*установленный комплект\*\*' "$CORE" \
  && ok "стандарт называет цену команды поставщика в режиме «копия»" \
  || bad "§ 9.3 п. 7 снова молчит о том, ЧЕМ проверяют"
# Домов у этой команды ЧЕТЫРЕ, а не два. Четвёртый — исполняемый рецепт в навыке
# разбора; именно его пропустил первый заход починки, и машина, поставленная тогда
# на два дома, была слепа ровно к тому, из-за которого находка и возникла.
# Перебор идёт по всем навыкам, а не по названным поимённо: папка навыков растёт.
SKILLS=$(ls ../../skills/*/SKILL.md 2>/dev/null)
[ -n "$SKILLS" ] || bad "навыков не найдено — перебор пуст, а не чист"
BARE=""
for s in $SKILLS; do
  grep -q 'lore-validate' "$s" || continue
  grep -q 'standard/validate.py' "$s" || BARE="$BARE $(basename "$(dirname "$s")")"
done
[ -z "$BARE" ] \
  && ok "каждый навык, зовущий валидатор, разведён по режимам ($(echo "$SKILLS" | grep -c .) навыка)" \
  || bad "навык зовёт только lore-validate, без локального пути:$BARE — в режиме «копия» прогон уедет в комплект поставщика"

echo "── Источник, названный markdown-ссылкой, — тот же корень ──"
# `sources: ["[[И]]", "[И](И.md)"]` — один файл, названный двумя формами. Пока разбор
# знал только wiki-форму, проверка 5 печатала «✅ Консенсус обеспечен корнями» на одном
# источнике: базу краснила другая проверка, то есть зелёного прогона обход не давал,
# но в ОТЧЁТЕ стояла неправда, а отчёт и есть то, что человек читает.
TMP=$(mktemp -d)
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\n---\n- [[К]]\n' > "$TMP/00-index.md"
printf -- '---\ntitle: К\ntype: knowledge\nschema_version: "1.0"\nsources: ["[[И1]]", "[И1](И1.md)"]\nconsensus: confirmed\n---\nт [[И1]]\n' > "$TMP/К.md"
printf -- '---\ntitle: И1\ntype: source\nschema_version: "1.0"\nsource_type: research\nreliability: A\n---\nт [[К]]\n' > "$TMP/И1.md"
OUT=$(python3 "$V" "$TMP" 2>&1)
has "две формы одной ссылки схлопываются в один корень" "при 1 независимом корне"
if echo "$OUT" | grep -q "✅ Консенсус обеспечен корнями"; then
  bad "консенсус объявлен обеспеченным на одном источнике, названном дважды"
else ok "ложного «консенсус обеспечен» на двух формах одного имени нет"; fi
if echo "$OUT" | grep -q "не ведёт ни в одну заметку базы"; then
  bad "markdown-форма в sources ложно объявлена несуществующей заметкой"
else ok "markdown-форма в sources разрешается в заметку"; fi
rm -rf "$TMP"

echo "── Шапка валидатора перечисляет все проверки, а не часть ──"
# Шапка кончалась на 21 при 22 проверках в коде — файл врал о самом себе там,
# где его читают, чтобы узнать, что он делает. Класс «текст врёт о машине».
# Сверяется СОСТАВ, а не количество. Пока сравнивались два числа, задвоенный номер в
# шапке проходил молча: перечень называл один номер дважды и не называл другой, счёт
# при этом сходился — то есть «текст врёт о машине» ровно в том виде, ради которого
# проверка и написана. Номера сравниваются множествами, и расхождение печатается
# поимённо: чинящему нужен номер, а не разница счётчиков.
HEAD_CHECKS=$(python3 - "$V" <<'PYH'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
в_коде = {int(n) for n in re.findall(r'── (\d+)\.', src)}
шапка = src.split("Зависимость: PyYAML")[0]
в_шапке = [int(n) for n in re.findall(r'^ +(\d+)\. ', шапка, re.M)]
дубли = sorted({n for n in в_шапке if в_шапке.count(n) > 1})
только_код = sorted(в_коде - set(в_шапке))
только_шапка = sorted(set(в_шапке) - в_коде)
беды = []
if дубли:        беды.append("в шапке дважды: " + ", ".join(map(str, дубли)))
if только_код:   беды.append("есть в коде, нет в шапке: " + ", ".join(map(str, только_код)))
if только_шапка: беды.append("есть в шапке, нет в коде: " + ", ".join(map(str, только_шапка)))
print(("BAD " + "; ".join(беды)) if беды else f"OK шапка перечисляет все проверки кода ({len(в_коде)})")
PYH
)
case "$HEAD_CHECKS" in
  OK*) ok "${HEAD_CHECKS#OK }" ;;
  *)   bad "${HEAD_CHECKS#BAD }" ;;
esac

echo "── Список комплекта «Копия» совпадает во всех трёх домах ──"
# Он жил в трёх местах и не сверялся ничем: таблица стандарта, проза навыка и
# исполняемая команда cp. Новый файл, внесённый в один дом, у пользователя режима
# «Копия» не появился бы, а стандарт продолжал бы на него ссылаться.
SET_OUT=$(python3 - "$CORE" "$INIT" <<'PYEOF'
import re, sys
core = open(sys.argv[1], encoding='utf-8').read()
init = open(sys.argv[2], encoding='utf-8').read()
tbl = re.search(r'\*\*Комплект «Копия» — поимённо\*\*.*?(?=\n\n\*\*Шаг 2)', core, re.S)
if not tbl:
    print("BAD таблица комплекта в § 9.3 не найдена — сверять не с чем"); sys.exit(0)
# tests/ объявлен необязательным в самой таблице — из обязательного набора исключаем
из_таблицы = {f for f in re.findall(r'^\| `([^`]+)`', tbl.group(0), re.M) if f != 'tests/'}
проза = re.search(r'\*\*Копия\*\* — перенести поимённо.*?\n\n', init, re.S)
из_прозы = set(re.findall(r'`([^`]+)`', проза.group(0))) if проза else set()
из_прозы = {f for f in из_прозы if f != 'tests/'}
cmd = re.search(r'cp "\$CLAUDE_PLUGIN_ROOT"/standard/\{([^}]+)\}', init)
из_команды = set(cmd.group(1).split(',')) if cmd else set()
# Ловим КОМАНДУ, а не упоминание пути: удали строку `cp`, оставь путь в прозе —
# и проверка на упоминание осталась бы зелёной.
if re.search(r'^\s*cp\s+[^\n]*standard/templates/\*\.md', init, re.M):
    из_команды.add('templates/')
for имя, множество in (('проза навыка', из_прозы), ('команда cp', из_команды)):
    лишнее, нехватка = множество - из_таблицы, из_таблицы - множество
    if лишнее or нехватка:
        print(f"BAD {имя} расходится с таблицей § 9.3: лишнее {sorted(лишнее)}, нет {sorted(нехватка)}")
        sys.exit(0)
# Третья сверка — С ДИСКОМ. Без неё тест ловит расхождение ТЕКСТОВ и никогда —
# файл, который физически лежит в standard/ и не назван ни в одном доме. А дефект
# сформулирован именно так: «новый файл комплекта у пользователей не появится».
import os
на_диске = set()
for имя in os.listdir('../'):
    if имя in ('tests', '__pycache__') or имя.startswith('.'):
        continue
    на_диске.add(имя + '/' if os.path.isdir(os.path.join('../', имя)) else имя)
неназванные = на_диске - из_таблицы
if неназванные:
    print(f"BAD в standard/ лежит то, чего нет в таблице § 9.3: {sorted(неназванные)} — "
          f"у пользователя режима «Копия» этих файлов не появится")
    sys.exit(0)
нет_на_диске = из_таблицы - на_диске
if нет_на_диске:
    print(f"BAD таблица § 9.3 называет то, чего в standard/ нет: {sorted(нет_на_диске)}")
    sys.exit(0)
print("OK три дома списка комплекта и диск совпадают (%d файлов)" % len(из_таблицы))
PYEOF
)
case "$SET_OUT" in
  OK*) ok "${SET_OUT#OK }" ;;
  *)   bad "${SET_OUT#BAD }" ;;
esac

echo "── Пометка архивности в sources: работает, и не делает архивом саму заметку ──"
# § 7.4 требует маркер «в строке ссылки», но `sources:` — не проза: во frontmatter
# слово «архив» некуда вписать, не испортив имени источника. Рецепт § 7.4 —
# комментарий той же строки. Он работает только вместе с тем, что шапка архива
# ищется в ТЕЛЕ: пока её искали в начале файла целиком, этот же комментарий
# объявлял архивной саму ссылающуюся заметку, и правило требовало пометку на неё.
TA=$(mktemp -d); mkdir -p "$TA/knowledge"
printf -- '---\ntitle: 00-index\ntype: moc\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-08-03\ntags: [и]\n---\n- [[Факт]]\n- [[Приказ]] — исторический снимок\n' > "$TA/knowledge/00-index.md"
printf -- '---\ntitle: Приказ\ntype: source\nschema_version: "1.0"\nstatus: archived\ncreated: 2026-08-03\ntags: [и]\n---\nотменённый документ\n' > "$TA/knowledge/Приказ.md"
факт() { printf -- '---\ntitle: Факт\ntype: knowledge\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-08-03\ntags: [и]\nsources: ["[[Приказ]]"]%s\n---\nПравила отменены.\n' "$1" > "$TA/knowledge/Факт.md"; }
факт '   # исторический снимок: правила отменены'
OUT=$(python3 "$V" "$TA/knowledge" 2>&1)
echo "$OUT" | grep -q 'Факт.md.*ссылка на архив' \
  && bad "рецепт § 7.4 не работает: помеченная комментарием ссылка всё равно красная" \
  || ok "пометка архивности комментарием строки sources принимается (§ 7.4)"
echo "$OUT" | grep -q 'ссылка на архив «Факт»' \
  && bad "пометка на строке sources объявила архивом саму заметку" \
  || ok "пометка в sources не делает архивом ссылающуюся заметку"
факт ''
python3 "$V" "$TA/knowledge" 2>&1 | grep -q 'Факт.md.*ссылка на архив' \
  && ok "без пометки та же ссылка краснеет (правило не ослаблено)" \
  || bad "ложно-зелёный: ссылка на архив без пометки прошла"
printf -- '---\ntitle: Старьё\ntype: source\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-08-03\ntags: [и]\n---\n**Исторический снимок** на 2024-05.\n' > "$TA/knowledge/Старьё.md"
# Шапка с указателем на преемника — идиома, которую поощряет § 6 п. 4 («где второй
# дом неизбежен, кладу указатель»). Пока отбрасывалась любая строка со ссылкой,
# такая шапка переставала быть шапкой, и проверка 6 выключалась для заметки ЦЕЛИКОМ.
printf -- '---\ntitle: Отменённый\ntype: source\nschema_version: "1.0"\nstatus: stable\ncreated: 2026-08-03\ntags: [и]\n---\n**Исторический снимок.** Правила отменены; актуальное — [[Факт]].\n' > "$TA/knowledge/Отменённый.md"
printf -- '- [[Отменённый]]\n' >> "$TA/knowledge/00-index.md"
python3 "$V" "$TA/knowledge" 2>&1 | grep -q 'ссылка на архив «Отменённый»' \
  && ok "шапка архива с указателем на преемника остаётся шапкой (§ 6 п. 4)" \
  || bad "шапка с указателем перестала считаться архивом — проверка 6 выключена для заметки"
# Имя-ловушка: у архивной заметки, чьё ИМЯ содержит слово-маркер, любая ссылка
# выглядела уже помеченной — маркер искался по всей строке, включая имя ссылки.
printf -- '---\ntitle: Отмена приказа\ntype: source\nschema_version: "1.0"\nstatus: archived\ncreated: 2026-08-03\ntags: [и]\n---\nтекст\n' > "$TA/knowledge/Отмена приказа.md"
printf -- '- [[Отмена приказа]]\n' >> "$TA/knowledge/00-index.md"
python3 "$V" "$TA/knowledge" 2>&1 | grep -q 'ссылка на архив «Отмена приказа»' \
  && ok "слово-маркер в ИМЕНИ архива не считается пометкой ссылки на него" \
  || bad "ложный зелёный: имя архива работает пометкой само на себя"
printf -- '- [[Старьё]]\n' >> "$TA/knowledge/00-index.md"
python3 "$V" "$TA/knowledge" 2>&1 | grep -q 'ссылка на архив «Старьё»' \
  && ok "шапка «исторический снимок» в ТЕЛЕ по-прежнему опознаётся как архив" \
  || bad "архив, объявленный шапкой в теле, перестал опознаваться"
rm -rf "$TA"

echo "── Каждый пример YAML в комплекте обязан разбираться ──"
# Машины не было, и это стоило регресса в тот же день, когда её отсутствие заметили:
# в паспорт добавили строку `size: <измерить: du -sb my/ | cut -f1>` — двоеточие
# внутри плейсхолдера сломало разбор ВСЕГО примера. Файл называется config.yaml,
# § 9.3 п. 6 объявляет его домом комплектации, а пример не читал ни один парсер.
# Проверять глазами нельзя: YAML ломается символом, который в прозе незаметен.
#
# ПЕРЕБОР ИДЁТ ПО КЛАССУ, А НЕ ПО АДРЕСУ: берутся ВСЕ файлы комплекта и ВСЕ блоки
# в них. Машина, читающая один файл — тот, где дефект заметили первым, — слепа ко
# всему остальному классу, а класс тут широкий: двоеточие внутри плейсхолдера
# ломает любой пример, не только пример конфига.
YAML_OUT=$(python3 - <<'PYY'
import re, sys, pathlib, shlex
try:
    import yaml
except ImportError:
    print("SKIP PyYAML нет — примеры не проверены (это не «примеры валидны»)"); sys.exit(0)
# Забор кода собирается из кода символа: обратная кавычка внутри $( … ) обрывает
# разбор команды в оболочке, и тест падал ещё до первой проверки.
З = chr(96) * 3
корень = pathlib.Path("../..")
файлы = sorted(p for p in корень.rglob("*.md") if "__pycache__" not in p.parts)
всего = 0
for f in файлы:
    t = f.read_text(encoding="utf-8")
    # Забор ловится ВМЕСТЕ С ОТСТУПОМ: блок внутри пункта списка отбит пробелами, и
    # образец, прижатый к началу строки, таких блоков не видит вовсе. Отступ потом
    # снимается с каждой строки — иначе YAML увидит лишний уровень вложенности.
    блоки = []
    for m in re.finditer(r'^([ \t]*)' + З + r'yaml\n(.*?)^\1' + З, t, re.S | re.M):
        отступ = m.group(1)
        блоки.append("\n".join(l[len(отступ):] if l.startswith(отступ) else l
                               for l in m.group(2).splitlines()))
    for n, b in enumerate(блоки, 1):
        всего += 1
        try:
            куски = [d for d in yaml.safe_load_all(b) if isinstance(d, dict)]
        except Exception as e:
            print(f"BAD {f}: блок yaml №{n} не разбирается: {str(e).splitlines()[0]}")
            sys.exit(0)
        # Мало «разбирается»: значение, которое кто-то ЗАПУСКАЕТ, обязано быть
        # запускаемым. Комментарии-решётки внутри свёрнутого скаляра `>` YAML
        # считает текстом, пример разбирается — и уезжает в argv целиком.
        for d in куски:
            v = d.get("validate")
            cmd = (v or {}).get("command") if isinstance(v, dict) else None
            if not cmd:
                continue
            argv = shlex.split(cmd)
            if any(a.startswith("#") for a in argv):
                print(f"BAD {f}: блок yaml №{n} — в команде прогона остался "
                      f"комментарий: {argv[:8]}. Решётка внутри блока «>» — это "
                      f"текст, а не комментарий; объяснения кладутся НАД ключом")
                sys.exit(0)
if всего == 0:
    print("BAD в комплекте нет ни одного блока yaml — проверять нечего, а паспорт обещан")
    sys.exit(0)
# Число разобранных блоков сверяется с числом ЗАБОРОВ на диске. Без этого разбор
# можно молча сузить — например перестать понимать блоки с отступом, — и прогон
# останется зелёным просто потому, что проверять станет нечего: единственным
# условием провала было «ни одного блока». Забор считается независимо от того,
# как устроен разбор, поэтому сужение разбора сразу видно.
# Обратных кавычек в этом блоке нет намеренно: он лежит внутри $( … ), и
# кавычка оборвала бы разбор команды оболочкой ещё до первой проверки.
заборов = sum(len(re.findall(r'^[ \t]*' + З + r'yaml$', f.read_text(encoding="utf-8"), re.M))
              for f in файлы)
if всего != заборов:
    print(f"BAD разобрано блоков {всего}, а меток забора yaml на диске {заборов}. "
          f"Разбор у́же класса: часть блоков не проверяется вовсе")
    sys.exit(0)
print(f"OK все примеры yaml в комплекте разбираются и запускаемы ({всего} в {len(файлы)} файлах)")
PYY
)
case "$YAML_OUT" in
  OK*)   ok "${YAML_OUT#OK }" ;;
  SKIP*) ok "${YAML_OUT#SKIP }" ;;
  *)     bad "${YAML_OUT#BAD }" ;;
esac

echo "── Копия комплекта вместе с tests/ не краснит собственный прогон ──"
# Таблица § 9.3 объявляет tests/ необязательными, но не запрещает их копировать.
# Пока --core их не отсекал, скопировавший комплект целиком получал на первом
# прогоне красный экран из НАМЕРЕННО сломанных заготовок — и ни одна ошибка не была
# про его базу. Первое знакомство с продуктом, у которого «зелёный молчит».
TMP=$(mktemp -d)
mkdir -p "$TMP/standard" "$TMP/knowledge"
cp -R ../../standard/* "$TMP/standard/" 2>/dev/null
rm -rf "$TMP/standard/__pycache__"
mv "$TMP/standard/templates" "$TMP/standard/_templates" 2>/dev/null
sed "s|^created: <.*>$|created: 2026-01-02|" ../templates/00-index.md \
  | sed 's|^title: <.*>$|title: 00-index|' > "$TMP/knowledge/00-index.md"
OUT=$(cd "$TMP" && python3 standard/validate.py knowledge --core standard 2>&1); RC=$?
if echo "$OUT" | grep -q "tests/fixtures"; then
  bad "прогон копии ругается на собственные фикстуры комплекта"
else ok "фикстуры смоук-теста в --core не попадают"; fi
if [ "$RC" -eq 0 ]; then ok "копия вместе с tests/ даёт зелёный прогон"
else bad "exit $RC: копия комплекта краснит сама себя, а не базу пользователя"; fi
rm -rf "$TMP"

echo "── Хук о собственной поломке говорит вслух, а не молчит ──"
# Сломанный сторож, о котором не сказали, — это ложное чувство защиты. Довод про шум
# («хук отрабатывает при каждом старте») здесь не перевешивает: без Python в комплекте
# не работает вообще ничего, а кому шум не нужен — выключает хук у себя. Проверяем обе
# стороны: поломка слышна, исправная работа тиха.
TMP=$(mktemp -d)
printf 'версия: 0.21.0\nрежим: копия\n' > "$TMP/.loreground"
# СПИСКА ИМЁН ЗДЕСЬ НЕТ, и это тот же приём, что выше у дат. Папка хуков растёт, а
# список имён, набранный по памяти, растёт не всегда: новый хук проходил бы смоук
# молча, даже если бы глушил свою поломку. Список берётся с диска.
HOOKS=$(ls ../../hooks/*.py | xargs -n1 basename | sed 's/\.py$//' | grep -v '^_')
HOOKS_N=$(echo "$HOOKS" | grep -c .)
[ "$HOOKS_N" -gt 0 ] || bad "в hooks/ не найдено ни одного хука — перебор пуст, а не чист"
MUTE=0
NOISY=0
NOCMD=0
for h in $HOOKS; do
  # Копируется вся папка хуков: ответ на собственную поломку живёт в соседнем
  # файле (один дом на четыре хука), и хук без него — не тот хук, что у людей.
  mkdir -p "$TMP/hooks"
  cp ../../hooks/*.py "$TMP/hooks/"
  sed "s|^def main():|def main():\n    raise RuntimeError('сбой изнутри хука')|" \
    ../../hooks/$h.py > "$TMP/hooks/$h.py"
  OUT=$(cd "$TMP" && echo '{}' | python3 "$TMP/hooks/$h.py" 2>&1); RC=$?
  echo "$OUT" | grep -q "не отработал" || MUTE=$((MUTE+1))
  [ "$RC" -eq 0 ] || MUTE=$((MUTE+1))
  # Команда для ручного прогона обязана быть готовой к копированию: свой интерпретатор
  # и свой путь. `python3 <папка плагина>/…` заставляло искать папку самому, а `python3`
  # на машине с двумя Python мог и не воспроизвести поломку.
  echo "$OUT" | grep -qF "$SELF $TMP/hooks/$h.py" || NOCMD=$((NOCMD+1))
  # исправный хук на исправном проекте про поломку молчать обязан
  OUT2=$(cd "$TMP" && echo '{}' | python3 ../../hooks/$h.py 2>&1)
  echo "$OUT2" | grep -q "не отработал" && NOISY=$((NOISY+1))
done
if [ "$MUTE" -eq 0 ]; then ok "все хуки папки ($HOOKS_N) называют свою поломку вслух и не роняют сессию"
else bad "$MUTE проверок провалено: хук глушит свою поломку либо роняет старт"; fi
if [ "$NOCMD" -eq 0 ]; then ok "поломка: команда ручного прогона готова к копированию (свой Python, свой путь)"
else bad "$NOCMD хук(ов) дают команду с заглушкой вместо пути или интерпретатора"; fi
if [ "$NOISY" -eq 0 ]; then ok "исправный хук о поломке не заявляет (ложного шума нет)"
else bad "$NOISY хуков кричат о поломке на исправной работе — ложный красный"; fi
rm -rf "$TMP"

case "$FAIL" in
  *1[1-4]) FW=провалов ;;
  *1) FW=провал ;;
  *[2-4]) FW=провала ;;
  *) FW=провалов ;;
esac
echo "Итого: $PASS ок, $FAIL $FW"
[ "$FAIL" -eq 0 ] || exit 1
