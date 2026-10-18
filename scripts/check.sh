#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_*.py' -v
mkdir -p .build/check-cache
sources=()
for source in Sources/Tangerine/*.swift; do
  if [ "$(basename "$source")" != main.swift ]; then sources+=("$source"); fi
done
swiftc -O -module-cache-path .build/check-cache "${sources[@]}" tests/NativeChecks.swift -o .build/native-checks
.build/native-checks
git diff --check
