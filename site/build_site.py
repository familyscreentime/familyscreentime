import html, os
DATE = {'fr': '22 octobre 2026', 'nl': '22 oktober 2026', 'en': '22 October 2026'}
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
<p class="muted">Pour Android aujourd'hui, Windows ensuite. Sans compte, sans publicité, et tout reste sur l'appareil.</p>
</div></div>
<ul class="features">
<li>Temps par jour et par semaine, pour le temps total, un groupe d'applis (jeux, vidéo…) ou une appli.</li>
<li>Horaires jour par jour, pauses obligatoires, périodes particulières (vacances, examens…).</li>
<li>Temps de grâce, épargne du temps non utilisé, limite ferme après des dépassements répétés.</li>
<li>Actions rapides du parent : temps en plus, blocage, levée pour la journée, ouverture anticipée d'un horaire.</li>
<li>Décompte flottant façon Time Timer, avertissements, message clair quand le temps est écoulé.</li>
<li>L'enfant voit tout : son temps restant, ses règles, et il peut se fixer ses propres limites.</li>
<li>Écoute seule pour les applis de musique : une fois le temps des clips écoulé, l'appli s'ouvre juste le temps de choisir la musique, qui continue en arrière-plan.</li>
</ul>
<h2>À venir</h2>
<ul class="features">
<li>Synchronisation entre les appareils de la famille : réglages depuis le téléphone du parent, temps partagé entre la tablette et le téléphone de l'enfant.</li>
<li>Par le réseau local de la maison, ou par un serveur que vous hébergez vous-même (PHP et MySQL, un hébergement ordinaire suffit).</li>
<li>Une version Windows, ensuite.</li>
</ul>
<p class="muted">La synchronisation restera facultative. Sans elle, rien ne quitte l'appareil ; avec un serveur, les données vont uniquement sur le vôtre.</p>
<p>Conçue et testée par Olivier Berten, l'application est écrite par Claude, une IA d'Anthropic. C'est un logiciel libre (licence MIT) : <a href="'''+REPO+'''">son code source est sur GitHub</a>. Elle est en phase de test.</p>
<p><a href="confidentialite.html">Règles de confidentialité</a></p>
'''),
'nl': ('Family Screen Time — schermtijd in het gezin', 'Schermtijdbeheer voor gezinnen: limieten, tijden, pauzes, zonder verplicht account of server.', '''
<div class="hero"><img src="icon.png" alt=""><div>
<h1>Schermtijd, samen geregeld</h1>
<p class="muted">Vandaag voor Android, daarna Windows. Zonder account, zonder reclame, en alles blijft op het toestel.</p>
</div></div>
<ul class="features">
<li>Tijd per dag en per week, voor de totale schermtijd, een groep apps (spellen, video…) of één app.</li>
<li>Tijden per dag, verplichte pauzes, bijzondere periodes (vakantie, examens…).</li>
<li>Extra tijd, sparen van ongebruikte tijd, vaste limiet na herhaalde overschrijdingen.</li>
<li>Snelle acties voor de ouder: extra tijd, blokkeren, beperkingen opheffen voor de dag, tijden vroeger openen.</li>
<li>Zwevend aftellen in Time Timer-stijl, waarschuwingen, een duidelijke melding als de tijd om is.</li>
<li>Het kind ziet alles: de resterende tijd, de regels, en het kan zichzelf limieten geven.</li>
<li>Alleen luisteren voor muziekapps: als de tijd voor clips op is, gaat de app nog even open om muziek te kiezen, die op de achtergrond verder speelt.</li>
</ul>
<h2>Binnenkort</h2>
<ul class="features">
<li>Synchronisatie tussen de toestellen van het gezin: instellen vanaf de telefoon van de ouder, tijd gedeeld tussen de tablet en de telefoon van het kind.</li>
<li>Via het lokale netwerk thuis, of via een server die u zelf host (PHP en MySQL, gewone webhosting volstaat).</li>
<li>Daarna een Windows-versie.</li>
</ul>
<p class="muted">De synchronisatie blijft optioneel. Zonder synchronisatie verlaat niets het toestel; met een server gaan de gegevens alleen naar uw eigen server.</p>
<p>De app is ontworpen en getest door Olivier Berten en geschreven door Claude, een AI van Anthropic. Het is vrije software (MIT-licentie): <a href="'''+REPO+'''">de broncode staat op GitHub</a>. Ze is in testfase.</p>
<p><a href="privacybeleid.html">Privacybeleid</a></p>
'''),
'en': ('Family Screen Time — screen time, as a family', 'Screen time management for families: limits, hours, breaks, with no account or server required.', '''
<div class="hero"><img src="icon.png" alt=""><div>
<h1>Screen time, sorted out as a family</h1>
<p class="muted">For Android today, Windows next. No account, no ads, and everything stays on the device.</p>
</div></div>
<ul class="features">
<li>Time per day and per week, for total screen time, a group of apps (games, video…) or a single app.</li>
<li>Hours set day by day, mandatory breaks, special periods (holidays, exams…).</li>
<li>Grace time, saving unused time, a firm limit after repeated overruns.</li>
<li>Quick actions for the parent: extra time, blocking, lifting restrictions for the day, opening hours early.</li>
<li>A floating Time Timer-style countdown, warnings, a clear message when time is up.</li>
<li>The child sees everything: time left, the rules, and can set limits for themselves.</li>
<li>Listen only for music apps: once the time for clips is up, the app opens just long enough to pick the music, which keeps playing in the background.</li>
</ul>
<h2>Coming next</h2>
<ul class="features">
<li>Syncing between the family's devices: settings from the parent's phone, time shared between the child's tablet and phone.</li>
<li>Over the home network, or through a server you host yourself (PHP and MySQL, ordinary web hosting is enough).</li>
<li>A Windows version, after that.</li>
</ul>
<p class="muted">Syncing will stay optional. Without it, nothing leaves the device; with a server, the data only goes to yours.</p>
<p>Designed and tested by Olivier Berten, the app is written by Claude, an AI by Anthropic. It is free software (MIT licence): <a href="'''+REPO+'''">its source code is on GitHub</a>. It is in testing.</p>
<p><a href="privacy.html">Privacy policy</a></p>
'''),
}

