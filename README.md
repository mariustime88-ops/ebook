# Application de lecture

Prototype Flutter d'une plateforme de lecture de livres numériques.

## Lancer l'application dans Chrome

1. Ouvrir le dossier du projet dans Visual Studio Code.
2. Ouvrir un terminal dans Visual Studio Code.
3. Redémarrer Visual Studio Code après l'installation de Flutter, puis exécuter :

```powershell
flutter doctor
flutter run -d chrome --web-port=5013 --dart-define=API_BASE_URL=http://localhost:3000/api
```

Au premier lancement, l'inscription s'affiche. Après création d'un compte
lecteur, l'accueil s'ouvre ; un auteur doit d'abord être validé par un
administrateur. Un compte existant peut choisir « J'ai déjà un compte ».

## API et configuration locale

Un backend Node.js / Express est disponible dans [`backend/`](./backend).
L'application Flutter commence par l'inscription ou la connexion ; la page
d'accueil n'est accessible qu'après connexion. Elle peut ensuite charger le
catalogue serveur, déposer des livres PDF/DOCX et gérer la modération. Les tables
`platform_` ont été créées dans la base `ebook`, qui était vide. Consultez
[`backend/README.md`](./backend/README.md) pour le démarrage du serveur et la
création sécurisée du premier administrateur.

Les achats passent par FedaPay. Pour tester, configurez une nouvelle clé
secrète sandbox exclusivement dans `backend/.env` et redémarrez l’API ; toute
clé secrète déjà publiée doit être révoquée. Le mode sandbox ne débite pas
d’argent réel. L’API vérifie la transaction, son montant et sa devise avant de
confirmer l’achat et d’autoriser le téléchargement du fichier.

Les paiements passent uniquement par FedaPay. Les commissions sont calculées,
mais les versements aux auteurs restent manuels ; sans taux configuré, la
commission est de 0 %. Les webhooks, les virements automatiques, le DRM et la
lecture intégrée restent à développer. Voir
[`backend/README.md`](./backend/README.md) pour configurer le mode sandbox.

Pour pointer Flutter vers une autre adresse d'API, utilisez
`--dart-define=API_BASE_URL=https://votre-serveur/api`. La valeur par défaut est
`http://localhost:3000/api`, pratique sur le navigateur de développement local.

## Vérifier le code

```powershell
flutter analyze
flutter test
```

## Lancer sur Android

Android Studio et le SDK Android ne sont pas encore installés. Il faudra les
installer et accepter les licences Android avant de pouvoir lancer l'application
sur un téléphone ou un émulateur.

Les images d'origine et le cahier des charges sont conservés à la racine du projet.
