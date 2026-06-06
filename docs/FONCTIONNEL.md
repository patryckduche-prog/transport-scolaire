# Documentation fonctionnelle

## Roles

- Conducteur : choix de tournee, depart depot, declaration de statut, GPS, arrets, signature.
- Parent / eleve : statut bus, presence ou absence, carte, historique des alertes.
- Entreprise : vehicules, conducteurs, retards, motifs, alertes exploitation.
- Region : suivi global, statistiques, lignes saturees, arrets peu frequentes, rapports annuels.

## Retards

Statuts : a l'heure, retard 5, 10, 15, 30 minutes, superieur a 30 minutes.
Motifs : neige, verglas, panne mecanique, accident, bouchon, route barree, meteo, autre.

## Hors connexion

L'application mobile contient une file locale `pending_events`. Les presences et points GPS peuvent y etre stockes quand le reseau est indisponible, puis envoyes au retour de la connexion.

## Donnees Nomad

Les lignes Nomad Car sont importees depuis le GTFS officiel publie sur transport.data.gouv.fr. L'ecran conducteur `Circuits Nomad` affiche toutes les lignes importees et met en avant le secteur Aumale / Blangy-sur-Bresle / Neufchatel-en-Bray via les lignes 520, 521 et 522.

Source : https://transport.data.gouv.fr/datasets/nomad-car-region-normandie

Les fiches horaires scolaires 2025-2026 restent referencees par Nomad sous forme de PDF numerotes sur la page officielle : https://nomad.normandie.fr/horaires-circuits-scolaires-2025-2026