PRIV = {
'fr': ('Règles de confidentialité — Family Screen Time', '''
<h1>Règles de confidentialité</h1>
<p class="muted">Application Android Family Screen Time (org.familyscreentime). Dernière mise à jour : {date}.</p>
<div class="card"><p><strong>En bref :</strong> Family Screen Time ne collecte aucune donnée. Tout ce que l'application enregistre reste sur l'appareil où elle est installée. Rien n'est envoyé à l'éditeur ni à des tiers : pas de compte, pas de publicité, pas de statistiques d'audience, pas de service tiers.</p></div>

<h2>Qui sommes-nous ?</h2>
<p>Family Screen Time est un logiciel libre (licence MIT) publié sur familyscreentime.org. Pour toute question : {contact}.</p>

<h2>Ce que l'application traite, sur l'appareil seulement</h2>
<table>
<tr><th>Donnée</th><th>Pourquoi</th></tr>
<tr><td>L'appli à l'écran et la durée de son utilisation</td><td>Compter le temps d'écran et appliquer les limites fixées par le parent.</td></tr>
<tr><td>L'historique d'utilisation des applis tenu par Android (environ 10 jours, à la première ouverture)</td><td>Afficher les statistiques d'utilisation dès le premier jour. Il ne sert pas aux limites.</td></tr>
<tr><td>Les règles, groupes d'applis, noms donnés aux applis, périodes, bonus et blocages</td><td>Faire fonctionner l'application selon les réglages du parent.</td></tr>
<tr><td>Le prénom de l'enfant</td><td>L'afficher dans l'application.</td></tr>
<tr><td>Le code parent, enregistré sous forme d'empreinte (PBKDF2), jamais en clair</td><td>Protéger les réglages.</td></tr>
<tr><td>Les limites que l'enfant se fixe et leur historique</td><td>Les appliquer, et montrer au parent comment elles sont tenues. L'enfant en est informé.</td></tr>
</table>
<p>Ces données sont stockées dans l'espace privé de l'application. Elles sont effacées quand l'application est désinstallée.</p>

<h2>Le service d'accessibilité</h2>
<p>L'application utilise le service d'accessibilité d'Android pour savoir quelle appli est à l'écran, pour fermer une appli bloquée et pour afficher les avertissements, le décompte et l'écran de verrouillage par-dessus les autres applis. Quand le parent active la protection contre la désinstallation, elle ferme aussi les pages des réglages qui permettraient de désactiver l'application. Pour les reconnaître, elle lit le contenu de l'écran uniquement sur les pages de sécurité et d'autorisations d'Android, sans rien enregistrer. L'utilisateur est informé et donne son accord avant l'activation de ce service.</p>

<h2>Autorisations</h2>
<ul>
<li><b>Accessibilité</b> : voir ci-dessus.</li>
<li><b>Accès aux données d'utilisation</b> : historique d'utilisation, repérage de l'appli à l'écran si l'accessibilité est coupée.</li>
<li><b>Affichage par-dessus les autres applis</b> : écran de blocage, décompte.</li>
<li><b>Notifications</b> : décompte, avertissements, mode parent.</li>
<li><b>Administrateur de l'appareil</b> (facultatif) : empêcher la désinstallation sans le parent. Aucune autre règle d'administration n'est utilisée.</li>
<li><b>Démarrage, service au premier plan, exclusion de l'optimisation de batterie</b> : garder le suivi actif.</li>
</ul>

<h2>Partage</h2>
<p>Aucune donnée n'est partagée, vendue ni transmise. L'application ne contient aucun outil de suivi.</p>

<h2>Enfants</h2>
<p>L'application est conçue pour être installée par un parent sur l'appareil de son enfant. Elle ne collecte aucune donnée personnelle sur l'enfant pour l'éditeur. L'enfant voit ses règles, son temps restant, et sait que le parent voit l'historique de ses propres limites.</p>

<h2>Évolutions</h2>
<p>Une version future pourra proposer une synchronisation entre les appareils de la famille, par le réseau local ou par un serveur que la famille héberge elle-même. Ces règles seront mises à jour avant toute version qui fera sortir des données de l'appareil.</p>

<h2>Vos droits</h2>
<p>Comme aucune donnée ne quitte l'appareil, l'éditeur ne détient aucune donnée vous concernant. Vous pouvez effacer toutes les données en désinstallant l'application ou en vidant ses données dans les réglages d'Android. Pour toute question : {contact}.</p>
'''),
'nl': ('Privacybeleid — Family Screen Time', '''
<h1>Privacybeleid</h1>
<p class="muted">Android-app Family Screen Time (org.familyscreentime). Laatst bijgewerkt: {date}.</p>
<div class="card"><p><strong>Kort:</strong> Family Screen Time verzamelt geen gegevens. Alles wat de app bijhoudt, blijft op het toestel waarop ze geïnstalleerd is. Er wordt niets naar de uitgever of naar derden gestuurd: geen account, geen reclame, geen bezoekersstatistieken, geen diensten van derden.</p></div>

<h2>Wie zijn we?</h2>
<p>Family Screen Time is vrije software (MIT-licentie), gepubliceerd op familyscreentime.org. Vragen: {contact}.</p>

<h2>Wat de app verwerkt, alleen op het toestel</h2>
<table>
<tr><th>Gegeven</th><th>Waarom</th></tr>
<tr><td>De app op het scherm en hoe lang ze gebruikt wordt</td><td>De schermtijd tellen en de limieten van de ouder toepassen.</td></tr>
<tr><td>De gebruiksgeschiedenis van apps die Android bijhoudt (ongeveer 10 dagen, bij de eerste opening)</td><td>Vanaf de eerste dag gebruiksstatistieken tonen. Ze wordt niet voor de limieten gebruikt.</td></tr>
<tr><td>De regels, app-groepen, namen van apps, periodes, extra tijd en blokkeringen</td><td>De app laten werken volgens de instellingen van de ouder.</td></tr>
<tr><td>De voornaam van het kind</td><td>Die in de app tonen.</td></tr>
<tr><td>De oudercode, bewaard als vingerafdruk (PBKDF2), nooit leesbaar</td><td>De instellingen beveiligen.</td></tr>
<tr><td>De limieten die het kind zichzelf geeft en hun geschiedenis</td><td>Ze toepassen en de ouder tonen hoe ze worden volgehouden. Het kind weet dat.</td></tr>
</table>
<p>Deze gegevens staan in de privéruimte van de app. Ze worden gewist als de app verwijderd wordt.</p>

<h2>De toegankelijkheidsdienst</h2>
<p>De app gebruikt de toegankelijkheidsdienst van Android om te weten welke app op het scherm staat, om een geblokkeerde app te sluiten en om waarschuwingen, het aftellen en het vergrendelscherm boven andere apps te tonen. Als de ouder de beveiliging tegen verwijderen inschakelt, sluit ze ook de instellingenpagina's waarmee de app uitgeschakeld kan worden. Om die te herkennen, leest ze de scherminhoud alleen op de beveiligings- en toestemmingspagina's van Android, zonder iets te bewaren. De gebruiker wordt ingelicht en geeft toestemming voor deze dienst wordt ingeschakeld.</p>

<h2>Toestemmingen</h2>
<ul>
<li><b>Toegankelijkheid</b>: zie hierboven.</li>
<li><b>Toegang tot gebruiksgegevens</b>: gebruiksgeschiedenis, de app op het scherm herkennen als toegankelijkheid uit staat.</li>
<li><b>Weergeven boven andere apps</b>: blokkeerscherm, aftellen.</li>
<li><b>Meldingen</b>: aftellen, waarschuwingen, oudermodus.</li>
<li><b>Apparaatbeheerder</b> (optioneel): verwijderen zonder de ouder voorkomen. Er wordt geen ander beheerbeleid gebruikt.</li>
<li><b>Opstarten, voorgronddienst, uitzondering op batterijoptimalisatie</b>: de opvolging actief houden.</li>
</ul>

<h2>Delen</h2>
<p>Er worden geen gegevens gedeeld, verkocht of doorgegeven. De app bevat geen volgsoftware.</p>

<h2>Kinderen</h2>
<p>De app is gemaakt om door een ouder op het toestel van het kind geïnstalleerd te worden. Ze verzamelt geen persoonsgegevens over het kind voor de uitgever. Het kind ziet zijn regels en resterende tijd, en weet dat de ouder de geschiedenis van zijn eigen limieten ziet.</p>

<h2>Wijzigingen</h2>
<p>Een toekomstige versie kan synchronisatie tussen de toestellen van het gezin aanbieden, via het lokale netwerk of een server die het gezin zelf host. Dit beleid wordt bijgewerkt vóór elke versie die gegevens buiten het toestel brengt.</p>

<h2>Uw rechten</h2>
<p>Omdat geen enkel gegeven het toestel verlaat, heeft de uitgever geen gegevens over u. U kunt alle gegevens wissen door de app te verwijderen of haar gegevens te wissen in de Android-instellingen. Vragen: {contact}.</p>
'''),
'en': ('Privacy policy — Family Screen Time', '''
<h1>Privacy policy</h1>
<p class="muted">Family Screen Time Android app (org.familyscreentime). Last updated: {date}.</p>
<div class="card"><p><strong>In short:</strong> Family Screen Time collects no data. Everything the app records stays on the device it is installed on. Nothing is sent to the publisher or to third parties: no account, no ads, no analytics, no third-party services.</p></div>

<h2>Who we are</h2>
<p>Family Screen Time is free software (MIT licence) published at familyscreentime.org. Questions: {contact}.</p>

<h2>What the app processes, on the device only</h2>
<table>
<tr><th>Data</th><th>Why</th></tr>
<tr><td>The app on screen and how long it is used</td><td>To count screen time and apply the limits the parent set.</td></tr>
<tr><td>The app usage history Android keeps (about 10 days, on first launch)</td><td>To show usage statistics from the first day. It is not used for limits.</td></tr>
<tr><td>Rules, app groups, names given to apps, periods, extra time and blocks</td><td>To run the app as the parent set it up.</td></tr>
<tr><td>The child's first name</td><td>To show it in the app.</td></tr>
<tr><td>The parent code, stored as a hash (PBKDF2), never in clear</td><td>To protect the settings.</td></tr>
<tr><td>The limits the child sets for themselves and their history</td><td>To apply them, and show the parent how they are kept. The child is told.</td></tr>
</table>
<p>This data is stored in the app's private storage and erased when the app is uninstalled.</p>

<h2>The accessibility service</h2>
<p>The app uses Android's accessibility service to know which app is on screen, to close a blocked app, and to show warnings, the countdown and the lock screen over other apps. When the parent turns on uninstall protection, it also closes the settings pages that would switch the app off. To recognise them, it reads screen content only on Android's security and permission pages, and stores nothing. The user is informed and agrees before this service is turned on.</p>

<h2>Permissions</h2>
<ul>
<li><b>Accessibility</b>: see above.</li>
<li><b>Usage access</b>: usage history; knowing the app on screen when accessibility is off.</li>
<li><b>Display over other apps</b>: block screen, countdown.</li>
<li><b>Notifications</b>: countdown, warnings, parent mode.</li>
<li><b>Device administrator</b> (optional): preventing uninstallation without the parent. No other administration policy is used.</li>
<li><b>Start at boot, foreground service, exemption from battery optimisation</b>: keeping monitoring running.</li>
</ul>

<h2>Sharing</h2>
<p>No data is shared, sold or transferred. The app contains no tracking tools.</p>

<h2>Children</h2>
<p>The app is designed to be installed by a parent on their child's device. It collects no personal data about the child for the publisher. The child sees their rules and time left, and knows that the parent sees the history of their own limits.</p>

<h2>Changes</h2>
<p>A future version may offer synchronisation between the family's devices, over the local network or through a server the family hosts itself. This policy will be updated before any version that takes data off the device.</p>

<h2>Your rights</h2>
<p>As no data leaves the device, the publisher holds no data about you. You can erase all data by uninstalling the app or clearing its data in Android's settings. Questions: {contact}.</p>
'''),
}

out = os.getcwd()
for lang, (title, desc, body) in HOME.items():
    open(os.path.join(out, PAGES['home'][lang]), 'w').write(page('home', lang, title, body, desc))
for lang, (title, body) in PRIV.items():
    b = body.replace('{date}', DATE[lang]).replace('{contact}', f'<a href="mailto:{CONTACT}">{CONTACT}</a>')
    open(os.path.join(out, PAGES['privacy'][lang]), 'w').write(page('privacy', lang, title, b, title))
print('ok')
