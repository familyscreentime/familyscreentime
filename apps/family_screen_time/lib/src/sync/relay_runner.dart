/// Keeps a device in sync through the relay server the parent set up, for
/// as long as it is set up and the device holds the content key.
library;

import 'package:screentime_sync/screentime_sync.dart';

import 'family_sync.dart';

/// How often a device asks the relay, screen on and off.
const relayInterval = Duration(minutes: 1);
const relayIdleInterval = Duration(minutes: 5);

/// The server's `api.php` from what the parent typed: `https://` added
/// when missing, and `api.php` when the address is the server's folder.
/// `null` when it is not an address.
Uri? relayEndpoint(String typed) {
  var text = typed.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.hasAuthority ||
      !{'http', 'https'}.contains(uri.scheme)) {
    return null;
  }
  final folder = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.endsWith('.php') ? uri.path : '${folder}api.php',
  );
}

class RelayRunner {
  final FamilySync log;

  RelaySync? _sync;
  HttpRelayApi? _api;
  String? _url;
  bool _idle = false;

  RelayRunner(this.log);

  /// The relay sync running, if any.
  RelaySync? get sync => _sync;

  /// Starts, moves to another address, or stops, as the log now says; a
  /// pass soon when it runs already.
  Future<void> update() async {
    final url = log.relayUrl;
    final key = await log.contentKey();
    final endpoint = url == null ? null : Uri.tryParse(url);
    if (endpoint == null || key == null) {
      await stop();
      return;
    }
    if (url == _url && _sync != null) {
      _sync!.poke();
      return;
    }
    await stop();
    final familyId = log.node.root.familyId;
    final api = _api = HttpRelayApi(endpoint, familyId, log.node.me);
    _url = url;
    _sync = RelaySync(
      node: log.node,
      api: api,
      cipher: ContentCipher(key, familyId),
      members: () => log.members,
      save: (state) => log.saveRelayState(url, state),
      state: await log.loadRelayState(url!),
    )..start(interval: _idle ? relayIdleInterval : relayInterval);
  }

  /// Less often while the screen is off.
  set screenOn(bool on) {
    _idle = !on;
    _sync?.interval = on ? relayInterval : relayIdleInterval;
  }

  Future<void> stop() async {
    final sync = _sync;
    _sync = null;
    _url = null;
    await sync?.stop();
    _api?.close();
    _api = null;
  }
}
