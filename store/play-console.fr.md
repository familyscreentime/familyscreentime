# Console Google Play : quoi remplir (console en français)

Étapes et réponses pour publier Family Screen Time (org.familyscreentime)
sur Google Play, en commençant par les tests internes. Les libellés sont
ceux de la console en français ; Google les retouche parfois. Si un menu
n'est pas à l'endroit indiqué, la barre de recherche en haut de la console
le retrouve.

Les textes à coller pour les examinateurs de Google sont en anglais : c'est
la langue dans laquelle ils sont relus le plus vite. Ils peuvent aussi être
collés en français.

## 1. Créer l'application

Toutes les applications › **Créer une application** :

- Nom de l'application : Family Screen Time
- Langue par défaut : français – fr-FR
- Application ou jeu : **Application**
- Sans frais ou payante : **Sans frais**
- Cocher les déclarations (Règles du programme pour les développeurs, lois
  des États-Unis en matière d'exportation), puis **Créer l'application**.

## 2. Contenu de l'application (Règles et programmes › Contenu de l'application)

| Section | Réponse |
| --- | --- |
| Règles de confidentialité | https://familyscreentime.org/confidentialite.html (anglais : /privacy.html, néerlandais : /privacybeleid.html) |
| Accès à l'application | Certaines fonctionnalités sont soumises à des restrictions. Instructions ci-dessous. |
| Annonces | Non, mon application ne contient pas d'annonces. |
| Classification du contenu | Questionnaire ci-dessous. |
| Public cible et contenu | Décision à prendre : voir ci-dessous. |
| Sécurité des données | Aucune donnée collectée ni partagée (échanges entre appareils reliés chiffrés de bout en bout, exemptés). Détails ci-dessous. |
| Applications gouvernementales | Non. |
| Fonctionnalités financières | Aucune. |
| Santé | Aucune fonctionnalité de santé. |
| Applications d'actualités | Non. |
| API d'accessibilité | Déclaration ci-dessous. |
| Services de premier plan | Déclaration ci-dessous. |

### Accès à l'application : instructions pour les examinateurs

Ajouter des instructions (le nom de l'instruction : « Parent mode »), sans
identifiant ni mot de passe, puis coller :

> Parent mode is protected by a parent code the user creates on first
> launch. To review: open the app, choose a language, create any 6-digit
> parent code (for example 123456), enter a child's first name, then grant
> the permissions listed (accessibility service, usage access, display over
> other apps, notifications). Parent mode: tap the lock icon on the child's
> screen and enter the code. No account or login is needed; the app works
> fully offline.

### Classification du contenu (questionnaire IARC)

- Adresse e-mail de contact : la tienne (ou contact@familyscreentime.org une
  fois créée).
- Catégorie : **Utilitaires, productivité, communication ou autres**
  (« Toutes les autres applications » selon la version du questionnaire).
- Violence, sexualité, langage grossier, substances contrôlées, jeux
  d'argent : **Non** partout.
- Les utilisateurs peuvent interagir ou échanger du contenu : **Non**.
- Partage la position de l'utilisateur : **Non**.
- Achats numériques : **Non**.
- Accès non restreint à Internet (navigateur) : **Non**.
- Enregistrer, puis **Envoyer** : la classification s'affiche aussitôt.

### Public cible et contenu : une décision à prendre

L'appli est installée et réglée par un parent, mais l'enfant utilise son
écran enfant sur son propre appareil.

- **Option A, recommandée : 18 ans et plus.** L'appli est présentée comme un
  outil pour les parents, qui l'installent et la configurent, comme les
  autres applis de contrôle parental. L'examen est plus simple.
- **Option B : inclure les moins de 13 ans.** L'appli relève alors du
  programme « Familles » de Google. Elle en respecte déjà l'essentiel (pas
  d'annonces, aucune collecte de données), mais une appli destinée aux
  enfants qui utilise le service d'accessibilité et l'administration de
  l'appareil risque un examen plus poussé.

À la question « Votre application pourrait-elle involontairement attirer
les enfants ? », répondre **Non** avec l'option A : la fiche et les visuels
s'adressent aux parents.

La fiche du Play Store et les règles de confidentialité disent clairement
que l'appli est installée par un parent sur l'appareil d'un enfant, quelle
que soit l'option choisie.

### Sécurité des données

Depuis la 0.20, les appareils reliés échangent des données entre eux : le
formulaire doit en tenir compte. Ce qui circule, uniquement entre les
appareils que le parent a reliés, chiffré de bout en bout, sans aucun
serveur de l'éditeur : sur le Wi-Fi de la maison, et depuis la 0.23 par un
serveur relais que la famille héberge elle-même (ou une personne de
confiance), si le parent en configure un :

- le prénom des enfants ;
- les règles, groupes d'applis, bonus, blocages et le temps hors appareil ;
- le temps passé dans chaque appli (appli, début, fin, appareil) ;
- le nom et l'icône des applis installées sur chaque appareil d'enfant ;
- un identifiant aléatoire, un nom et une clé publique par appareil.

Un appareil qui n'est relié à aucun autre n'envoie rien.

L'aide de Google (« Fournir des informations pour la section Sécurité
des données », octobre 2026) définit la collecte comme la transmission de
données hors de l'appareil, mais exempte explicitement le chiffrement de
bout en bout : « User data that is sent off device, but that is unreadable
by you or anyone other than the sender and recipient as a result of
end-to-end encryption does not need to be disclosed. » Condition : aucun
intermédiaire, développeur compris, ne peut lire les données ; seuls
l'expéditeur et le destinataire ont les clés. C'est le cas ici : chaque
session entre deux appareils est chiffrée avec des clés éphémères
(X25519, ChaCha20-Poly1305) connues d'eux seuls. Par le serveur relais,
chaque événement est chiffré sur l'appareil avant de partir
(XChaCha20-Poly1305), avec une clé que seuls les appareils reliés
détiennent : le serveur stocke et transmet des données chiffrées, que ni
lui ni son administrateur ne peuvent lire. Ce serveur n'est pas celui du
développeur, qui n'en exploite aucun.

Les exports (CSV, ActivityWatch) sont des fichiers que le parent remet
lui-même à l'appli de son choix par le menu de partage d'Android : une
action de l'utilisateur, pas une collecte par l'application.

Réponses :

- Votre application collecte-t-elle ou partage-t-elle certains des types
  de données utilisateur requis ? **Non.**
- Les questions sur le chiffrement en transit et la suppression ne
  s'affichent plus. Si elles s'affichent : sans objet.
- Vérifier l'aperçu (« Aucune donnée collectée », « Aucune donnée
  partagée »), puis **Envoyer**.

