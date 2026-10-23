/// DNS-SD on the local network through Bonsoir (Android NSD, Windows).
library;

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:screentime_sync/screentime_sync.dart';

class BonsoirDirectory implements LanDirectory {
  final _broadcasts = <String, BonsoirBroadcast>{};

  @override
  Future<void> advertise({
    required String type,
    required String name,
    required int port,
    required Map<String, String> attributes,
  }) async {
    await stopAdvertising(type);
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: name,
        type: type,
        port: port,
        attributes: attributes,
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcasts[type] = broadcast;
  }

  @override
  Future<void> stopAdvertising(String type) async {
    await _broadcasts.remove(type)?.stop();
  }

  @override
  Stream<LanService> discover(String type) {
    late final StreamController<LanService> out;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? events;
    out = StreamController<LanService>(
      onListen: () async {
        try {
          final d = discovery = BonsoirDiscovery(type: type);
          await d.initialize();
          events = d.eventStream?.listen((event) {
            switch (event) {
              case BonsoirDiscoveryServiceFoundEvent():
                event.service.resolve(d.serviceResolver);
              case BonsoirDiscoveryServiceResolvedEvent(:final service):
                _resolved(out, service);
              case BonsoirDiscoveryServiceUpdatedEvent(:final service):
                _resolved(out, service);
              case BonsoirDiscoveryServiceLostEvent():
                final s = event.service;
                out.add(
                  LanService(
                    name: s.name,
                    host: s.hostAddress ?? '',
                    port: s.port,
                    attributes: s.attributes,
                    lost: true,
                  ),
                );
              default:
            }
          });
          await d.start();
        } on Object catch (e) {
          out.addError(e);
        }
      },
      onCancel: () async {
        await events?.cancel();
        await discovery?.stop();
      },
    );
    return out.stream;
  }

  static void _resolved(StreamController<LanService> out, BonsoirService s) {
    final host = s.hostAddress ?? s.hostname;
    if (host == null) return;
    out.add(
      LanService(
        name: s.name,
        host: host,
        port: s.port,
        attributes: s.attributes,
      ),
    );
  }
}
