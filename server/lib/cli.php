<?php
/**
 * Command line, for hosts with a shell (and the tests):
 *   php lib/cli.php install-sqlite <admin password>   SQLite in data/
 *   php lib/cli.php install-mysql <host> <db> <user> <password> [admin password]
 *   php lib/cli.php invite [label] [days]             prints a code
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__ . '/db.php';

$command = $argv[1] ?? '';
if ($command === 'install-sqlite') {
    $db = ['driver' => 'sqlite', 'path' => dirname(__DIR__) . '/data/relay.sqlite', 'prefix' => 'fst_'];
    (new Db($db))->install();
    $config = ['db' => $db, 'admin_hash' => password_hash($argv[2] ?? bin2hex(random_bytes(12)), PASSWORD_DEFAULT)];
    file_put_contents(dirname(__DIR__) . '/config.php', "<?php\nreturn " . var_export($config, true) . ";\n");
    echo "installed\n";
    exit;
}
if ($command === 'install-mysql') {
    [, , $host, $name, $user, $password] = $argv + array_fill(0, 7, '');
    $db = ['driver' => 'mysql', 'host' => $host, 'port' => 3306, 'name' => $name, 'user' => $user, 'password' => $password, 'prefix' => 'fst_'];
    (new Db($db))->install();
    $config = ['db' => $db, 'admin_hash' => password_hash($argv[7] ?? bin2hex(random_bytes(12)), PASSWORD_DEFAULT)];
    file_put_contents(dirname(__DIR__) . '/config.php', "<?php\nreturn " . var_export($config, true) . ";\n");
    echo "installed\n";
    exit;
}
if ($command === 'invite') {
    $config = load_config() ?? exit("not installed\n");
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $raw = '';
    for ($i = 0; $i < 12; $i++) {
        $raw .= $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
    $days = (int)($argv[3] ?? 7);
    (new Db($config['db']))->run(
        'INSERT INTO {p}invitations (code_hash, label, created_at, expires_at) VALUES (?, ?, ?, ?)',
        [hash('sha256', $raw), $argv[2] ?? '', now_ms(), now_ms() + $days * 86400000],
    );
    echo implode('-', str_split($raw, 4)), "\n";
    exit;
}
fwrite(STDERR, "usage: php lib/cli.php install-sqlite <admin password> | invite [label] [days]\n");
exit(1);
