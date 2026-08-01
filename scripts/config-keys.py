#!/usr/bin/env python3
"""Every Config.<Table>.<Key> read anywhere, checked against the table.

WHY THIS EXISTS: luau-analyze cannot see through `Config.Hud.WarnedText`.
A key that is missing — renamed, deleted, or written into the wrong
table — is a nil that shows up on the exact frame something needs it,
which is the worst possible time to find out. It has cost this project
a frozen camera and a missile that errored every step, both from edits
that looked clean.
"""
import re, os, sys

CFG = 'src/ReplicatedStorage/BloxKart/Config/'
tables = {f[:-5]: open(CFG + f).read() for f in os.listdir(CFG)
          if f.endswith('.luau') and f != 'init.luau'}

# A module can exist on disk, be read as Config.X.Y everywhere, and
# still be nil at runtime because nothing added it to Config/init.luau.
# The key check below cannot see that: it resolves tables from the
# DIRECTORY, so an unregistered module passes every key it declares.
# This caught Config.Lobby the day it was written.
init_src = open(CFG + 'init.luau').read()
registered = set(re.findall(r'(\w+)\s*=\s*require\(script\.(\w+)\)', init_src))
reg_names = {a for a, b in registered}
missing_reg = sorted(set(tables) - reg_names)
mismatched = sorted(f'{a} = require(script.{b})' for a, b in registered if a != b)
extra_reg = sorted(reg_names - set(tables))

roots = ['src/ServerScriptService/KartServer/',
         'src/StarterPlayer/StarterPlayerScripts/KartClient/',
         'src/ReplicatedStorage/BloxKart/',
         'src/ReplicatedStorage/BloxKart/Items/']

bad = []
for name in missing_reg:
    bad.append(f'Config/{name}.luau exists but is NOT in Config/init.luau — Config.{name} is nil at runtime')
for name in extra_reg:
    bad.append(f'Config/init.luau requires script.{name}, which does not exist')
for line in mismatched:
    bad.append(f'Config/init.luau: {line} — the field and the module disagree')
for root in roots:
    if not os.path.isdir(root):
        continue
    for f in sorted(os.listdir(root)):
        if not f.endswith('.luau'):
            continue
        src = open(root + f).read()
        # Aliases are declared, never guessed: `local IT = Config.Items`.
        for alias, table in re.findall(r'local (\w+) = Config\.(\w+)\b', src):
            if table not in tables:
                bad.append(f"{f}: Config.{table} — no such config module")
                continue
            for key in sorted(set(re.findall(rf'\b{alias}\.(\w+)', src))):
                if (key + ' =') not in tables[table]:
                    bad.append(f"{f}: {alias}.{key}  →  Config.{table} has no {key}")
        # And direct reads that skip the alias.
        for table, key in re.findall(r'Config\.(\w+)\.(\w+)', src):
            if table in tables and (key + ' =') not in tables[table]:
                bad.append(f"{f}: Config.{table}.{key} — missing")

if bad:
    print("MISSING CONFIG KEYS")
    for b in sorted(set(bad)):
        print("  " + b)
    sys.exit(1)
print("config keys OK")
