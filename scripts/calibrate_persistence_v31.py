#!/usr/bin/env python3
"""Measure actual V3/V3.1 Session target-loss transitions with bounded doubles.

Runs 32 rows: two actual bundles, four scheduled FPS values, and four temporary
occlusion/part-absence scenarios. This does not run Roblox or measure FPS.
"""
from __future__ import annotations

from collections import defaultdict
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
BASELINE = "7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a"


def main() -> None:
    runner = find_tool("luau", "LUAU")
    compiler = find_tool("luau-compile", "LUAU_COMPILE")
    lab = ROOT / "tests/cam_v31_persistence_lab.luau"
    compiled = subprocess.run([compiler, "--binary", str(lab)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if compiled.returncode:
        sys.stderr.buffer.write(compiled.stderr)
        raise SystemExit(compiled.returncode)
    source = (ROOT / "SedwareCamLock.lua").read_text(encoding="utf-8")
    baseline = subprocess.check_output(["git", "show", BASELINE + ":SedwareCamLock.lua"], cwd=ROOT, text=True)
    # Separate from check_cam, the motion lab and any development harness.
    harness = ROOT / "tests/.generated_v31_persistence.luau"
    harness.write_text('require("./cam_v31_persistence_lab")(' + literal(source) + "," + literal(baseline) + ")\n", encoding="utf-8")
    try:
        result = subprocess.run([runner, str(harness)], cwd=ROOT, text=True, capture_output=True, timeout=60)
    finally:
        harness.unlink(missing_ok=True)
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    (build / "v31-persistence.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        print(result.stdout[-4000:])
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    lines = result.stdout.splitlines()
    header = next(line.removeprefix("V31_PERSISTENCE_HEADER,") for line in lines if line.startswith("V31_PERSISTENCE_HEADER,"))
    data = [line.removeprefix("V31_PERSISTENCE,") for line in lines if line.startswith("V31_PERSISTENCE,")]
    csv_data = header + "\n" + "\n".join(data) + "\n"
    rows = list(csv.DictReader(io.StringIO(csv_data)))
    if len(rows) != 32:
        raise RuntimeError(f"Expected 32 actual-Session rows, received {len(rows)}")
    (build / "v31-persistence.csv").write_text(csv_data, encoding="utf-8")
    groups: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[(row["version"], row["scenario"])].append(row)
    summaries = []
    for key, grouped in groups.items():
        summaries.append({
            "version": key[0], "scenario": key[1], "rows": len(grouped),
            "totalObservedLosses": sum(int(float(row["lossCount"])) for row in grouped),
            "totalObservedReacquisitions": sum(int(float(row["reacquisitionCount"])) for row in grouped),
            "meanPausedSeconds": sum(float(row["pausedSeconds"]) for row in grouped) / len(grouped),
            "meanUnlockedSeconds": sum(float(row["unlockedSeconds"]) for row in grouped) / len(grouped),
            "finalSamePlayerRows": sum(row["recoveredSamePlayer"] == "true" for row in grouped),
            "automaticReacquisitionRows": sum(row["autoReacquired"] == "true" for row in grouped),
            "otherPlayerSelections": sum(int(float(row["otherPlayerSelections"])) for row in grouped),
        })
    report = {
        "baselineCommit": BASELINE,
        "baselineSha256": hashlib.sha256(baseline.encode()).hexdigest(),
        "currentSha256": hashlib.sha256(source.encode()).hexdigest(),
        "rows": len(rows), "pairedConfigurations": len(rows) // 2,
        "scheduledFps": [30, 60, 120, 144], "warmupSeconds": .5, "recoveryWindowSeconds": .8,
        "faultSeconds": {"BriefOcclusion": .1, "LongOcclusion": .4, "BriefPartAbsence": .1, "LongPartAbsence": .3},
        "commonConfig": {"Enabled": True, "SmartSelection": True, "TargetGraceSeconds": .2, "Radius": 180, "MaxDistance": 350, "HitPart": "HumanoidRootPart"},
        "environment": "Official Luau CLI with CamV2Mock API doubles executing actual standalone Session code; no native rendering, physics, network, weapon, hit confirmation, measured FPS or Da Hood run",
        "faultPolicy": "Occlusion is an explicit Raycast double; part absence destroys HumanoidRootPart and creates a new BasePart in the same loaded character",
        "lossReference": "Observed GetLockedTarget transitions from the selected Player to nil, including synchronous destruction callbacks",
        "pauseReference": "Sum of scheduled frame durations whose end state remains locked to the selected Player and exposes non-nil pauseReason",
        "timeReference": "Fault durations are exact; last timestep of each segment can be shorter than 1/FPS. First-loss/recovery -1 means no transition observed",
        "recoveryReference": "recoveredSamePlayer means that GetLockedTarget equals the original Player at the end, including cases that never lost it; autoReacquired requires observed loss and subsequent reacquisition",
        "policyDifference": "Natural defaults preserved: V3 implicitly reacquires after loss; V3.1 ReacquireOnLoss=false retains a real loss until a user action. Different long-fault final locks reflect this intentional policy, not prediction accuracy",
        "candidateLimitation": "One loaded candidate per row; otherPlayerSelections=0 is a fixture integrity check, not multi-player anti-switch validation",
        "diagnosticsLimitation": "V3 has no GetTrackingDiagnostics; finalTrackingState/lastLossCode are Unavailable, not inferred",
        "groups": summaries,
    }
    (build / "v31-persistence-summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(next(line for line in reversed(lines) if line.startswith("V31 PERSISTENCE SUMMARY:")))
    for group in summaries:
        print("{} {}: losses {}, paused {:.4f}s, final same player {}/4, automatic reacquisition {}/4".format(
            group["version"], group["scenario"], group["totalObservedLosses"], group["meanPausedSeconds"],
            group["finalSamePlayerRows"], group["automaticReacquisitionRows"]))
    print("Results: build/v31-persistence.csv and build/v31-persistence-summary.json; actual Session doubles only")


if __name__ == "__main__":
    main()
