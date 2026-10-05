# CROC_PRO 0.5.0 — отчёт реализации

## Что добавлено

### Интерфейс
Современный тёмный shell на WinForms с `EnableVisualStyles()`, Segoe UI, едиными отступами, округлёнными кнопками, тултипами и статус-баром. Добавлены отдельные роли client/admin и блокировка админских экранов для клиента. Добавлена страница FAQ/правил.

### Аккаунты
Исправлены обработчики вкладки «Аккаунты»: добавление, изменение и удаление теперь проходят через единый role-aware путь; удаление требует подтверждения. Кнопка запуска больше не расшифровывает пароль и не передаёт его командной строкой. Проверка Steam API остаётся админской функцией.

### Товары и заказы
Google Sheets стал источником каталога на админском ПК, а локальный cache — fallback и источник для клиентов. Клиент выбирает товар, количество и Cash/Card, после чего создаётся заказ.

Админ получает заказ в единой панели и переводит его в `new → preparing → delivered/rejected`. Изменение названия, цены и количества доступно только после мастер-пароля.

### Вызов администратора
Клиент отправляет `problem/question/other`. Админ видит ПК и причину; запись хранится локально и подтверждается ACK.

### Offline-first
Добавлен `data\queue.json`, атомарная запись и повторная передача очереди. Заказы/вызовы сначала фиксируются локально, поэтому перезапуск GUI или временная потеря сети не удаляют заявку.

### Discovery и карта зала
UDP beacon на 50505 автоматически обнаруживает узлы. Админский экран показывает плитки ПК, состояние online/offline, зону, хост и версию; доступны message/block/unblock/emergency.

### Массовое развёртывание
Добавлены `config.template.ini`, `Fleet.ps1`, `Deploy-Croc.cmd` и SMB-синхронизация общего конфига и cache товаров. PC ID, role, DPAPI-секреты и service-account path не раздаются по флоту.

### Watchdog и kiosk
`launcher.vbs` запускает `watchdog.ps1`. Watchdog контролирует PID/heartbeat и перезапускает GUI при закрытии/зависании. Для client install включается HKCU `DisableTaskMgr`; для admin GUI закрытие требует мастер-пароль.

### Логирование
`CyberCroc.log` и `errors.log` ротируются при 10 MB или 7 днях; архивы ZIP хранятся ограниченным количеством.

## Зачем это приложению

Главная цель 0.5.0 — убрать рутину, ради которой администратор сейчас должен бегать по залу, переключаться между таблицей и GUI и вручную собирать заявки. При этом приложение не пытается стать заменой Langame.

## Как использовать

### Клиентский ПК
На Windows 10/11 от имени установочного администратора:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -Role client -PcId PC-07 -Zone standard
```

Затем `launcher.vbs` запускается автоматически через HKCU Run.

### Админский ПК

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -Role admin -PcId MAIN-01 -Zone admin
```

Установщик попросит задать мастер-пароль и сохранит его через DPAPI. После запуска в настройках задаются Google Sheets и путь к JSON service account.

### Google Sheets
Один из вариантов структуры:

`name | price | quantity | category | sku`

Таблица должна быть доступна service account по e-mail из его JSON-ключа. Клиентские ПК не должны получать service-account JSON.

### Массовая синхронизация
После того как admin PC увидел client beacon-ы, в «КАРТА ЗАЛА» используется кнопка синхронизации fleet. Она раздаёт общий конфиг и products cache через `\\PC\C$\CyberCroc\...` при наличии административного SMB-доступа.

### Заказы и вызовы
Клиент использует «ТОВАРЫ / ЗАКАЗЫ» и «ПОЗВАТЬ АДМИНА». Администратор получает всплывающий notification со звуком и подтверждает заявку.

## Ограничения 0.5.0

- полноценный failover резервных стоек ещё не включён;
- persistent rollback после трёх неудачных стартов ещё не включён;
- баланс Langame не читается и не изменяется;
- продление выполняется вручную администратором в Langame;
- shift handover, feedback, reservation/tournaments/loyalty и остальные функции v2/v3 не входят в 0.5.0;
- реальный сетевой и WinForms тест нужно выполнить на Windows 10/11 в клубном сегменте;
- массовая установка самого приложения пока остаётся отдельным deployment шагом (`install.ps1`/`Deploy-Croc.cmd`), а из GUI раздаётся общий config/cache.

## Версия

`version.txt = 0.5.0`

## Внешние технические источники

Google service-account OAuth/JWT: https://developers.google.com/identity/protocols/oauth2/service-account
Google Sheets API Values.get: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/get
Google Sheets API Values.update: https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/update
Steam catalog pages used to verify seeded AppID values are referenced in the delivery note.
