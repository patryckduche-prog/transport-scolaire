# Tests Android Studio

Profils d'emulateurs crees pour Bus Scolaire Connect :

- `BusConnect_S24Plus_like` : grand telephone recent, proche Samsung S24+.
- `BusConnect_S24_like` : telephone recent standard, proche Samsung S24.
- `BusConnect_SmallPhone` : petit telephone pour verifier les petits ecrans.
- `BusConnect_Tablet` : tablette Android.
- `BusConnect_Foldable` : grand ecran pliable.

Dans Android Studio :

1. Ouvrir `Tools > Device Manager`.
2. Lancer un profil `BusConnect_*`.
3. Ouvrir le dossier `mobile`.
4. Lancer l'application Flutter sur l'emulateur choisi.

Version APK de test sauvegardee :

- `outputs/bus-scolaire-connect-release.apk`
- lien local/public pendant le tunnel : `/download/bus-scolaire-connect.apk`

Note : les emulateurs ne remplacent pas totalement les tests sur Samsung reel, surtout pour GPS, Play Protect, notifications et batterie.
