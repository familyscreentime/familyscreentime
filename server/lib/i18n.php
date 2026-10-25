<?php
/** Texts of the installation and administration pages, in three languages. */

declare(strict_types=1);

const TEXTS = [
    'fr' => [
        'title_install' => 'Installer le serveur',
        'title_admin' => 'Administration du serveur',
        'installed' => 'Le serveur est déjà installé. Pour le réinstaller, supprimez config.php.',
        'checks' => 'Vérifications',
        'php' => 'PHP 8.2 ou plus récent',
        'sodium' => 'Extension sodium (signatures)',
        'pdo_mysql' => 'Extension PDO MySQL',
        'pdo_sqlite' => 'Extension PDO SQLite (facultative)',
        'writable' => 'Dossier du serveur accessible en écriture (pour config.php)',
        'database' => 'Base de données',
        'driver' => 'Type',
        'mysql' => 'MySQL ou MariaDB',
        'sqlite' => 'SQLite (un fichier, pour un petit usage)',
        'host' => 'Serveur',
        'port' => 'Port',
        'name' => 'Nom de la base',
        'user' => 'Utilisateur',
        'password' => 'Mot de passe',
        'prefix' => 'Préfixe des tables',
        'admin_password' => 'Mot de passe d\'administration (12 caractères minimum)',
        'admin_password2' => 'Le même, une seconde fois',
        'install' => 'Installer',
        'done' => 'Installation terminée.',
        'app_address' => 'Adresse à entrer dans l\'application :',
        'next' => 'Créez maintenant une invitation dans la page d\'administration, puis supprimez install.php.',
        'go_admin' => 'Ouvrir l\'administration',
        'err_passwords' => 'Les deux mots de passe d\'administration diffèrent, ou font moins de 12 caractères.',
        'err_db' => 'Connexion à la base impossible :',
        'err_write' => 'Impossible d\'écrire config.php. Créez-le vous-même avec ce contenu :',
        'err_checks' => 'Corrigez d\'abord les points en rouge.',
        'login' => 'Se connecter',
        'logout' => 'Se déconnecter',
        'bad_login' => 'Mot de passe incorrect.',
        'not_installed' => 'Le serveur n\'est pas encore installé : ouvrez install.php.',
        'delete' => 'Supprimer',
        'brand' => 'Serveur relais Family Screen Time',
        'home_text' => 'Ce serveur relaie la synchronisation entre les appareils reliés d\'une famille quand ils ne sont pas sur le même Wi-Fi. Il ne peut pas lire ce qu\'il transmet : tout est chiffré sur les appareils, de bout en bout.',
        'home_address' => 'Adresse du serveur, à entrer dans l\'application',
        'home_how' => 'Sur l\'appareil d\'un parent : Mode parent › Appareils reliés › Serveur › Configurer, puis cette adresse et le code d\'invitation reçu de l\'administrateur.',
        'home_not_installed' => 'Le serveur n\'est pas encore installé.',
        'home_install' => 'Installer le serveur',
        'home_admin' => 'Administration',
        'address_title' => 'Adresse du serveur',
        'address_text' => 'À entrer dans l\'application avec un code d\'invitation, sur l\'appareil d\'un parent : Mode parent › Appareils reliés › Serveur › Configurer. Les autres appareils reliés de la famille l\'apprennent ensuite d\'eux-mêmes.',
        'invite_title' => 'Inviter une famille',
        'invite_text' => 'Une invitation par famille, pas par enfant ni par appareil : elle sert une seule fois, au premier appareil qui configure le serveur. Les autres appareils de la famille n\'en ont pas besoin.',
        'note' => 'Note (pour vous seul)',
        'note_hint' => 'Par exemple « Famille Dupont ». Elle n\'est montrée qu\'ici.',
        'valid_for' => 'Valable',
        'days_n' => '{n} jours',
        'create_invitation' => 'Créer l\'invitation',
        'new_code' => 'Code d\'invitation à transmettre à la famille',
        'code_once' => 'Notez-le maintenant : il ne sera plus affiché.',
        'invitations' => 'Invitations',
        'no_invitations' => 'Aucune invitation pour l\'instant.',
        'created_on' => 'Créée le',
        'state' => 'État',
        'state_pending' => 'Valable jusqu\'au {date}',
        'state_used' => 'Utilisée le {date}',
        'state_expired' => 'Expirée le {date}',
        'cancel' => 'Annuler',
        'families' => 'Familles inscrites',
        'families_text' => 'Le serveur ne voit ni les noms, ni les règles, ni l\'usage des applications : seulement des identifiants d\'appareils, des numéros et des dates.',
        'no_families' => 'Aucune famille inscrite.',
        'family' => 'Famille',
        'no_note' => 'Sans note',
        'registered' => 'Inscrite le',
        'devices' => 'Appareils',
        'last_contact' => 'Dernier contact',
        'data' => 'Données',
        'events_size' => '{n} événements · {size}',
        'device' => 'Appareil',
        'receives' => 'Reçoit',
        'role_parent' => 'Tout (appareil d\'un parent)',
        'role_child' => 'La famille et l\'enfant {n}',
        'role_none' => 'La famille seulement',
        'role_all' => 'Tout (liste signée avant la version 0.25)',
        'details' => 'Détails',
        'delete_family_title' => 'Supprimer la famille',
        'delete_family_text' => 'Efface la famille du serveur et tous ses événements. Ses appareils continuent de fonctionner et de se synchroniser sur le Wi-Fi ; pour utiliser à nouveau le serveur, il faudra une nouvelle invitation.',
        'delete_family_sure' => 'Je confirme',
        'delete_family' => 'Supprimer définitivement',
        'family_deleted' => 'Famille supprimée.',
        'server_info' => 'API {api} · PHP {php} · {db}',
        'never' => 'jamais',
    ],
    'nl' => [
        'title_install' => 'De server installeren',
        'title_admin' => 'Beheer van de server',
        'installed' => 'De server is al geïnstalleerd. Verwijder config.php om opnieuw te installeren.',
        'checks' => 'Controles',
        'php' => 'PHP 8.2 of recenter',
        'sodium' => 'Extensie sodium (handtekeningen)',
        'pdo_mysql' => 'Extensie PDO MySQL',
        'pdo_sqlite' => 'Extensie PDO SQLite (optioneel)',
        'writable' => 'Servermap beschrijfbaar (voor config.php)',
        'database' => 'Databank',
        'driver' => 'Soort',
        'mysql' => 'MySQL of MariaDB',
        'sqlite' => 'SQLite (één bestand, voor klein gebruik)',
        'host' => 'Server',
        'port' => 'Poort',
        'name' => 'Naam van de databank',
        'user' => 'Gebruiker',
        'password' => 'Wachtwoord',
        'prefix' => 'Voorvoegsel van de tabellen',
        'admin_password' => 'Beheerwachtwoord (minstens 12 tekens)',
        'admin_password2' => 'Hetzelfde, nog een keer',
        'install' => 'Installeren',
        'done' => 'Installatie voltooid.',
        'app_address' => 'Adres om in de app in te voeren:',
        'next' => 'Maak nu een uitnodiging aan op de beheerpagina en verwijder daarna install.php.',
        'go_admin' => 'Beheer openen',
        'err_passwords' => 'De twee beheerwachtwoorden verschillen, of zijn korter dan 12 tekens.',
        'err_db' => 'Geen verbinding met de databank:',
        'err_write' => 'config.php kan niet geschreven worden. Maak het zelf aan met deze inhoud:',
        'err_checks' => 'Los eerst de rode punten op.',
        'login' => 'Aanmelden',
        'logout' => 'Afmelden',
        'bad_login' => 'Verkeerd wachtwoord.',
        'not_installed' => 'De server is nog niet geïnstalleerd: open install.php.',
        'delete' => 'Verwijderen',
        'brand' => 'Relayserver Family Screen Time',
        'home_text' => 'Deze server geeft de synchronisatie door tussen de gekoppelde toestellen van een gezin als ze niet op dezelfde wifi zitten. Hij kan niet lezen wat hij doorgeeft: alles is op de toestellen end-to-end versleuteld.',
        'home_address' => 'Adres van de server, in te voeren in de app',
        'home_how' => 'Op het toestel van een ouder: Oudermodus › Gekoppelde toestellen › Server › Instellen, dan dit adres en de uitnodigingscode van de beheerder.',
        'home_not_installed' => 'De server is nog niet geïnstalleerd.',
        'home_install' => 'De server installeren',
        'home_admin' => 'Beheer',
        'address_title' => 'Adres van de server',
        'address_text' => 'In te voeren in de app met een uitnodigingscode, op het toestel van een ouder: Oudermodus › Gekoppelde toestellen › Server › Instellen. De andere gekoppelde toestellen van het gezin krijgen het daarna vanzelf.',
        'invite_title' => 'Een gezin uitnodigen',
        'invite_text' => 'Eén uitnodiging per gezin, niet per kind of per toestel: ze dient maar één keer, voor het eerste toestel dat de server instelt. De andere toestellen van het gezin hebben er geen nodig.',
        'note' => 'Notitie (alleen voor u)',
        'note_hint' => 'Bijvoorbeeld „Gezin Peeters”. Ze wordt alleen hier getoond.',
        'valid_for' => 'Geldig',
        'days_n' => '{n} dagen',
        'create_invitation' => 'Uitnodiging aanmaken',
        'new_code' => 'Uitnodigingscode om aan het gezin te bezorgen',
        'code_once' => 'Noteer hem nu: hij wordt niet meer getoond.',
        'invitations' => 'Uitnodigingen',
        'no_invitations' => 'Nog geen uitnodigingen.',
        'created_on' => 'Aangemaakt op',
        'state' => 'Status',
        'state_pending' => 'Geldig tot {date}',
        'state_used' => 'Gebruikt op {date}',
        'state_expired' => 'Verlopen op {date}',
        'cancel' => 'Annuleren',
        'families' => 'Aangemelde gezinnen',
        'families_text' => 'De server ziet geen namen, regels of appgebruik: alleen toestel-id\'s, nummers en datums.',
        'no_families' => 'Geen aangemelde gezinnen.',
        'family' => 'Gezin',
        'no_note' => 'Zonder notitie',
        'registered' => 'Aangemeld op',
        'devices' => 'Toestellen',
        'last_contact' => 'Laatste contact',
        'data' => 'Gegevens',
        'events_size' => '{n} gebeurtenissen · {size}',
        'device' => 'Toestel',
        'receives' => 'Ontvangt',
        'role_parent' => 'Alles (toestel van een ouder)',
        'role_child' => 'Het gezin en kind {n}',
        'role_none' => 'Alleen het gezin',
        'role_all' => 'Alles (lijst ondertekend vóór versie 0.25)',
        'details' => 'Details',
        'delete_family_title' => 'Het gezin verwijderen',
        'delete_family_text' => 'Wist het gezin en al zijn gebeurtenissen van de server. De toestellen blijven werken en synchroniseren via de wifi; om de server opnieuw te gebruiken is een nieuwe uitnodiging nodig.',
        'delete_family_sure' => 'Ik bevestig',
        'delete_family' => 'Definitief verwijderen',
        'family_deleted' => 'Gezin verwijderd.',
        'server_info' => 'API {api} · PHP {php} · {db}',
        'never' => 'nooit',
    ],
    'en' => [
        'title_install' => 'Install the server',
        'title_admin' => 'Server administration',
        'installed' => 'The server is installed already. To install it again, delete config.php.',
        'checks' => 'Checks',
        'php' => 'PHP 8.2 or later',
        'sodium' => 'sodium extension (signatures)',
        'pdo_mysql' => 'PDO MySQL extension',
        'pdo_sqlite' => 'PDO SQLite extension (optional)',
        'writable' => 'Server folder writable (for config.php)',
        'database' => 'Database',
        'driver' => 'Kind',
        'mysql' => 'MySQL or MariaDB',
        'sqlite' => 'SQLite (one file, for light use)',
        'host' => 'Host',
        'port' => 'Port',
        'name' => 'Database name',
        'user' => 'User',
        'password' => 'Password',
        'prefix' => 'Table prefix',
        'admin_password' => 'Administration password (12 characters at least)',
        'admin_password2' => 'The same, once more',
        'install' => 'Install',
        'done' => 'Installation complete.',
        'app_address' => 'Address to enter in the app:',
        'next' => 'Now create an invitation in the administration page, then delete install.php.',
        'go_admin' => 'Open the administration',
        'err_passwords' => 'The two administration passwords differ, or are shorter than 12 characters.',
        'err_db' => 'Cannot connect to the database:',
        'err_write' => 'config.php cannot be written. Create it yourself with this content:',
        'err_checks' => 'Fix the points in red first.',
        'login' => 'Sign in',
        'logout' => 'Sign out',
        'bad_login' => 'Wrong password.',
        'not_installed' => 'The server is not installed yet: open install.php.',
        'delete' => 'Delete',
        'brand' => 'Family Screen Time relay server',
        'home_text' => 'This server relays the sync between a family\'s linked devices when they are not on the same Wi-Fi. It cannot read what it passes on: everything is encrypted end to end, on the devices.',
        'home_address' => 'The server\'s address, to enter in the app',
        'home_how' => 'On a parent\'s device: Parent mode › Linked devices › Server › Set up, then this address and the invitation code from the administrator.',
        'home_not_installed' => 'The server is not installed yet.',
        'home_install' => 'Install the server',
        'home_admin' => 'Administration',
        'address_title' => 'The server\'s address',
        'address_text' => 'To enter in the app with an invitation code, on a parent\'s device: Parent mode › Linked devices › Server › Set up. The family\'s other linked devices then learn it by themselves.',
        'invite_title' => 'Invite a family',
        'invite_text' => 'One invitation per family, not per child or device: it works once, for the first device that sets the server up. The family\'s other devices do not need one.',
        'note' => 'Note (for you only)',
        'note_hint' => 'For example "The Smiths". It is only shown here.',
        'valid_for' => 'Valid for',
        'days_n' => '{n} days',
        'create_invitation' => 'Create the invitation',
        'new_code' => 'Invitation code to give the family',
        'code_once' => 'Write it down now: it will not be shown again.',
        'invitations' => 'Invitations',
        'no_invitations' => 'No invitations yet.',
        'created_on' => 'Created on',
        'state' => 'Status',
        'state_pending' => 'Valid until {date}',
        'state_used' => 'Used on {date}',
        'state_expired' => 'Expired on {date}',
        'cancel' => 'Cancel',
        'families' => 'Registered families',
        'families_text' => 'The server sees no names, rules or use of apps: only device ids, numbers and dates.',
        'no_families' => 'No registered families.',
        'family' => 'Family',
        'no_note' => 'No note',
        'registered' => 'Registered on',
        'devices' => 'Devices',
        'last_contact' => 'Last contact',
        'data' => 'Data',
        'events_size' => '{n} events · {size}',
        'device' => 'Device',
        'receives' => 'Receives',
        'role_parent' => 'Everything (a parent\'s device)',
        'role_child' => 'The family and child {n}',
        'role_none' => 'The family only',
        'role_all' => 'Everything (list signed before version 0.25)',
        'details' => 'Details',
        'delete_family_title' => 'Delete the family',
        'delete_family_text' => 'Erases the family and all its events from the server. Its devices keep working and syncing over the Wi-Fi; using the server again takes a new invitation.',
        'delete_family_sure' => 'I confirm',
        'delete_family' => 'Delete for good',
        'family_deleted' => 'Family deleted.',
        'server_info' => 'API {api} · PHP {php} · {db}',
        'never' => 'never',
    ],
];

