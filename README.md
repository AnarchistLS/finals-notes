# THE FINALS · Патчноуты

Персональное приложение (Flutter) для отслеживания обновлений THE FINALS:
номер патча, дата, текст изменений, скриншоты из обновления и — главное —
сравнение числовых показателей «было → стало» с цветовой подсветкой.

## Где что живёт

| Что | Адрес |
|---|---|
| Mini App (веб) | https://anarchistls.github.io/finals-notes/ |
| Mini App в Telegram | https://t.me/finals_notes_bot/app |
| Репозиторий и запуски | https://github.com/AnarchistLS/finals-notes/actions |

Бот проверяет сайт каждые 15 минут по расписанию GitHub Actions: новый патч
переводится один раз, публикуется в канал и попадает в данные Mini App.

## Что уже умеет
- Тянет патчноуты с `reachthefinals.com` через машиночитаемый JSON
  (`?format=json`), без парсинга HTML-вёрстки списка.
- Разбирает тело статьи: заголовки, категории (`Gadgets`, `Weapons`, …),
  предметы (`Zipline`, `ARN-220`) и пункты списка.
- Находит числовые изменения в прозе официальных заметок:
  `Decreased cooldown from 37s to 30s`, `Increased max placement distance from 40m to 50m`.
- Понимает, что «лучше», а что «хуже»: для кулдауна и перезарядки снижение —
  улучшение (зелёный), для урона и обоймы снижение — ухудшение (красный).
- Подсвечивает изменённые числа прямо в тексте патчноута.
- Кеширует последний ответ и работает без сети.
- Интерфейс, названия характеристик и текст патчей — по-русски; имена
  предметов, локаций, классов и специализаций остаются как в игре.

## Локализация

- Словарь терминов (`lib/l10n/glossary.dart`) переводит названия
  характеристик мгновенно и без сети: `cooldown` → «кулдаун»,
  `magazine size` → «размер магазина», `Duration of Smoke` → «длительность дыма».
  Фраза переводится словарём только целиком: если словарь её не знает,
  она уходит в машинный перевод — гибридов вроде «Длительность of дым»
  в интерфейсе не бывает.
- Текст пунктов переводится машинно (`lib/services/translator.dart`),
  результат кешируется на устройстве. Движка два: **DeepL** (точнее на связном
  тексте, нужен ключ) и **Google** (без ключа и лимитов). Переключение —
  в настройках; если DeepL недоступен (нет ключа, кончилась квота, регион
  заблокирован), приложение само уходит на Google и не показывает ошибок.
- Строки переводятся пакетами: до 40 строк или 3000 символов за один запрос.
  Крупный патчноут не ждёт сотни отдельных обращений к сервису, а готовые
  переводы появляются в интерфейсе по мере поступления.
- Ключ DeepL в сборку не вшит: он передаётся только при сборке APK
  (`--dart-define=DEEPL_KEY=...`, см. `tool/build-apk.ps1`), поэтому в
  опубликованном веб-коде его нет. В настройках ключ можно ввести вручную —
  там же кнопка «Проверить ключ»: она показывает расход символов за месяц
  и точную причину, если DeepL не отвечает.
- DeepL отдаёт `451 Unavailable in your region` из некоторых стран (в том числе
  из России). Тогда нужен VPN на телефоне или свой прокси: поле «Прокси»
  в настройках принимает адрес сервиса, совместимого с DeepL API (например,
  Cloudflare Worker, который подставляет ключ).
- Перед переводом имена собственные (`ARN-220`, `Monaco`, `Light`,
  `Grappling Hook`) заменяются маркерами и возвращаются обратно, чтобы
  переводчик их не искажал.
- Перевод можно выключить в настройках (иконка в правом верхнем углу).

## Бот для Telegram-канала

Тот же разбор и перевод, но без приложения: бот следит за сайтом и публикует
новый патч в канал.

- **Дайджест** (по умолчанию) — версия, дата, счётчик усилений и ослаблений
  и все изменения баланса стрелками `▲`/`▼`. Обычно влезает в одно сообщение;
  если патч без числовых изменений — показываются заголовки и пункты.
- **Полный текст** (`--full`) — весь переведённый патч, разбитый на сообщения
  по 4096 символов.

### Настройка

