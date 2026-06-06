# Securite

- Authentification JWT avec expiration courte.
- Mots de passe haches avec bcrypt.
- Permissions par role dans le middleware Express.
- Headers securises via Helmet.
- Historique des connexions dans `login_history`.
- Donnees sensibles a chiffrer au repos selon l'infrastructure cible.
- FCM utilise uniquement pour les messages d'alerte et rappels operationnels.
- Politique RGPD a completer : duree de conservation, DPO, droits d'acces et suppression.
