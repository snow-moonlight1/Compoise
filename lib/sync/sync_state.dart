/// Mergeable sync state: per-field last-writer-wins records plus tombstones.
///
/// Merging is commutative, associative and idempotent, so devices that
/// exchange their states in any order and any number of times end up with
/// the same result. A field keeps the value with the larger clock; equal
/// clocks fall back to comparing the canonical JSON of the two values, so the
/// winner never depends on which device runs the merge.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'sync_clock.dart';
import 'sync_json.dart';

class SyncFormatException implements Exception {
  const SyncFormatException(this.message);

  final String message;

  @override
  String toString() => 'SyncFormatException: $message';
}

const int _maxKeyLength = 2048;

class SyncRecord {
  SyncRecord({Map<String, Object?>? fields, Map<String, int>? clocks})
    : fields = fields ?? <String, Object?>{},
      clocks = clocks ?? <String, int>{};

  final Map<String, Object?> fields;
  final Map<String, int> clocks;

  int get maxClock {
    var max = 0;
    for (final clock in clocks.values) {
      if (clock > max) max = clock;
    }
    return max;
  }

  SyncRecord copy() => SyncRecord(
    fields: {
      for (final entry in fields.entries) entry.key: jsonCopy(entry.value),
    },
    clocks: Map<String, int>.of(clocks),
  );

  /// Writes [value] when [clock] beats the current clock of [field].
  bool offer(String field, Object? value, int clock) {
    final current = clocks[field];
    if (current != null) {
      if (clock < current) return false;
      if (clock == current) {
        final mine = canonicalJson(fields[field]);
        final theirs = canonicalJson(value);
        if (theirs.compareTo(mine) <= 0) return false;
      }
    }
    fields[field] = jsonCopy(value);
    clocks[field] = clock;
    return true;
  }

  /// The most common clock, stored once per record; only fields edited at
  /// another time carry their own clock. Fields are sorted, so the same
  /// record always encodes to the same bytes.
  Map<String, dynamic> toJson() {
    final counts = <int, int>{};
    for (final clock in clocks.values) {
      counts[clock] = (counts[clock] ?? 0) + 1;
    }
    var base = 0;
    var best = -1;
    for (final entry in counts.entries) {
      if (entry.value > best || (entry.value == best && entry.key > base)) {
        base = entry.key;
        best = entry.value;
      }
    }
    final names = clocks.keys.toList()..sort();
    final own = <String, int>{
      for (final name in names)
        if (clocks[name] != base) name: clocks[name]!,
    };
    return {
      't': base,
      'f': {for (final name in names) name: fields[name]},
      if (own.isNotEmpty) 'c': own,
    };
  }
}

class SyncState {
  SyncState({
    Map<String, SyncRecord>? records,
    Map<String, int>? tombstones,
    this.clock = 0,
  }) : records = records ?? <String, SyncRecord>{},
       tombstones = tombstones ?? <String, int>{};

  final Map<String, SyncRecord> records;
  final Map<String, int> tombstones;

  /// Largest clock contained in this state.
  int clock;

  bool get isEmpty => records.isEmpty && tombstones.isEmpty;

  /// A record is alive unless a tombstone is at least as new as every field.
  bool isAlive(String key) {
    final record = records[key];
    if (record == null) return false;
    final deletedAt = tombstones[key];
    return deletedAt == null || record.maxClock > deletedAt;
  }

  Iterable<String> get aliveKeys => records.keys.where(isAlive);

  void setField(String key, String field, Object? value, int at) {
    (records[key] ??= SyncRecord()).offer(field, value, at);
    if (at > clock) clock = at;
  }

  void tombstone(String key, int at) {
    final current = tombstones[key];
    if (current == null || at > current) tombstones[key] = at;
    if (at > clock) clock = at;
  }

