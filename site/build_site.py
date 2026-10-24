import html, os
DATE = {'fr': '23 octobre 2026', 'nl': '23 oktober 2026', 'en': '23 October 2026'}
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
<li>Appareils reliés, si vous le souhaitez : la tablette et le téléphone d'un enfant partagent ses règles et son temps, et le parent règle tout depuis son propre téléphone. Directement entre vos appareils, sur le Wi-Fi de la maison, chiffré de bout en bout. Un appareil installé seul peut être relié plus tard, sans repartir de zéro.</li>
</ul>
<h2>À venir</h2>
<ul class="features">
<li>La synchronisation par un serveur que vous hébergez vous-même (PHP et MySQL, un hébergement ordinaire suffit), pour les appareils qui ne sont pas à la maison.</li>
<li>Une version Windows, ensuite.</li>
</ul>
<p class="muted">Relier des appareils reste facultatif. Sans cela, rien ne quitte l'appareil ; avec, les données ne vont que sur vos appareils, et plus tard sur votre serveur.</p>
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
<li>Gekoppelde toestellen, als u dat wilt: de tablet en de telefoon van een kind delen zijn regels en zijn tijd, en de ouder regelt alles vanaf de eigen telefoon. Rechtstreeks tussen uw toestellen, via de wifi thuis, end-to-end versleuteld. Een toestel dat op zichzelf geïnstalleerd is, kan later gekoppeld worden, zonder opnieuw te beginnen.</li>
</ul>
<h2>Binnenkort</h2>
<ul class="features">
<li>Synchronisatie via een server die u zelf host (PHP en MySQL, gewone webhosting volstaat), voor toestellen die niet thuis zijn.</li>
<li>Daarna een Windows-versie.</li>
</ul>
<p class="muted">Toestellen koppelen blijft optioneel. Zonder koppeling verlaat niets het toestel; met koppeling gaan de gegevens alleen naar uw eigen toestellen, en later naar uw eigen server.</p>
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
<li>Linked devices, if you wish: a child's tablet and phone share their rules and time, and the parent sets everything from their own phone. Directly between your devices, over the home Wi-Fi, end-to-end encrypted. A device set up on its own can be linked later, without starting over.</li>
</ul>
<h2>Coming next</h2>
<ul class="features">
<li>Syncing through a server you host yourself (PHP and MySQL, ordinary web hosting is enough), for devices away from home.</li>
<li>A Windows version, after that.</li>
</ul>
<p class="muted">Linking devices stays optional. Without it, nothing leaves the device; with it, the data only goes to your own devices, and later to your own server.</p>
<p>Designed and tested by Olivier Berten, the app is written by Claude, an AI by Anthropic. It is free software (MIT licence): <a href="'''+REPO+'''">its source code is on GitHub</a>. It is in testing.</p>
<p><a href="privacy.html">Privacy policy</a></p>
'''),
}

PRIV = {
'fr': ('Règles de confidentialité — Family Screen Time', '''
<h1>Règles de confidentialité</h1>
<p class="muted">Application Android Family Screen Time (org.familyscreentime). Dernière mise à jour : {date}.</p>
<div class="card"><p><strong>En bref :</strong> Family Screen Time ne collecte aucune donnée. Tout ce que l'application enregistre reste sur l'appareil où elle est installée. Rien n'est envoyé à l'éditeur ni à des tiers : pas de compte, pas de publicité, pas de statistiques d'audience, pas de service tiers. Si le parent relie plusieurs appareils, ils échangent ces données entre eux, directement sur le réseau Wi-Fi de la maison, chiffrées de bout en bout.</p></div>

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
<p>Ces données sont stockées dans l'espace privé de l'application. Elles sont effacées quand l'application est désinstallée.</p>

