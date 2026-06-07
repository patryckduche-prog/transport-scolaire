# Bus Scolaire Connect - Noyau exploitation

## Objectif

Supprimer la dependance au badgeage eleve et rendre le conducteur autonome avec une interface simple :

- suivi GPS temps reel ;
- detection automatique d'approche d'arret par geofencing 50 m ;
- notifications parents basees sur les lignes favorites et les arrets ;
- absence parent transmise au conducteur ;
- trombinoscope tactile conducteur ;
- SOS regulation ;
- check fin de service pour eviter tout oubli d'enfant ;
- fonctionnement offline-first avec file locale d'evenements.

## Tables ajoutees

- `students` : eleves actifs, rattachement parent optionnel.
- `student_route_assignments` : affectation eleve -> ligne -> arret.
- `route_stop_geofences` : coordonnees d'arrets et rayon de detection.
- `daily_runs` : tournee journaliere conducteur.
- `daily_run_stop_events` : approche/arrivee/depart/saut d'arret.
- `daily_run_student_presence` : etat attendu/present/absent/non vu.
- `run_incidents` : SOS ou incident conducteur.
- `run_finish_checks` : verification fin de service.

## API cycle de tournee

- `POST /api/runs/start` : demarre une tournee.
- `GET /api/runs/current` : recupere la tournee active du conducteur.
- `GET /api/runs/:runId/students` : trombinoscope et presences.
- `POST /api/runs/:runId/gps` : position GPS + detection geofence.
- `POST /api/runs/:runId/stops/:stopExternalId/arrive` : validation manuelle d'arret.
- `POST /api/runs/:runId/students/:studentId/presence` : validation tactile conducteur.
- `POST /api/runs/absence` : absence declaree par parent/eleve.
- `POST /api/runs/:runId/incidents` : SOS/incident regulation.
- `POST /api/runs/:runId/finish-check` : cloture securisee.

## Temps reel

WebSocket disponible sur `/ws`.

Evenements emis :

- `run.started`
- `run.gps`
- `run.stop.approaching`
- `run.stop.arrived`
- `run.student.presence`
- `run.student.absence`
- `run.incident`
- `run.finish_check`

## Offline-first conducteur

Le mobile conducteur garde localement les evenements si le reseau coupe :

- GPS de tournee ;
- presence/non vu ;
- SOS ;
- check fin de service.

La classe Flutter `OfflineEventQueue` rejoue les evenements au retour reseau ou sur action `Synchroniser`.

## Securite mineurs

- Eleves identifies par UUID.
- Trombinoscope affiche nom/prenom minimum, photo optionnelle.
- Acces API protege par JWT et role.
- Donnees sensibles non exposees sur endpoints publics.
- Les eleves n'ont aucune action obligatoire.

## A finir pour production

- Import officiel des coordonnees exactes d'arrets.
- Validation exploitation des routes car scolaire.
- FCM serveur final avec compte de service Render.
- Supervision WebSocket cote entreprise/region.
- Politique RGPD complete : duree conservation GPS/presences, export/suppression.
