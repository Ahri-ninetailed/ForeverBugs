# Tests

The tests run Forever Bugs outside the game: `mock.lua` stands in for the
WoW API, and `tests.lua` loads the addon files in `.toc` order into a fresh
"game" for every test. They run in Lua 5.1, the same Lua version as WoW,
through Python's `lupa` package.

```
pip install -r tests/requirements.txt
python tests/run.py
```

The last line shows how many checks passed and failed. This folder is not
part of the release: `.pkgmeta` leaves it out of the CurseForge package.

---

# Тесты

Тесты запускают Forever Bugs без игры: `mock.lua` подменяет API WoW, а
`tests.lua` загружает файлы аддона в порядке из `.toc` в новую «игру» для
каждого теста. Они работают на Lua 5.1, той же версии Lua, что и в WoW,
через пакет `lupa` для Python.

```
pip install -r tests/requirements.txt
python tests/run.py
```

Последняя строка показывает, сколько проверок прошло и сколько упало. В релиз
эта папка не попадает: `.pkgmeta` исключает её из архива для CurseForge.