  /// Drops the content of records deleted before [horizon] and returns how
  /// many fields went. Their tombstones stay, so the deletion still wins over
  /// any older copy another device uploads; that copy is pruned again here on
  /// the next round. Only a field written after the deletion survives.
  int prune(int horizon) {
    var removed = 0;
    for (final entry in tombstones.entries) {
      if (entry.value >= horizon) continue;
      final record = records[entry.key];
      if (record == null) continue;
      record.clocks.removeWhere((field, at) {
        if (at > entry.value) return false;
        record.fields.remove(field);
        removed++;
        return true;
      });
      if (record.clocks.isEmpty) records.remove(entry.key);
    }
    return removed;
  }

  SyncState copy() => SyncState(
    records: {
      for (final entry in records.entries) entry.key: entry.value.copy(),
    },
    tombstones: Map<String, int>.of(tombstones),
    clock: clock,
  );

  /// Folds [other] into this state.
  void mergeFrom(SyncState other) {
    for (final entry in other.records.entries) {
      final mine = records[entry.key] ??= SyncRecord();
      final theirs = entry.value;
      for (final field in theirs.clocks.keys) {
        mine.offer(field, theirs.fields[field], theirs.clocks[field]!);
      }
    }
    for (final entry in other.tombstones.entries) {
      tombstone(entry.key, entry.value);
    }
    if (other.clock > clock) clock = other.clock;
  }

  static SyncState mergeAll(Iterable<SyncState> states) {
    final result = SyncState();
    for (final state in states) {
      result.mergeFrom(state);
    }
    return result;
  }

  Map<String, dynamic> toJson() {
    final keys = records.keys.toList()..sort();
    final deleted = tombstones.keys.toList()..sort();
    return {
      'clock': clock,
      'records': {for (final key in keys) key: records[key]!.toJson()},
      'tombstones': {for (final key in deleted) key: tombstones[key]},
    };
  }

  /// JSON text of [toJson]. Records and fields are sorted, so equal states
  /// encode to equal text.
  String encode() => jsonEncode(toJson());

  /// Content digest of [encode].
  String digest() => digestOf(encode());

  static String digestOf(String encoded) =>
      crypto.sha256.convert(utf8.encode(encoded)).toString();

  static SyncState fromJson(Object? json) {
    if (json is! Map) throw const SyncFormatException('State is not an object');
    final rawRecords = json['records'];
    final rawTombstones = json['tombstones'];
    final rawClock = json['clock'];
    if (rawRecords is! Map || rawTombstones is! Map) {
      throw const SyncFormatException('State is missing records');
    }
    if (!isValidClock(rawClock)) {
      throw const SyncFormatException('Invalid state clock');
    }
    final state = SyncState(clock: rawClock as int);
    for (final entry in rawRecords.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty || key.length > _maxKeyLength) {
        throw const SyncFormatException('Invalid record key');
      }
      final raw = entry.value;
      final own = raw is Map ? raw['c'] ?? const {} : null;
      if (raw is! Map || raw['f'] is! Map || own is! Map) {
        throw SyncFormatException('Invalid record $key');
      }
      final base = raw['t'];
      if (!isValidClock(base)) {
        throw SyncFormatException('Invalid clock for $key');
      }
      final fields = raw['f'] as Map;
      final record = SyncRecord();
      for (final fieldEntry in fields.entries) {
        final field = fieldEntry.key;
        if (field is! String || field.isEmpty) {
          throw SyncFormatException('Invalid field name in $key');
        }
        final clock = own[field] ?? base;
        if (!isValidClock(clock)) {
          throw SyncFormatException('Invalid clock for $key.$field');
        }
        record.fields[field] = jsonCopy(fieldEntry.value);
        record.clocks[field] = clock as int;
      }
      if (own.keys.any((field) => !fields.containsKey(field))) {
        throw SyncFormatException('Clock without field in $key');
      }
      state.records[key] = record;
      if (record.maxClock > state.clock) state.clock = record.maxClock;
    }
    for (final entry in rawTombstones.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty || key.length > _maxKeyLength) {
        throw const SyncFormatException('Invalid tombstone key');
      }
      if (!isValidClock(entry.value)) {
        throw SyncFormatException('Invalid tombstone clock for $key');
      }
      state.tombstone(key, entry.value as int);
    }
    return state;
  }
}
