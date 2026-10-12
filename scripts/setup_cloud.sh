#!/usr/bin/env bash
set -euo pipefail
repo_dir=/workspace/sedon-
tool_dir=/workspace/tools/luau-source
expected_commit=1f6ff5d6f0072f2fab2adf35d1ffbaae7d848ad0
test -d "$repo_dir"
command -v python3 >/dev/null
command -v git >/dev/null
command -v g++ >/dev/null
command -v make >/dev/null
mkdir -p /workspace/tools
if [ ! -d "$tool_dir/.git" ]; then
  git clone --depth 1 --branch 0.695 https://github.com/luau-lang/luau.git "$tool_dir"
fi
actual_commit=$(git -C "$tool_dir" rev-parse HEAD)
if [ "$actual_commit" != "$expected_commit" ]; then
  echo "Luau tool checkout differs from pinned commit; preserve it and choose a separate tool directory." >&2
  exit 1
fi
make --no-print-directory -s -C "$tool_dir" config=release luau luau-compile -j2
export LUAU="$tool_dir/luau"
export LUAU_COMPILE="$tool_dir/luau-compile"
cd "$repo_dir"
python3 scripts/check.py
