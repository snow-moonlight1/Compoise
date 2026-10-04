import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/neumorphic/neumorphic.dart';

String _hex(Color color) {
  String channel(double value) =>
      (value * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}';
}

void main() {
  test('role text and borders stay distinct without relying on shadow', () {
    for (final brightness in Brightness.values) {
      for (final highContrast in const <bool>[false, true]) {
        for (final reduceMotion in const <bool>[false, true]) {
          final spec = NeuSpec.resolve(
            brightness: brightness,
            highContrast: highContrast,
            reduceMotion: reduceMotion,
          );
          expect(spec.canvas.a, 1);
          expect(spec.focusRing.a, 1);
          expect(
            neuContrast(spec.focusRing, spec.canvas),
            greaterThanOrEqualTo(3),
            reason: 'focus ${_hex(spec.focusRing)} on ${_hex(spec.canvas)}',
          );
          if (highContrast || reduceMotion) {
            expect(spec.shadows(pressed: false), isNull);
            expect(spec.shadows(pressed: true), isNull);
          } else {
            expect(
              spec.shadows(pressed: false)!.length,
              greaterThanOrEqualTo(2),
            );
            expect(spec.shadows(pressed: true), isNotEmpty);
          }
          for (final role in NeuRole.values) {
            final normal = spec.styleFor(role);
            final pressed = spec.styleFor(role, pressed: true);
            final disabled = spec.styleFor(role, disabled: true);
            final error = spec.styleFor(role, error: true);
            for (final style in [normal, pressed, disabled, error]) {
              expect(style.fill.a, 1);
              expect(style.foreground.a, 1);
              expect(style.border.a, 1);
              expect(style.borderWidth, greaterThanOrEqualTo(2));
              expect(
                neuContrast(style.foreground, style.fill),
                greaterThanOrEqualTo(4.5),
                reason:
                    '$brightness hc=$highContrast $role '
                    '${_hex(style.foreground)} on ${_hex(style.fill)}',
              );
              expect(
                neuContrast(style.border, spec.canvas),
                greaterThanOrEqualTo(3),
                reason:
                    '$brightness hc=$highContrast $role border '
                    '${_hex(style.border)} on ${_hex(spec.canvas)}',
              );
            }
            expect(
              normal.fill != pressed.fill ||
                  normal.borderWidth != pressed.borderWidth,
              isTrue,
              reason: '$role pressed is the same shape as normal',
            );
            expect(disabled.markers, contains(Icons.block));
            expect(
              normal.fill != disabled.fill ||
                  normal.borderWidth != disabled.borderWidth,
              isTrue,
            );
            expect(error.markers, contains(Icons.error_outline));
            if (role == NeuRole.danger) {
              expect(normal.markers, contains(Icons.warning_amber_outlined));
            }
          }
        }
      }
    }
  });
}
