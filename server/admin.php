<?php
/**
 * Administration: the address to give, invitations for new families, and
 * the families registered (whose events the server cannot read).
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/api.php';
require_once __DIR__ . '/lib/i18n.php';

$config = load_config();
if ($config === null) {
    page_start(t('title_admin'));
    echo '<div class="card"><p>' . h(t('not_installed')) . '</p></div>';
    page_end();
    exit;
}

session_name('fst_admin');
session_start([
    'cookie_httponly' => true,
    'cookie_samesite' => 'Strict',
    'cookie_secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
]);
$_SESSION['csrf'] ??= bin2hex(random_bytes(16));
$post = ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST';
$self = 'admin.php?lang=' . lang();

/** A hidden field with the form's token. */
$csrf = fn() => '<input type="hidden" name="csrf" value="' . h($_SESSION['csrf']) . '">';

if ($post && isset($_POST['login'])) {
    if (password_verify((string)($_POST['password'] ?? ''), $config['admin_hash'])) {
        session_regenerate_id(true);
        $_SESSION['admin'] = true;
        header('Location: ' . $self, true, 303);
        exit;
    }
    sleep(2);
    $loginError = true;
}
if (empty($_SESSION['admin'])) {
    page_start(t('title_admin'));
    if (!empty($loginError)) {
        echo '<div class="notice bad">' . h(t('bad_login')) . '</div>';
    }
    echo '<form method="post" action="' . h($self) . '" class="card"><label for="password">' . h(t('password')) . '</label>'
        . '<input id="password" name="password" type="password" autocomplete="current-password" autofocus>'
        . '<button name="login" value="1">' . h(t('login')) . '</button></form>';
    page_end();
    exit;
}

$db = new Db($config['db']);
if ($post) {
    if (!hash_equals($_SESSION['csrf'], (string)($_POST['csrf'] ?? ''))) {
        http_response_code(400);
        exit('Bad request');
    }
    $action = $_POST['action'] ?? '';
    if ($action === 'logout') {
        session_destroy();
        header('Location: index.php?lang=' . lang(), true, 303);
        exit;
    }
    if ($action === 'invite') {
        // 12 letters and digits, without the ambiguous ones, in groups of 4.
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $raw = '';
        for ($i = 0; $i < 12; $i++) {
            $raw .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }
        $days = max(1, min(90, (int)($_POST['days'] ?? 7)));
        $label = mb_substr(trim((string)($_POST['label'] ?? '')), 0, 100);
        $db->run(
            'INSERT INTO {p}invitations (code_hash, label, created_at, expires_at) VALUES (?, ?, ?, ?)',
            [hash('sha256', $raw), $label, now_ms(), now_ms() + $days * 86400000],
        );
        // Shown once, after the redirect.
        $_SESSION['new_code'] = implode('-', str_split($raw, 4));
        $_SESSION['new_label'] = $label;
    }
    if ($action === 'delete_invitation') {
        $db->run('DELETE FROM {p}invitations WHERE code_hash = ? AND used_by IS NULL', [(string)($_POST['id'] ?? '')]);
    }
    if ($action === 'delete_family' && ($_POST['sure'] ?? '') === '1') {
        $id = (string)($_POST['id'] ?? '');
        $db->transaction(function () use ($db, $id) {
            foreach (['events', 'heads', 'devices'] as $table) {
                $db->run("DELETE FROM {p}$table WHERE family_id = ?", [$id]);
            }
            $db->run('DELETE FROM {p}families WHERE id = ?', [$id]);
        });
        $_SESSION['flash'] = t('family_deleted');
    }
    header('Location: ' . $self, true, 303);
    exit;
}

$date = fn(?int $ms) => $ms ? date('Y-m-d H:i', intdiv($ms, 1000)) : t('never');
$day = fn(?int $ms) => $ms ? date('Y-m-d', intdiv($ms, 1000)) : t('never');
$size = fn(int $bytes) => $bytes < 1048576
    ? number_format($bytes / 1024, 0) . ' Ko'
    : number_format($bytes / 1048576, 1) . ' Mo';

