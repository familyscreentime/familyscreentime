# Family Screen Time relay server

Linked devices sync directly over the home Wi-Fi. With this server, they
also sync away from home: each device sends it the events the others lack
and takes those it received since it last asked.

The server cannot read what it relays. Every event is encrypted end to end
with a key only the devices hold (XChaCha20-Poly1305). The server only sees
random device ids, numbers and times. Devices are let in by their public
keys, from a list signed by the parent key, and each request is signed by
the device that makes it.

## Requirements

- PHP 8.2 or later with the `sodium` extension (bundled with PHP).
- MySQL 8 or MariaDB 10.6 or later, with PDO MySQL. SQLite (PDO SQLite) also
  works for light use.
- HTTPS. Plain HTTP works on a local network; the events stay encrypted, but
  the requests' metadata does not.

Any ordinary shared hosting is enough: no shell, no cron job, no rewrite
rules.

## Installing

1. Create a database and a database user on your hosting.
2. Copy this folder (for example as `fst/`) into your web space.
3. Open `https://your.site/fst/install.php`. It checks PHP, asks for the
   database and an administration password (12 characters at least), writes
   `config.php` and creates the tables. It shows the address to enter in the
   app: `https://your.site/fst/api.php`.
4. Delete `install.php`. It refuses to run once `config.php` exists, but it
   is better gone.
5. Open `admin.php` and create an invitation for each family.

On Apache, `lib/` and `data/` are closed by their `.htaccess`. On nginx,
deny them in the site's configuration:

```nginx
location ~ ^/fst/(lib|data)/ { deny all; }
```

## In the app

In parent mode, on a linked device: Linked devices › Server › Set up. Enter
the address and the invitation code. The other linked devices learn of the
server the next time they sync over the Wi-Fi, and use it from then on.

Devices linked before version 0.23 get the server's key when the parent
code is next entered on them.

## Updating

Replace the folder's files with the new version's, keeping `config.php` and
`data/`. The tables do not change.

Version 0.25 of the app needs this version of the server (API 2): update the
server first.

## Administration

The home page (`index.php`) shows the address to enter in the app.
`admin.php`, behind the administration password:

- invitations: one per family (not per child or device), used once by the
  first device that sets the server up, valid 1 to 90 days, with a note for
  the administrator only;
- families, with their invitation's note: devices, last contact, number and
  size of events; for each device, what it receives and its last contact;
  deleting a family deletes all its events.

Use of apps is kept 47 days, then deleted. Settings are kept as long as the
family exists.

With a shell, `php lib/cli.php invite "label" 7` prints an invitation code.

## API

`api.php?r=<route>`, JSON. Every route but `info` is signed: headers
`X-FST-Family`, `X-FST-Device`, `X-FST-Time` (milliseconds) and
`X-FST-Signature`, the device's Ed25519 signature of

```
fst-req-v1\n<method>\n<query string>\n<family>\n<device>\n<time>\n<hex SHA-256 of the body>
```

The time must be within 15 minutes of the server's; the server's time is
in the `X-FST-Server-Time` header of every answer.

| Method | Route | Body / query | Answer |
|---|---|---|---|
| GET | `info` | | `{server, api, time}` |
| POST | `family` | `{invitation, parentKey, members}` | `{created}` |
| POST | `members` | `{statement, sig}` | `{version, updated}` |
| GET | `heads` | | `{heads: {origin: seq}, members, seen: {device: ms}, last}` |
| POST | `events` | `{events: [{o, s, b}]}` (500 at most) | `{stored, refused: [{o, s, head}]}` |
| GET | `events` | `after`, `limit` (500 at most) | `{events: [{n, o, s, b}], next, more}` |

`members` is a list of devices signed by the parent key: `statement` is the
canonical JSON of `{familyId, version, devices: {id: signKey}, scopes: {id:
scope}, floors: {origin: seq}}`, `sig` the Ed25519 signature of
`fst-members-v1\n<statement>`. A later version replaces the list.

Each child's data goes only to that child's devices and the parents'.
Origins say what their events concern: `<device>[~<process>]@<scope>[#usage]`,
where the scope is a child's id, `_parents`, or empty for the whole family;
origins without `@` come from apps before 0.25. A device's scope is `*`
(everything: a parent's device), a child's id (the family's and that
child's), or empty (the family's only); a device without one receives
everything. `GET events` leaves out what the device does not receive (and
`next` still moves past it); `POST events` refuses (403 `not_allowed`)
another device's events the sender does not receive. `floors` name the
events from before 0.25 that a snapshot replaced: the server deletes them.

Events come in order: for each origin, an event must follow the last one
held, or it is refused (use of apps, whose old events are deleted, may have
gaps). `b` is the encrypted event: base64 of nonce (24 bytes), ciphertext and
tag, with `fst-relay-v1|<family>|<origin>|<seq>` as associated data.

Errors: `{error, message, time}` with an HTTP status: `unsigned`, `clock`,
`unknown_device` (401), `bad_invitation`, `bad_members_signature`,
`not_allowed` (403), `no_family`, `no_route` (404), `family_exists` (409),
`too_large` (413).
