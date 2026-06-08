# Architecture production Bus Scolaire Connect

Objectif : disposer d'une application exploitable serieusement, transferable entre Render, Hetzner, OVH, Scaleway ou tout serveur Docker.

## Architecture cible

```text
Parents / conducteurs / admins
        |
        | HTTPS
        v
Reverse proxy Caddy
SSL automatique Let's Encrypt
        |
        v
API Docker Node.js / Express
        |
        v
PostgreSQL separe
        |
        v
Sauvegardes quotidiennes
```

## Elements obligatoires

- API dans un conteneur Docker.
- PostgreSQL separe de l'application.
- Certificats SSL automatiques via Caddy ou hebergeur.
- Sauvegarde PostgreSQL quotidienne.
- Serveur de secours pret a demarrer.
- Supervision 24h/24 via Uptime Kuma, Better Stack, UptimeRobot ou equivalent.
- Healthcheck public : `/health`.

## Docker

Lancer la production sur VPS :

```bash
cp .env.docker.example .env
docker compose -f docker-compose.prod.yml up -d --build
```

Avec supervision locale :

```bash
docker compose --profile monitoring -f docker-compose.prod.yml up -d --build
```

Uptime Kuma sera disponible sur :

```text
http://serveur:3001
```

Ajouter un monitor HTTP sur :

```text
https://votre-domaine/health
```

## SSL automatique

Le service Caddy lit :

- `DOMAIN`
- `ACME_EMAIL`

Exemple `.env` :

```text
DOMAIN=api.bus-scolaire-connect.fr
ACME_EMAIL=contact@votre-societe.fr
```

Le domaine doit pointer vers l'IP du serveur. Caddy genere et renouvelle les certificats SSL automatiquement.

## PostgreSQL separe

Recommandation :

- PostgreSQL manage si possible : Neon, Scaleway Managed Database, OVH Managed Databases, Render PostgreSQL.
- Sinon PostgreSQL Docker local avec volume persistant.

Base externe :

```text
DATABASE_URL=postgresql://user:password@host:5432/db?sslmode=require
DATABASE_SSL=true
```

Base locale Docker :

```text
DATABASE_URL=postgres://bus:bus@postgres:5432/bus_scolaire_connect
DATABASE_SSL=false
```

## Sauvegardes quotidiennes

Script :

```bash
scripts/backup-postgres.sh
```

Sur un VPS, installer le client PostgreSQL si la base est externe :

```bash
sudo apt update
sudo apt install -y postgresql-client gzip
```

Variables utiles :

```text
BACKUP_DIR=/var/backups/bus-scolaire-connect/postgres
RETENTION_DAYS=30
DATABASE_URL=postgresql://...
```

Cron quotidien a 02h15 :

```cron
15 2 * * * cd /opt/bus-scolaire-connect && BACKUP_DIR=/var/backups/bus-scolaire-connect/postgres RETENTION_DAYS=30 scripts/backup-postgres.sh >> /var/log/bus-scolaire-backup.log 2>&1
```

Restaurer :

```bash
scripts/restore-postgres.sh /var/backups/bus-scolaire-connect/postgres/bus-scolaire-connect-YYYYMMDD-HHMMSS.sql.gz
```

Bonnes pratiques :

- conserver au moins 30 jours de sauvegarde ;
- copier les sauvegardes hors du serveur principal ;
- tester une restauration une fois par mois ;
- proteger les fichiers de sauvegarde car ils contiennent des donnees sensibles.

## Serveur de secours

Principe :

1. Installer Docker sur un second serveur.
2. Cloner le depot.
3. Copier `.env` sans exposer les secrets publiquement.
4. Restaurer la derniere sauvegarde PostgreSQL ou pointer vers la meme base managee.
5. Lancer `docker compose -f docker-compose.prod.yml up -d --build`.
6. Basculer le DNS si le serveur principal tombe.

Option plus avancee :

- garder PostgreSQL manage et separer seulement l'API ;
- utiliser deux serveurs API qui pointent vers la meme base PostgreSQL ;
- basculer via DNS faible TTL ou load balancer.

## Surveillance 24h/24

A surveiller :

- `https://domaine/health`
- expiration SSL ;
- espace disque ;
- memoire ;
- CPU ;
- dernier fichier de sauvegarde ;
- reponse Firebase/FCM si possible.

Services possibles :

- Uptime Kuma auto-heberge ;
- UptimeRobot ;
- Better Stack ;
- Grafana Cloud ;
- service de monitoring OVH/Scaleway/Hetzner.

Script de controle simple :

```bash
HEALTH_URL=https://domaine/health scripts/monitor-health.sh
```

## Securite

- Ne jamais committer `firebase-service-account.json`.
- Utiliser `FIREBASE_SERVICE_ACCOUNT_JSON` en variable secrete.
- `JWT_SECRET` doit etre long et unique.
- Acces PostgreSQL limite.
- Sauvegardes chiffrees ou stockees dans un espace protege.
- Logs sans donnees personnelles inutiles.

## Strategie recommandee

Phase actuelle :

- Render + Neon + Firebase.

Phase production robuste :

- API Docker sur VPS Hetzner/OVH/Scaleway.
- PostgreSQL manage separe.
- Caddy SSL automatique.
- Uptime Kuma ou Better Stack.
- Sauvegardes quotidiennes exportees hors serveur.
- Serveur de secours prepare, pas forcement actif en permanence.