<h2>Appareils reliés</h2>
<p>C'est facultatif : un appareil installé seul ne communique avec aucun autre. Le parent peut relier des appareils (la tablette et le téléphone d'un enfant, le téléphone d'un parent, par exemple), en mode parent et en comparant un code affiché sur les deux écrans. Ils partagent alors les réglages, le temps utilisé, la liste des appareils reliés (nom, rôle, enfant) et, pour chaque appareil d'enfant, le nom et l'icône des applis installées, pour que le parent puisse les limiter depuis un autre appareil. Ces échanges se font directement entre les appareils, sur le réseau local de la maison : ils sont chiffrés de bout en bout, et chaque appareil vérifie que les décisions du parent sont signées par la clé des appareils reliés. Ils ne passent par aucun serveur de l'éditeur. Un appareil détaché ou retiré n'est plus synchronisé ; un appareil détaché ne garde que les données de son enfant et le temps utilisé sur lui.</p>

<h2>Le service d'accessibilité</h2>
<p>L'application utilise le service d'accessibilité d'Android pour savoir quelle appli est à l'écran, pour fermer une appli bloquée et pour afficher les avertissements, le décompte et l'écran de verrouillage par-dessus les autres applis. Quand le parent active la protection contre la désinstallation, elle ferme aussi les pages des réglages qui permettraient de désactiver l'application. Pour les reconnaître, elle lit le contenu de l'écran uniquement sur les pages de sécurité et d'autorisations d'Android, sans rien enregistrer. L'utilisateur est informé et donne son accord avant l'activation de ce service.</p>

<h2>Autorisations</h2>
<ul>
<li><b>Accessibilité</b> : voir ci-dessus.</li>
<li><b>Accès aux données d'utilisation</b> : historique d'utilisation, repérage de l'appli à l'écran si l'accessibilité est coupée.</li>
<li><b>Affichage par-dessus les autres applis</b> : écran de blocage, décompte.</li>
<li><b>Notifications</b> : décompte, avertissements, mode parent.</li>
<li><b>Réseau</b> (Internet, état du réseau, multidiffusion Wi-Fi) : trouver les appareils reliés sur le réseau de la maison et échanger avec eux.</li>
<li><b>Administrateur de l'appareil</b> (facultatif) : empêcher la désinstallation sans le parent. Aucune autre règle d'administration n'est utilisée.</li>
<li><b>Démarrage, service au premier plan, exclusion de l'optimisation de batterie</b> : garder le suivi actif.</li>
</ul>

<h2>Partage</h2>
<p>Aucune donnée n'est partagée avec l'éditeur ni avec des tiers, vendue ni transmise, en dehors des appareils que le parent a reliés. L'application ne contient aucun outil de suivi.</p>

<h2>Enfants</h2>
<p>L'application est conçue pour être installée par un parent sur l'appareil de son enfant. Elle ne collecte aucune donnée personnelle sur l'enfant pour l'éditeur. L'enfant voit ses règles, son temps restant, et sait que le parent voit l'historique de ses propres limites.</p>

<h2>Évolutions</h2>
<p>Une version future pourra aussi synchroniser les appareils reliés par un serveur que la famille héberge elle-même. Ces règles seront mises à jour avant toute version qui enverra des données ailleurs que sur les appareils reliés.</p>

<h2>Vos droits</h2>
<p>Comme aucune donnée ne quitte vos appareils, l'éditeur ne détient aucune donnée vous concernant. Vous pouvez effacer toutes les données en désinstallant l'application ou en vidant ses données dans les réglages d'Android. Pour toute question : {contact}.</p>
'''),
'nl': ('Privacybeleid — Family Screen Time', '''
<h1>Privacybeleid</h1>
<p class="muted">Android-app Family Screen Time (org.familyscreentime). Laatst bijgewerkt: {date}.</p>
<div class="card"><p><strong>Kort:</strong> Family Screen Time verzamelt geen gegevens. Alles wat de app bijhoudt, blijft op het toestel waarop ze geïnstalleerd is. Er wordt niets naar de uitgever of naar derden gestuurd: geen account, geen reclame, geen bezoekersstatistieken, geen diensten van derden. Als de ouder meerdere toestellen koppelt, wisselen die deze gegevens onderling uit, rechtstreeks over het wifinetwerk thuis, end-to-end versleuteld.</p></div>

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
<p>Deze gegevens staan in de privéruimte van de app. Ze worden gewist als de app verwijderd wordt.</p>

