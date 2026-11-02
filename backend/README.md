# API Application Livre

API Node.js / Express pour les comptes, le catalogue, les soumissions d’auteurs
et la modération. Elle utilise des tables dédiées préfixées `platform_` dans
MySQL et ne remplace ni ne supprime les tables déjà présentes dans `ebook`.

## Préparer MySQL

1. Copier `.env.example` vers `.env`, puis renseigner l’utilisateur et le mot
   de passe MySQL. Ne partagez et ne commitez jamais `.env`.
2. Créer une clé JWT forte. Dans PowerShell :

   ```powershell
   node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
   ```

3. Vérifier la base choisie (`MYSQL_DATABASE=ebook`) et lire
   `src/db/migrations/001-platform-schema.sql`.
4. Appliquer les migrations après sauvegarde de la base :

   ```powershell
   npm install
   npm run db:migrate
   ```

   Les migrations SQL ne sont pas transactionnelles dans MySQL : une erreur
   peut laisser des tables déjà créées, sans supprimer les données. La migration
   `003-fedapay-only.sql` retire les anciennes destinations de versement MTN
   MoMo ; les achats passent uniquement par FedaPay.
5. Pour créer le premier administrateur, définir temporairement
   `ADMIN_INITIAL_EMAIL`, `ADMIN_INITIAL_DISPLAY_NAME` et un
   `ADMIN_INITIAL_PASSWORD` d’au moins 8 caractères dans `.env`, puis lancer :

   ```powershell
   npm run admin:create
   ```

   Retirer ensuite le mot de passe initial du fichier `.env`.
6. Démarrer l’API :

   ```powershell
   npm run dev
   ```

7. Lancer Flutter avec la même URL que celle autorisée par `CORS_ORIGINS` :

   ```powershell
   flutter run -d chrome --web-port=5013 --dart-define=API_BASE_URL=http://localhost:3000/api
   ```

   L’inscription est le premier écran. Un compte auteur peut ensuite déposer son fichier depuis
   **Mes livres** ; les demandes de compte auteur restent bloquées jusqu’à
   leur activation par un administrateur. Les lecteurs peuvent charger le
   catalogue approuvé depuis **Découvrir**.

   Sur un émulateur Android, remplacez `localhost` par `10.0.2.2`.
   L’autorisation HTTP sans TLS est limitée au manifeste Android de debug ;
   utilisez exclusivement HTTPS pour une version distribuée.

## Hébergement gratuit pour tester l’application

