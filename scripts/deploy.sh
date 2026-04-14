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

is_project_reverse_proxy_running() {
  local service

  for service in nginx caddy; do
    if docker ps \
      --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
      --filter "label=com.docker.compose.service=${service}" \
      --format '{{.ID}}' | grep -q .; then
      return 0
    fi
  done

  return 1
}

print_port_usage() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :${port} )" || true
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN || true
    return
  fi

  echo "Impossible d'identifier le processus: ni 'ss' ni 'lsof' n'est disponible."
}

ensure_port_available() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    if ss -H -ltn "( sport = :${port} )" | grep -q .; then
      echo "Erreur: le port ${port}/tcp est déjà utilisé sur l'hôte."
      echo "Service détecté :"
      print_port_usage "${port}"
      echo
      echo "Libérez ce port puis relancez : bash scripts/deploy.sh"
      exit 1
    fi
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Erreur: le port ${port}/tcp est déjà utilisé sur l'hôte."
      echo "Service détecté :"
      print_port_usage "${port}"
      echo
      echo "Libérez ce port puis relancez : bash scripts/deploy.sh"
      exit 1
    fi
  fi
}

ensure_compose_resources() {
  docker compose create nginx certbot >/dev/null
}

ensure_external_volume() {
  local volume_name="$1"

  if ! docker volume inspect "${volume_name}" >/dev/null 2>&1; then
    docker volume create "${volume_name}" >/dev/null
  fi
}

domain_resolves() {
  if getent ahosts "${FINAL_DOMAIN}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v host >/dev/null 2>&1 && host "${FINAL_DOMAIN}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v nslookup >/dev/null 2>&1 && nslookup "${FINAL_DOMAIN}" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

has_certificate() {
  docker run --rm \
    -v "${NGINX_CERTS_VOLUME}:/etc/letsencrypt" \
    alpine:3.20 \
    test -f "/etc/letsencrypt/renewal/${FINAL_DOMAIN}.conf"
}

create_dummy_certificate() {
  echo "Initialisation d'un certificat temporaire pour ${FINAL_DOMAIN}..."

  docker run --rm \
    -v "${NGINX_CERTS_VOLUME}:/etc/letsencrypt" \
    alpine:3.20 \
    /bin/sh -eu -c "
      apk add --no-cache openssl >/dev/null
      mkdir -p /etc/letsencrypt/live/${FINAL_DOMAIN}
      openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout /etc/letsencrypt/live/${FINAL_DOMAIN}/privkey.pem \
        -out /etc/letsencrypt/live/${FINAL_DOMAIN}/fullchain.pem \
        -subj '/CN=${FINAL_DOMAIN}' >/dev/null 2>&1
    "
}

remove_certificate_material() {
  docker run --rm \
    -v "${NGINX_CERTS_VOLUME}:/etc/letsencrypt" \
    alpine:3.20 \
    /bin/sh -eu -c "
      rm -rf /etc/letsencrypt/live/${FINAL_DOMAIN}
      rm -rf /etc/letsencrypt/archive/${FINAL_DOMAIN}
      rm -f /etc/letsencrypt/renewal/${FINAL_DOMAIN}.conf
    "
}

request_certificate() {
  docker compose run --rm --no-deps --entrypoint certbot certbot certonly \
    --webroot \
    -w /var/www/certbot \
    --email "${TLS_EMAIL}" \
    --agree-tos \
    --no-eff-email \
    --rsa-key-size 4096 \
    --non-interactive \
    -d "${FINAL_DOMAIN}"
}

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
NGINX_CERTS_VOLUME="${PROJECT_NAME}_nginx_certs"
NGINX_WEBROOT_VOLUME="${PROJECT_NAME}_nginx_webroot"

if ! is_project_reverse_proxy_running; then
  ensure_port_available 80
  ensure_port_available 443
fi

echo "Projet       : ${PROJECT_NAME}"
echo "Domaine final: ${FINAL_DOMAIN}"
echo "URL publique : https://${FINAL_DOMAIN}"
echo

cd "${REPO_ROOT}"
ensure_external_volume "${NGINX_CERTS_VOLUME}"
ensure_external_volume "${NGINX_WEBROOT_VOLUME}"
ensure_compose_resources

if ! has_certificate; then
  create_dummy_certificate
fi

echo "Démarrage de la stack Docker Compose avec nginx..."
docker compose up -d --remove-orphans

if ! has_certificate; then
  if ! domain_resolves; then
    echo
    echo "Le domaine ${FINAL_DOMAIN} ne résout pas encore en DNS public."
    echo "Créez les enregistrements DNS A/AAAA, attendez la propagation, puis relancez : bash scripts/deploy.sh"
    exit 1
  fi

  echo
  echo "Demande du certificat Let's Encrypt pour ${FINAL_DOMAIN}..."
  remove_certificate_material

  if ! request_certificate; then
    echo "Échec de l'obtention du certificat Let's Encrypt."
    echo "Restauration d'un certificat temporaire pour garder nginx démarrable."
    create_dummy_certificate
    docker compose exec -T nginx nginx -s reload >/dev/null 2>&1 || true
    echo "Vérifiez le DNS, les ports 80/443 et relancez : bash scripts/deploy.sh"
    exit 1
  fi

  docker compose exec -T nginx nginx -s reload >/dev/null
  echo "Certificat Let's Encrypt installé et nginx rechargé."
fi

echo
echo "Déploiement lancé."
echo "Commandes utiles :"
echo "  docker compose ps"
echo "  docker compose logs -f nginx"
echo "  docker compose logs -f certbot"
echo "  docker compose logs -f wordpress"
echo "  docker compose logs -f mariadb"
echo "  docker compose exec -T nginx nginx -t"
echo "  docker compose run --rm --no-deps --entrypoint certbot certbot certificates"
echo "  docker compose exec wordpress php -r 'echo getenv(\"WP_HOME\"), PHP_EOL;'"