function lang(): string
{
    $asked = $_GET['lang'] ?? null;
    if (is_string($asked) && isset(TEXTS[$asked])) {
        return $asked;
    }
    foreach (explode(',', $_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '') as $part) {
        $code = strtolower(substr(trim($part), 0, 2));
        if (isset(TEXTS[$code])) {
            return $code;
        }
    }
    return 'en';
}

/** The text [key] in the page's language, with `{name}` replaced from [vars]. */
function t(string $key, array $vars = []): string
{
    $text = TEXTS[lang()][$key] ?? TEXTS['en'][$key] ?? $key;
    foreach ($vars as $name => $value) {
        $text = str_replace('{' . $name . '}', (string)$value, $text);
    }
    return $text;
}

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/**
 * The start of a page: the server's name, links to the other languages
 * and, for the administration, [actions] (HTML) at the right.
 */
function page_start(string $title, string $actions = ''): void
{
    header('Content-Type: text/html; charset=utf-8');
    header('X-Frame-Options: DENY');
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: no-referrer');
    header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'");
    $page = basename($_SERVER['SCRIPT_NAME'] ?? 'index.php');
    $langs = '';
    foreach (array_keys(TEXTS) as $code) {
        $langs .= $code === lang()
            ? '<strong>' . strtoupper($code) . '</strong>'
            : '<a href="' . h($page . '?lang=' . $code) . '">' . strtoupper($code) . '</a>';
    }
    echo '<!doctype html><html lang="' . lang() . '"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<meta name="robots" content="noindex">'
        . '<title>' . h($title === t('brand') ? $title : $title . ' — ' . t('brand')) . '</title><style>' . PAGE_CSS . '</style></head><body>'
        . '<header><div class="wrap bar"><a class="brand" href="index.php?lang=' . lang() . '">' . h(t('brand')) . '</a>'
        . '<nav>' . $actions . '<span class="langs">' . $langs . '</span></nav></div></header>'
        . '<main class="wrap"><h1>' . h($title) . '</h1>';
}

