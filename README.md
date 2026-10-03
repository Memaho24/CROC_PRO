# CyberCroc 0.4

GUI-first мастер-приложение для Windows 10/11 компьютерного клуба.

## Запуск

Основной вход: `launcher.vbs`. Он запускает PowerShell GUI скрыто.
`CyberCroc.cmd` и `Master.cmd` оставлены как совместимые точки входа и больше не содержат консольного меню.

## Структура

```
CyberCroc.ps1          WinForms GUI
launcher.vbs           скрытый запуск GUI
version.txt            текущая версия
config.ini             локальная конфигурация
accounts.json          локальная БД аккаунтов (не коммитить)
tools\Core.ps1         логирование, INI, общие helpers
tools\Accounts.ps1     аккаунты + DPAPI + launch/check adapters
tools\Hardware.ps1     мониторинг и инвентаризация
tools\Apps.ps1         исправленная проверка приложений
tools\Updater.ps1      обновление через SMB
logs\                  CyberCroc.log и errors.log
```

## Логирование

Ошибки функций пишутся в `logs\errors.log` с датой, функцией и полным исключением. Обычные операции идут в `logs\CyberCroc.log`.

## Аккаунты

Пароли хранятся не в открытом виде: PowerShell DPAPI защищает их для текущего Windows-пользователя. `accounts.json` добавлен в gitignore.

Steam: при наличии `STEAM_API_KEY` выполняются GetOwnedGames и GetPlayerBans; список игр и часы сохраняются в карточке аккаунта. Steam Web API документирует оба метода. Riot/Battle.net/Epic не имеют эквивалентного универсального публичного API, поэтому приложение не делает фиктивные проверки: для них показывается состояние «не проверен», а запуск использует локальный сохранённый сеанс лаунчера.

## Обновление

Укажите `UPDATE_SHARE=\\MAIN-PC\CyberCroc_Update` или другой SMB путь в `config.ini`. Каждый час приложение проверяет `version.txt`; при более новой версии скрытый updater выполняет staging + robocopy, не заменяя `config.ini`, `accounts.json`, `logs\` и `BACKUP\`, затем перезапускает GUI.

## Важное ограничение

Нельзя безопасно считать Steam/Riot/Battle.net/Epic пароли или токены из чужих профилей. CyberCroc хранит только введённые администратором данные и не выводит секреты в логи. Для Steam `-login` может передавать пароль командной строкой, поэтому на клубных ПК доступ к локальному администрированию должен быть ограничен.

## Ветка разработки

Эта версия собрана в отдельной ветке `cybercroc2-refactor`, чтобы не ломать текущую `main`.
