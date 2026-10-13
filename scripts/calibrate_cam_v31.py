#!/usr/bin/env python3
"""Compare actual V3 / V3.1 bundles with bounded CLI trajectories and CSV output.

The capture delay fixture is unavailable to either estimator. Timesteps are
scheduled FPS values, never a measurement of Roblox rendering performance.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
from collections import defaultdict

from check import find_tool
from check_cam import literal

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quick', action='store_true', help='30/144 FPS, 60/300 ms, Manual only smoke matrix')
    parser.add_argument('--duration', type=float, default=3.0, help='Fixture duration, 3..6 seconds')
    args = parser.parse_args()
    if not 3 <= args.duration <= 6:
        parser.error('--duration must be between 3 and 6 seconds')
    runner = find_tool('luau', 'LUAU')
    build = ROOT/'build'
    build.mkdir(exist_ok=True)
    source = (ROOT/'SedwareCamLock.lua').read_text(encoding='utf-8')
    baseline = subprocess.check_output(['git', 'show', BASELINE+':SedwareCamLock.lua'], cwd=ROOT, text=True)
    # This filename is private to this runner; check_cam owns another harness.
    harness = ROOT/'tests/.generated_v31_lab.luau'
    harness.write_text('require("./cam_v31_lab")('+literal(source)+','+literal(baseline)+',{' +
                       'quick='+str(args.quick).lower()+',duration='+str(args.duration)+'})\n', encoding='utf-8')
    try:
        result = subprocess.run([runner, str(harness)], cwd=ROOT, text=True, capture_output=True, timeout=120)
    finally:
        harness.unlink(missing_ok=True)
    suffix = '-quick' if args.quick else ''
    (build/f'v31-lab{suffix}.log').write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        print(result.stdout[-4000:])
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    lines = result.stdout.splitlines()
    header = next(line.removeprefix('V31_HEADER,') for line in lines if line.startswith('V31_HEADER,'))
    data = [line.removeprefix('V31_LAB,') for line in lines if line.startswith('V31_LAB,')]
    csv_data = header+'\n'+'\n'.join(data)+'\n'
    rows = list(csv.DictReader(io.StringIO(csv_data)))
    expected = 288 if args.quick else 2304
    if len(rows) != expected:
        raise RuntimeError(f'Expected {expected} comparisons, received {len(rows)}')
    (build/f'v31-lab{suffix}.csv').write_text(csv_data, encoding='utf-8')
    numeric = ['meanAngularDegrees', 'meanYawErrorDegrees', 'meanPitchErrorDegrees',
               'meanSetpointAngularDegrees', 'meanPredictedErrorStuds', 'meanInstantPositionErrorStuds',
               'acquisitionSeconds', 'yawSignChanges', 'pitchSignChanges',
               'stopYawOvershootDegrees', 'landingPitchUndershootDegrees']
    groups: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    scenarios: dict[tuple[str, str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[(row['version'], row['mode'])].append(row)
        scenarios[(row['version'], row['mode'], row['scenario'])].append(row)
    def summary(key: tuple[str, ...], grouped: list[dict[str, str]]) -> dict:
        result = {'group': list(key), 'rows': len(grouped)}
        for metric in numeric:
            values = [float(row[metric]) for row in grouped]
            if metric == 'acquisitionSeconds':
                values = [value for value in values if value >= 0]
            result[metric] = sum(values)/len(values) if values else None
        result['acquisitionFailures'] = sum(float(row['acquisitionSeconds']) < 0 for row in grouped)
        return result
    report = {
        'baselineCommit': BASELINE,
        'baselineSha256': hashlib.sha256(baseline.encode()).hexdigest(),
        'currentSha256': hashlib.sha256(source.encode()).hexdigest(),
        'rows': len(rows), 'pairedConfigurations': len(rows)//2,
        'durationSeconds': args.duration, 'quick': args.quick,
        'receiptSamplingHz': 30, 'rttSamplingHz': 5,
        'deterministicNoiseStuds': {'xAmplitude': 0.04, 'yAmplitude': 0.025, 'zAmplitude': 0},
        'fpsTimesteps': [30, 144] if args.quick else [30, 60, 120, 144],
        'nominalRttMs': [60, 300] if args.quick else [60, 100, 150, 300],
        'environment': 'Official Luau CLI and CamV2Mock API doubles; no Roblox renderer, physics, network, FPS measurement, weapon or Da Hood run',
        'capturePolicy': 'Simulator delays captured position by instantaneous RTT/2; estimator receives receipt time and independently sampled RTT',
        'predictedErrorReference': 'Future trajectory at requested unmodified horizontal and vertical horizons; shorter safety horizons can increase this metric',
        'instantErrorReference': 'Trajectory at current receipt time; prediction may intentionally lead it',
        'acquisitionReference': 'Time when a run of at least 100ms within 1 degree of predicted setpoint completes; does not measure player-selection acquisition. CSV -1 means not acquired; summary means exclude failed rows',
        'signChangeReference': 'Error sign changes beyond +/-0.05 degree; changing targets can cause them and they do not prove controller oscillation',
        'aggregateWarning': 'Means weight rows equally, not frames; max errors and axis rates include initial acquisition',
        'groups': [summary(key, value) for key, value in groups.items()],
        'scenarios': [summary(key, value) for key, value in scenarios.items()],
    }
    (build/f'v31-lab{suffix}-summary.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(next(line for line in reversed(lines) if line.startswith('V31 SUMMARY:')))
    for group in report['groups']:
        print('{} {}: mean yaw {:.4f}°, pitch {:.4f}°, instant {:.4f} studs, future {:.4f} studs; {} acquisition failures'.format(
            *group['group'], group['meanYawErrorDegrees'], group['meanPitchErrorDegrees'],
            group['meanInstantPositionErrorStuds'], group['meanPredictedErrorStuds'], group['acquisitionFailures']))
    print(f'Results: build/v31-lab{suffix}.csv and build/v31-lab{suffix}-summary.json; CLI fixtures only')


if __name__ == '__main__':
    main()