$logout = '<form method="post" action="' . h($self) . '" class="inline">' . $csrf()
    . '<button class="quiet" name="action" value="logout">' . h(t('logout')) . '</button></form>';
page_start(t('title_admin'), $logout);

if (isset($_SESSION['flash'])) {
    echo '<div class="notice ok">' . h($_SESSION['flash']) . '</div>';
    unset($_SESSION['flash']);
}

// The address, and a new code if one was just made.
$address = server_base() . '/api.php';
if (isset($_SESSION['new_code'])) {
    echo '<div class="notice new"><h2>' . h(t('new_code'))
        . ($_SESSION['new_label'] !== '' ? ' — ' . h($_SESSION['new_label']) : '') . '</h2>'
        . '<p class="code big">' . h($_SESSION['new_code']) . '</p>'
        . '<p><strong>' . h(t('code_once')) . '</strong></p>'
        . '<p class="small">' . h(t('address_text')) . '</p>'
        . '<p class="code">' . h($address) . '</p></div>';
    unset($_SESSION['new_code'], $_SESSION['new_label']);
}
echo '<section class="card"><h2>' . h(t('address_title')) . '</h2><p class="code">' . h($address) . '</p>'
    . '<p class="muted small">' . h(t('address_text')) . '</p></section>';

// A new invitation.
echo '<section class="card"><h2>' . h(t('invite_title')) . '</h2><p class="muted">' . h(t('invite_text')) . '</p>'
    . '<form method="post" action="' . h($self) . '">' . $csrf() . '<input type="hidden" name="action" value="invite">'
    . '<div class="row"><div><label for="label">' . h(t('note')) . '</label><input id="label" name="label" maxlength="100">'
    . '<div class="muted small">' . h(t('note_hint')) . '</div></div>'
    . '<div><label for="days">' . h(t('valid_for')) . '</label><select id="days" name="days">';
foreach ([1, 7, 30, 90] as $n) {
    echo '<option value="' . $n . '"' . ($n === 7 ? ' selected' : '') . '>' . h(t('days_n', ['n' => $n])) . '</option>';
}
echo '</select></div></div><button>' . h(t('create_invitation')) . '</button></form>';

$invitations = $db->run('SELECT code_hash, label, created_at, expires_at, used_by, used_at FROM {p}invitations ORDER BY created_at DESC')->fetchAll();
echo '<h2 style="margin-top:1.5rem">' . h(t('invitations')) . '</h2>';
if (!$invitations) {
    echo '<p class="muted">' . h(t('no_invitations')) . '</p>';
} else {
    echo '<table><tr><th>' . h(t('note')) . '</th><th class="hide-small">' . h(t('created_on')) . '</th><th>' . h(t('state')) . '</th><th></th></tr>';
    foreach ($invitations as $i) {
        if ($i['used_by'] !== null) {
            $state = '<span class="badge ok">' . h(t('state_used', ['date' => $day((int)$i['used_at'])])) . '</span>';
        } elseif ((int)$i['expires_at'] < now_ms()) {
            $state = '<span class="badge off">' . h(t('state_expired', ['date' => $day((int)$i['expires_at'])])) . '</span>';
        } else {
            $state = '<span class="badge wait">' . h(t('state_pending', ['date' => $day((int)$i['expires_at'])])) . '</span>';
        }
        $cancel = $i['used_by'] === null
            ? '<form method="post" action="' . h($self) . '" class="inline">' . $csrf()
                . '<input type="hidden" name="action" value="delete_invitation"><input type="hidden" name="id" value="' . h($i['code_hash']) . '">'
                . '<button class="quiet">' . h($i['expires_at'] < now_ms() ? t('delete') : t('cancel')) . '</button></form>'
            : '';
        echo '<tr><td>' . ($i['label'] !== '' ? h($i['label']) : '<span class="muted">' . h(t('no_note')) . '</span>') . '</td>'
            . '<td class="hide-small">' . h($day((int)$i['created_at'])) . '</td><td>' . $state . '</td><td>' . $cancel . '</td></tr>';
    }
    echo '</table>';
}
echo '</section>';