<h2>Gekoppelde toestellen</h2>
<p>Dit is optioneel: een toestel dat op zichzelf geïnstalleerd is, communiceert met geen enkel ander toestel. De ouder kan toestellen koppelen (de tablet en de telefoon van een kind, de telefoon van een ouder, bijvoorbeeld), in de oudermodus en door een code te vergelijken die op beide schermen verschijnt. Ze delen dan de instellingen, de gebruikte tijd, de lijst van gekoppelde toestellen (naam, rol, kind) en, voor elk toestel van een kind, de naam en het pictogram van de geïnstalleerde apps, zodat de ouder ze vanaf een ander toestel kan beperken. Dat gebeurt rechtstreeks tussen de toestellen, op het lokale netwerk thuis: end-to-end versleuteld, en elk toestel controleert dat de beslissingen van de ouder ondertekend zijn met de sleutel van de gekoppelde toestellen. Er komt geen server van de uitgever aan te pas. Een losgekoppeld of verwijderd toestel wordt niet meer gesynchroniseerd; een losgekoppeld toestel houdt alleen de gegevens van zijn kind en de tijd die erop gebruikt is.</p>

<h2>De toegankelijkheidsdienst</h2>
<p>De app gebruikt de toegankelijkheidsdienst van Android om te weten welke app op het scherm staat, om een geblokkeerde app te sluiten en om waarschuwingen, het aftellen en het vergrendelscherm boven andere apps te tonen. Als de ouder de beveiliging tegen verwijderen inschakelt, sluit ze ook de instellingenpagina's waarmee de app uitgeschakeld kan worden. Om die te herkennen, leest ze de scherminhoud alleen op de beveiligings- en toestemmingspagina's van Android, zonder iets te bewaren. De gebruiker wordt ingelicht en geeft toestemming voor deze dienst wordt ingeschakeld.</p>

<h2>Toestemmingen</h2>
<ul>
<li><b>Toegankelijkheid</b>: zie hierboven.</li>
<li><b>Toegang tot gebruiksgegevens</b>: gebruiksgeschiedenis, de app op het scherm herkennen als toegankelijkheid uit staat.</li>
<li><b>Weergeven boven andere apps</b>: blokkeerscherm, aftellen.</li>
<li><b>Meldingen</b>: aftellen, waarschuwingen, oudermodus.</li>
<li><b>Netwerk</b> (internet, netwerkstatus, wifi-multicast): de gekoppelde toestellen vinden op het netwerk thuis en ermee uitwisselen.</li>
<li><b>Apparaatbeheerder</b> (optioneel): verwijderen zonder de ouder voorkomen. Er wordt geen ander beheerbeleid gebruikt.</li>
<li><b>Opstarten, voorgronddienst, uitzondering op batterijoptimalisatie</b>: de opvolging actief houden.</li>
</ul>

<h2>Delen</h2>
<p>Er worden geen gegevens gedeeld met de uitgever of met derden, verkocht of doorgegeven, behalve tussen de toestellen die de ouder heeft gekoppeld. De app bevat geen volgsoftware.</p>

<h2>Kinderen</h2>
<p>De app is gemaakt om door een ouder op het toestel van het kind geïnstalleerd te worden. Ze verzamelt geen persoonsgegevens over het kind voor de uitgever. Het kind ziet zijn regels en resterende tijd, en weet dat de ouder de geschiedenis van zijn eigen limieten ziet.</p>

<h2>Wijzigingen</h2>
<p>Een toekomstige versie kan de gekoppelde toestellen ook synchroniseren via een server die het gezin zelf host. Dit beleid wordt bijgewerkt vóór elke versie die gegevens ergens anders heen stuurt dan naar de gekoppelde toestellen.</p>

