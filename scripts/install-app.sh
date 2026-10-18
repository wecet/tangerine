#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
install_dir="${TANGERINE_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$install_dir"
/usr/bin/ditto build/Tangerine.app "$install_dir/Tangerine.app"
/usr/bin/codesign --verify --deep --strict "$install_dir/Tangerine.app"
printf 'Installed %s/Tangerine.app\n' "$install_dir"
printf 'Quit any older Tangerine instance, then open the installed app.\n'
