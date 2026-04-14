#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Erreur: fichier .env introuvable dans ${REPO_ROOT}"
  echo "Créez-le avec : cp .env.example .env"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Erreur: Docker n'est pas installé ou n'est pas dans le PATH."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Erreur: docker compose n'est pas disponible sur ce VPS."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

required_vars=(
  PROJECT_NAME
  SUBDOMAIN
  ROOT_DOMAIN
  TLS_EMAIL
  WORDPRESS_DB_NAME
  WORDPRESS_DB_USER
  WORDPRESS_DB_PASSWORD
  WORDPRESS_TABLE_PREFIX
  MARIADB_ROOT_PASSWORD
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Erreur: la variable ${var_name} est vide dans .env"
    exit 1
  fi
done

FINAL_DOMAIN="${SUBDOMAIN}.${ROOT_DOMAIN}"

echo "Projet       : ${PROJECT_NAME}"
echo "Domaine final: ${FINAL_DOMAIN}"
echo "URL publique : https://${FINAL_DOMAIN}"
echo
echo "Démarrage de la stack Docker Compose..."

cd "${REPO_ROOT}"
docker compose up -d

echo
echo "Déploiement lancé."
echo "Commandes utiles :"
echo "  docker compose ps"
echo "  docker compose logs -f caddy"
echo "  docker compose logs -f wordpress"
echo "  docker compose logs -f mariadb"
echo "  docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile"
echo "  docker compose exec wordpress php -r 'echo getenv(\"WP_HOME\"), PHP_EOL;'"
