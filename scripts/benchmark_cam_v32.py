#!/usr/bin/env python3
"""Same-host V3.1 / V3.2 client CPU comparison under explicit Roblox API doubles."""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys

from check import find_tool
from check_cam import literal

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'da44a4c7af3857c1fed22b9fb757c012180650ac'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=int, default=1200, help='120..12000 scheduled frames per configuration')
    parser.add_argument('--far', action='store_true', help='z=-800 fixture, common MaxDistance / ESPMaxDistance = 1500')
    args = parser.parse_args()
    if not 120 <= args.iterations <= 12000:
        parser.error('--iterations must be between 120 and 12000')
    runner = find_tool('luau', 'LUAU')
    build = ROOT/'build'
    build.mkdir(exist_ok=True)
    source_bytes = (ROOT/'SedwareCamLock.lua').read_bytes()
    baseline_bytes = subprocess.check_output(['git', 'show', BASELINE+':SedwareCamLock.lua'], cwd=ROOT)
    source, baseline = source_bytes.decode('utf-8'), baseline_bytes.decode('utf-8')
    harness = ROOT/'tests/.generated_v32_perf.luau'
    harness.write_text('require("./cam_v32_perf_body")('+literal(source)+','+literal(baseline)+
                       ',{iterations='+str(args.iterations)+',far='+str(args.far).lower()+'})\n', encoding='utf-8')
    try:
        result = subprocess.run([runner, str(harness)], cwd=ROOT, text=True, capture_output=True, timeout=120)
    finally:
        harness.unlink(missing_ok=True)
    suffix = '-far' if args.far else ''
    (build/f'v32-perf{suffix}.log').write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        print(result.stdout[-4000:])
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    lines = result.stdout.splitlines()
    header = next(line.removeprefix('V32_PERF_HEADER,') for line in lines if line.startswith('V32_PERF_HEADER,'))
    data = [line.removeprefix('V32_PERF,') for line in lines if line.startswith('V32_PERF,')]
    csv_data = header+'\n'+'\n'.join(data)+'\n'
    rows = list(csv.DictReader(io.StringIO(csv_data)))
    if len(rows) != 24:
        raise RuntimeError(f'Expected 24 configurations, received {len(rows)}')
    (build/f'v32-perf{suffix}.csv').write_text(csv_data, encoding='utf-8')
    index = {(row['version'], row['players'], row['espEnabled'], row['camEnabled']): row for row in rows}
    comparisons = []
    for players in ('5', '15', '30'):
        for esp in ('false', 'true'):
            for cam in ('false', 'true'):
                old, new = index[('V31', players, esp, cam)], index[('V32', players, esp, cam)]
                old_ms, new_ms = float(old['meanHostFrameMs']), float(new['meanHostFrameMs'])
                comparisons.append({
                    'players': int(players), 'espEnabled': esp == 'true', 'camEnabled': cam == 'true',
                    'v31MeanHostFrameMs': old_ms, 'v32MeanHostFrameMs': new_ms,
                    'hostCostRatioV32OverV31': new_ms/old_ms if old_ms else None,
                    'v31MeanSessionMs': float(old['meanSessionMs']), 'v32MeanSessionMs': float(new['meanSessionMs']),
                    'v31Raycasts': int(old['raycasts']), 'v32Raycasts': int(new['raycasts']),
                    'v31Projections': int(old['projections']), 'v32Projections': int(new['projections']),
                })
    report = {
        'baselineCommit': BASELINE,
        'baselineSha256': hashlib.sha256(baseline_bytes).hexdigest(),
        'currentSha256': hashlib.sha256(source_bytes).hexdigest(),
        'configurations': len(rows), 'framesPerConfiguration': args.iterations,
        'totalScheduledFrames': len(rows)*args.iterations, 'scheduledFps': 60,
        'warmupSeconds': 0.4,
        'profile': 'far' if args.far else 'near', 'targetZStuds': -800 if args.far else -60,
        'commonRangeOverrides': {'MaxDistance': 1500, 'ESPMaxDistance': 1500} if args.far else {},
        'environment': 'Official Luau CLI and CamV2Mock; same host. No Roblox rendering, FPS measurement, network, physical movement, hits or Da Hood run',
        'fixture': '5/15/30 stationary visible simulated character models; VisibleOnly ESP and configurable camera enablement; Fly/Speed OFF. Far profile changes range equally in both versions; both standalone bundles retain their own distant projection/LOS scheduling',
        'hostFrameReference': 'CPU for Mock.advance and all callbacks per scheduled frame, including double overhead',
        'sessionReference': 'Mean and maximum instrumented Session._step CPU time; excludes double default-camera/frame plumbing',
        'invariants': 'Indicator pool / instances / connections stable after warmup; GetPlayers scans zero during hot loop; connections, render bindings, active tweens zero after Unload',
        'limitation': 'A single same-host run is sensitive to scheduling and garbage collection; cost ratios are not Roblox FPS ratios',
        'comparisons': comparisons,
    }
    (build/f'v32-perf{suffix}-summary.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(next(line for line in reversed(lines) if line.startswith('V32 PERF SUMMARY:')))
    for comparison in comparisons:
        print('players={} ESP={} Cam={}: V3.1 {:.6f}ms → V3.2 {:.6f}ms (host frame CPU)'.format(
            comparison['players'], comparison['espEnabled'], comparison['camEnabled'],
            comparison['v31MeanHostFrameMs'], comparison['v32MeanHostFrameMs']))
    print(f'Results: build/v32-perf{suffix}.csv and build/v32-perf{suffix}-summary.json; no native FPS result')


if __name__ == '__main__':
    main()