Render ne propose pas de base MySQL gratuite. Son PostgreSQL gratuit expire au
bout de 30 jours et nécessiterait de réécrire les requêtes MySQL du backend.
Pour conserver ce backend, le Blueprint `render.yaml` déploie l’API sur Render
Free et utilise TiDB Cloud Starter en mode MySQL-compatible pour la base.
L’offre TiDB Starter inclut une enveloppe gratuite soumise à des quotas ; voir
les [limites Render Free](https://render.com/docs/free) et les
[quotas TiDB Starter](https://docs.pingcap.com/tidbcloud/select-cluster-tier/).

1. Créez une instance TiDB Cloud Starter **MySQL-compatible**, activez son
   endpoint public et notez son hôte, son port, sa base et son utilisateur.
   Dans la liste d’accès réseau de TiDB, autorisez les plages IP sortantes
   affichées dans **Connect > Outbound** sur le service Render ; n’ouvrez pas
   la base à toutes les adresses IP. TiDB impose TLS.
2. Depuis le dépôt GitHub lié à Render, créez un Blueprint et sélectionnez
   `render.yaml`. Dans les variables `MYSQL_HOST`, `MYSQL_DATABASE`,
   `MYSQL_USER` et `MYSQL_PASSWORD` du service, entrez les valeurs TiDB.
   Laissez `MYSQL_PORT=4000` et `MYSQL_SSL=true`. Render génère le `JWT_SECRET`.
   Définissez séparément `FEDAPAY_SECRET_KEY` avec une clé sandbox, si les
   paiements sont nécessaires.
3. Après le premier déploiement, exécutez depuis la racine du dépôt :

   ```powershell
   .\backend\scripts\copy-local-data.ps1
   ```

   Le script lit la base locale configurée dans `backend/.env`, demande les
   identifiants TiDB en saisie masquée et copie les comptes, livres, paramètres
   et commandes sans afficher leur contenu. Il refuse de remplacer des données
   déjà présentes dans la base cloud. Sauvegardez vos données avant cette
   opération. Le fichier `platform_users.sql` est une sauvegarde contenant des
   données personnelles et des empreintes de mots de passe : gardez-le local et
   ne le poussez pas sur GitHub. Les références aux PDF/DOCX sont copiées, mais
   pas les fichiers eux-mêmes ; leur stockage doit être configuré séparément.
4. Copiez l’URL publique HTTPS du service Render et générez l’APK en remplaçant
   l’adresse par exemple ci-dessous :

   ```powershell
   flutter build apk --release --dart-define=API_BASE_URL=https://VOTRE-API.onrender.com/api
   ```

   L’APK se trouvera dans `build\app\outputs\flutter-apk\app-release.apk`.

Render Free met le service en veille après une période d’inactivité ; le premier
réveil peut prendre environ une minute. Son disque local n’est pas persistant :
les PDF/DOCX téléversés sur l’API ne doivent pas y être conservés à long terme.
Utilisez un stockage de fichiers persistant avant de compter sur le téléchargement
des livres après un redémarrage ou une mise en veille.

## Paiements FedaPay

Les paiements de livres utilisent FedaPay. Pour tester en sandbox, définissez
`FEDAPAY_ENVIRONMENT=sandbox` et ajoutez une **nouvelle clé secrète sandbox**
dans `FEDAPAY_SECRET_KEY` de `backend/.env`, puis redémarrez l’API. Le projet
refuse le mode live et toute clé qui ne commence pas par `sk_sandbox_`, afin
d’éviter tout débit réel pendant les tests. Pour
enregistrer une nouvelle clé sans l’afficher dans le terminal, exécutez depuis
le dossier `backend` :

```powershell
.\scripts\configure-fedapay.ps1
```

Le script demande la clé en saisie masquée, vérifie son préfixe sandbox et
l’écrit uniquement dans `.env`. Ne mettez jamais cette clé dans Flutter, dans
Git ou dans un message. Toute clé secrète déjà partagée doit d’abord être
révoquée depuis FedaPay. Sans clé, l’API démarre normalement mais le checkout
répond que le paiement n’est pas configuré.

Le compte marchand FedaPay reçoit les encaissements. Les montants, la devise,
la commission configurée et la référence de transaction sont conservés dans
`platform_orders`. L’achat n’est marqué payé qu’après une vérification serveur
auprès de FedaPay du statut approuvé, du montant, de la devise et de la
transaction attendue. Le fichier privé n’est téléchargeable qu’après cette
confirmation. Le bac à sable ne débite pas d’argent réel. Si l’administrateur
n’a pas défini de commission, le taux appliqué est 0 %.

La part auteur est calculée, mais les reversements restent manuels : aucun
transfert automatique vers les auteurs n’est déclenché. Les webhooks, la production
FedaPay, la lecture intégrée des fichiers et le DRM ne sont pas inclus dans
cette première intégration. Avant d’activer la production, configurer et tester
le compte marchand, déployer l’API sous HTTPS et vérifier les exigences
FedaPay pour les paiements et reversements.

## Routes disponibles

- `GET /api/health/live` et `GET /api/health/ready`
- `POST /api/auth/register` — comptes lecteur et auteur ; les auteurs attendent
  l’activation d’un administrateur
- `POST /api/auth/login` et `GET /api/auth/me`
- `GET /api/books` — catalogue approuvé
- `POST /api/payments/checkout` — création ou reprise d’un checkout FedaPay
- `GET /api/payments/orders/:id` — vérification serveur de la transaction
- `GET /api/purchases/:bookId/file` — téléchargement après achat confirmé
- `GET /api/author/books` et `POST /api/author/books` — soumission PDF/DOCX
- `GET /api/admin/users`, `PATCH /api/admin/users/:id/status`
- `GET /api/admin/books`, `GET /api/admin/books/:id/file` et
  `PATCH /api/admin/books/:id/review`
- `GET /api/admin/dashboard`
- `GET /api/admin/settings/commission` et
  `PUT /api/admin/settings/commission`
- `GET /api/admin/settings/payment-provider` — statut de configuration FedaPay

Les fichiers soumis sont conservés dans `PRIVATE_FILES_DIR`, hors des dossiers
servis publiquement. L’API vérifie les signatures PDF et la structure DOCX, et
limite les envois à 25 Mo.

Au premier lancement, l'application affiche l'inscription ; un compte lecteur
est activé immédiatement et donne accès à l'accueil. Les comptes auteurs restent
en attente de validation et ne peuvent pas encore accéder à leur espace jusqu'à
leur activation par un administrateur.

Il n’existe plus d’écran ou de route de paiement MTN MoMo. Le statut de paiement
est confirmé par FedaPay côté serveur ; le retour navigateur seul ne suffit pas.

## Tests

```powershell
npm test
```
