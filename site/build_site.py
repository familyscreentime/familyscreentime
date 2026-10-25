import html, os
DATE = {'fr': '25 octobre 2026', 'nl': '25 oktober 2026', 'en': '25 October 2026'}
SERVER_ZIP = 'familyscreentime-server.zip'
CONTACT = 'contact@familyscreentime.org'
REPO = 'https://github.com/familyscreentime/familyscreentime'
PAGES = {
  'home': {'fr': 'index.html', 'nl': 'nl.html', 'en': 'en.html'},
  'privacy': {'fr': 'confidentialite.html', 'nl': 'privacybeleid.html', 'en': 'privacy.html'},
}

def page(kind, lang, title, body, desc):
    links = ''.join(
        f'<a href="{PAGES[kind][l]}" hreflang="{l}"{" aria-current=\"true\"" if l == lang else ""}>{l.upper()}</a>'
        for l in ('fr', 'nl', 'en'))
    alt = ''.join(f'<link rel="alternate" hreflang="{l}" href="https://familyscreentime.org/{PAGES[kind][l]}">' for l in ('fr','nl','en'))
    home = PAGES['home'][lang]
    privacy = PAGES['privacy'][lang]
    foot = {'fr': f'<a href="{privacy}">Règles de confidentialité</a> · <a href="{REPO}">Logiciel libre (licence MIT)</a> · {CONTACT}',
            'nl': f'<a href="{privacy}">Privacybeleid</a> · <a href="{REPO}">Vrije software (MIT-licentie)</a> · {CONTACT}',
            'en': f'<a href="{privacy}">Privacy policy</a> · <a href="{REPO}">Free software (MIT licence)</a> · {CONTACT}'}[lang]
    return f'''<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
{alt}
<link rel="icon" href="favicon.png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<link rel="stylesheet" href="style.css">
</head>
<body>
<header><div class="wrap">
<img src="icon.png" alt=""><a class="home" href="{home}">Family Screen Time</a>
<nav class="lang" aria-label="Language">{links}</nav>
</div></header>
<main class="wrap">
{body}
</main>
<footer class="wrap">{foot}</footer>
</body>
</html>
'''

