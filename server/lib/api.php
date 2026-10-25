<?php
/**
 * The relay's API. It keeps each family's log as the devices send it:
 * events encrypted end to end, which it cannot read, numbered in the
 * order received. Devices are known by their public keys, from a list
 * signed by the family's parent key.
 *
 * Requests: `api.php?r=<route>&…`, JSON bodies. Every request but `info`
 * is signed by a device (headers X-FST-Family, X-FST-Device, X-FST-Time,
 * X-FST-Signature), see `request_message()`.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/** 2: origins cut per child (0.25). */
const API_VERSION = 2;

/** How far a request's time may be from the server's. */
const CLOCK_WINDOW_MS = 15 * 60 * 1000;

/** Use of apps is kept 47 days (the 40 the rules look at, and a week). */
const USAGE_KEPT_MS = 47 * 24 * 3600 * 1000;

const MAX_BODY = 4 * 1024 * 1024;
const MAX_EVENTS = 500;
const PAGE = 500;

final class ApiError extends Exception
{
    public function __construct(public readonly int $status, public readonly string $error, string $message = '')
    {
        parent::__construct($message === '' ? $error : $message);
    }
}

/** What a device signs for each request. */
function request_message(string $method, string $query, string $family, string $device, string $time, string $body): string
{
    return implode("\n", ['fst-req-v1', $method, $query, $family, $device, $time, hash('sha256', $body)]);
}

/** What the parent key signs for the list of devices. */
function members_message(string $statement): string
{
    return "fst-members-v1\n" . $statement;
}

function b64d(string $s, int $length): string
{
    $raw = base64_decode($s, true);
    if ($raw === false || strlen($raw) !== $length) {
        throw new ApiError(400, 'bad_encoding');
    }
    return $raw;
}

function verify(string $message, string $sigB64, string $keyB64): bool
{
    try {
        return sodium_crypto_sign_verify_detached(b64d($sigB64, 64), $message, b64d($keyB64, 32));
    } catch (ApiError) {
        return false;
    }
}

function valid_id(mixed $id): bool
{
    return is_string($id) && preg_match('/^[A-Za-z0-9_-]{1,64}$/', $id) === 1;
}

/**
 * The device behind an origin: `<device>`, `<device>~ui`, then `@` and the
 * child its events concern (nothing: the whole family), then `#usage`.
 */
function device_of_origin(string $origin): string
{
    return preg_split('/[~#@]/', $origin, 2)[0];
}

/**
 * The child an origin's events concern (or `_parents`); '' for the whole
 * family; `null` for an origin from before 0.25, which mixes everything.
 */
function scope_of_origin(string $origin): ?string
{
    $at = strpos($origin, '@');
    if ($at === false) {
        return null;
    }
    $rest = substr($origin, $at + 1);
    $hash = strpos($rest, '#');
    return $hash === false ? $rest : substr($rest, 0, $hash);
}

function valid_origin(mixed $o): bool
{
    if (!is_string($o) || strlen($o) > 100 || !valid_id(device_of_origin($o))) {
        return false;
    }
    $scope = scope_of_origin($o);
    return $scope === null || $scope === '' || valid_id($scope);
}

/**
 * Whether a device receiving [scope] (`*`: everything; a child's id: the
 * family's and that child's; '': the family's only) gets [origin]'s
 * events. The relay cannot read them: use of apps from before 0.25 goes by
 * the device that recorded it ([scopes]: each device's scope).
 */
function relay_allows(string $scope, string $origin, array $scopes): bool
{
    if ($scope === '*') {
        return true;
    }
    $s = scope_of_origin($origin);
    if ($s !== null) {
        return $s === '' || $s === $scope;
    }
    if (!is_usage_origin($origin)) {
        return true;
    }
    return $scope !== '' && ($scopes[device_of_origin($origin)] ?? null) === $scope;
}

function is_usage_origin(string $origin): bool
{
    return str_ends_with($origin, '#usage');
}

/**
 * Checks a signed list of devices: `{familyId, version, devices: {id:
 * signKey}, scopes: {id: scope}, floors: {origin: seq}}` as canonical
 * JSON, signed by [parentKey]. Returns it decoded. A device without a
 * scope receives everything; floors say which events from before 0.25 a
 * snapshot replaced (they are forgotten).
 */
