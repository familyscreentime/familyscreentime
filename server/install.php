<?php
/**
 * Installs the relay: checks PHP, writes config.php and creates the
 * tables. Locked once config.php exists; delete it afterwards.
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/i18n.php';

page_start(t('title_install'));

if (load_config() !== null) {
    echo '<div class="card"><p>' . h(t('installed')) . '</p><a class="button" href="admin.php?lang=' . lang() . '">' . h(t('go_admin')) . '</a></div>';
    page_end();
    exit;
}

$checks = [
    'php' => PHP_VERSION_ID >= 80200,
    'sodium' => function_exists('sodium_crypto_sign_verify_detached'),
    'pdo_mysql' => extension_loaded('pdo_mysql'),
    'pdo_sqlite' => extension_loaded('pdo_sqlite'),
    'writable' => is_writable(__DIR__),
];
$required = $checks['php'] && $checks['sodium'] && ($checks['pdo_mysql'] || $checks['pdo_sqlite']);

$error = null;
$written = null;
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && $required) {
    $driver = ($_POST['driver'] ?? 'mysql') === 'sqlite' ? 'sqlite' : 'mysql';
    $pass = (string)($_POST['admin_password'] ?? '');
    if ($pass !== (string)($_POST['admin_password2'] ?? '') || mb_strlen($pass) < 12) {
        $error = t('err_passwords');
    } else {
        $db = $driver === 'sqlite'
            ? ['driver' => 'sqlite', 'path' => __DIR__ . '/data/relay.sqlite']
            : [
                'driver' => 'mysql',
                'host' => trim((string)($_POST['host'] ?? 'localhost')),
                'port' => (int)($_POST['port'] ?? 3306),
                'name' => trim((string)($_POST['name'] ?? '')),
                'user' => trim((string)($_POST['user'] ?? '')),
                'password' => (string)($_POST['password'] ?? ''),
            ];
        $db['prefix'] = preg_replace('/[^A-Za-z0-9_]/', '', (string)($_POST['prefix'] ?? 'fst_'));
        try {
            (new Db($db))->install();
            $config = ['db' => $db, 'admin_hash' => password_hash($pass, PASSWORD_DEFAULT)];
            $php = "<?php\n// Family Screen Time relay settings, written by install.php.\nreturn " . var_export($config, true) . ";\n";
            if (@file_put_contents(__DIR__ . '/config.php', $php, LOCK_EX) === false) {
                $written = $php;
            } else {
                @chmod(__DIR__ . '/config.php', 0600);
                echo '<div class="notice ok">' . h(t('done')) . '</div><div class="card">';
                echo '<p>' . h(t('app_address')) . '</p><p class="code">' . h(server_base() . '/api.php') . '</p>';
                echo '<p>' . h(t('next')) . '</p><p><a class="button" href="admin.php?lang=' . lang() . '">' . h(t('go_admin')) . '</a></p></div>';
                page_end();
                exit;
            }
        } catch (Throwable $e) {
            $error = t('err_db') . ' ' . $e->getMessage();
        }
    }
}

echo '<div class="card"><h2>' . h(t('checks')) . '</h2><ul class="checks">';
foreach ($checks as $key => $ok) {
    $class = $ok ? 'ok' : ($key === 'pdo_sqlite' || $key === 'writable' ? 'muted' : 'bad');
    echo '<li class="' . $class . '">' . ($ok ? '✓ ' : '✗ ') . h(t($key)) . '</li>';
}
echo '</ul></div>';
if (!$required) {
    echo '<div class="notice bad">' . h(t('err_checks')) . '</div>';
    page_end();
    exit;
}
if ($error !== null) {
    echo '<div class="notice bad">' . h($error) . '</div>';
}
if ($written !== null) {
    echo '<div class="notice bad">' . h(t('err_write')) . '</div><pre class="card">' . h($written) . '</pre>';
    page_end();
    exit;
}
$v = fn(string $k, string $d = '') => h((string)($_POST[$k] ?? $d));
echo '<form method="post" class="card"><h2>' . h(t('database')) . '</h2>'
    . '<label>' . h(t('driver')) . '</label><select name="driver">'
    . ($checks['pdo_mysql'] ? '<option value="mysql">' . h(t('mysql')) . '</option>' : '')
    . ($checks['pdo_sqlite'] ? '<option value="sqlite">' . h(t('sqlite')) . '</option>' : '')
    . '</select>'
    . '<label>' . h(t('host')) . '</label><input name="host" value="' . $v('host', 'localhost') . '">'
    . '<label>' . h(t('port')) . '</label><input name="port" value="' . $v('port', '3306') . '" inputmode="numeric">'
    . '<label>' . h(t('name')) . '</label><input name="name" value="' . $v('name') . '">'
    . '<label>' . h(t('user')) . '</label><input name="user" value="' . $v('user') . '" autocomplete="off">'
    . '<label>' . h(t('password')) . '</label><input name="password" type="password" autocomplete="off">'
    . '<label>' . h(t('prefix')) . '</label><input name="prefix" value="' . $v('prefix', 'fst_') . '">'
    . '<h2 style="margin-top:1.5rem">' . h(t('home_admin')) . '</h2>'
    . '<label>' . h(t('admin_password')) . '</label><input name="admin_password" type="password" autocomplete="new-password">'
    . '<label>' . h(t('admin_password2')) . '</label><input name="admin_password2" type="password" autocomplete="new-password">'
    . '<button>' . h(t('install')) . '</button></form>';
page_end();
