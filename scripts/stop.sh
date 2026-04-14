#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "Erreur: Docker n'est pas installé ou n'est pas dans le PATH."
  exit 1
fi

cd "${REPO_ROOT}"
docker compose down --remove-orphans

echo "Stack arrêtée proprement. Les volumes persistants ont été conservés."
