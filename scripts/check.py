#!/usr/bin/env python3
"""Verify sources, package both deliverables, compile and run behavior tests."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]


def find_tool(name, variable):
    value = os.environ.get(variable) or shutil.which(name)
    if not value:
        candidate = Path('/workspace/tools/luau-source') / name
        if candidate.is_file():
            value = str(candidate)
    if not value:
        sys.exit(f"Missing {name}: install official Luau CLI or set {variable} (see docs/STUDIO.md)")
    return value


def main():
    compiler = find_tool('luau-compile', 'LUAU_COMPILE')
    runner = find_tool('luau', 'LUAU')
    subprocess.run([sys.executable, 'scripts/build_standalone.py', '--check'], cwd=ROOT, check=True)
    sources = sorted((ROOT / 'src').rglob('*.luau')) + [p for p in sorted((ROOT / 'tests').rglob('*.luau')) if not p.name.startswith('.')]
    sources.append(ROOT / 'DaHoodPrediction.lua')
    if (ROOT / 'Loader.template.lua').is_file():
        sources.append(ROOT / 'Loader.template.lua')
    for path in sources:
        result = subprocess.run([compiler, '--binary', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode:
            sys.stderr.buffer.write(result.stderr)
            sys.exit(result.returncode)
    print(f"Compilation passed: {len(sources)} Luau files", flush=True)
    subprocess.run([runner, 'tests/run.luau'], cwd=ROOT, check=True)
    subprocess.run([runner, 'tests/standalone.luau'], cwd=ROOT, check=True)
    # The actual bundle runs inside an explicit event/lifecycle double. This
    # checks GUI callbacks and cleanup, NOT the Roblox renderer or physics.
    source = (ROOT / 'DaHoodPrediction.lua').read_text(encoding='utf-8')
    level = 0
    while ']' + '=' * level + ']' in source:
        level += 1
    literal = '[' + '=' * level + '[\n' + source + ']' + '=' * level + ']'
    harness = ROOT / 'tests/.generated_gui.luau'
    harness.write_text('local mock=require("./RobloxMock").new()\n'
                       'local source=' + literal + '\n'
                       'local function reloadBundle(env)\n'
                       ' local chunk=assert(loadstring(source, "DaHoodPrediction.guiTest"))\n'
                       ' setfenv(chunk,env)\n return chunk()\nend\n'
                       'local bundle=reloadBundle(mock.env)\n'
                       'require("./gui_body")(mock,bundle,reloadBundle)\n', encoding='utf-8')
    try:
        subprocess.run([runner, str(harness)], cwd=ROOT, check=True)
    finally:
        harness.unlink(missing_ok=True)
    subprocess.run([sys.executable, 'scripts/build_place.py'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
