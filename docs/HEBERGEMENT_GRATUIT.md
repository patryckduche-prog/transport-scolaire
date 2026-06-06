# Hebergement gratuit recommande

Objectif : remplacer le lien temporaire Cloudflare par une adresse stable.

## Choix recommande

- Backend Node.js : Render Free Web Service.
- Base PostgreSQL : Neon Free.
- APK Android : servie par le backend via `/download/`.

Render peut s'endormir apres inactivite sur l'offre gratuite. Au premier lancement apres une pause, l'application peut mettre quelques secondes a repondre.

## 1. Creer la base Neon

1. Aller sur https://neon.com
2. Creer un compte gratuit.
3. Creer un projet PostgreSQL.
4. Copier l'URL de connexion PostgreSQL.
5. Garder cette URL pour Render dans `DATABASE_URL`.

## 2. Mettre le projet sur GitHub

Render deploye le plus simplement depuis GitHub.

1. Creer un depot GitHub prive ou public.
2. Envoyer le dossier `bus-scolaire-connect` dans ce depot.
3. Verifier que `.env`, `node_modules` et les fichiers Firebase secrets ne sont pas envoyes.

## 3. Creer le backend Render

1. Aller sur https://render.com
2. New > Web Service.
3. Connecter le depot GitHub.
4. Si Render detecte `render.yaml`, accepter le Blueprint.
5. Ajouter les variables :

```text
DATABASE_URL=postgresql://...
DATABASE_SSL=true
JWT_SECRET=une-longue-chaine-secrete
```

6. Deployer.

## 4. Initialiser la base

Dans Render, ouvrir le shell du service ou lancer une commande manuelle :

```bash
npm run deploy:init
```

Cela cree les tables et les comptes de test.

Code conducteur de test :

```text
AUMALE-2026
```

## 5. Reconstruire l'application mobile

Quand Render donne l'adresse finale, par exemple :

```text
https://bus-scolaire-connect-api.onrender.com
```

Reconstruire l'APK avec :

```bash
flutter build apk --release --dart-define=API_URL=https://bus-scolaire-connect-api.onrender.com/api
```

Puis remplacer :

```text
backend/public/download/bus-scolaire-connect.apk
```

## Alternative gratuite

- Koyeb pour le backend.
- Supabase pour PostgreSQL.
- GitHub Releases ou Google Drive pour partager l'APK.

Pour une application vraiment fiable en production, un petit hebergement payant sera plus stable qu'une offre gratuite.
