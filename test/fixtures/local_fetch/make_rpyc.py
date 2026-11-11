"""Writes the compiled-script fixtures for renpy_local_test.dart.

Ren'Py pickles its statement classes (renpy.ast.Define, renpy.sl2.slast.SLScreen
and so on) with __slots__, so their state is (None, {attributes}); a PyCode's
state is (1, source, location, mode, py) with the source a PyExpr. These
stand-ins pickle the same way, so the files read like a real game's.

    python test/fixtures/local_fetch/make_rpyc.py
"""
import copyreg
import os
import pickle
import struct
import sys
import types
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))


def module(name):
    m = types.ModuleType(name)
    sys.modules[name] = m
    return m


renpy = module("renpy")
ast = module("renpy.ast")
sl2 = module("renpy.sl2")
slast = module("renpy.sl2.slast")


class Slotted:
    def __init__(self, **attrs):
        self.attrs = attrs

    def __reduce_ex__(self, protocol):
        return (copyreg.__newobj__, (type(self),), (None, self.attrs))


class PyExpr(str):
    def __new__(cls, s, filename="game/x.rpy", line=1):
        o = str.__new__(cls, s)
        o.filename, o.line = filename, line
        return o

    def __getnewargs__(self):
        return (str(self), self.filename, self.line)


class PyCode:
    def __init__(self, source):
        self.source = PyExpr(source)

    def __reduce_ex__(self, protocol):
        return (copyreg.__newobj__, (type(self),), (1, self.source, ("game/x.rpy", 1), "eval", None))


for cls in ("Init", "Define", "Default", "Python", "Image", "Screen"):
    globals()[cls] = type(cls, (Slotted,), {"__module__": "renpy.ast"})
    setattr(ast, cls, globals()[cls])
PyCode.__module__ = "renpy.ast"
ast.PyCode = PyCode
PyExpr.__module__ = "renpy.ast"
ast.PyExpr = PyExpr
for cls in ("SLScreen", "SLDisplayable"):
    globals()[cls] = type(cls, (Slotted,), {"__module__": "renpy.sl2.slast"})
    setattr(slast, cls, globals()[cls])


def define(store, name, source):
    return Define(store=store, varname=name, code=PyCode(source), operator="=", index=None)


def rpyc(path, stmts, data_header=None):
    header_data = data_header if data_header is not None else {"version": 5003000, "key": "unlocked"}
    data = zlib.compress(pickle.dumps((header_data, stmts), protocol=2))
    header = b"RENPY RPC2"
    first = len(header) + 12 * 3
    out = header + struct.pack("<III", 1, first, len(data)) + struct.pack("<III", 2, first, len(data))
    out += struct.pack("<III", 0, 0, 0) + data
    with open(os.path.join(HERE, path), "wb") as f:
        f.write(out)


# A Ren'Py 8 style options file: an empty config.name (the real name is in
# build.name), and config.version from a variable.
rpyc("options.rpyc", [Init(block=[
    define("store.config", "name", '_("")'),
    define("store.build", "name", '"MyTestGame"'),
    define("store", "game_version", '"0.4b"'),
    define("store.config", "version", "game_version"),
    define("store.gui", "main_menu_background", '"gui/main_menu.png"'),
])])

# A main menu screen that shows its own art and a small button.
menu = SLScreen(name="main_menu", children=[
    SLDisplayable(positional=['"gui/real menu.png"'], keyword=[]),
    SLDisplayable(positional=[], keyword=[("idle", '"gui/patreon.png"')]),
])
rpyc("screens.rpyc", [Init(block=[Screen(screen=menu)])])

# A Ren'Py 7 / Python 2 style file: attribute names are byte strings, and the
# header holds a defaultdict with items added to it.
import collections


class Py2Define(Slotted):
    pass


Py2Define.__name__ = "Define"
Py2Define.__qualname__ = "Define"
Py2Define.__module__ = "renpy.ast"
setattr(ast, "Define", Py2Define)


def py2_define(store, name, source):
    d = Py2Define()
    d.attrs = {b"store": store.encode(), b"varname": name.encode(), b"code": PyCode(source)}
    return d


errors = collections.defaultdict(list)
errors["game/options.rpy"].append("an old warning")
rpyc("options_py2.rpyc", [Init(block=[
    py2_define("store.config", "name", '_("Old Engine Game")'),
    py2_define("store.config", "version", '"0.9"'),
])], data_header={"version": 5003000, "deferred_parse_errors": errors})
print("written")
