#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_*.py' -v
mkdir -p .build/check-cache
swiftc -O -module-cache-path .build/check-cache Sources/Tangerine/Settings.swift Sources/Tangerine/FileActions.swift Sources/Tangerine/ImageEditor.swift Sources/Tangerine/Wheel.swift tests/NativeChecks.swift -o .build/native-checks
.build/native-checks
git diff --check
