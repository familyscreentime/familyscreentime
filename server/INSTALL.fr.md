# Installer le serveur Family Screen Time

Le serveur permet aux appareils reliés de se synchroniser aussi hors de la
maison. Il ne peut pas lire ce qu'il transmet : tout est chiffré de bout en
bout avec une clé que seuls les appareils connaissent.

## Ce qu'il faut

- Un hébergement web avec PHP 8.2 ou plus récent (l'extension sodium est
  incluse dans PHP).
- Une base MySQL ou MariaDB. À défaut, SQLite convient pour une famille.
- Une adresse en HTTPS (un certificat Let's Encrypt suffit ; la plupart des
  hébergeurs le proposent d'un clic).

Ni accès SSH, ni tâche planifiée, ni réglage du serveur web ne sont
nécessaires.

## Étapes

1. **Créez une base de données** et son utilisateur dans l'espace client de
   l'hébergeur. Notez le serveur (souvent `localhost`), le nom de la base,
   l'utilisateur et le mot de passe.
2. **Envoyez le dossier `server`** dans votre espace web, par FTP ou par le
   gestionnaire de fichiers de l'hébergeur, par exemple sous le nom `fst`.
3. **Ouvrez `https://votre-site/fst/install.php`.** La page vérifie PHP,
   puis demande la base de données et un mot de passe d'administration
   (12 caractères au moins). Elle affiche ensuite l'adresse à entrer dans
   l'application : `https://votre-site/fst/api.php`.
4. **Supprimez `install.php`** du serveur. Il refuse de toute façon de
   fonctionner une seconde fois, mais mieux vaut l'enlever.
5. **Ouvrez `https://votre-site/fst/admin.php`**, connectez-vous et créez
   une invitation. Notez le code affiché (par exemple `K7QM-3VXA-RT9D`) : il
   ne sera plus montré.

Sur un hébergement Apache (le cas le plus courant), les dossiers `lib` et
`data` sont protégés automatiquement. Sur nginx, il faut les interdire dans
la configuration du site (voir README.md).

## Dans l'application

1. Sur un appareil déjà relié aux autres, ouvrez le mode parent, puis
   **Appareils reliés › Serveur › Configurer**.
2. Entrez l'adresse du serveur et le code d'invitation, puis **Connecter**.
3. Les autres appareils reliés apprennent l'existence du serveur à leur
   prochaine synchronisation sur le Wi-Fi de la maison, puis l'utilisent
   partout.

Les appareils reliés avant la version 0.23 reçoivent la clé du serveur à la
prochaine saisie du code parent sur chacun d'eux.

L'écran Appareils reliés indique la dernière synchronisation par le serveur
et, pour chaque appareil, son dernier contact, par le Wi-Fi ou par le
serveur.

## Mise à jour

Remplacez les fichiers du dossier par ceux de la nouvelle version, sans
toucher à `config.php` ni au dossier `data`. Aucune étape de plus : les
tables restent les mêmes.

Pour la version 0.25 de l'application, mettez le serveur à jour **avant**
les appareils : un serveur plus ancien refuse ce qu'ils envoient.

## Administration

La page d'accueil du serveur (`https://votre-site/fst/`) rappelle l'adresse à
entrer dans l'application. La page `admin.php` permet :

- de créer des invitations : une par famille (pas par enfant ni par
  appareil), valable de 1 à 90 jours, qui ne sert qu'une fois, au premier
  appareil qui configure le serveur. La note est pour vous seul ;
- de voir les familles inscrites, avec la note de leur invitation : nombre
  d'appareils, dernier contact, données ; et, dans les détails, chaque
  appareil, ce qu'il reçoit (tout pour un appareil de parent, la famille et
  un enfant pour un appareil d'enfant) et son dernier contact. Le serveur ne
  connaît pas les noms : les enfants y sont numérotés ;
- de supprimer une famille et toutes ses données.

L'utilisation des applis est conservée 47 jours, puis effacée
automatiquement. Les réglages sont conservés tant que la famille existe.

Pour héberger d'autres familles (des amis, par exemple), créez-leur une
invitation : chaque famille a ses propres clés, et aucune ne peut lire les
données d'une autre, pas plus que vous.
