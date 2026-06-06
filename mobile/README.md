# Application mobile

Ouvrir ce dossier dans Android Studio ou Visual Studio Code.

Si Android Studio demande `local.properties`, lancer dans `mobile/` :

```bash
flutter create . --platforms=android
flutter pub get
```

Le code applicatif est dans `lib/`. L'URL API Android emulator par defaut est `http://10.0.2.2:3000/api`.
