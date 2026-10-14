#!/usr/bin/env python3
"""Compare the published V3.1 and canonical V3.2 bundles with CLI API doubles.

This measures scheduled trajectories, not Roblox rendering FPS, native physics,
weapon hits, networking, or compatibility with a third-party experience.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import subprocess
import sys

from check import find_tool
from check_cam import literal

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'da44a4c7af3857c1fed22b9fb757c012180650ac'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quick', action='store_true', help='30/144 Hz, 60/300 ms, Manual only smoke matrix')
    parser.add_argument('--duration', type=float, default=3.0, help='Fixture duration, 3..6 seconds')
    args = parser.parse_args()
    if not 3 <= args.duration <= 6:
        parser.error('--duration must be between 3 and 6 seconds')
    runner = find_tool('luau', 'LUAU')
    build = ROOT/'build'
    build.mkdir(exist_ok=True)
    source_path = ROOT/'SedwareCamLock.lua'
    source = source_path.read_text(encoding='utf-8')
    baseline = subprocess.check_output(['git', 'show', BASELINE+':SedwareCamLock.lua'], cwd=ROOT, text=True)
    harness = ROOT/'tests/.generated_v32_lab.luau'
    harness.write_text('require("./cam_v32_lab")('+literal(source)+','+literal(baseline)+',{' +
                       'quick='+str(args.quick).lower()+',duration='+str(args.duration)+'})\n', encoding='utf-8')
    try:
        result = subprocess.run([runner, str(harness)], cwd=ROOT, text=True, capture_output=True, timeout=120)
    finally:
        harness.unlink(missing_ok=True)
    suffix = '-quick' if args.quick else ''
    (build/f'v32-lab{suffix}.log').write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        print(result.stdout[-4000:])
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    if source_path.read_text(encoding='utf-8') != source:
        raise RuntimeError('Canonical source changed during the run; rerun after freezing the bundle')
    lines = result.stdout.splitlines()
    header = next(line.removeprefix('V32_HEADER,') for line in lines if line.startswith('V32_HEADER,'))
    data = [line.removeprefix('V32_LAB,') for line in lines if line.startswith('V32_LAB,')]
    csv_data = header+'\n'+'\n'.join(data)+'\n'
    rows = list(csv.DictReader(io.StringIO(csv_data)))
    expected = 288 if args.quick else 2304
    if len(rows) != expected:
        raise RuntimeError(f'Expected {expected} comparison rows, received {len(rows)}')
    for row in rows:
        for name, value in row.items():
            if name not in {'version', 'scenario', 'mode', 'policy'} and not math.isfinite(float(value)):
                raise RuntimeError(f'Non-finite result in {name}')
    (build/f'v32-lab{suffix}.csv').write_text(csv_data, encoding='utf-8')
    numeric = ['meanAngularDegrees', 'meanYawErrorDegrees', 'meanPitchErrorDegrees',
               'meanSetpointAngularDegrees', 'meanPredictedErrorStuds', 'meanInstantPositionErrorStuds',
               'meanYawAfterWarmupDegrees', 'meanPitchAfterWarmupDegrees',
               'acquisitionSeconds', 'yawSignChanges', 'pitchSignChanges',
               'stopYawOvershootDegrees', 'landingPitchUndershootDegrees']
    maxima = ['maxYawRateDegreesPerSecond', 'maxPitchRateDegreesPerSecond',
              'maxPitchAccelerationDegreesPerSecond2', 'maxContinuousPitchAccelerationDegreesPerSecond2',
              'stableGoalOvershootMaxDegrees']
    counters = ['pitchAccelerationViolationFrames', 'hardConstraintFrames', 'initialReferenceFrames',
                'brakingRecoveryFrames', 'goalCrossingFrames', 'movingGoalFrames',
                'verticalAnomalyFrames', 'apexLeadLimitedFrames', 'unknownRawVelocityFrames']
    groups: dict[tuple[str, ...], list[dict[str, str]]] = defaultdict(list)
    scenarios: dict[tuple[str, ...], list[dict[str, str]]] = defaultdict(list)
    rtt_groups: dict[tuple[str, ...], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[(row['version'], row['mode'])].append(row)
        scenarios[(row['version'], row['mode'], row['scenario'])].append(row)
        rtt_groups[(row['version'], row['mode'], row['nominalRttMs'])].append(row)

    def summarize(key: tuple[str, ...], grouped: list[dict[str, str]]) -> dict:
        summary = {'group': list(key), 'rows': len(grouped)}
        for metric in numeric:
            values = [float(row[metric]) for row in grouped]
            if metric == 'acquisitionSeconds':
                values = [value for value in values if value >= 0]
            summary[metric] = sum(values)/len(values) if values else None
        for metric in maxima:
            summary[metric] = max(float(row[metric]) for row in grouped)
        for metric in counters:
            summary[metric] = sum(int(float(row[metric])) for row in grouped)
        summary['acquisitionFailures'] = sum(float(row['acquisitionSeconds']) < 0 for row in grouped)
        return summary

    report = {
        'baselineCommit': BASELINE,
        'baselineSha256': hashlib.sha256(baseline.encode()).hexdigest(),
        'currentCanonicalFile': 'SedwareCamLock.lua',
        'currentSha256': hashlib.sha256(source.encode()).hexdigest(),
        'rows': len(rows), 'pairedConfigurations': len(rows)//2,
        'scheduledSamples': sum(int(float(row['samples'])) for row in rows),
        'durationSeconds': args.duration, 'quick': args.quick,
        'receiptSamplingHz': 30, 'rttSamplingHz': 5,
        'deterministicNoiseStuds': {'xAmplitude': 0.04, 'yAmplitude': 0.025, 'zAmplitude': 0},
        'fpsTimesteps': [30, 144] if args.quick else [30, 60, 120, 144],
        'nominalRttMs': [60, 300] if args.quick else [60, 100, 150, 300],
        'scenarios': ['Walking', 'Running', 'RepeatedJump', 'Landing', 'Falling', 'Reversal',
                      'Near', 'Far', 'Circle', 'Stop', 'Teleport', 'VariablePing'],
        'environment': 'Official Luau CLI and CamV2Mock API doubles; no Roblox renderer, physics, network, measured FPS, weapon, or Da Hood execution',
        'capturePolicy': 'Simulator delays captured position by instantaneous RTT/2; estimators receive local receipt time and separately sampled RTT, never capture time',
        'predictionReference': 'Future trajectory at requested unmodified axis horizons; prudent shorter lead can increase this metric',
        'instantReference': 'Trajectory at current receipt time; intentional prediction lead can increase this metric',
        'acquisitionReference': 'Completion of at least 100ms within 1 degree of predicted setpoint. CSV -1 means not acquired; means exclude failures. This does not measure player selection or weapon hits',
        'warmupReference': 'Yaw/pitch after t>=0.5 seconds are reported separately from initial acquisition; all-frame metrics are also retained',
        'accelerationReference': 'Differences between consecutive applied CFrame pitches divided by timestep. All-frame maxima include transitions; scoped maxima exclude explicitly flagged hard constraints and initial/reset epochs. Baseline lacks these flags and is measured directly',
        'accelerationScope': 'Continuous pitch only with AngularSafety and prediction context. No global yaw-acceleration guarantee, no bound across resets/camera replacement/hard poles/external camera writes',
        'overshootReference': 'Stable-setpoint crossing is reported separately from moving-goal crossings and current-trajectory landing undershoot; moving targets and deliberate lead can change error sign without controller oscillation',
        'metadataAvailability': 'New epoch, recovery, anomaly and overshoot metadata are absent in baseline; zero counts for absent metadata are not proof that baseline never experienced those events',
        'aggregateWarning': 'Means weight configurations equally, not frames; maxima include acquisition. Warmup metrics supplement and never replace all-frame error',
        'groups': [summarize(key, grouped) for key, grouped in groups.items()],
        'scenarioGroups': [summarize(key, grouped) for key, grouped in scenarios.items()],
        'rttGroups': [summarize(key, grouped) for key, grouped in rtt_groups.items()],
    }
    (build/f'v32-lab{suffix}-summary.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(next(line for line in reversed(lines) if line.startswith('V32 SUMMARY:')))
    for group in report['groups']:
        print('{} {}: mean yaw {:.4f}°, pitch {:.4f}°; continuous pitch accel {:.2f}°/s²; {} violations, {} hard conflicts; {} acquisition failures'.format(
            *group['group'], group['meanYawErrorDegrees'], group['meanPitchErrorDegrees'],
            group['maxContinuousPitchAccelerationDegreesPerSecond2'], group['pitchAccelerationViolationFrames'],
            group['hardConstraintFrames'], group['acquisitionFailures']))
    print(f'Results: build/v32-lab{suffix}.csv and summary JSON; CLI math / API doubles only')


if __name__ == '__main__':
    main()