Si un examinateur conteste, citer l'exemption ci-dessus. S'il maintient
son avis, déclarer : collecte **Oui** ; chiffrées en transit **Oui** ;
suppression **Oui** (détacher l'appareil, désinstaller l'appli ou vider
ses données) ; types **Informations personnelles › Nom**, **Activité dans
les applis › Interactions avec l'appli** et **Applis installées**,
**Identifiants de l'appareil ou autres** ; pour chacun collectées oui,
partagées non, collecte facultative, finalité **Fonctionnalités de
l'appli**.

Le serveur relais ne stocke que des événements chiffrés de bout en bout :
l'exemption s'applique.

### Déclaration relative à l'API d'accessibilité

Contenu de l'application › API d'accessibilité. L'attribut
`isAccessibilityTool` n'est pas renseigné : l'appli n'est donc pas
déclarée comme outil d'accessibilité, ce qui est juste. Le formulaire
(octobre 2026) pose trois questions :

- **Utilisation** : cocher seulement **Fonctionnement de l'appli**
  (compter le temps des applis à l'écran, fermer une appli bloquée,
  afficher le décompte et le verrouillage, protection contre la
  désinstallation). Rien pour l'analyse, la publicité, la
  personnalisation, les comptes ni les communications.
- **Données sensibles** : **Non**, comme dans la section Sécurité des
  données. Le service ne transmet rien au développeur ni à des tiers ;
  l'appli à l'écran et la durée d'utilisation restent sur l'appareil, ou
  vont aux appareils reliés et au serveur relais de la famille, chiffrées
  de bout en bout (exemption prévue par l'aide de Google, à laquelle la
  question renvoie). Si un examinateur conteste, répondre **Oui** ici et
  déclarer la collecte dans Sécurité des données (voir plus haut) : la
  mention dans l'appli dit déjà ce qui est fait de ces données.
