#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then
  umask 077
  printf 'TANGERINE_TOKEN=%s\n' "$(openssl rand -hex 32)" > .env
fi
./scripts/build-app.sh
docker compose up -d --build --wait --wait-timeout 150
printf '\nDeployment ready. Launch: open "%s/build/Tangerine.app"\n' "$PWD"