1. Создайте бота у [@BotFather](https://t.me/BotFather) и получите токен.
2. Добавьте бота в канал администратором с правом «Публиковать сообщения».
3. Скопируйте `tool\bot.env.example` в `tool\bot.env` и заполните
   `TELEGRAM_BOT_TOKEN` и `TELEGRAM_CHANNEL` (`@username` или `-100…`).
4. Проверьте вёрстку без отправки:

```powershell
dart run tool/bot.dart --dry-run
```

5. Опубликуйте последний патч:

```powershell
dart run tool/bot.dart --once
```

6. Дальше — либо запускать вручную, либо держать в фоне:

```powershell
dart run tool/bot.dart --watch --interval=600
```

Если в канале уже есть старые патчи, начните с `--init`: бот запомнит текущий
патч и не будет публиковать его повторно.

### Ключи

| Ключ | Что делает |
|---|---|
| `--dry-run` | показать сообщения, ничего не отправляя |
| `--once` | проверить и опубликовать новый патч (по умолчанию) |
| `--watch --interval=600` | проверять сайт каждые 10 минут |
| `--full` | публиковать весь текст, а не дайджест |
| `--patch=ID` | взять конкретный патч (id из `--list`) |
| `--list` | показать найденные патчи |
| `--force` | опубликовать, даже если патч уже был |
| `--init` | запомнить текущий патч без публикации |

### Где держать

Бот — обычный консольный Dart-процесс, но держать компьютер включённым не
обязательно: есть готовый workflow `.github/workflows/update.yml`, который
раз в 15 минут запускает `tool/bot.dart --once` на GitHub Actions. Если хостинг
в России, DeepL ответит `451 Unavailable in your region` — бот сам уйдёт на
Google (в логе будет `движок: Google (DeepL недоступен)`), либо укажите
`DEEPL_ENDPOINT` с прокси. На раннере GitHub блокировки нет, поэтому DeepL
там работает без VPN.

Состояние и кеш переводов лежат в `tool/.bot-state.json` и
`tool/.translation-cache.json` и коммитятся в репозиторий: так CI не постит
один патч дважды и не тратит квоту DeepL на уже переведённые строки.

## Mini App в Telegram

Тот же интерфейс, но открывается прямо в Telegram — по кнопке под постом или
по прямой ссылке. Отдельного сервера нет: это статическая сборка Flutter Web,
а переводы считаются заранее.

### Как устроено

```
GitHub Actions (раз в 15 минут, ~1–2 мин)
  └─ tool/bot.dart --once      пост в канал + кнопка «Открыть приложение»
  └─ tool/publish.dart         web/data/patches_ru.json (текст + переводы)
  └─ коммит данных
GitHub Pages
  └─ build/web + data/patches_ru.json  ← читает Mini App
```

Хостинг — GitHub Pages (`https://<логин>.github.io/finals-notes/`), а не
Cloudflare Pages: провайдеры в России блокируют `*.pages.dev`, домен
подменяется заглушкой. `github.io` открывается без VPN.

- `tool/publish.dart` тянет патчи, переводит их один раз и пишет
  `web/data/patches_ru.json`: сам патч плюс карта «оригинал → перевод».
- Mini App читает этот файл с того же домена (`lib/data/published.dart`),
  поэтому не упирается в CORS сайта и ничего не переводит на телефоне.
  Настройки движка и ключей в Mini App скрыты — они там не нужны.
- Если файла нет (обычный `flutter run -d chrome`), приложение работает
  по-старому: тянет сайт и переводит на лету.
- Кеш переводов общий с ботом, поэтому новый патч переводится один раз.
- `patches_ru.json` перезаписывается только когда патчи или переводы реально
  изменились: иначе файл менялся бы каждые 15 минут, а каждый коммит запускал
  бы сборку и деплой.
- Расписание GitHub — раз в 10 минут, но сам GitHub выполняет его примерно
  раз в 40 минут (троттлинг планировщика). Поэтому частые проверки — каждые
  15 минут — делает внешний cron-job.org: он вызывает `workflow_dispatch`
  через API. Расписание GitHub остаётся страховкой на случай, если внешний
  cron перестанет работать.
- Деплой сайта запускается только когда данные реально изменились, иначе
  каждые 15 минут впустую собиралась бы Flutter-сборка.
- GitHub отключает расписание в публичном репозитории после 60 дней без
  коммитов, поэтому раз в месяц workflow сам коммитит `tool/.last-run`.

Почему не локальная модель: Telegram WebView не запустит Gemma, а держать ПК
включённым 24/7 не нужно. DeepL при этом доступен — блокировка `451` зависит
от IP, а раннер GitHub находится в США. Бесплатных 500 тыс. символов в месяц
хватает: сезонный патч — это ~100 тыс., а кеш не даёт платить дважды.

### Настройка (один раз)

1. Репозиторий на GitHub, **публичный**, и `git push` из папки проекта.
   Публичный нужен потому, что GitHub Pages бесплатен только для открытых
   репозиториев. Секретов в коде нет: ключ DeepL передаётся при сборке через
   `--dart-define` и в репозитории не хранится.
2. Settings → Pages → **Source: GitHub Actions**. После первого пуша адрес
   будет `https://<логин>.github.io/finals-notes/`.
3. Secrets репозитория (Settings → Secrets and variables → Actions):

   | Secret | Значение |
   |---|---|
   | `TELEGRAM_BOT_TOKEN` | токен от @BotFather |
   | `TELEGRAM_CHANNEL` | `@username` или `-100…` |
   | `DEEPL_KEY` | ключ DeepL API Free (для бота и пайплайна в CI) |

   Variable `MINIAPP_URL` = `https://t.me/<бот>/<short name>` — из неё бот
   делает кнопку под постом (в каналах кнопки `web_app` не работают, поэтому
   нужна именно ссылка).
4. BotFather → `/newapp`: выбрать бота, задать название, описание, иконку и
   **Web App URL** = `https://<логин>.github.io/finals-notes/`, short name —
   `app`. После этого `https://t.me/<бот>/app` открывает приложение.
5. Первый запуск: Actions → «Обновление патчей» → Run workflow с включённым
   `init`, чтобы бот запомнил текущий патч и не опубликовал его повторно.

> **Ключ DeepL в репозитории не хранится.** `lib/services/bundled_key.dart`
> читает его из `--dart-define=DEEPL_KEY=...`, поэтому в веб-сборке ключа нет
> (Mini App ничего не переводит, а ключ в `main.dart.js` смог бы достать
> кто угодно). Для APK ключ передаёт `tool/build-apk.ps1`, беря его из
> `tool/bot.env` или переменной окружения `DEEPL_KEY`.

Если `github.io` окажется медленным, привяжите свой домен (Settings → Pages →
Custom domain): приложению всё равно, откуда читать `data/patches_ru.json`.

### Внешний cron (каждые 15 минут)

GitHub выполняет `schedule` не чаще ~40 минут, поэтому частоту задаёт
cron-job.org: он раз в 15 минут дёргает API GitHub и запускает
«Обновление патчей». Токен живёт только в cron-job.org, прав на код у него
нет — только на запуск workflow.

1. GitHub → Settings → Developer settings → Personal access tokens →
   **Fine-grained tokens** → Generate new token:
   - Resource owner: `AnarchistLS`
   - Repository access: **Only select repositories** → `finals-notes`
   - Permissions → Repository permissions → **Actions: Read and write**
   - Expiration: 1 год
   Скопируйте токен (`github_pat_…`).
2. Зарегистрируйтесь на https://cron-job.org и подтвердите почту.
3. Create cronjob:
   - Title: `finals-notes update`
   - URL: `https://api.github.com/repos/AnarchistLS/finals-notes/actions/workflows/update.yml/dispatches`
   - Schedule: every 15 minutes (`*/15 * * * *`)
   - Advanced → Request method: `POST`
   - Headers:
     `Authorization: Bearer github_pat_…`,
     `Accept: application/vnd.github+json`,
     `X-GitHub-Api-Version: 2022-11-28`,
     `Content-Type: application/json`
   - Request body: `{"ref":"main"}`
   - Notifications: включите письмо при ошибке.
4. «Test run»: в ответе должно быть `204`, а в Actions — новый запуск
   «Обновление патчей» с типом `workflow_dispatch`.
5. Когда убедились, что работает, расписание GitHub можно сделать редким
   (`0 */3 * * *`) — оно останется страховкой.

### Локальная проверка

```powershell
dart run tool/publish.dart            # собрать web/data/patches_ru.json
flutter build web --release --base-href /finals-notes/
dart run tool/serve.dart build/web 8081
```

`http://localhost:8081/finals-notes/` — ровно то, что увидит Telegram
(только без его шапки). Без `--base-href` откройте просто `http://localhost:8081/`.

## Структура

```
lib/
  models/models.dart          модель патча, секций и изменений
  parser/stat_parser.dart     разбор «from X to Y» + логика бафф/нерф
  parser/patch_parser.dart    HTML патчноута -> структурированный объект
  data/repository.dart        загрузка страниц + кеш в SharedPreferences
  data/published.dart         чтение готового patches_ru.json (Mini App)
  data/settings.dart          настройки (перевод, движок, ключ DeepL, FPS)
  data/prefs_cache.dart       кеш переводов в SharedPreferences
  l10n/glossary.dart          словарь терминов и защита имён собственных
  services/translator.dart    машинный перевод с кешем (DeepL + Google)
  services/doc_translator.dart  какие строки патча переводить (общее с ботом)
  services/deepl.dart         клиент DeepL API: перевод, /usage, коды ошибок
  services/translation_cache.dart  интерфейс кеша (общий с ботом)
  services/bundled_key.dart   ключ DeepL по умолчанию
  telegram/render.dart        вёрстка постов для Telegram + разбивка на сообщения
  ui/                         экраны списка и патча, тема, виджеты
  ui/settings_sheet.dart      шторка настроек: движок, ключ DeepL, FPS
web/index.html                оболочка Mini App: Telegram SDK, заставка, тема
web/data/patches_ru.json      готовые переведённые патчи (собирает publish.dart)
tool/bot.dart                 бот-постер для Telegram-канала
tool/publish.dart             пайплайн данных для Mini App
tool/env.dart                 чтение bot.env + переменных окружения
tool/file_cache.dart          кеш переводов в файле (общий для бота и пайплайна)
tool/bot.env.example          шаблон настроек бота
tool/proxy.dart               локальный CORS-прокси для запуска в браузере
tool/serve.dart               раздача release-сборки web
tool/build-apk.ps1            сборка APK (через ASCII-путь, см. ниже)
tool/make-icon.ps1            генерация иконки приложения
.github/workflows/update.yml  раз в 15 минут: пост в канал + данные для Mini App
.github/workflows/deploy.yml  сборка web и деплой на GitHub Pages
test/stat_parser_test.dart    тесты логики сравнения показателей
test/translator_test.dart     тесты пакетного перевода и кеша
test/deepl_test.dart          тесты DeepL: запрос, ошибки, откат на Google
test/telegram_render_test.dart  тесты вёрстки постов и разбивки на сообщения
test/published_data_test.dart   тесты готового файла Mini App и его чтения
```

## Запуск на компьютере (Chrome)

Сайт не отдаёт CORS-заголовки, поэтому для браузера нужен маленький прокси.

```powershell
# 1. зависимости
flutter pub get

# 2. прокси (отдельное окно терминала)
dart run tool/proxy.dart 8080

# 3. приложение
flutter run -d chrome --dart-define=API_BASE=http://localhost:8080
```

Без прокси приложение тоже запустится, но список не загрузится
(покажет кеш, если он есть). Для Android/iOS прокси не нужен: там нет CORS,
приложение ходит на `https://www.reachthefinals.com` напрямую.

## Сборка для телефона (Android)

Нужны Android SDK (platform 36, build-tools 36) и JDK 17+. Проще всего —
Android Studio, но достаточно и command-line tools + Temurin 21.

Проект лежит в папке с кириллицей, а Dart AOT-снапшоттер такие пути не читает,
поэтому собирать напрямую нельзя. Для этого есть скрипт: он зеркалит исходники
в ASCII-путь (`%LOCALAPPDATA%\finals-notes-build`), собирает там APK и
возвращает его в `build\app\outputs\flutter-apk\app-release.apk`.

```powershell
powershell -ExecutionPolicy Bypass -File tool\build-apk.ps1
```

Установка на телефон:

- по кабелю (включена отладка по USB): `adb install -r build\app\outputs\flutter-apk\app-release.apk`
- без кабеля: перекинуть APK в облако/мессенджер, открыть на телефоне и
  разрешить установку из неизвестных источников.

Release подписан debug-ключом (так в шаблоне Flutter) — для личной установки
этого достаточно, для Google Play понадобится собственный keystore.

Если на телефоне кажется, что интерфейс идёт рывками, есть два инструмента:

- в приложении: «Настройки → Счётчик FPS» — показывает реальный fps и частоту,
  которую система отдаёт приложению (например, `58 fps · 60 Гц` значит, что
  ограничение на стороне телефона, а не приложения);
- вариант сборки без Impeller (второй рендерер движка), кладётся рядом
  как `app-release-noimpeller.apk`:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build-apk.ps1 -NoImpeller
```

### Частота обновления экрана

Движок Flutter не сообщает Android, какая частота кадров нужна приложению
(в нём нет вызова `Surface.setFrameRate`), поэтому на 120-герцовых телефонах
окно по умолчанию живёт на 60 Гц: экран рисует 120, а приложение получает
60 кадров. `MainActivity.kt` выбирает режим экрана с максимальной частотой и
голосует за неё на поверхности отрисовки — приложение работает на 120 fps.
Проверить можно счётчиком FPS в настройках.

Прокси для телефона не нужен: CORS существует только в браузере, приложение
ходит на `https://www.reachthefinals.com` напрямую.

### iOS

Собрать iOS можно только на macOS с Xcode: `flutter create --platforms=ios .`,
затем запуск на устройстве (бесплатный Apple ID даёт подпись на 7 дней).

## Тесты

```powershell
flutter test
```

## Как это работает
1. `GET /patchnotes?format=json` — список обновлений (9 штук на страницу,
   следующая страница через `&offset=<publishOn>`).
2. Для каждого элемента берётся `body` (HTML) и разбирается по тегам
   `h2/h3/p/li/img`.
3. Для строк с числами срабатывает `stat_parser`: он вытаскивает показатель,
   «до» и «после», определяет полярность показателя и считает влияние.
4. UI красит усиления в зелёный, ослабления — в красный.