function check_members(array $members, string $familyId, string $parentKey): array
{
    $statement = $members['statement'] ?? null;
    $sig = $members['sig'] ?? null;
    if (!is_string($statement) || !is_string($sig) || strlen($statement) > 200000) {
        throw new ApiError(400, 'bad_members');
    }
    if (!verify(members_message($statement), $sig, $parentKey)) {
        throw new ApiError(403, 'bad_members_signature');
    }
    $list = json_decode($statement, true);
    if (!is_array($list) || ($list['familyId'] ?? null) !== $familyId
        || !is_int($list['version'] ?? null) || !is_array($list['devices'] ?? null)) {
        throw new ApiError(400, 'bad_members');
    }
    foreach ($list['devices'] as $id => $key) {
        if (!valid_id((string)$id) || !is_string($key)) {
            throw new ApiError(400, 'bad_members');
        }
        b64d($key, 32);
    }
    $scopes = $list['scopes'] ?? [];
    $floors = $list['floors'] ?? [];
    if (!is_array($scopes) || !is_array($floors)) {
        throw new ApiError(400, 'bad_members');
    }
    foreach ($scopes as $id => $scope) {
        if (!valid_id((string)$id) || !is_string($scope) || ($scope !== '*' && $scope !== '' && !valid_id($scope))) {
            throw new ApiError(400, 'bad_members');
        }
    }
    foreach ($floors as $origin => $seq) {
        $origin = (string)$origin;
        if (!valid_origin($origin) || scope_of_origin($origin) !== null || is_usage_origin($origin) || !is_int($seq)) {
            throw new ApiError(400, 'bad_members');
        }
    }
    return $list;
}

/** Each device's scope, from the family's list ([check_members]). */
function member_scopes(?string $statement): array
{
    $list = json_decode((string)$statement, true);
    $scopes = is_array($list) ? ($list['scopes'] ?? []) : [];
    return is_array($scopes) ? $scopes : [];
}

/** Forgets the events a snapshot replaced (see [check_members]). */
function forget_replaced(Db $db, string $familyId, array $list): void
{
    foreach ($list['floors'] ?? [] as $origin => $seq) {
        $db->run('DELETE FROM {p}events WHERE family_id = ? AND origin = ? AND seq <= ?', [$familyId, (string)$origin, $seq]);
    }
}

/** Saves the list of devices allowed in [familyId]. */
function save_members(Db $db, string $familyId, array $list): void
{
    $db->run('UPDATE {p}devices SET active = 0 WHERE family_id = ?', [$familyId]);
    foreach ($list['devices'] as $id => $key) {
        $id = (string)$id;
        $found = $db->one('SELECT device_id FROM {p}devices WHERE family_id = ? AND device_id = ?', [$familyId, $id]);
        if ($found) {
            $db->run('UPDATE {p}devices SET sign_key = ?, active = 1 WHERE family_id = ? AND device_id = ?', [$key, $familyId, $id]);
        } else {
            $db->run('INSERT INTO {p}devices (family_id, device_id, sign_key, active, last_seen) VALUES (?, ?, ?, 1, 0)', [$familyId, $id, $key]);
        }
    }
}

final class Api
{
    private ?string $family = null;
    private ?string $device = null;

    public function __construct(private readonly Db $db)
    {
    }

    /**
     * Handles one request; returns [status, body].
     * [headers]: the X-FST-* headers, lower-cased names.
     */
    public function handle(string $method, string $query, array $headers, string $body): array
    {
        try {
            parse_str($query, $q);
            $route = $q['r'] ?? '';
            if ($route === 'info') {
                return [200, ['server' => 'family-screen-time', 'api' => API_VERSION, 'time' => now_ms()]];
            }
            if (strlen($body) > MAX_BODY) {
                throw new ApiError(413, 'too_large');
            }
            $json = $body === '' ? [] : json_decode($body, true);
            if (!is_array($json)) {
                throw new ApiError(400, 'bad_json');
            }
            $creating = $route === 'family' && $method === 'POST';
            $this->authenticate($method, $query, $headers, $body, $creating, $json);
            return [200, match ([$method, $route]) {
                ['POST', 'family'] => $this->createFamily($json),
                ['POST', 'members'] => $this->members($json),
                ['GET', 'heads'] => $this->heads(),
                ['POST', 'events'] => $this->putEvents($json),
                ['GET', 'events'] => $this->getEvents((int)($q['after'] ?? 0), (int)($q['limit'] ?? PAGE)),
                default => throw new ApiError(404, 'no_route'),
            }];
        } catch (ApiError $e) {
            return [$e->status, ['error' => $e->error, 'message' => $e->getMessage(), 'time' => now_ms()]];
        }
    }

