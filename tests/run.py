"""Runs the Forever Bugs tests in a Lua 5.1 interpreter (the WoW Lua version).

    pip install -r tests/requirements.txt
    python tests/run.py

Exit code 0 means all tests passed.
"""
import pathlib
import sys

from lupa import lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    tests = (ROOT / "tests" / "tests.lua").read_text(encoding="utf-8")
    run = lua.execute("return function(source, root) return assert(loadstring(source, '@tests/tests.lua'))(root) end")
    failed = run(tests, ROOT.as_posix())
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
