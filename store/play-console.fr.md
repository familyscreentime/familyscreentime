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
appareils que le parent a reliés, sur le Wi-Fi de la maison, chiffré de
bout en bout, sans aucun serveur de l'éditeur :

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
(X25519, ChaCha20-Poly1305) connues d'eux seuls, sans serveur ni relais.

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

À revoir avec le serveur auto-hébergé : il restera hors exemption s'il
peut lire les données ; il faudra donc qu'il ne stocke que des événements
chiffrés de bout en bout.

### Déclaration relative à l'API d'accessibilité

- Votre application est-elle un outil d'accessibilité
  (isAccessibilityTool) ? **Non.**
- Description de l'utilisation, à coller :

> Family Screen Time is a parental control app. Its accessibility service
> detects which app is in the foreground (package and activity names of
> window changes), so that screen time is counted and the limits set by the
> parent are applied; it sends the user to the home screen when an app is
> blocked; and it shows the countdown, warnings, block notices and the
> optional device lock as accessibility overlays, which stay visible over
> full-screen apps. When the parent turns on uninstall protection, the
> service also closes the Android settings pages that would switch the app
> off (device administrator deactivation, the app's own settings pages,
> Android's security page offering to remove its access). For this, screen
> content is read only on Android's security and permission pages. No data
> is stored beyond usage times, which stay on the device, or go only to the
> user's other devices the parent linked (over the home Wi-Fi, end-to-end
> encrypted, never to the developer or third parties). Before the
> service is turned on, an in-app disclosure explains this and asks for
> consent. The source code is public: https://github.com/familyscreentime/familyscreentime

- Vidéo : Google peut demander une courte vidéo (un lien, par exemple
  YouTube en « non répertoriée »). Montrer : le premier lancement, l'écran
  des autorisations, la fenêtre d'information avec « Accepter et activer »,
  l'activation du service dans les paramètres Android, puis une appli
  limitée qui se ferme avec son message.

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
  bout. Aucun serveur n'est contacté ; un appareil relié à aucun autre
  n'utilise pas le réseau.

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
