#!/usr/bin/env python3
"""Package the existing project; issue a loader only after verifying a real Raw URL.

Default operation is entirely local. No Git operations, credentials, publishing,
TLS overrides or automatic execution of downloaded code are performed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
DOWNLOADS = ROOT.parent / "downloads"
PAYLOAD = ROOT / "DaHoodPrediction.lua"
MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024
SOURCE_FILES = ("DaHoodPrediction.lua", "Loader.template.lua", "README.md",
                "default.project.json", ".gitignore")
SOURCE_DIRS = {
    "src": {".lua", ".luau"},
    "tests": {".lua", ".luau"},
    "scripts": {".py", ".sh"},
    "docs": {".md"},
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def regular_file(path: Path) -> bool:
    """Do not include symlinks, including files inside a symlinked directory."""
    return (path.is_file() and not path.is_symlink()
            and all(not (ROOT / parent).is_symlink()
                    for parent in path.relative_to(ROOT).parents))


def validate_raw_url(url: str) -> str:
    if not url or not url.isascii() or any(ord(char) <= 32 for char in url):
        raise ValueError("Provide an actual ASCII HTTPS GitHub Raw URL copied from GitHub")
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.netloc != "raw.githubusercontent.com"
            or parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("Expected https://raw.githubusercontent.com/... without credentials, query or fragment")
    parts = parsed.path.strip("/").split("/")
    if len(parts) < 4 or parts[-1] != "DaHoodPrediction.lua" or any(p in ("", ".", "..") for p in parts):
        raise ValueError("The Raw URL must identify the published DaHoodPrediction.lua file")
    return url


class RawOnlyRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_raw_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def verified_loader(url: str, payload: bytes) -> tuple[str, str]:
    """Fetch with standard TLS verification and compare, never execute the response."""
    url = validate_raw_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "DH-Prediction-Lab-distribution/1"})
    opener = urllib.request.build_opener(RawOnlyRedirects())
    with opener.open(request, timeout=15) as response:
        validate_raw_url(response.geturl())
        if response.status != 200:
            raise ValueError(f"GitHub Raw returned HTTP {response.status}")
        remote = response.read(MAX_DOWNLOAD_BYTES + 1)
    if len(remote) > MAX_DOWNLOAD_BYTES:
        raise ValueError("Remote script exceeds the 2 MiB download limit")
    remote.decode("utf-8")
    if remote != payload:
        raise ValueError("Published script differs from the local DaHoodPrediction.lua; upload the current file or use its exact Raw URL")
    # Validated ASCII URLs can be quoted identically in JSON and Lua strings.
    quoted_url = json.dumps(url)
    template = (ROOT / "Loader.template.lua").read_text(encoding="utf-8")
    loader = template.replace('local URL_RAW_DEL_SCRIPT = ""', f"local URL_RAW_DEL_SCRIPT = {quoted_url}", 1)
    one_line = f"loadstring(game:HttpGet({quoted_url}))()"
    return loader, one_line


def archive(path: Path, members: dict[str, bytes]) -> None:
    """Write deterministic archive contents and re-read every member to verify bytes."""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, data in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zipped.writestr(info, data)
    path.chmod(0o644)
    with zipfile.ZipFile(path) as zipped:
        corrupt = zipped.testzip()
        if corrupt:
            raise ValueError(f"Corrupt ZIP member: {corrupt}")
        for name, expected in members.items():
            if zipped.read(name) != expected:
                raise ValueError(f"ZIP byte mismatch: {name}")


def package(raw_url: str | None = None) -> dict[str, str]:
    if not regular_file(PAYLOAD):
        raise ValueError("Missing DaHoodPrediction.lua; generate it before packaging")
    payload = PAYLOAD.read_bytes()
    payload.decode("utf-8")
    # Verification precedes all file mutations when a real URL is requested.
    loader = command = None
    if raw_url is not None:
        loader, command = verified_loader(raw_url, payload)
    BUILD.mkdir(exist_ok=True)
    DOWNLOADS.mkdir(exist_ok=True)
    DOWNLOADS.chmod(0o755)

    members: dict[str, bytes] = {}
    for name in SOURCE_FILES:
        path = ROOT / name
        if regular_file(path):
            members[name] = path.read_bytes()
    for directory, suffixes in SOURCE_DIRS.items():
        for path in (ROOT / directory).rglob("*"):
            if path.suffix in suffixes and regular_file(path):
                members[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    for name in ("AimLab.rbxlx", "DHPredictionLab.rbxlx", "standalone-manifest.json"):
        path = BUILD / name
        if regular_file(path):
            members[f"build/{name}"] = path.read_bytes()

    if loader is not None:
        (ROOT / "Loader.lua").write_text(loader, encoding="utf-8")
        (ROOT / "Loader.lua").chmod(0o644)
        (BUILD / "LOADSTRING.txt").write_text(command + "\n", encoding="utf-8")
        members["Loader.lua"] = loader.encode("utf-8")
        members["build/LOADSTRING.txt"] = (command + "\n").encode("utf-8")

    manifest = {name: sha256(data) for name, data in sorted(members.items())}
    manifest_data = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    (BUILD / "distribution-manifest.json").write_bytes(manifest_data)
    members["build/distribution-manifest.json"] = manifest_data
    archive(BUILD / "DaHoodPrediction.zip", {"DaHoodPrediction.lua": payload})
    archive(BUILD / "DHPredictionLab-source.zip", members)

    copies = {
        "DaHoodPrediction.lua": PAYLOAD,
        "DaHoodPrediction.txt": PAYLOAD,
        "Loader.template.lua": ROOT / "Loader.template.lua",
        "DaHoodPrediction.zip": BUILD / "DaHoodPrediction.zip",
        "DHPredictionLab-source.zip": BUILD / "DHPredictionLab-source.zip",
    }
    place = BUILD / "DHPredictionLab.rbxlx"
    if regular_file(place):
        copies[place.name] = place
    if loader is not None:
        copies["Loader.lua"] = ROOT / "Loader.lua"
        copies["LOADSTRING.txt"] = BUILD / "LOADSTRING.txt"
    for name, source in copies.items():
        destination = DOWNLOADS / name
        shutil.copyfile(source, destination)
        destination.chmod(0o644)
        if destination.read_bytes() != source.read_bytes():
            raise ValueError(f"Download copy differs: {name}")
    report = {"payload_sha256": sha256(payload), "source_members": str(len(members)),
              "downloads": str(DOWNLOADS), "raw_url_verified": str(loader is not None)}
    print(json.dumps(report, indent=2))
    if command:
        print(command)
    else:
        print("No real Raw URL verified; Loader.lua and a final one-line command were not generated.")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-url", help="Actual public GitHub Raw URL; its bytes must match the current payload")
    args = parser.parse_args()
    try:
        package(args.raw_url)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Distribution preparation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
