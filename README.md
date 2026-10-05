# CyberCroc 0.5

GUI-first мастер-приложение для Windows 10/11 компьютерного клуба.

## Запуск

Основной вход: `launcher.vbs`. Он запускает PowerShell GUI скрыто и поднимает watchdog. `CyberCroc.cmd` и `Master.cmd` оставлены как совместимые точки входа.

## Структура

```
CyberCroc.ps1          WinForms GUI / client-admin shell
launcher.vbs           скрытый запуск GUI + watchdog
watchdog.ps1           PID/heartbeat watchdog
install.ps1             первичная установка
Deploy-Croc.cmd         wrapper развёртывания
version.txt             текущая версия
accounts.json             локальные данные аккаунтов
data\queue.json         offline queue
data\orders.json        журнал заказов
data\calls.json         журнал вызовов
data\products-cache.json кэш товаров
tools\Core.ps1         INI, DPAPI, atomic JSON, logging
tools\Network.ps1      UDP 50505 + discovery
tools\Queue.ps1        persistent queue
tools\Orders.ps1       orders/calls + ACK
tools\Products.ps1     Google Sheets v4 + cache
tools\Fleet.ps1        SMB config/cache distribution
tools\Accounts.ps1     account adapters
tools\Updater.ps1      SMB updater
```

## Роли и секреты

`ROLE=client` — клиентский ПК. `ROLE=admin` — стойка.

Мастер-пароль хранится в `ADMIN_PASSWORD_PROTECTED` через Windows DPAPI. Открытого `ADMIN_PASSWORD=` в конфиге 0.5.0 нет. Путь к JSON service account задаётся только на админском ПК и исключён из fleet sync.

CyberCroc не извлекает чужие Steam/Riot/Battle.net/Epic пароли из профилей и не передаёт сохранённый пароль командной строкой.

## Товары

Админский ПК может читать и редактировать Google Sheets через service-account JWT + Sheets API v4. Клиентские ПК используют локальный cache. При потере Google/network-соединения каталог продолжает работать по кэшу.

## Offline-first

Заказы и вызовы сначала сохраняются в `data\queue.json`, затем отправляются UDP broadcast на 50505. Клиент удаляет операцию из очереди только после ACK от админской стойки.

## Обновление

Основной канал: SMB `UPDATE_SHARE`. GitHub включается отдельно через `GITHUB_UPDATE_ENABLED=1`. Локальные настройки, `data`, `runtime` и логи не перезаписываются.

## Установка

Клиент:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -Role client -PcId PC-07 -Zone standard
```

Админ:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -Role admin -PcId MAIN-01 -Zone admin
```

Установщик попросит задать мастер-пароль интерактивно.

## Проверка на целевой Windows

Запустите:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tests\Static-Validate.ps1
```

Полноценный WinForms/network тест должен выполняться на Windows 10/11 в клубном сегменте; в Linux-окружении разработки Windows PowerShell 5.1 и WinForms runtime отсутствуют.

## Что не входит в 0.5.0

Failover резервных стоек, persistent rollback, read-only баланс Langame, shift handover, feedback и функции из третьей версии оставлены следующими этапами.

Ветка: `cybercroc2-refactor`.