    private function authenticate(string $method, string $query, array $h, string $body, bool $creating, array $json): void
    {
        $family = $h['x-fst-family'] ?? '';
        $device = $h['x-fst-device'] ?? '';
        $time = $h['x-fst-time'] ?? '';
        $sig = $h['x-fst-signature'] ?? '';
        if (!valid_id($family) || !valid_id($device) || !ctype_digit($time) || $sig === '') {
            throw new ApiError(401, 'unsigned');
        }
        if (abs((int)$time - now_ms()) > CLOCK_WINDOW_MS) {
            throw new ApiError(401, 'clock', 'The device clock is too far from the server\'s');
        }
        $message = request_message($method, $query, $family, $device, $time, $body);
        if ($creating) {
            // Not known yet: the key is the one in the list sent.
            $statement = json_decode((string)($json['members']['statement'] ?? ''), true);
            $key = $statement['devices'][$device] ?? null;
        } else {
            $row = $this->db->one('SELECT sign_key FROM {p}devices WHERE family_id = ? AND device_id = ? AND active = 1', [$family, $device]);
            $key = $row['sign_key'] ?? null;
        }
        if (!is_string($key) || !verify($message, $sig, $key)) {
            throw new ApiError(401, 'unknown_device');
        }
        $this->family = $family;
        $this->device = $device;
        if (!$creating) {
            $this->db->run('UPDATE {p}devices SET last_seen = ? WHERE family_id = ? AND device_id = ?', [now_ms(), $family, $device]);
        }
    }

