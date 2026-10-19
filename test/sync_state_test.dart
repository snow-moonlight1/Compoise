import 'dart:convert';
import 'dart:math';

import 'package:compoise/sync/sync_clock.dart';
import 'package:compoise/sync/sync_json.dart';
import 'package:compoise/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

SyncState _randomState(Random random, int edits) {
  final state = SyncState();
  for (var i = 0; i < edits; i++) {
    final key = 't:${random.nextInt(6)}';
    final at = 1 + random.nextInt(40);
    if (random.nextInt(5) == 0) {
      state.tombstone(key, at);
    } else {
      final field = ['title', 'done', 'notes'][random.nextInt(3)];
      final value = random.nextBool() ? 'v${random.nextInt(4)}' : null;
      state.setField(key, field, value, at);
    }
  }
  return state;
}

String _canon(SyncState state) => canonicalJson(state.toJson());

void main() {
  group('HybridClock', () {
    test('ticks past wall time and past observed clocks', () {
      var wall = 1000;
      final clock = HybridClock(nowMs: () => wall);
      final first = clock.tick();
      expect(first, 1000 * clockCounterSpan);
      expect(clock.tick(), first + 1, reason: 'same millisecond');
      clock.observe(5000 * clockCounterSpan);
      expect(clock.tick(), 5000 * clockCounterSpan + 1);
      wall = 9000;
      expect(clock.tick(), 9000 * clockCounterSpan);
      expect(HybridClock.millisecondsOf(clock.last), 9000);
    });

    test('a wall clock that jumps back never reorders edits', () {
      var wall = 2000;
      final clock = HybridClock(nowMs: () => wall);
      final a = clock.tick();
      wall = 1000;
      expect(clock.tick(), greaterThan(a));
    });

    test('clock values stay JSON-safe for centuries', () {
      final year2200 = DateTime.utc(2200).millisecondsSinceEpoch;
      expect(year2200 * clockCounterSpan, lessThan(maxSyncClock));
      expect(isValidClock(maxSyncClock), isTrue);
      expect(isValidClock(maxSyncClock + 1), isFalse);
      expect(isValidClock(-1), isFalse);
      expect(isValidClock(1.5), isFalse);
    });
  });

  group('SyncRecord', () {
    test('later clock wins; equal clocks pick the same value everywhere', () {
      final a = SyncRecord()..offer('title', 'one', 5);
      expect(a.offer('title', 'old', 4), isFalse);
      expect(a.offer('title', 'two', 6), isTrue);
      final left = SyncRecord()
        ..offer('title', 'apple', 7)
        ..offer('title', 'banana', 7);
      final right = SyncRecord()
        ..offer('title', 'banana', 7)
        ..offer('title', 'apple', 7);
      expect(left.fields['title'], right.fields['title']);
    });

    test('null is a value: clearing a field wins when newer', () {
      final record = SyncRecord()..offer('deadline', 123, 1);
      expect(record.offer('deadline', null, 2), isTrue);
      expect(record.fields['deadline'], isNull);
      expect(record.fields.containsKey('deadline'), isTrue);
    });

    test('stored values are copies', () {
      final tags = ['a'];
      final record = SyncRecord()..offer('tags', tags, 1);
      tags.add('b');
      expect(record.fields['tags'], ['a']);
    });
  });

  group('SyncState merge', () {
    test('is commutative, associative and idempotent', () {
      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final a = _randomState(random, 12);
        final b = _randomState(random, 12);
        final c = _randomState(random, 12);
        final ab = a.copy()..mergeFrom(b);
        final ba = b.copy()..mergeFrom(a);
        expect(_canon(ab), _canon(ba), reason: 'commutative');
        final abC = ab.copy()..mergeFrom(c);
        final bc = b.copy()..mergeFrom(c);
        final aBc = a.copy()..mergeFrom(bc);
        expect(_canon(abC), _canon(aBc), reason: 'associative');
        final again = abC.copy()
          ..mergeFrom(c)
          ..mergeFrom(a);
        expect(_canon(again), _canon(abC), reason: 'idempotent');
        expect(abC.digest(), aBc.digest());
      }
    });

    test(
      'a record is alive only while it has an edit newer than its tombstone',
      () {
        final state = SyncState()
          ..setField('t:1', 'title', 'x', 10)
          ..tombstone('t:1', 12);
        expect(state.isAlive('t:1'), isFalse);
        state.setField('t:1', 'notes', 'kept', 15);
        expect(state.isAlive('t:1'), isTrue);
        state.tombstone('t:1', 11);
        expect(state.tombstones['t:1'], 12, reason: 'tombstones only advance');
      },
    );

    test('round-trips through JSON and rejects malformed files', () {
      final state = SyncState()
        ..setField('t:1', 'title', 'hello', 3)
        ..setField('t:1', 'tags', ['a', 'b'], 4)
        ..tombstone('t:2', 9);
      final decoded = SyncState.fromJson(
        jsonDecode(jsonEncode(state.toJson())),
      );
      expect(_canon(decoded), _canon(state));
      expect(decoded.clock, 9);

      Matcher rejects = throwsA(isA<SyncFormatException>());
      expect(() => SyncState.fromJson('x'), rejects);
      expect(
        () => SyncState.fromJson({'records': {}, 'tombstones': {}}),
        rejects,
      );
      expect(
        () => SyncState.fromJson({
          'clock': 1,
          'records': {
            't:1': {
              'f': {'title': 'x'},
              'c': {'title': -1},
            },
          },
          'tombstones': {},
        }),
        rejects,
      );
      expect(
        () => SyncState.fromJson({
          'clock': 1,
          'records': {
            't:1': {
              't': 1,
              'f': {'title': 'x'},
              'c': {'other': 2},
            },
          },
          'tombstones': {},
        }),
        rejects,
      );
      expect(
        () => SyncState.fromJson({
          'clock': 1,
          'records': {},
          'tombstones': {'t:1': 'soon'},
        }),
        rejects,
      );
    });

    test('records store one shared clock plus the exceptions', () {
      final state = SyncState()
        ..setField('t:1', 'title', 'a', 7)
        ..setField('t:1', 'done', false, 7)
        ..setField('t:1', 'notes', null, 9);
      final json = state.toJson()['records']['t:1'];
      expect(json, {
        't': 7,
        'f': {'done': false, 'notes': null, 'title': 'a'},
        'c': {'notes': 9},
      });
      final back = SyncState.fromJson(jsonDecode(state.encode()));
      expect(back.records['t:1']!.clocks, {'title': 7, 'done': 7, 'notes': 9});
      expect(back.records['t:1']!.fields.containsKey('notes'), isTrue);
    });

    test('digest ignores insertion order', () {
      final a = SyncState()
        ..setField('t:1', 'a', 1, 1)
        ..setField('t:2', 'b', 2, 2);
      final b = SyncState()
        ..setField('t:2', 'b', 2, 2)
        ..setField('t:1', 'a', 1, 1);
      expect(a.digest(), b.digest());
    });
  });

  group('prune', () {
    test('drops old deleted content but keeps the tombstone', () {
      final state = SyncState()
        ..setField('t:old', 'title', 'secret', 5)
        ..tombstone('t:old', 10)
        ..setField('t:new', 'title', 'recent', 50)
        ..tombstone('t:new', 60)
        ..setField('t:back', 'title', 'v1', 5)
        ..tombstone('t:back', 10)
        ..setField('t:back', 'notes', 'edited offline', 20);
      final removed = state.prune(30);
      expect(removed, 2);
      expect(state.records.containsKey('t:old'), isFalse);
      expect(state.tombstones['t:old'], 10);
      expect(state.records['t:new']!.fields['title'], 'recent');
      expect(state.records['t:back']!.fields.keys, ['notes']);
      expect(state.isAlive('t:back'), isTrue);

      // An older copy from another device comes back in; pruning removes it
      // again and the record stays deleted throughout.
      final peer = SyncState()..setField('t:old', 'title', 'secret', 5);
      state.mergeFrom(peer);
      expect(state.isAlive('t:old'), isFalse);
      state.prune(30);
      expect(state.records.containsKey('t:old'), isFalse);
    });
  });
}
