# Bus Scolaire Connect

Projet complet Flutter + Node.js/Express + PostgreSQL pour le suivi des transports scolaires.

## Structure

- `mobile/` : application Flutter Android compatible Android Studio et VS Code.
- `backend/` : API REST Express, authentification JWT, FCM, GPS, presences, retards, rapports.
- `database/` : schema PostgreSQL et donnees de demonstration.
- `scripts/` : scripts d'installation et de demarrage.
- `docs/` : documentation fonctionnelle et technique.

## Demarrage rapide

1. Installer Flutter, Node.js 20+, Docker Desktop.
2. Copier `backend/.env.example` vers `backend/.env`.
3. Lancer la base et le backend :

```bash
cd backend
npm install
docker compose up -d
npm run migrate
npm run seed
npm run dev
```

4. Lancer l'application mobile :

```bash
cd mobile
flutter pub get
flutter run
```

## Acces application

- Parent / eleve : acces direct depuis l'ecran d'accueil, sans nom, sans email et sans code.
- Conducteur : acces par code de secteur. Le code de demonstration est `AUMALE-2026`.
- Entreprise / region : acces de gestion par email et mot de passe.

## Generer un code de secteur conducteur

Depuis le dossier `backend`, lancer :

```bash
npm run driver-code -- --code=AUMALE-2026 --email=conducteur@demo.local --label="Code secteur Aumale" --sector="Aumale / Blangy / Neufchatel / Bresle" --keywords="aumale,blangy,neufchatel,neufchâtel,bresle,gamaches"
```

Le meme code peut ensuite etre donne a tous les conducteurs d'une meme entreprise, region ou zone. Les circuits visibles seront limites aux lignes et arrets correspondant aux mots-cles du secteur.

## Mini-application de generation de codes

Quand le backend est lance, ouvrir :

```text
http://localhost:3000/code-generator/
```

Connexion de demonstration :

- Email : `entreprise@demo.local`
- Mot de passe : `demo1234`

La page permet de generer un code de secteur automatiquement, de definir les mots-cles de filtrage des lignes, puis de transmettre ce meme code a la societe ou aux conducteurs concernes.

## Circuits scolaires PDF integres

Les PDF scolaires fournis sont copies dans `backend/data/pdf-scolaires`.

Un import automatique a genere `backend/data/school_sector_routes.generated.json` avec les circuits detectes dans les fiches :

`5001`, `5002`, `5003`, `5004`, `5007`, `5009`, `5010`, `5011`, `5012`, `5013`, `5015`, `5017`, `5019`, `5980`.

Le code de secteur `AUMALE-2026` est volontairement filtre sur `aumale` pour afficher uniquement les circuits lies a Aumale, dont Aumale vers Forges-les-Eaux.

## Branchement Firebase

Pour activer les notifications push reelles :

1. Copier le fichier Android Firebase dans :

```text
mobile/android/app/google-services.json
```

2. Copier le compte de service Firebase Admin dans :

```text
backend/config/firebase-service-account.json
```

3. Verifier dans `backend/.env` :

```text
FCM_SERVICE_ACCOUNT_PATH=./config/firebase-service-account.json
```

Sans ces fichiers officiels, l'application continue de fonctionner mais les notifications restent en mode journal serveur.
