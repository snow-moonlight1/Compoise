import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrixflow_native/credential_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'platform credential store writes, reads and deletes an inert probe',
    (_) async {
      final key =
          'matrixflow-os09-probe-${DateTime.now().microsecondsSinceEpoch}';
      final store = SystemCredentialStore(key: key);
      const sentinel = 'SYNTHETIC_OS09_PLATFORM_PROBE_INVALID';
      try {
        expect(await store.read(), isNull);
        await store.write(sentinel);
        expect(await store.read(), sentinel);
        await store.delete();
        expect(await store.read(), isNull);
      } finally {
        await store.delete();
      }
    },
  );
}
