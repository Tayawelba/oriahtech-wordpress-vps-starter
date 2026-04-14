# oriahtech-wordpress-vps-starter

Starter kit Docker Compose prêt pour la production afin de déployer un site WordPress sur un VPS Linux avec MariaDB, `nginx` et Let's Encrypt. Le domaine public est construit automatiquement à partir de `SUBDOMAIN` et `ROOT_DOMAIN`, par exemple `client1.oriah.tech`.

## Contenu du dépôt

- `docker-compose.yml` : stack WordPress + MariaDB + nginx + certbot
- `nginx/default.conf.template` : template nginx du reverse proxy
- `scripts/deploy.sh` : script de déploiement avec bootstrap SSL
- `scripts/stop.sh` : script d'arrêt propre
- `.env.example` : modèle de configuration

## Prérequis VPS

- VPS Linux public avec une IP fixe
- Docker Engine installé
- Docker Compose plugin installé (`docker compose`)
- accès SSH au serveur
- un nom de domaine dont vous contrôlez la zone DNS

Le reverse proxy `nginx` tourne dans Docker. Il n'est pas nécessaire d'installer `nginx` sur l'hôte.
Les volumes des certificats sont conservés explicitement pour éviter toute perte de SSL lors des redéploiements.

## Configuration DNS

Créez un enregistrement DNS pour le domaine final vers l'IP publique du VPS.

Exemple :

- `SUBDOMAIN=client1`
- `ROOT_DOMAIN=oriah.tech`
- domaine final : `client1.oriah.tech`

Enregistrements recommandés :

- type `A` pour `client1.oriah.tech` vers l'IPv4 du VPS
- type `AAAA` si vous exposez aussi l'IPv6 du VPS

Attendez la propagation DNS avant le premier déploiement, sinon Let's Encrypt échouera.

## Ports à ouvrir

Ouvrez au minimum :

- `80/tcp` pour le challenge HTTP Let's Encrypt et la redirection vers HTTPS
- `443/tcp` pour le trafic HTTPS

Optionnel mais courant :

- `22/tcp` pour SSH

## Configuration du fichier .env

Copiez le modèle puis adaptez les variables :

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
ROOT_DOMAIN=oriah.tech
TLS_EMAIL=hello@oriah.tech
WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=change_me_wordpress_db_password
WORDPRESS_TABLE_PREFIX=wp_
MARIADB_ROOT_PASSWORD=change_me_mariadb_root_password
```

## Démarrage

Utilisation prévue :

```bash
cp .env.example .env
# modifiez .env
bash scripts/deploy.sh
```

Le script :

- vérifie la présence du fichier `.env`
- valide les variables obligatoires
- vérifie que les ports `80` et `443` sont disponibles si aucun reverse proxy du projet n'est déjà en cours d'exécution
- calcule le domaine final
- crée un certificat temporaire au premier démarrage pour permettre à `nginx` de monter
- lance `docker compose up -d --remove-orphans`
- demande ensuite le certificat Let's Encrypt réel
- recharge `nginx`
- affiche les commandes utiles de debug

Une fois la stack prête, ouvrez `https://<SUBDOMAIN>.<ROOT_DOMAIN>` dans le navigateur pour terminer l'installation WordPress si c'est le premier démarrage.

## Architecture

- `nginx` est le seul service exposé publiquement sur `80` et `443`
- `certbot` gère l'obtention et le renouvellement des certificats Let's Encrypt
- `wordpress` n'expose aucun port au public
- `mariadb` n'expose aucun port au public
- `wordpress` et `mariadb` communiquent sur un réseau Docker interne
- `nginx` relaie le trafic HTTPS vers `wordpress`
- HTTP redirige vers HTTPS
- WordPress force l'URL publique en HTTPS avec `WP_HOME`, `WP_SITEURL` et `FORCE_SSL_ADMIN`
- le cas reverse proxy HTTPS est géré via `HTTP_X_FORWARDED_PROTO`

## Mise à jour

Pour mettre à jour les images puis redémarrer proprement :

```bash
docker compose pull
docker compose up -d --remove-orphans
```

Pour vérifier l'état :

```bash
docker compose ps
```

## Arrêt

Pour arrêter la stack sans supprimer les volumes :

```bash
bash scripts/stop.sh
```

## Sauvegarde des volumes

Les volumes persistants sont nommés à partir de `PROJECT_NAME`.

Exemple avec `PROJECT_NAME=oriahtech-wordpress-client1` :

- `oriahtech-wordpress-client1_wordpress_data`
- `oriahtech-wordpress-client1_mariadb_data`
- `oriahtech-wordpress-client1_nginx_certs`
- `oriahtech-wordpress-client1_nginx_webroot`

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
  -v "${PROJECT_NAME}_nginx_certs:/source:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar czf "/backup/nginx-certs_$(date +%F_%H%M%S).tar.gz" -C /source .

docker run --rm \
  -v "${PROJECT_NAME}_nginx_webroot:/source:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar czf "/backup/nginx-webroot_$(date +%F_%H%M%S).tar.gz" -C /source .
```

## Logs et debug

Logs en direct :

```bash
docker compose logs -f nginx
docker compose logs -f certbot
docker compose logs -f wordpress
docker compose logs -f mariadb
```

Validation de la configuration nginx :

```bash
docker compose exec -T nginx nginx -t
```

Lister les certificats connus de certbot :

```bash
docker compose run --rm --no-deps --entrypoint certbot certbot certificates
```

Le conteneur `certbot` attend volontairement quelques minutes avant sa première boucle de renouvellement. Cela évite les conflits de verrou juste après un déploiement ou un redémarrage.

État de la stack :

```bash
docker compose ps
```

## Dépannage

### Le déploiement échoue avec `failed to bind host port 0.0.0.0:80`

Cela signifie qu'un autre service occupe déjà le port `80` sur le VPS. Cas fréquents :

- `nginx` déjà installé sur l'hôte
- `apache2` déjà installé sur l'hôte
- un autre conteneur Docker
- une autre stack reverse proxy

Commandes de diagnostic :

```bash
ss -ltnp '( sport = :80 or sport = :443 )'
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Exemples de résolution sur l'hôte :

```bash
systemctl stop nginx
systemctl disable nginx
```

```bash
systemctl stop apache2
systemctl disable apache2
```

Si le conflit vient d'un autre conteneur Docker, arrêtez-le ou retirez sa publication de ports `80/443`, puis relancez :

```bash
bash scripts/deploy.sh
```

### Le certificat Let's Encrypt ne s'obtient pas

Vérifiez les points suivants :

- le domaine pointe bien vers l'IP publique du VPS
- les ports `80` et `443` sont ouverts dans le firewall
- aucune protection externe ne bloque le challenge HTTP

Commandes de vérification :

```bash
getent ahosts client1.oriah.tech
host client1.oriah.tech
```

Si vous obtenez `NXDOMAIN`, le problème vient du DNS : l'enregistrement `A` ou `AAAA` du sous-domaine n'existe pas encore.

Puis relancez :

```bash
bash scripts/deploy.sh
```