<h2>Uw rechten</h2>
<p>Omdat geen enkel gegeven uw toestellen verlaat, heeft de uitgever geen gegevens over u. U kunt alle gegevens wissen door de app te verwijderen of haar gegevens te wissen in de Android-instellingen. Vragen: {contact}.</p>
'''),
'en': ('Privacy policy — Family Screen Time', '''
<h1>Privacy policy</h1>
<p class="muted">Family Screen Time Android app (org.familyscreentime). Last updated: {date}.</p>
<div class="card"><p><strong>In short:</strong> Family Screen Time collects no data. Everything the app records stays on the device it is installed on. Nothing is sent to the publisher or to third parties: no account, no ads, no analytics, no third-party services. If the parent links several devices, they exchange this data with each other, directly over the home Wi-Fi network, end-to-end encrypted.</p></div>

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
<p>This data is stored in the app's private storage and erased when the app is uninstalled.</p>

<h2>Linked devices</h2>
<p>This is optional: a device set up on its own talks to no other device. The parent can link devices (a child's tablet and phone, a parent's phone, for example), in parent mode and by comparing a code shown on both screens. They then share the settings, the time used, the list of linked devices (name, role, child) and, for each child's device, the names and icons of the apps installed, so the parent can limit them from another device. This happens directly between the devices, on the home's local network: end-to-end encrypted, and each device checks that the parent's decisions are signed with the linked devices' key. No server of the publisher is involved. A device unlinked or removed is no longer synced; an unlinked device keeps only its child's data and the time used on it.</p>

<h2>The accessibility service</h2>
<p>The app uses Android's accessibility service to know which app is on screen, to close a blocked app, and to show warnings, the countdown and the lock screen over other apps. When the parent turns on uninstall protection, it also closes the settings pages that would switch the app off. To recognise them, it reads screen content only on Android's security and permission pages, and stores nothing. The user is informed and agrees before this service is turned on.</p>

<h2>Permissions</h2>
<ul>
<li><b>Accessibility</b>: see above.</li>
<li><b>Usage access</b>: usage history; knowing the app on screen when accessibility is off.</li>
<li><b>Display over other apps</b>: block screen, countdown.</li>
<li><b>Notifications</b>: countdown, warnings, parent mode.</li>
<li><b>Network</b> (internet, network state, Wi-Fi multicast): find the linked devices on the home network and exchange with them.</li>
<li><b>Device administrator</b> (optional): preventing uninstallation without the parent. No other administration policy is used.</li>
<li><b>Start at boot, foreground service, exemption from battery optimisation</b>: keeping monitoring running.</li>
</ul>

<h2>Sharing</h2>
<p>No data is shared with the publisher or third parties, sold or transferred, except between the devices the parent has linked. The app contains no tracking tools.</p>

<h2>Children</h2>
<p>The app is designed to be installed by a parent on their child's device. It collects no personal data about the child for the publisher. The child sees their rules and time left, and knows that the parent sees the history of their own limits.</p>

<h2>Changes</h2>
<p>A future version may also sync linked devices through a server the family hosts itself. This policy will be updated before any version that sends data anywhere other than the linked devices.</p>

<h2>Your rights</h2>
<p>As no data leaves your devices, the publisher holds no data about you. You can erase all data by uninstalling the app or clearing its data in Android's settings. Questions: {contact}.</p>
'''),
}

out = os.getcwd()
for lang, (title, desc, body) in HOME.items():
    open(os.path.join(out, PAGES['home'][lang]), 'w').write(page('home', lang, title, body, desc))
for lang, (title, body) in PRIV.items():
    b = body.replace('{date}', DATE[lang]).replace('{contact}', f'<a href="mailto:{CONTACT}">{CONTACT}</a>')
    open(os.path.join(out, PAGES['privacy'][lang]), 'w').write(page('privacy', lang, title, b, title))
print('ok')
