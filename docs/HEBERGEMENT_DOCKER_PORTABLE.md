# Hebergement Docker portable

Objectif : pouvoir transferer Bus Scolaire Connect entre Render, Hetzner, OVH, Scaleway ou un VPS Docker sans reecrire l'application.

## Image Docker

Le `Dockerfile` a la racine embarque :

- le backend Node.js/Express ;
- le dossier `database/` necessaire aux migrations PostgreSQL ;
- un healthcheck `/health` ;
- le demarrage automatique `migrate + seed + start`.

Construire l'image :

```bash
docker build -t bus-scolaire-connect-api:latest .
```

Lancer avec une base externe Neon, OVH, Scaleway, Render ou autre :

```bash
docker run -d \
  --name bus-scolaire-connect-api \
  -p 3000:3000 \
  -e DATABASE_URL="postgresql://user:password@host:5432/db?sslmode=require" \
  -e DATABASE_SSL=true \
  -e JWT_SECRET="secret-long-et-unique" \
  -e FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account", "...":"..."}' \
  bus-scolaire-connect-api:latest
```

## Docker Compose complet

Pour un VPS Hetzner, OVH ou Scaleway avec PostgreSQL local :

```bash
cp .env.docker.example .env
docker compose -f docker-compose.prod.yml up -d --build
```

URL de verification :

```text
http://serveur:3000/health
```

## Variables importantes

- `DATABASE_URL` : URL PostgreSQL.
- `DATABASE_SSL` : `true` si base externe type Neon/Render/Scaleway managée.
- `JWT_SECRET` : secret long, jamais public.
- `FIREBASE_SERVICE_ACCOUNT_JSON` : cle Firebase Admin en variable d'environnement.
- `FCM_SERVICE_ACCOUNT_PATH` : alternative si la cle est montee comme fichier secret.
- `ROUTING_PROVIDER` : `osrm` ou `graphhopper`.
- `GRAPHHOPPER_API_KEY` : necessaire uniquement si GraphHopper est utilise.

## Strategie de transfert

1. Exporter la base PostgreSQL actuelle.
2. Creer une base PostgreSQL sur le nouvel hebergeur.
3. Renseigner `DATABASE_URL`, `DATABASE_SSL`, `JWT_SECRET`, Firebase.
4. Lancer le conteneur Docker.
5. Verifier `/health`.
6. Pointer le domaine vers le nouvel hebergeur.

## Corrections manuelles et donnees Nomad

Les migrations restent lancees au demarrage. Les futures synchronisations GTFS Nomad devront conserver une couche de corrections manuelles admin, afin qu'un transfert d'hebergeur ne perde pas les ajustements terrain.
