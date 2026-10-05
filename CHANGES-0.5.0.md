# CROC_PRO 0.5.0 — Phase 1

Фокус: эксплуатационная база клуба без дублирования Langame.

## Добавлено
- client/admin роли и DPAPI-защита мастер-пароля; миграция legacy plaintext `ADMIN_PASSWORD`;
- watchdog + PID/heartbeat + автозапуск; клиентский GUI нельзя закрыть без обхода kiosk-политики, админ может закрыть после мастер-пароля;
- `KioskPolicy.ps1` и HKCU-ограничение Task Manager для client install;
- persistent offline queue `data\queue.json`;
- UDP bus / discovery / beacons на 50505;
- Google Sheets API v4 для товаров + локальный cache; service-account путь остаётся только на admin PC;
- единые товары/заказы с Cash/Card, локальный журнал заказов и вызовов, ACK и повторная отправка;
- админская карта обнаруженных ПК в плиточном виде, команды message/block/unblock/emergency;
- массовая синхронизация общего конфига по SMB без копирования PC_ID, DPAPI-секретов и service-account JSON;
- ротация `CyberCroc.log` и `errors.log` по 10 MB / 7 дней;
- современный dark UI, Segoe UI, rounded buttons, status bar, tooltips;
- FAQ / правила клуба;
- исправлены обработчики вкладки «Аккаунты»: больше нет дублирующих `Click`-подписок, удаление требует подтверждения, клиент не получает admin-операции;
- аккаунт launch path больше не расшифровывает чужой пароль и не передаёт пароль командной строкой;
- расширен каталог игр: CS2, Dota 2, Valorant, LoL, Fortnite, PUBG, Apex, GTA V, Minecraft, Roblox, Overwatch 2, Rainbow Six Siege, Warface, World of Tanks, CrossFire, Point Blank;
- fuzzy search по играм и программам;
- `tests\Static-Validate.ps1` для запуска на целевой Windows.

## Важное
`tools\Bar.ps1` оставлен в репозитории только для обратной совместимости, но `CyberCroc.ps1` его больше не импортирует: биллинг/баланс Langame не дублируются.

## Не реализовано в 0.5.0
Failover резервных стоек, откат обновления после 3 неудачных стартов, read-only баланс Langame, shift handover, feedback и функции третьей версии.

## Проверенные Steam AppID каталога
730 (Counter-Strike 2), 1172470 (Apex Legends), 2357570 (Overwatch), 359550 (Rainbow Six Siege), 1407200 (World of Tanks). Проверять актуальность перед клубным развёртыванием через Steam-каталог.
