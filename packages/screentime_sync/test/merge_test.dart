import 'dart:io';

import 'package:screentime_sync/screentime_sync.dart';
import 'package:test/test.dart';

SyncEvent ev(
  String type,
  String key,
  Map<String, Object?> data, {
  required int at,
  String node = 'a',
  int seq = 1,
}) => SyncEvent(
  origin: node,
  seq: seq,
  hlc: Hlc(at, 0, node),
  type: type,
  key: key,
  data: data,
  signer: Signer.parent,
  sig: '',
);

void main() {
  group('canonical JSON', () {
    test('sorts keys at every level, whatever the build order', () {
      expect(
        canonicalJson({
          'b': 1,
          'a': [
            {'z': true, 'y': null},
          ],
        }),
        '{"a":[{"y":null,"z":true}],"b":1}',
      );
      expect(sameJson({'x': 1, 'y': 2}, {'y': 2, 'x': 1}), isTrue);
    });

    test('a whole number signs the same, read back as double or int', () {
      expect(canonicalJson(3.0), canonicalJson(3));
      expect(canonicalJson(2.5), '2.5');
    });
  });

  group('hybrid logical clock', () {
    test('moves on even when the wall clock stands still', () {
      final c = HlcClock('a');
      final wall = DateTime.utc(2026, 10, 23, 9);
      final first = c.now(wall);
      final second = c.now(wall);
      expect(second > first, isTrue);
      expect(Hlc.parse(second.pack()), second);
    });

    test('orders after what it received, a device behind or not', () {
      final c = HlcClock('a');
      final wall = DateTime.utc(2026, 10, 23, 9);
      final remote = Hlc(wall.millisecondsSinceEpoch + 5000, 3, 'b');
      c.receive(remote, wall);
      expect(c.now(wall) > remote, isTrue);
    });

    test('a device set far in the future does not drag the clock', () {
      final c = HlcClock('a');
      final wall = DateTime.utc(2026, 10, 23, 9);
      c.receive(Hlc(DateTime.utc(2027).millisecondsSinceEpoch, 0, 'b'), wall);
      expect(c.now(wall).millis, wall.millisecondsSinceEpoch);
    });

    test('device ids with colons or dashes survive the text form', () {
      const h = Hlc(12, 1, 'e1d2-3:4');
      expect(Hlc.parse(h.pack()), h);
    });
  });

  group('merge', () {
    test('the last change wins, field by field', () {
      final r = Replica();
      r.apply(ev('put', 'rule/1', {'quota': 30, 'grace': 5}, at: 1));
      // Two devices change different fields at about the same time.
      r.apply(ev('patch', 'rule/1', {'grace': 10}, at: 3, node: 'b'));
      r.apply(ev('patch', 'rule/1', {'quota': 45}, at: 2, node: 'c'));
      expect(r['rule/1'], {'quota': 45, 'grace': 10});
    });

    test('order of arrival does not matter', () {
      final events = [
        ev('put', 'rule/1', {'quota': 30, 'grace': 5}, at: 1),
        ev('patch', 'rule/1', {'quota': 45}, at: 2, node: 'b'),
        ev('patch', 'rule/1', {'quota': 60}, at: 4, node: 'c'),
        ev('delete', 'rule/2', {}, at: 5),
        ev('put', 'rule/2', {'quota': 10}, at: 3, node: 'b'),
      ];
      final forward = Replica();
      final backward = Replica();
      events.forEach(forward.apply);
      events.reversed.forEach(backward.apply);
      expect(forward.entities, backward.entities);
      expect(forward.entities, {
        'rule/1': {'quota': 60, 'grace': 5},
      });
    });

    test('a removal wins over older changes, not over a later re-creation', () {
      final r = Replica();
      r.apply(ev('put', 'bonus/1', {'min': 15}, at: 1));
      r.apply(ev('patch', 'bonus/1', {'min': 20}, at: 2, node: 'b'));
      r.apply(ev('delete', 'bonus/1', {}, at: 3));
      expect(r['bonus/1'], isNull);
      // A change alone does not bring it back…
      r.apply(ev('patch', 'bonus/1', {'min': 25}, at: 4, node: 'b'));
      expect(r['bonus/1'], isNull);
      // …a new whole entity does.
      r.apply(ev('put', 'bonus/1', {'min': 30}, at: 5));
      expect(r['bonus/1'], {'min': 30});
    });

    test('a whole entity clears the fields it leaves out', () {
      final r = Replica();
      r.apply(ev('put', 'rule/1', {'quota': 30, 'grace': 5}, at: 1));
      r.apply(ev('put', 'rule/1', {'quota': 30}, at: 2));
      expect(r['rule/1'], {'quota': 30});
    });

    test('survives a round trip through JSON', () {
      final r = Replica();
      r.apply(ev('put', 'rule/1', {'quota': 30}, at: 1));
      r.apply(ev('delete', 'rule/2', {}, at: 2));
      final back = Replica.fromJson(r.toJson());
      expect(back.entities, r.entities);
      back.apply(ev('put', 'rule/2', {'quota': 1}, at: 1));
      expect(back['rule/2'], isNull);
    });

    test('diff gives the events from one state to the next', () {
      final drafts = diffEntities(
        {
          'rule/1': {'quota': 30, 'grace': 5},
          'rule/2': {'quota': 10},
        },
        {
          'rule/1': {'quota': 45, 'grace': 5},
          'rule/3': {'quota': 20},
        },
      );
      expect(drafts.map((d) => d.toString()), [
        'patch rule/1 {"quota":45}',
        'put rule/3 {"quota":20}',
        'delete rule/2 {}',
      ]);
      expect(
        diffEntities(
          {
            'r': {'a': 1, 'b': 2},
          },
          {
            'r': {'a': 1},
          },
        ).single.data,
        {'b': null},
      );
    });
  });

  for (final (name, make) in [
    ('memory', MemorySyncStore.new),
    ('SQLite', SqliteSyncStore.inMemory),
  ]) {
    group('store ($name)', () {
      test('numbers events per device without gaps', () {
        final store = make();
        store.add(ev('put', 'x', {}, at: 1));
        expect(
          () => store.add(ev('put', 'x', {}, at: 2, seq: 3)),
          throwsStateError,
        );
        store.add(ev('put', 'y', {}, at: 1, node: 'b'));
        expect(store.vector, {'a': 1, 'b': 1});
        expect(store.missingFor({'a': 1}).single.origin, 'b');
        expect(store.merged['x'], <String, Object?>{});
      });

      test('use of apps may have gaps, and old use goes', () {
        final store = make();
        SyncEvent usage(int seq, int end) => SyncEvent(
          origin: 'a#usage',
          seq: seq,
          hlc: Hlc(end, 0, 'a'),
          type: 'usage',
          key: 'usage',
          data: {'end': end},
          signer: Signer.device,
          sig: '',
        );
        store.add(usage(1, 100));
        store.add(usage(4, 400));
        expect(store.accepts(usage(3, 300)), isFalse);
        expect(store.prune(DateTime.fromMillisecondsSinceEpoch(200)), 1);
        expect(store.vector, {'a#usage': 4});
        expect(store.missingFor(const {}).single.seq, 4);
      });

      test('pages through what a peer lacks, oldest first', () {
        final store = make();
        for (var i = 1; i <= 7; i++) {
          store.add(ev('put', 'k$i', {}, at: 10 - i, seq: i));
        }
        final pages = store.pagesFor(const {}, page: 3).toList();
        expect(pages.map((p) => p.length), [3, 3, 1]);
        expect(pages.expand((p) => p).map((e) => e.seq), [7, 6, 5, 4, 3, 2, 1]);
      });
    });
  }

  test('two connections to one SQLite file see each other', () async {
    final dir = await Directory.systemTemp.createTemp('fst-db');
    addTearDown(() => dir.delete(recursive: true));
    final a = SqliteSyncStore.open('${dir.path}/family.db');
    final b = SqliteSyncStore.open('${dir.path}/family.db');
    addTearDown(a.close);
    addTearDown(b.close);
    a.add(ev('put', 'rule/1', {'quota': 30}, at: 1));
    expect(b.merged['rule/1'], {'quota': 30});
    expect(b.addedElsewhere().single.key, 'rule/1');
    expect(b.addedElsewhere(), isEmpty);
    b.add(ev('put', 'rule/2', {}, at: 2, node: 'b'));
    expect(b.addedElsewhere(), isEmpty);
    expect(a.addedElsewhere().single.origin, 'b');
    // Both may try to add the same event: only one does.
    final e = ev('put', 'rule/3', {}, at: 3, node: 'c');
    a.add(e);
    expect(b.accepts(e), isFalse);
  });
}
