# API REST

Base URL locale : `http://localhost:3000/api`

- `POST /auth/login` : connexion.
- `GET /routes` : lignes, vehicules, arrets, horaires, compteurs.
- `POST /delays` : declaration de retard et notification FCM.
- `POST /presence` : presence ou absence a l'arret.
- `POST /gps` : position GPS conducteur.
- `GET /gps/latest/:routeId` : derniere position connue.
- `GET /reports/dashboard` : indicateurs de supervision.
- `GET /reports/attendance/monthly` : frequentation mensuelle.
- `GET /vehicles` / `POST /vehicles` : gestion des vehicules.
- `GET /nomad/routes` : lignes Nomad Car importees depuis le GTFS officiel.
- `GET /nomad/routes?highlighted=true` : lignes prioritaires du secteur Aumale / Blangy-sur-Bresle / Neufchatel-en-Bray.
- `GET /nomad/routes?q=521` : recherche par numero de ligne, nom de ligne ou nom d'arret.
- `GET /nomad/routes/:id` : detail complet d'une ligne Nomad avec ses arrets representatifs.