HOME = {
'fr': ('Family Screen Time — le temps d\'écran en famille', 'Gestion du temps d\'écran pour les familles : limites, horaires, pauses, sans compte ni serveur obligatoire.', '''
<div class="hero"><img src="icon.png" alt=""><div>
<h1>Le temps d'écran, réglé en famille</h1>
<p class="muted">Pour Android aujourd'hui, Windows ensuite. Sans compte, sans publicité, et tout reste chez vous.</p>
</div></div>
<ul class="features">
<li>Temps par jour et par semaine, pour le temps total, un groupe d'applis (jeux, vidéo…) ou une appli.</li>
<li>Horaires jour par jour, pauses obligatoires, périodes particulières (vacances, examens…).</li>
<li>Temps de grâce, épargne du temps non utilisé, limite ferme après des dépassements répétés.</li>
<li>Actions rapides du parent : temps en plus, blocage, levée pour la journée, ouverture anticipée d'un horaire.</li>
<li>Décompte flottant façon Time Timer, avertissements, message clair quand le temps est écoulé.</li>
<li>L'enfant voit tout : son temps restant, ses règles, et il peut se fixer ses propres limites.</li>
<li>Écoute seule pour les applis de musique : une fois le temps des clips écoulé, l'appli s'ouvre juste le temps de choisir la musique, qui continue en arrière-plan.</li>
<li>Statistiques par appli et par appareil, analyse sur plusieurs mois, export en CSV ou pour ActivityWatch.</li>
<li>Écran partagé et vidéo en petite fenêtre pris en compte : chaque appli visible est comptée et fermée si son temps est écoulé.</li>
<li>Appareils reliés, si vous le souhaitez : la tablette et le téléphone d'un enfant partagent ses règles et son temps, et le parent règle tout depuis son propre téléphone. Chaque appareil d'enfant ne reçoit que ce qui concerne cet enfant. Directement entre vos appareils sur le Wi-Fi de la maison, et hors de la maison par un serveur que vous hébergez vous-même, toujours chiffré de bout en bout. Un appareil installé seul peut être relié plus tard, sans repartir de zéro.</li>
</ul>
<h2>Le serveur relais</h2>
<p>Facultatif, pour que les appareils reliés se synchronisent aussi hors de la maison. Un hébergement web ordinaire suffit (PHP 8.2 et MySQL, MariaDB ou SQLite), sans accès SSH. Il ne peut pas lire ce qu'il transmet. Un même serveur peut accueillir d'autres familles, sur invitation.</p>
<p><a class="button" href="'''+SERVER_ZIP+'''">Télécharger le serveur (zip)</a> · <a href="'''+REPO+'''/blob/main/server/INSTALL.fr.md">Guide d'installation</a></p>
<h2>À venir</h2>
<ul class="features">
<li>Une version Windows.</li>
</ul>
<p class="muted">Relier des appareils reste facultatif. Sans cela, rien ne quitte l'appareil ; avec, les données ne vont que sur vos appareils et, si vous en installez un, sur votre serveur, chiffrées.</p>
<p>Conçue et testée par Olivier Berten, l'application est écrite par Claude, une IA d'Anthropic. C'est un logiciel libre (licence MIT) : <a href="'''+REPO+'''">son code source est sur GitHub</a>. Elle est en phase de test.</p>
<p><a href="confidentialite.html">Règles de confidentialité</a></p>
'''),
'nl': ('Family Screen Time — schermtijd in het gezin', 'Schermtijdbeheer voor gezinnen: limieten, tijden, pauzes, zonder verplicht account of server.', '''
<div class="hero"><img src="icon.png" alt=""><div>
<h1>Schermtijd, samen geregeld</h1>
<p class="muted">Vandaag voor Android, daarna Windows. Zonder account, zonder reclame, en alles blijft bij u thuis.</p>
</div></div>
<ul class="features">
<li>Tijd per dag en per week, voor de totale schermtijd, een groep apps (spellen, video…) of één app.</li>
<li>Tijden per dag, verplichte pauzes, bijzondere periodes (vakantie, examens…).</li>
<li>Extra tijd, sparen van ongebruikte tijd, vaste limiet na herhaalde overschrijdingen.</li>
<li>Snelle acties voor de ouder: extra tijd, blokkeren, beperkingen opheffen voor de dag, tijden vroeger openen.</li>
<li>Zwevend aftellen in Time Timer-stijl, waarschuwingen, een duidelijke melding als de tijd om is.</li>
<li>Het kind ziet alles: de resterende tijd, de regels, en het kan zichzelf limieten geven.</li>
<li>Alleen luisteren voor muziekapps: als de tijd voor clips op is, gaat de app nog even open om muziek te kiezen, die op de achtergrond verder speelt.</li>
<li>Statistieken per app en per toestel, analyse over meerdere maanden, export als CSV of voor ActivityWatch.</li>
<li>Gesplitst scherm en video in een klein venster worden meegeteld: elke zichtbare app telt mee en wordt gesloten als haar tijd op is.</li>
<li>Gekoppelde toestellen, als u dat wilt: de tablet en de telefoon van een kind delen zijn regels en zijn tijd, en de ouder regelt alles vanaf de eigen telefoon. Elk toestel van een kind krijgt alleen wat dat kind aangaat. Rechtstreeks tussen uw toestellen via de wifi thuis, en buitenshuis via een server die u zelf host, altijd end-to-end versleuteld. Een toestel dat op zichzelf geïnstalleerd is, kan later gekoppeld worden, zonder opnieuw te beginnen.</li>
</ul>
<h2>De relayserver</h2>
<p>Optioneel, zodat gekoppelde toestellen ook buitenshuis synchroniseren. Gewone webhosting volstaat (PHP 8.2 en MySQL, MariaDB of SQLite), zonder SSH. Hij kan niet lezen wat hij doorgeeft. Eén server kan ook andere gezinnen ontvangen, op uitnodiging.</p>
<p><a class="button" href="'''+SERVER_ZIP+'''">De server downloaden (zip)</a> · <a href="'''+REPO+'''/blob/main/server/README.md">Installatiegids (Engels)</a></p>
<h2>Binnenkort</h2>
<ul class="features">
<li>Een Windows-versie.</li>
</ul>
<p class="muted">Toestellen koppelen blijft optioneel. Zonder koppeling verlaat niets het toestel; met koppeling gaan de gegevens alleen naar uw eigen toestellen en, als u er een installeert, naar uw eigen server, versleuteld.</p>
<p>De app is ontworpen en getest door Olivier Berten en geschreven door Claude, een AI van Anthropic. Het is vrije software (MIT-licentie): <a href="'''+REPO+'''">de broncode staat op GitHub</a>. Ze is in testfase.</p>
<p><a href="privacybeleid.html">Privacybeleid</a></p>
'''),
'en': ('Family Screen Time — screen time, as a family', 'Screen time management for families: limits, hours, breaks, with no account or server required.', '''
<div class="hero"><img src="icon.png" alt=""><div>
<h1>Screen time, sorted out as a family</h1>
<p class="muted">For Android today, Windows next. No account, no ads, and everything stays at home.</p>
</div></div>
<ul class="features">
<li>Time per day and per week, for total screen time, a group of apps (games, video…) or a single app.</li>
<li>Hours set day by day, mandatory breaks, special periods (holidays, exams…).</li>
<li>Grace time, saving unused time, a firm limit after repeated overruns.</li>
<li>Quick actions for the parent: extra time, blocking, lifting restrictions for the day, opening hours early.</li>
<li>A floating Time Timer-style countdown, warnings, a clear message when time is up.</li>
<li>The child sees everything: time left, the rules, and can set limits for themselves.</li>
<li>Listen only for music apps: once the time for clips is up, the app opens just long enough to pick the music, which keeps playing in the background.</li>
<li>Statistics per app and per device, analysis over several months, export as CSV or for ActivityWatch.</li>
<li>Split screen and video in a small window are taken into account: every app on screen counts, and closes when its time is up.</li>
<li>Linked devices, if you wish: a child's tablet and phone share their rules and time, and the parent sets everything from their own phone. Each child's device only receives what concerns that child. Directly between your devices over the home Wi-Fi, and away from home through a server you host yourself, always end-to-end encrypted. A device set up on its own can be linked later, without starting over.</li>
</ul>
<h2>The relay server</h2>
<p>Optional, so that linked devices also sync away from home. Ordinary web hosting is enough (PHP 8.2 and MySQL, MariaDB or SQLite), with no SSH. It cannot read what it passes on. One server can host other families too, by invitation.</p>
<p><a class="button" href="'''+SERVER_ZIP+'''">Download the server (zip)</a> · <a href="'''+REPO+'''/blob/main/server/README.md">Installation guide</a></p>
<h2>Coming next</h2>
<ul class="features">
<li>A Windows version.</li>
</ul>
<p class="muted">Linking devices stays optional. Without it, nothing leaves the device; with it, the data only goes to your own devices and, if you install one, to your own server, encrypted.</p>
<p>Designed and tested by Olivier Berten, the app is written by Claude, an AI by Anthropic. It is free software (MIT licence): <a href="'''+REPO+'''">its source code is on GitHub</a>. It is in testing.</p>
<p><a href="privacy.html">Privacy policy</a></p>
'''),
}

