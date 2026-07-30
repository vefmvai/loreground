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
OUT=$(python3 "$V" /nonexistent-base-dir --core ../core.md 2>&1)
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
OUT=$(python3 "$V" /nonexistent-base-dir --core "$TMP/core-en.md" 2>&1); RC=$?
has "английский маркер статуса виден" "docs/absent.md"
if [ "$RC" -eq 1 ]; then ok "англоязычная база не зеленеет молча"; else bad "exit $RC — проверка 7 промолчала"; fi
# cwd больше не спасает: рядом с местом запуска путь есть, рядом с файлом — нет
CWDT=$(mktemp -d); mkdir -p "$CWDT/docs"; : > "$CWDT/docs/absent.md"
OUT=$(cd "$CWDT" && python3 "$VABS" /nonexistent-base-dir --core "$TMP/core-en.md" 2>&1)
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
OUT=$(python3 "$V" /nonexistent-base-dir --core "$TMP/prose.md" 2>&1); RCP=$?
if echo "$OUT" | grep -q "ССЫЛКИ СТАТУСОВ"; then bad "ложная ошибка на DOI/URL или тексте со слешем"; else ok "DOI, A/B-тест и 50/50 не считаются путями"; fi
# URL, КОНЧАЮЩИЙСЯ на .md — единственная форма, которую фильтр `.md` пропускает,
# и ради которой написан отсев схемы.
printf -- 'Ссылка [подтверждено — https://raw.githubusercontent.com/a/b/README.md].\n' > "$TMP/urlmd.md"
OUT=$(python3 "$V" /nonexistent-base-dir --core "$TMP/urlmd.md" 2>&1); RCU=$?
if echo "$OUT" | grep -q "ССЫЛКИ СТАТУСОВ"; then bad "URL на .md принят за путь к файлу"; else ok "URL на .md не считается путём"; fi
if [ "$RCU" -eq 0 ]; then ok "статус со ссылкой на веб зеленеет"; else bad "exit $RCU"; fi
if [ "$RCP" -eq 0 ]; then ok "честная проза со слешами зеленеет"; else bad "exit $RCP на исправном тексте"; fi
OUT=$(python3 "$V" /nonexistent-base-dir --core "$TMP/doc.md" 2>&1); RC=$?
has "статус без бэктиков проверяется" "docs/absent.md"
if [ "$RC" -eq 1 ]; then ok "путь без бэктиков роняет прогон"; else bad "exit $RC — статус молча зелёный"; fi
# существующий путь без бэктиков ложной ошибки не даёт
mkdir -p "$TMP/docs" && printf 'x\n' > "$TMP/docs/present.md"
printf -- 'Утверждение [подтверждено — docs/present.md] тут.\n' > "$TMP/doc2.md"
OUT=$(python3 "$V" /nonexistent-base-dir --core "$TMP/doc2.md" 2>&1); RC=$?
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
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=lim)
    print(p.stdout, end="")
    sys.exit(p.returncode)
except subprocess.TimeoutExpired:
    print("ТАЙМАУТ-ПРОГОНА")
    sys.exit(99)