function page_end(string $footer = ''): void
{
    echo '</main>' . ($footer === '' ? '' : '<footer class="wrap muted">' . $footer . '</footer>') . '</body></html>';
}

const PAGE_CSS = <<<'CSS'
:root{--fg:#1d2433;--muted:#5b6475;--bg:#f4f6f9;--card:#fff;--line:#dde1e8;--accent:#2f5bd3;--accent-fg:#fff;--ok:#1b7f3b;--ok-bg:#e5f4ea;--bad:#b3261e;--bad-bg:#fbe9e7;--warn:#8a5a00;--warn-bg:#fdf1d8}
@media (prefers-color-scheme:dark){:root{--fg:#e6e9ef;--muted:#9aa3b5;--bg:#12151c;--card:#1b1f29;--line:#2e3442;--accent:#7c9cff;--accent-fg:#0d1020;--ok:#7fd49a;--ok-bg:#16301f;--bad:#ff8a80;--bad-bg:#3a1a18;--warn:#f3c35f;--warn-bg:#352a12}}
*{box-sizing:border-box}
body{font:16px/1.5 system-ui,sans-serif;margin:0;color:var(--fg);background:var(--bg)}
.wrap{max-width:60rem;margin:0 auto;padding:0 1rem}
header{background:var(--card);border-bottom:1px solid var(--line)}
.bar{display:flex;align-items:center;justify-content:space-between;gap:1rem;min-height:3.2rem;flex-wrap:wrap}
.brand{font-weight:600;color:var(--fg);text-decoration:none}
nav{display:flex;align-items:center;gap:1rem}
.langs{display:flex;gap:.5rem;font-size:.9rem}
a{color:var(--accent)}
h1{font-size:1.6rem;margin:1.5rem 0 1rem}
h2{font-size:1.15rem;margin:0 0 .5rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:1.1rem 1.2rem;margin:0 0 1.2rem}
.muted{color:var(--muted)}
.card>p:first-child{margin-top:0}.card>p:last-child{margin-bottom:0}
.small{font-size:.9rem}
label{display:block;margin:.8rem 0 .25rem;font-weight:500}
input,select{font:inherit;color:inherit;background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:.45rem .6rem;width:100%;max-width:26rem}
input[type=checkbox]{width:auto}
.row{display:flex;gap:1rem;flex-wrap:wrap;align-items:flex-start}
.row>div{flex:1 1 14rem}
button,.button{font:inherit;padding:.5rem 1.1rem;margin-top:1rem;border-radius:6px;border:1px solid var(--accent);background:var(--accent);color:var(--accent-fg);cursor:pointer;text-decoration:none;display:inline-block}
button.quiet{background:transparent;color:var(--accent);margin:0;padding:.25rem .7rem}
button.danger{background:var(--bad);border-color:var(--bad);color:#fff}
.code{font:600 1.15rem ui-monospace,monospace;letter-spacing:.04em;background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:.5rem .8rem;display:inline-block;word-break:break-all;user-select:all}
.code.big{font-size:1.6rem;letter-spacing:.12em}
.notice{border-radius:8px;padding:.8rem 1rem;margin:0 0 1.2rem}
.notice.ok{background:var(--ok-bg);color:var(--ok)}
.notice.bad{background:var(--bad-bg);color:var(--bad)}
.notice.new{background:var(--ok-bg);border:1px solid var(--ok)}
.notice.new .code{background:var(--card)}
table{border-collapse:collapse;width:100%}
td,th{border-bottom:1px solid var(--line);padding:.5rem .4rem;text-align:left;vertical-align:top}
th{font-weight:500;color:var(--muted);font-size:.9rem}
.badge{display:inline-block;border-radius:8px;padding:.05rem .6rem;font-size:.85rem}
.badge.ok{background:var(--ok-bg);color:var(--ok)}
.badge.wait{background:var(--warn-bg);color:var(--warn)}
.badge.off{background:var(--bg);color:var(--muted);border:1px solid var(--line)}
details{margin-top:.6rem}
summary{cursor:pointer;color:var(--accent)}
.danger-zone{border-top:1px solid var(--line);margin-top:1rem;padding-top:.8rem}
.inline{display:inline}
.ok{color:var(--ok)}.bad{color:var(--bad)}
ul.checks{list-style:none;padding:0}
footer{padding:1rem 0 2rem;font-size:.85rem}
@media (max-width:40rem){.hide-small{display:none}}
CSS;
