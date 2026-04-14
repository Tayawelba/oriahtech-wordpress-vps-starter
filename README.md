# oriahtech-wordpress-vps-starter

Starter kit Docker Compose prêt pour la production afin de déployer un site WordPress sur un VPS Linux avec MariaDB et Caddy. Le domaine public est construit automatiquement à partir de `SUBDOMAIN` et `ROOT_DOMAIN`, par exemple `client1.oriahtech.com`.

## Contenu du dépôt

- `docker-compose.yml` : stack WordPress + MariaDB + Caddy
- `Caddyfile` : reverse proxy HTTPS avec certificats Let's Encrypt automatiques
- `scripts/deploy.sh` : script de déploiement
- `scripts/stop.sh` : script d'arrêt propre
- `.env.example` : modèle de configuration

## Prérequis VPS

- VPS Linux public avec une IP fixe
- Docker Engine installé
- Docker Compose plugin installé (`docker compose`)
- accès SSH au serveur
- un nom de domaine dont vous contrôlez la zone DNS

## Configuration DNS

Créez un enregistrement DNS pour le domaine final vers l'IP publique du VPS.

Exemple :

- `SUBDOMAIN=client1`
- `ROOT_DOMAIN=oriahtech.com`
- domaine final : `client1.oriahtech.com`

Enregistrement DNS recommandé :

- type `A` pour `client1.oriahtech.com` vers l'IPv4 du VPS
- type `AAAA` si vous exposez aussi l'IPv6 du VPS

Déployez uniquement après propagation DNS, sinon Let's Encrypt ne pourra pas émettre le certificat SSL.

## Ports à ouvrir

Ouvrez au minimum :

- `80/tcp` pour le challenge HTTP et la redirection vers HTTPS
- `443/tcp` pour le trafic HTTPS

Optionnel mais habituel :

- `22/tcp` pour SSH

## Configuration du fichier .env

Copiez le modèle puis adaptez toutes les variables :

```bash
cp .env.example .env
```

Variables attendues :

- `PROJECT_NAME` : nom logique du projet Docker Compose
- `SUBDOMAIN` : sous-domaine du client
- `ROOT_DOMAIN` : domaine racine
- `TLS_EMAIL` : email utilisé par Let's Encrypt
- `WORDPRESS_DB_NAME` : nom de la base WordPress
- `WORDPRESS_DB_USER` : utilisateur MariaDB de WordPress
- `WORDPRESS_DB_PASSWORD` : mot de passe MariaDB de WordPress
- `WORDPRESS_TABLE_PREFIX` : préfixe des tables WordPress
- `MARIADB_ROOT_PASSWORD` : mot de passe root MariaDB

Exemple :

```env
PROJECT_NAME=oriahtech-wordpress-client1
SUBDOMAIN=client1
ROOT_DOMAIN=oriahtech.com
TLS_EMAIL=admin@oriahtech.com
WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=change_me_wordpress_db_password
WORDPRESS_TABLE_PREFIX=wp_
MARIADB_ROOT_PASSWORD=change_me_mariadb_root_password
```

## Démarrage

L'utilisation prévue est :

```bash
cp .env.example .env
# modifiez .env
bash scripts/deploy.sh
```

Le script :

- vérifie la présence du fichier `.env`
- valide les variables obligatoires
- affiche le domaine final
- démarre la stack avec `docker compose up -d`
- affiche des commandes utiles de debug

Une fois la stack démarrée, ouvrez `https://<SUBDOMAIN>.<ROOT_DOMAIN>` dans le navigateur pour finaliser l'installation WordPress si c'est le premier démarrage.

## Architecture

- `caddy` est le seul service exposé publiquement sur `80` et `443`
- `wordpress` n'expose aucun port au public
- `mariadb` n'expose aucun port au public
- `wordpress` et `mariadb` communiquent sur un réseau Docker interne
- `caddy` relaie le trafic HTTPS vers `wordpress`
- WordPress force l'URL publique en HTTPS avec `WP_HOME`, `WP_SITEURL` et `FORCE_SSL_ADMIN`
- le cas reverse proxy HTTPS est géré via `HTTP_X_FORWARDED_PROTO`

## Mise à jour

Pour mettre à jour les images puis redémarrer proprement :

```bash
docker compose pull
docker compose up -d
```

Pour voir l'état après mise à jour :

```bash
docker compose ps
```

## Arrêt

Pour arrêter la stack sans supprimer les volumes :

```bash
bash scripts/stop.sh
```

## Sauvegarde des volumes

Les volumes persistants créés par Compose sont préfixés par `PROJECT_NAME`.

Exemple avec `PROJECT_NAME=oriahtech-wordpress-client1` :

- `oriahtech-wordpress-client1_wordpress_data`
- `oriahtech-wordpress-client1_mariadb_data`
- `oriahtech-wordpress-client1_caddy_data`
- `oriahtech-wordpress-client1_caddy_config`

Exemple de sauvegarde :

```bash
mkdir -p backups
set -a && source .env && set +a

docker run --rm \
  -v "${PROJECT_NAME}_wordpress_data:/source:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar czf "/backup/wordpress-data_$(date +%F_%H%M%S).tar.gz" -C /source .

docker run --rm \
  -v "${PROJECT_NAME}_mariadb_data:/source:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar czf "/backup/mariadb-data_$(date +%F_%H%M%S).tar.gz" -C /source .

docker run --rm \
  -v "${PROJECT_NAME}_caddy_data:/source:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar czf "/backup/caddy-data_$(date +%F_%H%M%S).tar.gz" -C /source .

docker run --rm \
  -v "${PROJECT_NAME}_caddy_config:/source:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar czf "/backup/caddy-config_$(date +%F_%H%M%S).tar.gz" -C /source .
```

## Logs et debug

Logs en direct :

```bash
docker compose logs -f caddy
docker compose logs -f wordpress
docker compose logs -f mariadb
```

Validation de la configuration Caddy :

```bash
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

État de la stack :

```bash
docker compose ps
```
