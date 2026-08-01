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

roots = ['src/ServerScriptService/KartServer/',
         'src/StarterPlayer/StarterPlayerScripts/KartClient/',
         'src/ReplicatedStorage/BloxKart/',
         'src/ReplicatedStorage/BloxKart/Items/']

bad = []
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
