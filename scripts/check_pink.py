#!/usr/bin/env python3
"""Compile Pink, run mathematical and actual-bundle event-double tests."""
from pathlib import Path
import subprocess
import sys
from check import find_tool
ROOT=Path(__file__).resolve().parents[1]


def main():
    compiler=find_tool('luau-compile','LUAU_COMPILE')
    runner=find_tool('luau','LUAU')
    subprocess.run([sys.executable,'scripts/build_pink.py','--check'],cwd=ROOT,check=True)
    sources=sorted((ROOT/'src/pink').glob('*.luau'))+sorted((ROOT/'src/pink_demo').glob('*.luau'))
    sources+=sorted((ROOT/'src/pink_weapon').glob('*.luau'))
    sources+=sorted((ROOT/'tests').glob('pink*.luau'))+[ROOT/'tests/PinkMock.luau',ROOT/'PinkDotLock.lua']
    if (ROOT/'PinkLoader.lua').exists(): sources.append(ROOT/'PinkLoader.lua')
    for path in sources:
        result=subprocess.run([compiler,'--binary',str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        if result.returncode:
            sys.stderr.buffer.write(result.stderr);sys.exit(result.returncode)
    print(f'Pink compilation passed: {len(sources)} files',flush=True)
    for test in ('pink_selection','pink_prediction','pink_adapter','pink_weapon'):
        subprocess.run([runner,f'tests/{test}.luau'],cwd=ROOT,check=True)
    source=(ROOT/'PinkDotLock.lua').read_text(encoding='utf-8')
    level=0
    while ']'+ '='*level + ']' in source: level+=1
    literal='['+'='*level+'[\n'+source+']'+'='*level+']'
    loader=(ROOT/'PinkLoader.lua').read_text(encoding='utf-8')
    loader_level=0
    while ']'+ '='*loader_level + ']' in loader: loader_level+=1
    loader_literal='['+'='*loader_level+'[\n'+loader+']'+'='*loader_level+']'
    harness=ROOT/'tests/.generated_pink.luau'
    harness.write_text('local mock=require("./PinkMock").new()\nlocal source='+literal+'\n'
        'local function reloadBundle(env)\n local chunk=assert(loadstring(source,"PinkDotLock.bundleTest"))\n'
        ' setfenv(chunk,env)\n return chunk()\nend\n'
        'local bundle=reloadBundle(mock.env)\nrequire("./pink_gui_body")(mock,bundle,reloadBundle)\n'
        'require("./pink_startup_body")(reloadBundle)\n'
        'require("./pink_lockkey_body")(reloadBundle)\n'
        'require("./pink_weapon_body")(mock,bundle,reloadBundle)\n'
        'require("./pink_loader_body")(source,'+loader_literal+')\n',encoding='utf-8')
    try: subprocess.run([runner,str(harness)],cwd=ROOT,check=True)
    finally: harness.unlink(missing_ok=True)


if __name__=='__main__': main()
