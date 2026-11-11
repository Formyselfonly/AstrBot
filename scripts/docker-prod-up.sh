#!/usr/bin/env bash
# Build and start compose.prod.yml (local or server). Loads deploy/.env into the shell
# so ${FISH_HTTP_PORT} and VITE_* build args interpolate correctly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/deploy/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/compose.prod.yml}"

cd "$ROOT"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — for local: cp deploy/.env.local.example deploy/.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if docker compose version &>/dev/null; then
  COMPOSE=(docker compose -f "$COMPOSE_FILE")
elif docker-compose version &>/dev/null; then
  COMPOSE=(docker-compose -f "$COMPOSE_FILE")
else
  echo "Install Docker Compose (docker compose or docker-compose)." >&2
  exit 1
fi

if [[ "${1:-}" == "down" ]]; then
  exec "${COMPOSE[@]}" down "${@:2}"
fi

if [[ "${1:-}" == "ps" ]]; then
  exec "${COMPOSE[@]}" ps "${@:2}"
fi

if [[ "${1:-}" == "logs" ]]; then
  exec "${COMPOSE[@]}" logs "${@:2}"
fi

exec "${COMPOSE[@]}" up -d --build "$@"