// The families.
echo '<section class="card"><h2>' . h(t('families')) . '</h2><p class="muted">' . h(t('families_text')) . '</p>';
$families = $db->run(
    'SELECT f.id, f.created_at, f.members, i.label FROM {p}families f LEFT JOIN {p}invitations i ON i.code_hash = f.invitation ORDER BY f.created_at',
)->fetchAll();
if (!$families) {
    echo '<p class="muted">' . h(t('no_families')) . '</p>';
}
foreach ($families as $f) {
    $devices = $db->run('SELECT device_id, last_seen FROM {p}devices WHERE family_id = ? AND active = 1 ORDER BY last_seen DESC', [$f['id']])->fetchAll();
    $e = $db->one('SELECT COUNT(*) AS c, SUM(LENGTH(body)) AS size FROM {p}events WHERE family_id = ?', [$f['id']]);
    $seen = $devices ? max(array_map(fn($d) => (int)$d['last_seen'], $devices)) : 0;
    $scopes = member_scopes($f['members']);
    // Children are numbered: the server does not know their names.
    $children = array_values(array_unique(array_filter($scopes, fn($s) => $s !== '*' && $s !== '')));
    sort($children);
    $receives = function (string $device) use ($scopes, $children): string {
        if (!$scopes) {
            return t('role_all');
        }
        $scope = $scopes[$device] ?? '*';
        return match (true) {
            $scope === '*' => t('role_parent'),
            $scope === '' => t('role_none'),
            default => t('role_child', ['n' => array_search($scope, $children, true) + 1]),
        };
    };
    $name = ($f['label'] ?? '') !== '' ? h($f['label']) : '<span class="muted">' . h(t('no_note')) . '</span>';
    echo '<div class="card" style="margin:.8rem 0 0;background:var(--bg)"><h2>' . $name
        . ' <code class="muted small">' . h(substr($f['id'], 0, 8)) . '</code></h2>'
        . '<table><tr><th>' . h(t('registered')) . '</th><th>' . h(t('devices')) . '</th><th>' . h(t('last_contact')) . '</th><th class="hide-small">' . h(t('data')) . '</th></tr>'
        . '<tr><td>' . h($day((int)$f['created_at'])) . '</td><td>' . count($devices) . '</td><td>' . h($date($seen)) . '</td>'
        . '<td class="hide-small">' . h(t('events_size', ['n' => (int)$e['c'], 'size' => $size((int)($e['size'] ?? 0))])) . '</td></tr></table>'
        . '<details><summary>' . h(t('details')) . '</summary>'
        . '<table><tr><th>' . h(t('device')) . '</th><th>' . h(t('receives')) . '</th><th>' . h(t('last_contact')) . '</th></tr>';
    foreach ($devices as $d) {
        echo '<tr><td><code>' . h(substr($d['device_id'], 0, 8)) . '</code></td><td>' . h($receives($d['device_id'])) . '</td>'
            . '<td>' . h($date((int)$d['last_seen'])) . '</td></tr>';
    }
    echo '</table><div class="danger-zone"><strong>' . h(t('delete_family_title')) . '</strong>'
        . '<p class="muted small">' . h(t('delete_family_text')) . '</p>'
        . '<form method="post" action="' . h($self) . '">' . $csrf()
        . '<input type="hidden" name="action" value="delete_family"><input type="hidden" name="id" value="' . h($f['id']) . '">'
        . '<label><input type="checkbox" name="sure" value="1" required> ' . h(t('delete_family_sure')) . '</label>'
        . '<button class="danger">' . h(t('delete_family')) . '</button></form></div></details></div>';
}
echo '</section>';
page_end(h(t('server_info', [
    'api' => API_VERSION,
    'php' => PHP_VERSION,
    'db' => $db->sqlite ? 'SQLite' : 'MySQL/MariaDB',
])));
