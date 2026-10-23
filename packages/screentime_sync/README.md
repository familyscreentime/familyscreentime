# screentime_sync

Synchronisation for Family Screen Time: the family's devices share one
signed event log and merge it into the same settings, over any channel.
Pure Dart (plus `dart:io` for the WebSocket transport); it depends on
[`cryptography`](https://pub.dev/packages/cryptography) and
[`sqlite3`](https://pub.dev/packages/sqlite3), whose build hook bundles
SQLite with the app (Android, Windows) and the tests.

## Model

| Part | What it does |
| --- | --- |
| `SyncEvent` | One change or record: device of origin, number (from 1, no gaps), hybrid logical clock, type, key, data, signer, Ed25519 signature. |
| `SyncStore` | The events a device holds and the merged entities, changed together. Its *vector* (last number held per origin) says what it has. `SqliteSyncStore` keeps them in one SQLite file (WAL), which a device's interface and background service open at once; `MemorySyncStore` is for tests. |
| Origins | A device records under several origins, each numbered on its own and signed with the device's key: `<device>` (background service), `<device>~ui` (interface), and `<device>#usage` / `<device>~ui#usage` for use of apps. Settings origins are kept whole and numbered without gaps; usage origins lose their old events (`prune`, after the 40 days the rules look at plus a week), so gaps are allowed there. |
| `MergedState` (`Replica` in memory) | The merge: `put` (whole entity: fields left out are cleared), `patch` (some fields; `null` clears), `delete`. The latest write wins, field by field; a removal wins over older writes, and only a later `put` brings an entity back. Any order of arrival gives the same result. |
| `diffEntities` | The events from one state of the entities to the next, so an app can keep its own model and emit what changed. |
| `HlcClock` | Hybrid logical clock: wall time when clocks agree, still ordered when they do not; a clock more than 24 h ahead is not followed. |

## Trust

- The family's root is the **parent key** (Ed25519). Its public half is
  given to every device when it joins; its private half is stored in the
  log sealed by the parent code (`ParentVault`: Argon2id, 19 MiB, 2 passes,
  then XChaCha20-Poly1305), so parent mode works offline on any device and
  a new code reaches every device.
- Each device has its own **signing key**, registered in the log by the
  parent (`device/<id>`: `signKey`, `name`, `role`, `childId`; `revoked`
  when removed).
- Events signed by the parent key are always accepted. A device's own
  signature is accepted only for what `SyncPolicy` allows (by default: its
  own usage, for its own child). Unknown, removed or tampered: refused.

## Sessions

- **Members** authenticate each other with their registered keys over an
  ephemeral X25519 exchange; session keys come from HKDF-SHA256 and
  messages are encrypted with ChaCha20-Poly1305. This replaces the pinned
  TLS certificate of the specification with the same guarantees, the same
  way on Android and Windows.
- **Pairing**: the joining device commits to its key first, then both
  screens show a 6-digit code derived from the exchange; the parent
  confirms it on both. A man in the middle has one chance in a million.
  The member device, in parent mode, then registers the newcomer and sends
  it the family root and the log.
- **Exchange** (`SyncSession`): each side sends its vector, receives what
  it lacks (oldest first), then new events flow both ways as they come,
  relayed to other devices. A gap triggers a new request.

`serveFrames` / `connectFrames` carry the frames over WebSockets on the
local network; other transports (the PHP server) plug into the same
`FrameChannel`.

## Local network

- `LanSync` listens on a free port, says on the network that the device is
  there (DNS-SD type `_fstime._tcp`, with a short tag of the family and the
  device id), finds the others and keeps one session open with each member
  device. When two devices connect to each other at once, both keep the
  session started by the smaller id. Devices seen but not connected are
  tried again every minute.
- `PairingHost` (a member in parent mode) advertises `_fstpair._tcp` with
  its name; `findPairingHosts` and `joinThrough` are the joining side.
- `LanDirectory` abstracts DNS-SD: the app uses Bonsoir (Android NSD,
  Windows); `MemoryLanDirectory` lets tests run several devices on the
  loopback interface.

## Tests

```
dart test
```