    /** A family's first device registers it, with an invitation. */
    private function createFamily(array $json): array
    {
        $code = $json['invitation'] ?? null;
        $parentKey = $json['parentKey'] ?? null;
        if (!is_string($code) || !is_string($parentKey)) {
            throw new ApiError(400, 'bad_request');
        }
        b64d($parentKey, 32);
        $list = check_members($json['members'] ?? [], $this->family, $parentKey);
        return $this->db->transaction(function () use ($code, $parentKey, $list, $json) {
            $existing = $this->db->one('SELECT parent_key FROM {p}families WHERE id = ?', [$this->family]);
            if ($existing) {
                // Registered already, from another device: nothing to do.
                if ($existing['parent_key'] !== $parentKey) {
                    throw new ApiError(409, 'family_exists');
                }
                return ['created' => false];
            }
            $hash = hash('sha256', strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code)));
            $inv = $this->db->one('SELECT expires_at, used_by FROM {p}invitations WHERE code_hash = ?', [$hash]);
            if (!$inv || $inv['used_by'] !== null || (int)$inv['expires_at'] < now_ms()) {
                throw new ApiError(403, 'bad_invitation', 'Unknown, used or expired invitation');
            }
            $now = now_ms();
            $this->db->run('UPDATE {p}invitations SET used_by = ?, used_at = ? WHERE code_hash = ?', [$this->family, $now, $hash]);
            $this->db->run(
                'INSERT INTO {p}families (id, parent_key, members_version, members, members_sig, invitation, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$this->family, $parentKey, $list['version'], $json['members']['statement'], $json['members']['sig'], $hash, $now],
            );
            save_members($this->db, $this->family, $list);
            forget_replaced($this->db, $this->family, $list);
            $this->db->run('UPDATE {p}devices SET last_seen = ? WHERE family_id = ? AND device_id = ?', [$now, $this->family, $this->device]);
            return ['created' => true];
        });
    }

    /** A newer list of the family's devices. */
    private function members(array $json): array
    {
        $family = $this->familyRow();
        $list = check_members($json, $this->family, $family['parent_key']);
        if ($list['version'] <= (int)$family['members_version']) {
            return ['version' => (int)$family['members_version'], 'updated' => false];
        }
        $this->db->transaction(function () use ($json, $list) {
            $this->db->run(
                'UPDATE {p}families SET members_version = ?, members = ?, members_sig = ? WHERE id = ?',
                [$list['version'], $json['statement'], $json['sig'], $this->family],
            );
            save_members($this->db, $this->family, $list);
            forget_replaced($this->db, $this->family, $list);
        });
        return ['version' => $list['version'], 'updated' => true];
    }

    /** The last number held for each origin, and the devices' last contact. */
    private function heads(): array
    {
        $family = $this->familyRow();
        $heads = [];
        foreach ($this->db->run('SELECT origin, seq FROM {p}heads WHERE family_id = ?', [$this->family]) as $row) {
            $heads[$row['origin']] = (int)$row['seq'];
        }
        $seen = [];
        foreach ($this->db->run('SELECT device_id, last_seen FROM {p}devices WHERE family_id = ? AND active = 1', [$this->family]) as $row) {
            $seen[$row['device_id']] = (int)$row['last_seen'];
        }
        $last = $this->db->one('SELECT MAX(n) AS n FROM {p}events WHERE family_id = ?', [$this->family]);
        return [
            'heads' => (object)$heads,
            'members' => (int)$family['members_version'],
            'seen' => (object)$seen,
            'last' => (int)($last['n'] ?? 0),
            'time' => now_ms(),
        ];
    }

    /**
     * Stores events, each `{o: origin, s: seq, b: encrypted body}`. Settings
     * come without gaps: an event that does not follow the last one held
     * for its origin is refused (use of apps may have gaps).
     */
    private function putEvents(array $json): array
    {
        $family = $this->familyRow();
        $scopes = member_scopes($family['members']);
        $scope = $scopes[$this->device] ?? '*';
        $events = $json['events'] ?? null;
        if (!is_array($events) || count($events) > MAX_EVENTS) {
            throw new ApiError(400, 'bad_events');
        }
        return $this->db->transaction(function () use ($events, $scopes, $scope) {
            $heads = [];
            foreach ($this->db->run('SELECT origin, seq FROM {p}heads WHERE family_id = ?', [$this->family]) as $row) {
                $heads[$row['origin']] = (int)$row['seq'];
            }
            $now = now_ms();
            $stored = 0;
            $refused = [];
            $changed = [];
            foreach ($events as $e) {
                $o = $e['o'] ?? null;
                $s = $e['s'] ?? null;
                $b = $e['b'] ?? null;
                if (!valid_origin($o) || !is_int($s) || $s < 1 || !is_string($b) || strlen($b) > 200000) {
                    throw new ApiError(400, 'bad_event');
                }
                // A child's device passes on another child's events: not its to send.
                if (device_of_origin($o) !== $this->device && !relay_allows($scope, $o, $scopes)) {
                    throw new ApiError(403, 'not_allowed');
                }
                $head = $heads[$o] ?? 0;
                if ($s <= $head) {
                    continue; // Held already.
                }
                $usage = is_usage_origin($o);
                if (!$usage && $s !== $head + 1) {
                    $refused[] = ['o' => $o, 's' => $s, 'head' => $head];
                    continue;
                }
                $this->db->run(
                    $this->db->insertIgnore() . ' INTO {p}events (family_id, origin, seq, is_usage, received_at, body) VALUES (?, ?, ?, ?, ?, ?)',
                    [$this->family, $o, $s, $usage ? 1 : 0, $now, $b],
                );
                $heads[$o] = $s;
                $changed[$o] = $s;
                $stored++;
            }
            foreach ($changed as $o => $s) {
                $found = $this->db->one('SELECT seq FROM {p}heads WHERE family_id = ? AND origin = ?', [$this->family, $o]);
                if ($found) {
                    $this->db->run('UPDATE {p}heads SET seq = ? WHERE family_id = ? AND origin = ?', [$s, $this->family, $o]);
                } else {
                    $this->db->run('INSERT INTO {p}heads (family_id, origin, seq) VALUES (?, ?, ?)', [$this->family, $o, $s]);
                }
            }
            $this->prune($now);
            return ['stored' => $stored, 'refused' => $refused];
        });
    }

    /**
     * Events received after number [after], in the order received: those
     * the device receives (see [relay_allows]).
     */
    private function getEvents(int $after, int $limit): array
    {
        $family = $this->familyRow();
        $scopes = member_scopes($family['members']);
        $scope = $scopes[$this->device] ?? '*';
        $limit = max(1, min(PAGE, $limit));
        $rows = $this->db->run(
            'SELECT n, origin, seq, body FROM {p}events WHERE family_id = ? AND n > ? ORDER BY n LIMIT ' . ($limit + 1),
            [$this->family, $after],
        )->fetchAll();
        $more = count($rows) > $limit;
        $rows = array_slice($rows, 0, $limit);
        $events = [];
        foreach ($rows as $r) {
            if (relay_allows($scope, $r['origin'], $scopes)) {
                $events[] = ['n' => (int)$r['n'], 'o' => $r['origin'], 's' => (int)$r['seq'], 'b' => $r['body']];
            }
        }
        // Past what was left out too.
        $next = $rows ? (int)end($rows)['n'] : $after;
        return ['events' => $events, 'next' => $next, 'more' => $more];
    }

    /** Forgets use of apps older than [USAGE_KEPT_MS], a batch at a time. */
    private function prune(int $now): void
    {
        $before = $now - USAGE_KEPT_MS;
        if ($this->db->sqlite) {
            $this->db->run(
                'DELETE FROM {p}events WHERE n IN (SELECT n FROM {p}events WHERE family_id = ? AND is_usage = 1 AND received_at < ? LIMIT 1000)',
                [$this->family, $before],
            );
        } else {
            $this->db->run(
                'DELETE FROM {p}events WHERE family_id = ? AND is_usage = 1 AND received_at < ? LIMIT 1000',
                [$this->family, $before],
            );
        }
    }

    private function familyRow(): array
    {
        $row = $this->db->one('SELECT parent_key, members_version, members FROM {p}families WHERE id = ?', [$this->family]);
        if (!$row) {
            throw new ApiError(404, 'no_family');
        }
        return $row;
    }
}
