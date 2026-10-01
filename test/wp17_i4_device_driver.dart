import 'package:integration_test/integration_test_driver.dart';

/// Driver for the WP17-I4 Android device OCR leg.
///
/// A five-minute budget covers the first model load plus the 12 synthetic
/// screenshots on an API 23 x86_64 emulator; the run is opt-in through
/// `--dart-define=WP17_I4_DEVICE=true`.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 8),
  responseDataCallback: (_) async {},
);
