<?php
/**
 * Database access: MySQL/MariaDB, or SQLite for small setups and tests.
 * Tables are prefixed (config `prefix`, `fst_` by default).
 */

declare(strict_types=1);

final class Db
{
    public readonly PDO $pdo;
    public readonly bool $sqlite;
    public readonly string $p;

    public function __construct(array $config)
    {
        $this->p = $config['prefix'] ?? 'fst_';
        if (!preg_match('/^[A-Za-z0-9_]*$/', $this->p)) {
            throw new RuntimeException('Bad table prefix');
        }
        $this->sqlite = ($config['driver'] ?? 'mysql') === 'sqlite';
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ];
        if ($this->sqlite) {
            $this->pdo = new PDO('sqlite:' . $config['path'], null, null, $options);
            $this->pdo->exec('PRAGMA journal_mode = WAL');
            $this->pdo->exec('PRAGMA busy_timeout = 5000');
        } else {
            $dsn = sprintf(
                'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                $config['host'] ?? 'localhost',
                (int)($config['port'] ?? 3306),
                $config['name'],
            );
            $this->pdo = new PDO($dsn, $config['user'], $config['password'], $options);
        }
    }

    /** Runs [sql] with [args]; the statement, to fetch from. */
    public function run(string $sql, array $args = []): PDOStatement
    {
        $st = $this->pdo->prepare(str_replace('{p}', $this->p, $sql));
        $st->execute($args);
        return $st;
    }

    public function one(string $sql, array $args = []): ?array
    {
        $row = $this->run($sql, $args)->fetch();
        return $row === false ? null : $row;
    }

    /** `INSERT IGNORE`, in this database's words. */
    public function insertIgnore(): string
    {
        return $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
    }

    public function transaction(callable $body): mixed
    {
        $this->pdo->beginTransaction();
        try {
            $result = $body();
            $this->pdo->commit();
            return $result;
        } catch (Throwable $e) {
            $this->pdo->rollBack();
            throw $e;
        }
    }

    /** Creates the tables, if they do not exist yet. */
    public function install(): void
    {
        $id = $this->sqlite
            ? 'INTEGER PRIMARY KEY AUTOINCREMENT'
            : 'BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY';
        $text = $this->sqlite ? 'TEXT' : 'MEDIUMTEXT';
        $engine = $this->sqlite ? '' : ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin';
        // Reading a family's events after a given number.
        $eventsKey = $this->sqlite ? '' : ',
                KEY {p}events_family (family_id, n)';
        $statements = [
            "CREATE TABLE IF NOT EXISTS {p}families (
                id VARCHAR(64) NOT NULL PRIMARY KEY,
                parent_key VARCHAR(64) NOT NULL,
                members_version BIGINT NOT NULL,
                members $text NOT NULL,
                members_sig VARCHAR(128) NOT NULL,
                invitation VARCHAR(100) NOT NULL,
                created_at BIGINT NOT NULL
            )$engine",
            "CREATE TABLE IF NOT EXISTS {p}devices (
                family_id VARCHAR(64) NOT NULL,
                device_id VARCHAR(64) NOT NULL,
                sign_key VARCHAR(64) NOT NULL,
                active SMALLINT NOT NULL,
                last_seen BIGINT NOT NULL,
                PRIMARY KEY (family_id, device_id)
            )$engine",
            "CREATE TABLE IF NOT EXISTS {p}events (
                n $id,
                family_id VARCHAR(64) NOT NULL,
                origin VARCHAR(100) NOT NULL,
                seq BIGINT NOT NULL,
                is_usage SMALLINT NOT NULL,
                received_at BIGINT NOT NULL,
                body $text NOT NULL,
                UNIQUE (family_id, origin, seq)$eventsKey
            )$engine",
            "CREATE TABLE IF NOT EXISTS {p}heads (
                family_id VARCHAR(64) NOT NULL,
                origin VARCHAR(100) NOT NULL,
                seq BIGINT NOT NULL,
                PRIMARY KEY (family_id, origin)
            )$engine",
            "CREATE TABLE IF NOT EXISTS {p}invitations (
                code_hash CHAR(64) NOT NULL PRIMARY KEY,
                label VARCHAR(100) NOT NULL,
                created_at BIGINT NOT NULL,
                expires_at BIGINT NOT NULL,
                used_by VARCHAR(64) NULL,
                used_at BIGINT NULL
            )$engine",
        ];
        foreach ($statements as $sql) {
            $this->run($sql);
        }
        if ($this->sqlite) {
            $this->run('CREATE INDEX IF NOT EXISTS {p}events_family ON {p}events (family_id, n)');
        }
    }

    /** Whether the tables exist. */
    public function installed(): bool
    {
        try {
            $this->run('SELECT 1 FROM {p}families LIMIT 1');
            return true;
        } catch (PDOException) {
            return false;
        }
    }
}

/** Milliseconds since the epoch. */
function now_ms(): int
{
    return (int)floor(microtime(true) * 1000);
}

/** The address of the server's folder, as this request reached it. */
function server_base(): string
{
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
    $dir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
    return ($https ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . $dir;
}

/** The configuration written by install.php, or `null`. */
function load_config(): ?array
{
    $file = __DIR__ . '/../config.php';
    if (!is_file($file)) {
        return null;
    }
    $config = require $file;
    return is_array($config) ? $config : null;
}
