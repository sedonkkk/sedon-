#!/usr/bin/env python3
"""Compile Cam Lock and run the actual standalone with native API doubles."""
from pathlib import Path
import subprocess
import sys
from check import find_tool

ROOT = Path(__file__).resolve().parents[1]


def literal(source):
    level = 0
    while ']' + '='*level + ']' in source:
        level += 1
    return '[' + '='*level + '[\n' + source + ']' + '='*level + ']'


def main():
    compiler = find_tool('luau-compile', 'LUAU_COMPILE')
    runner = find_tool('luau', 'LUAU')
    subprocess.run([sys.executable, 'scripts/build_cam.py', '--check'], cwd=ROOT, check=True)
    sources = sorted((ROOT/'src/cam').glob('*.luau')) + sorted((ROOT/'tests').glob('cam*.luau'))
    sources += [ROOT/'tests/CamMock.luau', ROOT/'SedwareCamLock.lua']
    sources += sorted((ROOT/'tests/studio').glob('Cam*.luau'))
    if (ROOT/'CamLoader.lua').exists():
        sources.append(ROOT/'CamLoader.lua')
    for path in sources:
        result = subprocess.run([compiler, '--binary', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode:
            sys.stderr.buffer.write(result.stderr)
            sys.exit(result.returncode)
    print(f'Cam compilation passed: {len(sources)} files', flush=True)
    for test in ('cam_math', 'cam_camera', 'cam_roll'):
        subprocess.run([runner, f'tests/{test}.luau'], cwd=ROOT, check=True)
    source = (ROOT/'SedwareCamLock.lua').read_text(encoding='utf-8')
    harness = ROOT/'tests/.generated_cam.luau'
    loader_test = ''
    if (ROOT/'CamLoader.lua').exists():
        loader_test = 'require("./cam_loader_body")(source,'+literal((ROOT/'CamLoader.lua').read_text(encoding='utf-8'))+')\n'
    harness.write_text('local source='+literal(source)+'\n'
        'local function reloadBundle(env)\n'
        ' local chunk=assert(loadstring(source,"SedwareCamLock.bundleTest"))\n'
        ' setfenv(chunk,env)\n return chunk()\nend\n'
        'require("./cam_gui_body")(reloadBundle)\n'+loader_test, encoding='utf-8')
    try:
        subprocess.run([runner, str(harness)], cwd=ROOT, check=True)
    finally:
        harness.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
