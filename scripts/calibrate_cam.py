#!/usr/bin/env python3
"""Run deterministic math lab and same-host V2/V3 API-double CPU comparison."""
from pathlib import Path
import subprocess,sys,csv,json,collections
from check import find_tool
from check_cam import literal
ROOT=Path(__file__).resolve().parents[1]
BASELINE='43612248fc40e2750678873acda642ab41f85c35'
def main():
 runner=find_tool('luau','LUAU');build=ROOT/'build';build.mkdir(exist_ok=True)
 result=subprocess.run([runner,'tests/cam_lab.luau'],cwd=ROOT,check=True,text=True,capture_output=True)
 (build/'v3-lab.log').write_text(result.stdout)
 lines=result.stdout.splitlines();header=lines[0]
 rows=[line.removeprefix('LAB,') for line in lines if line.startswith('LAB,')]
 (build/'v3-lab.csv').write_text(header+'\n'+'\n'.join(rows)+'\n')
 baseline=subprocess.check_output(['git','show',BASELINE+':SedwareCamLock.lua'],cwd=ROOT,text=True)
 harness=ROOT/'tests/.generated_cam.luau'
 harness.write_text('require("./cam_perf_compare_body")('+literal((ROOT/'SedwareCamLock.lua').read_text())+','+literal(baseline)+')\n')
 try:
  perf=subprocess.run([runner,str(harness)],cwd=ROOT,text=True,capture_output=True)
  if perf.returncode:
   print(perf.stdout);print(perf.stderr,file=sys.stderr);raise RuntimeError('Comparison failed')
 finally:harness.unlink(missing_ok=True)
 (build/'v3-perf.log').write_text(perf.stdout)
 (build/'v3-perf.csv').write_text('version,players,espEnabled,camEnabled,meanHostFrameMs\n'+'\n'.join(x.removeprefix('PERF,') for x in perf.stdout.splitlines() if x.startswith('PERF,'))+'\n')
 print(lines[-1]);print('\n'.join(x for x in perf.stdout.splitlines() if x.startswith('PERF,')))
 print('Results: build/v3-lab.csv, build/v3-perf.csv (CLI math and API doubles, NOT Roblox FPS)')
if __name__=='__main__':main()