- **Visibilité des communiqués** : un lien vers une vidéo (YouTube « non
  répertoriée », moins de 3 minutes) qui montre la mention présentée avant
  l'activation, puis cocher la confirmation.

Vidéo, sur une tablette avec l'enregistreur d'écran d'Android (une
installation neuve depuis le Play Store, en français ou en anglais) :

1. L'ouverture de l'appli et la configuration jusqu'à l'écran des
   autorisations.
2. Un appui sur **Accessibilité** : la fenêtre d'information s'ouvre. La
   laisser à l'écran le temps de lire tout le texte (quelques secondes ;
   faire défiler s'il dépasse).
3. Un appui sur **Accepter et activer** : la page d'accessibilité
   d'Android s'ouvre ; activer Family Screen Time et confirmer.
4. Le retour dans l'appli : l'accessibilité est cochée.
5. Facultatif mais utile : une appli limitée qui se ferme, avec son
   message, et la vidéo en petite fenêtre d'une appli bloquée qui se
   ferme.

Montrer aussi **Refuser** une fois (la fenêtre se ferme, rien n'est
activé) aide l'examinateur à voir que le choix est libre.

Texte de référence, si un examinateur demande une description de
l'utilisation (en anglais) :

> Family Screen Time is a parental control app. Its accessibility service
> detects which app is in the foreground (package and activity names of
> window changes) and which apps have windows on screen (package names of
> the window list: split screen, picture in picture), so that screen time
> is counted and the limits set by the parent are applied; it sends the
> user to the home screen when an app is blocked, and dismisses the
> picture-in-picture window of a blocked app; in browsers, it counts scroll
> events (their number, pace and distance, never the page content) to tell
> reading from quick scrolling through feeds; and it shows the countdown, warnings, block notices and the
> optional device lock as accessibility overlays, which stay visible over
> full-screen apps. When the parent turns on uninstall protection, the
> service also closes the Android settings pages that would switch the app
> off (device administrator deactivation, the app's own settings pages,
> Android's security page offering to remove its access). For this, screen
> content is read only on Android's security and permission pages. No data
> is stored beyond usage times, which stay on the device, or go only to the
> user's other devices the parent linked (over the home Wi-Fi, or through a
> relay server the family hosts itself, always end-to-end encrypted, never
> to the developer or third parties). Before the
> service is turned on, an in-app disclosure explains this and asks for
> consent. The source code is public: https://github.com/familyscreentime/familyscreentime

### Services de premier plan (utilisation spéciale)

- Type : **Utilisation spéciale** (specialUse). Le sous-type déclaré dans le
  manifeste : « Parental control: enforces the screen-time limits set by the
  parent. »
- Description, à coller :

> The foreground service runs the screen-time monitor: it records how long
> each app is used, evaluates the parent's rules and shows a persistent
> countdown notification. It must run continuously while the device is in
> use, otherwise limits would not be enforced; the user sees it as an
> ongoing notification. No other foreground service type fits this
> parental-control use.

- Vidéo, si elle est demandée : la notification permanente du décompte
  pendant l'utilisation d'une appli limitée.

### Autres autorisations, si un examinateur pose la question

