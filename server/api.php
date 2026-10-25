<?php
/**
 * Family Screen Time relay: the address to enter in the app is this file's
 * (https://example.org/fst/api.php). See README.md.
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/api.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

$config = load_config();
if ($config === null) {
    http_response_code(503);
    echo json_encode(['error' => 'not_installed', 'message' => 'Open install.php first', 'time' => now_ms()]);
    exit;
}

$headers = [];
foreach (['family', 'device', 'time', 'signature'] as $name) {
    $value = $_SERVER['HTTP_X_FST_' . strtoupper($name)] ?? null;
    if ($value !== null) {
        $headers['x-fst-' . $name] = (string)$value;
    }
}

try {
    $api = new Api(new Db($config['db']));
    [$status, $body] = $api->handle(
        $_SERVER['REQUEST_METHOD'] ?? 'GET',
        $_SERVER['QUERY_STRING'] ?? '',
        $headers,
        (string)file_get_contents('php://input'),
    );
} catch (Throwable $e) {
    error_log('Family Screen Time relay: ' . $e);
    [$status, $body] = [500, ['error' => 'server', 'message' => 'Server error', 'time' => now_ms()]];
}
header('X-FST-Server-Time: ' . now_ms());
http_response_code($status);
echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
