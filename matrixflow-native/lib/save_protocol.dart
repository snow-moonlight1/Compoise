import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A completed queue operation is not a power-loss durability guarantee.
/// The pointer names the only committed slot; an interrupted inactive-slot
/// write is ignored on restart. The legacy keys are compatibility mirrors.
typedef SaveWrite = Future<bool> Function(String key, String value);

class SaveResult {
  final bool success;
  final int revision;
  final bool committed;
  const SaveResult(this.success, this.revision, {this.committed = false});
}

class SavedBatch {
  final int revision;
  final Map<String, String> values;
  const SavedBatch(this.revision, this.values);
}

class SaveProtocol {
  static const pointerKey = 'matrixflow-save-pointer';
  static const _slotA = 'matrixflow-save-a';
  static const _slotB = 'matrixflow-save-b';
  final SharedPreferences prefs;
  final SaveWrite? writer;
  String? _activeSlot;
  int revision = 0;
  Future<void> _tail = Future.value();

  SaveProtocol(this.prefs, {this.writer});

  /// Null means no protocol exists. A malformed committed slot throws so the
  /// startup recovery screen can preserve every original value.
  SavedBatch? load() {
    final pointer = prefs.getString(pointerKey);
    if (pointer == null) {
      if (prefs.containsKey(_slotA) || prefs.containsKey(_slotB)) {
        // A first commit may have stopped before its pointer. Legacy keys win.
        return null;
      }
      return null;
    }
    if (pointer != _slotA && pointer != _slotB) {
      throw const FormatException('Invalid save pointer');
    }
    final raw = prefs.getString(pointer);
    if (raw == null) throw const FormatException('Missing committed batch');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['revision'] is! int ||
        decoded['values'] is! Map<String, dynamic> ||
        decoded['check'] is! int) {
      throw const FormatException('Invalid committed batch');
    }
    final values = Map<String, String>.from(decoded['values'] as Map);
    if (!{
      'matrixflow-tasks',
      'matrixflow-boards',
      'matrixflow-config',
      'matrixflow-settings',
      'matrixflow-active-board',
      'matrixflow-has-seen-onboarding',
    }.every(values.containsKey)) {
      throw const FormatException('Incomplete committed batch');
    }
    final body = jsonEncode({
      'revision': decoded['revision'],
      'values': values,
    });
    if (_checksum(body) != decoded['check']) {
      throw const FormatException('Committed batch checksum failed');
    }
    _activeSlot = pointer;
    revision = decoded['revision'] as int;
    return SavedBatch(revision, values);
  }

  Future<SaveResult> commit(Map<String, String> values) {
    final previous = _tail;
    final response = Completer<SaveResult>();
    _tail = () async {
      await previous;
      try {
        response.complete(await _commitOnce(values));
      } catch (error, stack) {
        response.completeError(error, stack);
      }
    }();
    return response.future;
  }

  Future<SaveResult> _commitOnce(Map<String, String> values) async {
    final next = revision + 1;
    final slot = _activeSlot == _slotA ? _slotB : _slotA;
    final body = jsonEncode({'revision': next, 'values': values});
    final payload = jsonEncode({
      'revision': next,
      'values': values,
      'check': _checksum(body),
    });
    try {
      if (!await _set(slot, payload)) return SaveResult(false, next);
      if (!await _set(pointerKey, slot)) {
        if (prefs.getString(pointerKey) != slot) return SaveResult(false, next);
      }
    } catch (_) {
      // An injected writer may throw after writing the pointer.
      if (prefs.getString(pointerKey) != slot) return SaveResult(false, next);
    }
    _activeSlot = slot;
    revision = next;
    // Compatibility mirrors are not the commit point. A failed mirror is
    // repaired by a later save; startup always reads the committed slot.
    for (final entry in values.entries) {
      try {
        if (entry.key == 'matrixflow-has-seen-onboarding') {
          await prefs.setBool(entry.key, entry.value == 'true');
        } else {
          await _set(entry.key, entry.value);
        }
      } catch (_) {
        /* committed snapshot remains authoritative */
      }
    }
    return SaveResult(true, next, committed: true);
  }

  Future<bool> _set(String key, String value) =>
      writer?.call(key, value) ?? prefs.setString(key, value);

  /// Remove legacy plaintext from both batch slots and the compatibility
  /// mirror. Safe to repeat after interruption. Call only after a secure-store
  /// write has been read back successfully (or when no credential exists).
  Future<bool> scrubCredentials() async {
    for (final slot in [_slotA, _slotB]) {
      final raw = prefs.getString(slot);
      if (raw == null) continue;
      String updated;
      try {
        final batch = jsonDecode(raw) as Map<String, dynamic>;
        final values = Map<String, String>.from(batch['values'] as Map);
        final config =
            jsonDecode(values['matrixflow-config']!) as Map<String, dynamic>;
        if (!config.containsKey('customApiKey')) continue;
        config.remove('customApiKey');
        values['matrixflow-config'] = jsonEncode(config);
        final body = jsonEncode({
          'revision': batch['revision'],
          'values': values,
        });
        updated = jsonEncode({
          'revision': batch['revision'],
          'values': values,
          'check': _checksum(body),
        });
      } catch (_) {
        // An uncommitted damaged slot cannot be used for recovery. Keep the
        // committed slot, but remove this copy in case it contains plaintext.
        if (slot == _activeSlot || !await prefs.remove(slot)) return false;
        continue;
      }
      try {
        if (!await _set(slot, updated) || prefs.getString(slot) != updated) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    final mirror = prefs.getString('matrixflow-config');
    if (mirror != null) {
      String? updated;
      try {
        final config = jsonDecode(mirror) as Map<String, dynamic>;
        if (config.containsKey('customApiKey')) {
          config.remove('customApiKey');
          updated = jsonEncode(config);
        }
      } catch (_) {
        // A committed slot is authoritative. A malformed compatibility mirror
        // must not leave a possible plaintext copy behind.
        if (_activeSlot == null || !await prefs.remove('matrixflow-config')) {
          return false;
        }
      }
      if (updated != null) {
        try {
          if (!await _set('matrixflow-config', updated) ||
              prefs.getString('matrixflow-config') != updated) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }
    }
    return true;
  }

  static int _checksum(String value) {
    var a = 1;
    var b = 0;
    for (final byte in utf8.encode(value)) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    return (b << 16) | a;
  }
}