PRIV = {
'fr': ('Règles de confidentialité — Family Screen Time', '''
<h1>Règles de confidentialité</h1>
<p class="muted">Application Android Family Screen Time (org.familyscreentime). Dernière mise à jour : {date}.</p>
<div class="card"><p><strong>En bref :</strong> Family Screen Time ne collecte aucune donnée. Tout ce que l'application enregistre reste sur l'appareil où elle est installée. Rien n'est envoyé à l'éditeur ni à des tiers : pas de compte, pas de publicité, pas de statistiques d'audience, pas de service tiers. Si le parent relie plusieurs appareils, ils échangent ces données entre eux, chiffrées de bout en bout : directement sur le Wi-Fi de la maison, ou par un serveur relais que la famille héberge elle-même et qui ne peut pas les lire.</p></div>

<h2>Qui sommes-nous ?</h2>
<p>Family Screen Time est un logiciel libre (licence MIT) publié sur familyscreentime.org. Pour toute question : {contact}.</p>

<h2>Ce que l'application traite, sur vos appareils seulement</h2>
<table>
<tr><th>Donnée</th><th>Pourquoi</th></tr>
<tr><td>L'appli à l'écran et la durée de son utilisation</td><td>Compter le temps d'écran et appliquer les limites fixées par le parent.</td></tr>
<tr><td>L'historique d'utilisation des applis tenu par Android (environ 10 jours, à la première ouverture)</td><td>Afficher les statistiques d'utilisation dès le premier jour. Il ne sert pas aux limites.</td></tr>
<tr><td>Les règles, groupes d'applis de chaque enfant, noms donnés aux applis, périodes, bonus et blocages</td><td>Faire fonctionner l'application selon les réglages du parent.</td></tr>
<tr><td>Le prénom de l'enfant</td><td>L'afficher dans l'application.</td></tr>
<tr><td>Le code parent, enregistré sous forme d'empreinte (PBKDF2), jamais en clair ; la clé des appareils reliés, chiffrée par ce code (Argon2id)</td><td>Protéger les réglages, et signer les décisions du parent pour les autres appareils reliés.</td></tr>
<tr><td>Les limites que l'enfant se fixe et leur historique</td><td>Les appliquer, et montrer au parent comment elles sont tenues. L'enfant en est informé.</td></tr>
</table>
<p>Ces données sont stockées dans l'espace privé de l'application. L'utilisation des applis est gardée le temps que le parent choisit (un an par défaut, au moins 40 jours pour les règles) ; tout est effacé quand l'application est désinstallée.</p>

<h2>Appareils reliés</h2>
<p>C'est facultatif : un appareil installé seul ne communique avec aucun autre. Le parent peut relier des appareils (la tablette et le téléphone d'un enfant, le téléphone d'un parent, par exemple), en mode parent et en comparant un code affiché sur les deux écrans. Ils partagent alors les réglages, le temps utilisé, la liste des appareils reliés (nom, rôle, enfant) et, pour chaque appareil d'enfant, le nom et l'icône des applis installées, pour que le parent puisse les limiter depuis un autre appareil. Ces échanges se font directement entre les appareils, sur le réseau local de la maison : ils sont chiffrés de bout en bout, et chaque appareil vérifie que les décisions du parent sont signées par la clé des appareils reliés. Ils ne passent par aucun serveur de l'éditeur. Un appareil d'enfant ne reçoit que ce qui concerne toute la famille et son propre enfant ; les appareils des parents reçoivent tout. Un appareil détaché ou retiré n'est plus synchronisé ; un appareil détaché ne garde que les données de son enfant et le temps utilisé sur lui.</p>

<h2>Serveur relais (facultatif)</h2>
<p>Pour que les appareils reliés se synchronisent aussi hors de la maison, le parent peut configurer un serveur relais : un logiciel que la famille installe sur son propre hébergement web, ou qu'une personne de confiance met à sa disposition sur invitation. L'éditeur n'en exploite aucun. Chaque donnée y est chiffrée sur les appareils avant l'envoi (XChaCha20-Poly1305), avec une clé que seuls les appareils reliés connaissent : ni le serveur ni son administrateur ne peuvent la lire. Le serveur voit seulement des identifiants aléatoires d'appareils, leurs clés publiques, ce que chacun reçoit (sous forme d'identifiants d'enfants, sans prénom), des numéros, des heures et la taille des données. Il efface l'utilisation des applis après 47 jours ; le reste est gardé tant que la famille l'utilise. Son administrateur peut supprimer une famille et toutes ses données ; la famille peut cesser de l'utiliser à tout moment.</p>

<h2>Export</h2>
<p>Le parent peut exporter l'utilisation des applis (enfant, appareil, appli, heures), en CSV ou pour le logiciel ActivityWatch. Le fichier est remis au menu de partage d'Android : c'est le parent qui choisit où il va (Drive, e-mail…), et ce qu'il en advient relève alors de l'application choisie.</p>

<h2>Le service d'accessibilité</h2>
<p>L'application utilise le service d'accessibilité d'Android pour savoir quelle appli est à l'écran, pour fermer une appli bloquée et pour afficher les avertissements, le décompte et l'écran de verrouillage par-dessus les autres applis. Quand le parent active la protection contre la désinstallation, elle ferme aussi les pages des réglages qui permettraient de désactiver l'application. Pour les reconnaître, elle lit le contenu de l'écran uniquement sur les pages de sécurité et d'autorisations d'Android, sans rien enregistrer. Elle liste aussi les fenêtres d'applis visibles, en ne lisant que leur nom, pour compter les applis affichées côte à côte et fermer la petite fenêtre vidéo d'une appli bloquée. L'utilisateur est informé et donne son accord avant l'activation de ce service.</p>

<h2>Autorisations</h2>
<ul>
<li><b>Accessibilité</b> : voir ci-dessus.</li>
<li><b>Accès aux données d'utilisation</b> : historique d'utilisation, repérage de l'appli à l'écran si l'accessibilité est coupée.</li>
<li><b>Affichage par-dessus les autres applis</b> : écran de blocage, décompte.</li>
<li><b>Notifications</b> : décompte, avertissements, mode parent.</li>
<li><b>Réseau</b> (Internet, état du réseau, multidiffusion Wi-Fi) : trouver les appareils reliés sur le réseau de la maison et échanger avec eux, et avec le serveur relais si le parent en a configuré un.</li>
<li><b>Administrateur de l'appareil</b> (facultatif) : empêcher la désinstallation sans le parent. Aucune autre règle d'administration n'est utilisée.</li>
<li><b>Démarrage, service au premier plan, exclusion de l'optimisation de batterie</b> : garder le suivi actif.</li>
</ul>

<h2>Partage</h2>
<p>Aucune donnée n'est partagée avec l'éditeur ni avec des tiers, vendue ni transmise, en dehors des appareils que le parent a reliés, du serveur relais qu'il a choisi (qui ne peut pas les lire) et des exports qu'il envoie lui-même. L'application ne contient aucun outil de suivi.</p>

<h2>Enfants</h2>
<p>L'application est conçue pour être installée par un parent sur l'appareil de son enfant. Elle ne collecte aucune donnée personnelle sur l'enfant pour l'éditeur. L'enfant voit ses règles, son temps restant, et sait que le parent voit l'historique de ses propres limites.</p>

<h2>Évolutions</h2>
<p>Ces règles seront mises à jour avant toute version qui changerait les données envoyées hors de l'appareil, ou leur destination.</p>

<h2>Vos droits</h2>
<p>L'éditeur ne détient aucune donnée vous concernant. Vous pouvez effacer toutes les données en désinstallant l'application ou en vidant ses données dans les réglages d'Android ; sur un serveur relais, en demandant à son administrateur de supprimer votre famille (ou en le faisant vous-même si c'est le vôtre). Pour toute question : {contact}.</p>
'''),
'nl': ('Privacybeleid — Family Screen Time', '''
<h1>Privacybeleid</h1>
<p class="muted">Android-app Family Screen Time (org.familyscreentime). Laatst bijgewerkt: {date}.</p>
<div class="card"><p><strong>Kort:</strong> Family Screen Time verzamelt geen gegevens. Alles wat de app bijhoudt, blijft op het toestel waarop ze geïnstalleerd is. Er wordt niets naar de uitgever of naar derden gestuurd: geen account, geen reclame, geen bezoekersstatistieken, geen diensten van derden. Als de ouder meerdere toestellen koppelt, wisselen die deze gegevens onderling uit, end-to-end versleuteld: rechtstreeks via de wifi thuis, of via een relayserver die het gezin zelf host en die ze niet kan lezen.</p></div>

<h2>Wie zijn we?</h2>
<p>Family Screen Time is vrije software (MIT-licentie), gepubliceerd op familyscreentime.org. Vragen: {contact}.</p>

<h2>Wat de app verwerkt, alleen op uw toestellen</h2>
<table>
<tr><th>Gegeven</th><th>Waarom</th></tr>
<tr><td>De app op het scherm en hoe lang ze gebruikt wordt</td><td>De schermtijd tellen en de limieten van de ouder toepassen.</td></tr>
<tr><td>De gebruiksgeschiedenis van apps die Android bijhoudt (ongeveer 10 dagen, bij de eerste opening)</td><td>Vanaf de eerste dag gebruiksstatistieken tonen. Ze wordt niet voor de limieten gebruikt.</td></tr>
<tr><td>De regels, app-groepen van elk kind, namen van apps, periodes, extra tijd en blokkeringen</td><td>De app laten werken volgens de instellingen van de ouder.</td></tr>
<tr><td>De voornaam van het kind</td><td>Die in de app tonen.</td></tr>
<tr><td>De oudercode, bewaard als vingerafdruk (PBKDF2), nooit leesbaar; de sleutel van de gekoppelde toestellen, versleuteld met die code (Argon2id)</td><td>De instellingen beveiligen, en de beslissingen van de ouder ondertekenen voor de andere gekoppelde toestellen.</td></tr>
<tr><td>De limieten die het kind zichzelf geeft en hun geschiedenis</td><td>Ze toepassen en de ouder tonen hoe ze worden volgehouden. Het kind weet dat.</td></tr>
</table>
<p>Deze gegevens staan in de privéruimte van de app. Het appgebruik wordt bewaard zolang de ouder kiest (standaard een jaar, minstens 40 dagen voor de regels); alles wordt gewist als de app verwijderd wordt.</p>

<h2>Gekoppelde toestellen</h2>
<p>Dit is optioneel: een toestel dat op zichzelf geïnstalleerd is, communiceert met geen enkel ander toestel. De ouder kan toestellen koppelen (de tablet en de telefoon van een kind, de telefoon van een ouder, bijvoorbeeld), in de oudermodus en door een code te vergelijken die op beide schermen verschijnt. Ze delen dan de instellingen, de gebruikte tijd, de lijst van gekoppelde toestellen (naam, rol, kind) en, voor elk toestel van een kind, de naam en het pictogram van de geïnstalleerde apps, zodat de ouder ze vanaf een ander toestel kan beperken. Dat gebeurt rechtstreeks tussen de toestellen, op het lokale netwerk thuis: end-to-end versleuteld, en elk toestel controleert dat de beslissingen van de ouder ondertekend zijn met de sleutel van de gekoppelde toestellen. Er komt geen server van de uitgever aan te pas. Een toestel van een kind krijgt alleen wat het hele gezin en zijn eigen kind aangaat; de toestellen van de ouders krijgen alles. Een losgekoppeld of verwijderd toestel wordt niet meer gesynchroniseerd; een losgekoppeld toestel houdt alleen de gegevens van zijn kind en de tijd die erop gebruikt is.</p>

<h2>Relayserver (optioneel)</h2>
<p>Om gekoppelde toestellen ook buitenshuis te laten synchroniseren, kan de ouder een relayserver instellen: software die het gezin op zijn eigen webhosting installeert, of die iemand die het vertrouwt op uitnodiging ter beschikking stelt. De uitgever beheert er geen. Elk gegeven wordt op de toestellen versleuteld voor het verstuurd wordt (XChaCha20-Poly1305), met een sleutel die alleen de gekoppelde toestellen kennen: de server en zijn beheerder kunnen het niet lezen. De server ziet alleen willekeurige toestel-id's, hun publieke sleutels, wat elk toestel ontvangt (als id's van kinderen, zonder voornaam), nummers, tijdstippen en de grootte van de gegevens. Hij wist het appgebruik na 47 dagen; de rest blijft bewaard zolang het gezin hem gebruikt. De beheerder kan een gezin en al zijn gegevens verwijderen; het gezin kan op elk moment stoppen met de server.</p>

<h2>Export</h2>
<p>De ouder kan het appgebruik exporteren (kind, toestel, app, tijdstippen), als CSV of voor de software ActivityWatch. Het bestand gaat naar het deelmenu van Android: de ouder kiest zelf waarheen (Drive, e-mail…), en wat er daarna mee gebeurt, hangt af van de gekozen app.</p>

<h2>De toegankelijkheidsdienst</h2>
<p>De app gebruikt de toegankelijkheidsdienst van Android om te weten welke app op het scherm staat, om een geblokkeerde app te sluiten en om waarschuwingen, het aftellen en het vergrendelscherm boven andere apps te tonen. Als de ouder de beveiliging tegen verwijderen inschakelt, sluit ze ook de instellingenpagina's waarmee de app uitgeschakeld kan worden. Om die te herkennen, leest ze de scherminhoud alleen op de beveiligings- en toestemmingspagina's van Android, zonder iets te bewaren. Ze somt ook de zichtbare appvensters op, waarvan ze alleen de naam leest, om apps naast elkaar mee te tellen en het kleine videovenster van een geblokkeerde app te sluiten. De gebruiker wordt ingelicht en geeft toestemming voor deze dienst wordt ingeschakeld.</p>

<h2>Toestemmingen</h2>
<ul>
<li><b>Toegankelijkheid</b>: zie hierboven.</li>
<li><b>Toegang tot gebruiksgegevens</b>: gebruiksgeschiedenis, de app op het scherm herkennen als toegankelijkheid uit staat.</li>
<li><b>Weergeven boven andere apps</b>: blokkeerscherm, aftellen.</li>
<li><b>Meldingen</b>: aftellen, waarschuwingen, oudermodus.</li>
<li><b>Netwerk</b> (internet, netwerkstatus, wifi-multicast): de gekoppelde toestellen vinden op het netwerk thuis en ermee uitwisselen, en met de relayserver als de ouder er een heeft ingesteld.</li>
<li><b>Apparaatbeheerder</b> (optioneel): verwijderen zonder de ouder voorkomen. Er wordt geen ander beheerbeleid gebruikt.</li>
<li><b>Opstarten, voorgronddienst, uitzondering op batterijoptimalisatie</b>: de opvolging actief houden.</li>
</ul>

<h2>Delen</h2>
<p>Er worden geen gegevens gedeeld met de uitgever of met derden, verkocht of doorgegeven, behalve tussen de toestellen die de ouder heeft gekoppeld, met de relayserver die hij koos (die ze niet kan lezen) en via exports die hij zelf verstuurt. De app bevat geen volgsoftware.</p>

<h2>Kinderen</h2>
<p>De app is gemaakt om door een ouder op het toestel van het kind geïnstalleerd te worden. Ze verzamelt geen persoonsgegevens over het kind voor de uitgever. Het kind ziet zijn regels en resterende tijd, en weet dat de ouder de geschiedenis van zijn eigen limieten ziet.</p>

<h2>Wijzigingen</h2>
<p>Dit beleid wordt bijgewerkt vóór elke versie die zou veranderen welke gegevens het toestel verlaten, of waarheen.</p>

<h2>Uw rechten</h2>
<p>De uitgever heeft geen gegevens over u. U kunt alle gegevens wissen door de app te verwijderen of haar gegevens te wissen in de Android-instellingen; op een relayserver door de beheerder te vragen uw gezin te verwijderen (of door het zelf te doen als het uw server is). Vragen: {contact}.</p>
'''),
'en': ('Privacy policy — Family Screen Time', '''
<h1>Privacy policy</h1>
<p class="muted">Family Screen Time Android app (org.familyscreentime). Last updated: {date}.</p>
<div class="card"><p><strong>In short:</strong> Family Screen Time collects no data. Everything the app records stays on the device it is installed on. Nothing is sent to the publisher or to third parties: no account, no ads, no analytics, no third-party services. If the parent links several devices, they exchange this data with each other, end-to-end encrypted: directly over the home Wi-Fi, or through a relay server the family hosts itself, which cannot read it.</p></div>

<h2>Who we are</h2>
<p>Family Screen Time is free software (MIT licence) published at familyscreentime.org. Questions: {contact}.</p>

<h2>What the app processes, on your devices only</h2>
<table>
<tr><th>Data</th><th>Why</th></tr>
<tr><td>The app on screen and how long it is used</td><td>To count screen time and apply the limits the parent set.</td></tr>
<tr><td>The app usage history Android keeps (about 10 days, on first launch)</td><td>To show usage statistics from the first day. It is not used for limits.</td></tr>
<tr><td>Rules, each child's app groups, names given to apps, periods, extra time and blocks</td><td>To run the app as the parent set it up.</td></tr>
<tr><td>The child's first name</td><td>To show it in the app.</td></tr>
<tr><td>The parent code, stored as a hash (PBKDF2), never in clear; the linked devices' key, encrypted with that code (Argon2id)</td><td>To protect the settings, and to sign the parent's decisions for the other linked devices.</td></tr>
<tr><td>The limits the child sets for themselves and their history</td><td>To apply them, and show the parent how they are kept. The child is told.</td></tr>
</table>
<p>This data is stored in the app's private storage. The use of apps is kept as long as the parent chooses (a year by default, at least 40 days for the rules); everything is erased when the app is uninstalled.</p>

<h2>Linked devices</h2>
<p>This is optional: a device set up on its own talks to no other device. The parent can link devices (a child's tablet and phone, a parent's phone, for example), in parent mode and by comparing a code shown on both screens. They then share the settings, the time used, the list of linked devices (name, role, child) and, for each child's device, the names and icons of the apps installed, so the parent can limit them from another device. This happens directly between the devices, on the home's local network: end-to-end encrypted, and each device checks that the parent's decisions are signed with the linked devices' key. No server of the publisher is involved. A child's device only receives what concerns the whole family and its own child; the parents' devices receive everything. A device unlinked or removed is no longer synced; an unlinked device keeps only its child's data and the time used on it.</p>

<h2>Relay server (optional)</h2>
<p>So that linked devices also sync away from home, the parent can set up a relay server: software the family installs on its own web hosting, or that someone it trusts makes available by invitation. The publisher runs none. Every piece of data is encrypted on the devices before it is sent (XChaCha20-Poly1305), with a key only the linked devices know: neither the server nor its administrator can read it. The server only sees random device ids, their public keys, what each device receives (as children's ids, with no first names), numbers, times and the size of the data. It deletes the use of apps after 47 days; the rest is kept while the family uses it. Its administrator can delete a family and all its data; the family can stop using it at any time.</p>

<h2>Export</h2>
<p>The parent can export the use of apps (child, device, app, times), as CSV or for the ActivityWatch software. The file is handed to Android's share menu: the parent chooses where it goes (Drive, email…), and what then becomes of it is up to the app chosen.</p>

<h2>The accessibility service</h2>
<p>The app uses Android's accessibility service to know which app is on screen, to close a blocked app, and to show warnings, the countdown and the lock screen over other apps. When the parent turns on uninstall protection, it also closes the settings pages that would switch the app off. To recognise them, it reads screen content only on Android's security and permission pages, and stores nothing. It also lists the app windows on screen, reading only their names, to count apps shown side by side and to close the small video window of a blocked app. The user is informed and agrees before this service is turned on.</p>

<h2>Permissions</h2>
<ul>
<li><b>Accessibility</b>: see above.</li>
<li><b>Usage access</b>: usage history; knowing the app on screen when accessibility is off.</li>
<li><b>Display over other apps</b>: block screen, countdown.</li>
<li><b>Notifications</b>: countdown, warnings, parent mode.</li>
<li><b>Network</b> (internet, network state, Wi-Fi multicast): find the linked devices on the home network and exchange with them, and with the relay server if the parent set one up.</li>
<li><b>Device administrator</b> (optional): preventing uninstallation without the parent. No other administration policy is used.</li>
<li><b>Start at boot, foreground service, exemption from battery optimisation</b>: keeping monitoring running.</li>
</ul>

<h2>Sharing</h2>
<p>No data is shared with the publisher or third parties, sold or transferred, except between the devices the parent has linked, with the relay server they chose (which cannot read it), and in exports they send themselves. The app contains no tracking tools.</p>

<h2>Children</h2>
<p>The app is designed to be installed by a parent on their child's device. It collects no personal data about the child for the publisher. The child sees their rules and time left, and knows that the parent sees the history of their own limits.</p>

<h2>Changes</h2>
<p>This policy will be updated before any version that would change what data leaves the device, or where it goes.</p>

<h2>Your rights</h2>
<p>The publisher holds no data about you. You can erase all data by uninstalling the app or clearing its data in Android's settings; on a relay server, by asking its administrator to delete your family (or doing it yourself if it is yours). Questions: {contact}.</p>
'''),
}

out = os.getcwd()
for lang, (title, desc, body) in HOME.items():
    open(os.path.join(out, PAGES['home'][lang]), 'w').write(page('home', lang, title, body, desc))
for lang, (title, body) in PRIV.items():
    b = body.replace('{date}', DATE[lang]).replace('{contact}', f'<a href="mailto:{CONTACT}">{CONTACT}</a>')
    open(os.path.join(out, PAGES['privacy'][lang]), 'w').write(page('privacy', lang, title, b, title))
print('ok')
