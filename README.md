# Forever Bugs

**Catches Lua errors and blocked actions and shows which addon is to blame.** Built for WoW Forever. Open it with the minimap button or `/fbugs`.

It also catches what other error catchers miss in WoW Forever: the message **"Interface action failed because of an AddOn"**, which this client often prints without telling addons anything.

*Русское описание ниже.*

## Features

- **Catches every Lua error** of every addon and of the game's own interface, with the call stack and the local variables at the moment of the error. Lua warnings are caught too.
- **Names the culprit.** For each error it shows the addon to blame, with the file and line, found from the error and its call stack (the game's own code is skipped).
- **Blocked actions ("Interface action failed because of an AddOn"):**
  - an addon tried to open or close a game window during combat: you see the addon, the window and the place in its code;
  - the game reports a protected call by an addon: the addon and the function;
  - an addon replaced a game function with its own: the addon is named;
  - only game code is involved (an addon changed the game's data earlier): you get a hint how to find it.
  - Every refusal is counted, not only the first one the game prints in chat.
- **A window with the list of errors** (newest on top) and the chosen error next to it:
  - tabs: all errors, this session, previous session, settings;
  - search in plain text (error, call stack, variables, addon), and a filter by addon with counts;
  - repeats are shown as one row with a count, the first and the last time, and the **history** of when it happened (the last 50 times of each error);
  - **"Each time separately"**: every occurrence as its own row with its time;
  - new errors are marked; **delete** a single error or all of them.
- **Copy-ready reports** for GitHub, CurseForge or Discord, always in English: the addon and game versions, times, history, place, call stack and variables. "Copy all shown" puts up to 10 errors into one text that fits a GitHub issue.
- **Minimap button:** red when there are errors you have not seen, yellow when all are seen, plain when there are none. The tooltip lists the newest errors. Click: open the window; Shift-click: reload the interface; right-click: settings; Alt-click: delete all errors (if you allow it). It can also sit in the game's addon menu at the minimap.
- **Alerts:** a sound (7 sounds of the game to choose from, also on the Master channel), a reminder in chat with a link that opens the error, or opening the window by itself (never during combat). All optional.
- **Settings** in the window and in the game menu (Esc > Options > AddOns). English and Russian, or the language of the game.
- **Taint log switch:** turns on the game's own taint log (`Logs\taint.log`) and keeps it on across restarts.
- **Stays light and safe:** loads before other addons so it sees their errors from the very start; keeps the last 500 errors; pauses recording if an addon throws more than 10 errors a second; does nothing while there are no errors. Blocked actions are watched through secure hooks only.
- **Replaces BugGrabber and BugSack.** Only one error catcher can work at a time, so Forever Bugs switches them off (from the next login on).

## Compared to BugSack and BugGrabber

BugSack and BugGrabber are the classic error catchers, and they work in WoW Forever too. Forever Bugs is made only for WoW Forever and adds:

- **Sees the silent "Interface action failed" refusals.** In WoW Forever the game often refuses an addon's action without firing any event: a window opened in combat, the gamepad navigation in the quest log. BugGrabber catches blocked actions only through game events, so it never sees these. Forever Bugs records every one.
- **Counts every blocked action.** BugGrabber keeps one record per addon per session; Forever Bugs counts each time and keeps the history.
- **Names the culprit for you**, with the file and line, instead of leaving you to read the call stack.
- **A list of all errors** with a filter by addon, instead of paging through them one at a time.
- **History:** when each error happened, not only how many times.
- **Copy-ready reports** in English with the addon and game versions, for one error or up to 10 at once.
- **Plain-text search:** searching for brackets or dots works as expected.
- **New or already seen:** the minimap button turns red only for errors you have not looked at yet.
- **One addon instead of two.**

What BugSack has and Forever Bugs does not: sending errors to another player in the game, sounds from other addons (LibSharedMedia), and support for other versions of WoW.

## How to use

1. Play as usual. When something breaks, the minimap button turns red.
2. Click it (or type `/fbugs`) and pick the error in the list.
3. To report it to the addon's author, press **Copy this error**, then Ctrl+C, and paste it into their GitHub, CurseForge page or Discord.

Commands: `/fbugs` opens or closes the window, `/fbugs options` the settings, `/fbugs clear` deletes all errors, `/fbugs 5` prints error number 5 to chat. `/foreverbugs` works too.

## Installation

Install it with the CurseForge app, or download the archive from [GitHub Releases](https://github.com/Ahri-ninetailed/ForeverBugs/releases) and unpack the `!!ForeverBugs` folder into `World of Warcraft\_forever_\Interface\AddOns`.

Game version: **WoW Forever**.

Uses LibStub, CallbackHandler, LibDataBroker and LibDBIcon for the minimap button.

License: all rights reserved, see [LICENSE](https://github.com/Ahri-ninetailed/ForeverBugs/blob/main/LICENSE). You are welcome to use the addon; please ask before copying or reuploading its code.

Source code and bug reports: [GitHub](https://github.com/Ahri-ninetailed/ForeverBugs)

---

# Forever Bugs (Русский)

**Ловит ошибки Lua и заблокированные действия и показывает, какой аддон виноват.** Сделан для WoW Forever. Открывается кнопкой у миникарты или командой `/fbugs`.

Ловит и то, что другие ловцы ошибок в WoW Forever пропускают: сообщение **«Interface action failed because of an AddOn»**, которое этот клиент часто выводит, ничего не сообщая аддонам.

## Возможности

- **Ловит все ошибки Lua** всех аддонов и самого интерфейса игры, с цепочкой вызовов и локальными переменными на момент ошибки. Предупреждения Lua тоже.
- **Называет виновника.** У каждой ошибки виден аддон, файл и строка, найденные по тексту ошибки и цепочке вызовов (код самой игры пропускается).
- **Заблокированные действия («Interface action failed because of an AddOn»):**
  - аддон пытался открыть или закрыть окно игры в бою: видно аддон, окно и место в его коде;
  - игра сообщила о защищённом вызове аддона: видно аддон и функцию;
  - аддон подменил функцию игры своей: аддон назван;
  - замешан только код игры (аддон заранее испортил её данные): есть подсказка, как его найти.
  - Считается каждый отказ, а не только первый, который игра пишет в чат.
- **Окно со списком ошибок** (свежие сверху) и выбранной ошибкой рядом:
  - вкладки: все ошибки, этот сеанс, прошлый сеанс, настройки;
  - поиск обычным текстом (ошибка, цепочка вызовов, переменные, аддон) и фильтр по аддону со счётчиками;
  - повторы показаны одной строкой со счётчиком, временем первого и последнего раза и **историей** появлений (последние 50 раз каждой ошибки);
  - **«Каждый раз отдельно»**: каждое появление отдельной строкой со своим временем;
  - новые ошибки отмечены; можно **удалить** одну ошибку или все.
- **Готовые отчёты** для GitHub, CurseForge или Discord, всегда на английском: версии аддона и игры, время, история, место, цепочка вызовов и переменные. «Копировать все показанные» собирает до 10 ошибок в один текст, который влезает в задачу на GitHub.
- **Кнопка у миникарты:** красная, если есть ошибки, которые вы ещё не видели; жёлтая, если все просмотрены; обычная, если ошибок нет. В подсказке свежие ошибки. Клик: открыть окно; Shift+клик: перезагрузить интерфейс; правый клик: настройки; Alt+клик: удалить все ошибки (если разрешено). Может быть и в меню аддонов у миникарты.
- **Оповещения:** звук (7 звуков игры на выбор, можно через общий канал), напоминание в чате со ссылкой на ошибку или автооткрытие окна (никогда в бою). Всё по желанию.
- **Настройки** в окне и в меню игры (Esc → Настройки → Модификации). Английский и русский язык или язык игры.
- **Журнал taint:** включает собственный журнал игры (`Logs\taint.log`) и держит его включённым после перезапусков.
- **Лёгкий и безопасный:** загружается раньше других аддонов, чтобы видеть их ошибки с самого начала; хранит последние 500 ошибок; приостанавливает запись, если аддон сыплет больше 10 ошибок в секунду; пока ошибок нет, ничего не делает. За блокировками следит только через безопасные перехваты.
- **Заменяет BugGrabber и BugSack.** Одновременно может работать только один ловец ошибок, поэтому Forever Bugs их отключает (со следующего входа в игру).

## Чем отличается от BugSack и BugGrabber

BugSack и BugGrabber — классические ловцы ошибок, и в WoW Forever они тоже работают. Forever Bugs сделан только для WoW Forever и добавляет:

- **Видит молчаливые отказы «Interface action failed».** В WoW Forever игра часто отказывает аддону, не сообщая об этом никаким событием: окно, открытое в бою, навигация геймпадом в списке заданий. BugGrabber ловит заблокированные действия только через события игры, поэтому таких отказов не видит. Forever Bugs записывает каждый.
- **Считает каждое заблокированное действие.** BugGrabber хранит одну запись на аддон за сеанс; Forever Bugs считает каждый раз и хранит историю.
- **Сам называет виновника** с файлом и строкой, а не оставляет разбираться в цепочке вызовов.
- **Список всех ошибок** с фильтром по аддону, а не листание по одной.
- **История:** когда случалась каждая ошибка, а не только сколько раз.
- **Готовые отчёты** на английском с версиями аддона и игры, для одной ошибки или до 10 сразу.
- **Поиск обычным текстом:** поиск скобок или точек работает как ожидается.
- **Новые и просмотренные:** кнопка у миникарты краснеет только из-за ошибок, которые вы ещё не видели.
- **Один аддон вместо двух.**

Что есть в BugSack и нет в Forever Bugs: отправка ошибок другому игроку прямо в игре, звуки из других аддонов (LibSharedMedia) и поддержка других версий WoW.

## Как пользоваться

1. Играйте как обычно. Когда что-то ломается, кнопка у миникарты краснеет.
2. Нажмите на неё (или наберите `/fbugs`) и выберите ошибку в списке.
3. Чтобы сообщить автору аддона, нажмите **Копировать ошибку**, затем Ctrl+C, и вставьте на его GitHub, страницу CurseForge или в Discord.

Команды: `/fbugs` открывает и закрывает окно, `/fbugs options` настройки, `/fbugs clear` удаляет все ошибки, `/fbugs 5` выводит ошибку номер 5 в чат. Работает и `/foreverbugs`.

## Установка

Через приложение CurseForge или скачайте архив из [GitHub Releases](https://github.com/Ahri-ninetailed/ForeverBugs/releases) и распакуйте папку `!!ForeverBugs` в `World of Warcraft\_forever_\Interface\AddOns`.

Версия игры: **WoW Forever**.

Для кнопки у миникарты используются LibStub, CallbackHandler, LibDataBroker и LibDBIcon.

Лицензия: все права защищены, см. [LICENSE](https://github.com/Ahri-ninetailed/ForeverBugs/blob/main/LICENSE). Пользоваться аддоном можно свободно; копировать или перевыкладывать его код — только с разрешения автора.

Исходный код и сообщения об ошибках: [GitHub](https://github.com/Ahri-ninetailed/ForeverBugs)