- REQUEST_IGNORE_BATTERY_OPTIMIZATIONS : la surveillance doit continuer en
  arrière-plan pour appliquer les limites ; l'optimisation de la batterie
  l'arrête. La demande se fait depuis l'écran des autorisations et peut être
  refusée.
- Administrateur de l'appareil : facultatif, sans aucune règle imposée ; il
  empêche seulement de désinstaller l'appli sans le parent. Il se désactive
  depuis le mode parent.
- PACKAGE_USAGE_STATS : statistiques d'utilisation et détection de l'appli
  au premier plan quand l'accessibilité ne suffit pas ; l'historique reste
  sur l'appareil.
- INTERNET, ACCESS_NETWORK_STATE, CHANGE_WIFI_MULTICAST_STATE : les
  appareils reliés, facultatifs, se trouvent sur le Wi-Fi de la maison
  (DNS-SD) et échangent réglages et usage directement, chiffrés de bout en
  bout, et avec le serveur relais configuré par le parent, s'il y en a un
  (celui de la famille, jamais celui du développeur). Un appareil relié à
  aucun autre n'utilise pas le réseau.

## 3. Fiche du Play Store

Développer votre audience › Présence sur le Play Store › **Fiche principale
du Play Store** (le menu peut aussi s'appeler « Fiche Play Store »). Les
textes en français, néerlandais et anglais sont dans `listing.md` ; les
visuels dans `graphics/` :

- Icône de l'application : `graphics/icon-512.png`
- Image de présentation : `graphics/feature-graphic-1024x500.png`
- Captures d'écran de téléphone : au moins 2 (à faire). Pour une tablette,
  les captures « Tablette 7 pouces » et « Tablette 10 pouces » sont
  facultatives mais aident l'appli à apparaître sur tablette.

Pour le néerlandais et l'anglais : **Gérer les traductions › Ajouter vos
propres traductions**, cocher nl-NL (ou nl-BE) et en-US, puis coller les
textes correspondants.

## 4. Importer une version en test interne

1. Tester et publier › Tests › **Tests internes** › **Créer une release**.
2. Signature d'application Play : accepter **Utiliser une clé générée par
   Google**. La clé de `familyscreentime-upload.jks` ne sert alors que de
   clé d'importation.
3. **Importer** le fichier `.aab` (par exemple
   `family-screen-time-0.16.0.aab`).
4. Nom de la release : la version (par exemple 0.16.0). Notes de version :
   une ligne en français, entre les balises `<fr-FR>` proposées.
5. Onglet **Testeurs** : **Créer une liste d'adresses e-mail** avec les
   comptes Google autorisés à installer (le tien, et celui de l'enfant pour
   essayer). Enregistrer.
6. **Suivant**, puis **Enregistrer et publier** (ou « Lancer le déploiement
   auprès des tests internes »).
7. Dans l'onglet **Testeurs**, **Copier le lien** sous « Rejoindre sur le
   Web ». L'ouvrir sur chaque appareil avec un compte testeur, accepter,
   puis installer depuis le lien Play Store proposé.

Chaque nouvel envoi demande un code de version plus élevé : c'est le nombre
après `+` dans `pubspec.yaml` (`version: 0.16.0+24`), que chaque version
augmente.

## 5. Sur la tablette de l'enfant

- Désinstaller d'abord toute version installée à la main : Play ne peut pas
  mettre à jour une appli signée avec une autre clé.
- À vérifier : si un compte supervisé peut rejoindre le test interne. Si
  oui, l'enfant installe depuis le lien et tu approuves dans Family Link
  comme pour toute appli. Sinon, un test fermé avec un groupe Google de
  testeurs sera peut-être nécessaire ; à voir une fois la console ouverte.

## 6. Plus tard : publication en production

Les comptes développeur personnels créés après le 13 novembre 2023 doivent
d'abord mener un **test fermé** avec au moins 12 testeurs inscrits pendant
14 jours d'affilée, avant de pouvoir **demander l'accès à la production**
(Tableau de bord › « Demander l'accès à la production »).