PY
}
TMP=$(mktemp -d)
printf 'Факт [подтверждено — `/*/*/*/*/*/*/*/*/nope.md`].\n' > "$TMP/bomb.md"
OUT=$(run_limited 15 python3 "$V" /nonexistent-base-dir --core "$TMP/bomb.md"); RC=$?
if [ "$RC" -eq 99 ]; then bad "глоб в токене вешает прогон"; else ok "глоб в токене не вешает прогон"; fi
has "глоб-токен объявлен несуществующим" "ССЫЛКИ СТАТУСОВ"
# оракул: существующий абсолютный путь обязан быть неотличим от выдуманного
printf 'Факт [подтверждено — `/etc/passwd`].\n' > "$TMP/abs1.md"
printf 'Факт [подтверждено — `/etc/definitely-not-here-xyz.md`].\n' > "$TMP/abs2.md"
O1=$(run_limited 15 python3 "$V" /nonexistent-base-dir --core "$TMP/abs1.md" | grep -c "ССЫЛКИ СТАТУСОВ")
O2=$(run_limited 15 python3 "$V" /nonexistent-base-dir --core "$TMP/abs2.md" | grep -c "ССЫЛКИ СТАТУСОВ")
if [ "$O1" = "$O2" ]; then ok "абсолютный путь не работает оракулом чужой ФС"; else bad "по выводу видно, есть ли файл на чужой машине"; fi
printf 'Факт [подтверждено — `../../../../etc/passwd`].\n' > "$TMP/up.md"
OUT=$(run_limited 15 python3 "$V" /nonexistent-base-dir --core "$TMP/up.md")
has "выход вверх (..) не резолвится" "ССЫЛКИ СТАТУСОВ"
# ОТНОСИТЕЛЬНЫЙ глоб: страж абсолютных путей его не отсекает, значит эта фикстура
# проверяет именно экранирование. Без неё поломка `glob.escape` прошла бы молча —
# бомба выше абсолютная, и её ловил другой страж.
printf -- 'Факт [подтверждено — `*/*/*/*/*/*/*/*/nope.md`].\n' > "$TMP/relbomb.md"
OUT=$(run_limited 15 python3 "$V" /nonexistent-base-dir --core "$TMP/relbomb.md"); RC=$?
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
open(d+'/x.md','w').write('---\ntitle: D\ntype: concept\nschema_version: \"1.0\"\ndeep: '+'['*3000+']'*3000+'\n---\nx\n')" "$TMP/deep"
OUT=$(python3 "$V" "$TMP/deep" 2>&1)
if echo "$OUT" | grep -q "Traceback"; then bad "аномальная вложенность роняет трейсбеком"; else ok "аномальная вложенность — сообщение, не трейсбек"; fi
has "вложенность названа поимённо" "вложен слишком глубоко"

echo "── Дыры покрытия, найденные мутацией валидатора ──"
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

echo "── Исполнитель паспорта стартовой загрузки (SessionStart-хук) ──"
# Паспорт § 6.3 до этого хука был декларацией. Проверяется ровно граница исполнения:
# by: hook грузится, by: rules и by: env — нет, и молчание отличимо от «нечего грузить».
KIT="$(cd ../.. && pwd)"
TSL="$(mktemp -d)"
sl() { (cd "$TSL" && CLAUDE_PROJECT_DIR="$TSL" python3 "$KIT/hooks/startup-load.py"); }
ctx() { python3 -c "
import sys, json
raw = sys.stdin.read().strip()
sys.stdout.write(json.loads(raw)['hookSpecificOutput']['additionalContext'] if raw else '')"; }

# Ворота проверяются на проекте, которому ЕСТЬ что грузить: иначе молчание объясняется
# отсутствием конфига, и снятие ворот проходит незамеченным. Мутация «снять ворота»
# первую редакцию этого случая не роняла — тест был ложно-зелёным.
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

printf '# Правила\n\nверсия кодекса %s\n' "$SRCV" > "$THK/CLAUDE.md"
OUT=$(hook "$KIT")
if [ -z "$OUT" ]; then ok "хук: совпавшие версии — молчание"; else bad "хук: шумит на свежей копии"; fi

printf '# Правила\n\nверсия кодекса 0\n' > "$THK/CLAUDE.md"
OUT=$(hook "$KIT"); RC=$?
has "хук: расхождение названо" "устарел"
has "хук: названа версия источника" "источник версии $SRCV"
has "хук: правку без согласия человека запрещает" "без его согласия не переписывай"
if [ "$RC" -eq 0 ]; then ok "хук: код выхода 0 и при находке"; else bad "хук: код выхода $RC сорвёт старт"; fi

# Вывод обязан быть разбираемым: сломанный JSON хост молча выбросит.
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['hookSpecificOutput']['hookEventName']=='SessionStart' else 1)" 2>/dev/null; then
  ok "хук: вывод — валидный JSON нужного события"
else bad "хук: вывод не разбирается как JSON события SessionStart"; fi
rm -rf "$THK"


case "$FAIL" in
  *1[1-4]) FW=провалов ;;
  *1) FW=провал ;;
  *[2-4]) FW=провала ;;
  *) FW=провалов ;;
esac
echo "Итого: $PASS ок, $FAIL $FW"
[ "$FAIL" -eq 0 ] || exit 1
